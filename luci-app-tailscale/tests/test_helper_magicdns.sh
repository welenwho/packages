#!/bin/sh

set -eu

TEST_DIR="$(mktemp -d)"
UCI_LOG="$TEST_DIR/uci.log"
UCI_STATE="$TEST_DIR/uci.state"
export UCI_LOG UCI_STATE
trap 'rm -rf "$TEST_DIR"' EXIT

printf '%s\n' initial >"$UCI_STATE"

cat >"$TEST_DIR/tailscale" <<-'EOF'
	#!/bin/sh
	if [ "${1:-}" = "status" ]; then
		printf '%s\n' '{"MagicDNSSuffix":"example.ts.net"}'
	fi
EOF

cat >"$TEST_DIR/uci" <<-'EOF'
	#!/bin/sh
	state="$(cat "$UCI_STATE")"
	case "$*" in
		"show dhcp")
			if [ "$state" = "initial" ]; then
				cat <<-'EOT'
					dhcp.@dnsmasq[0]=dnsmasq
					dhcp.@dnsmasq[0].address='/legacy.ts.net/100.100.100.100'
					dhcp.@dnsmasq[0].server='/stale.ts.net/100.100.100.100'
					dhcp.@dnsmasq[0].server='1.1.1.1'
					dhcp.@dnsmasq[0].rebind_domain='/legacy.ts.net/' '/stale.ts.net/' '/custom.example/'
				EOT
			else
				cat <<-'EOT'
					dhcp.@dnsmasq[0]=dnsmasq
					dhcp.@dnsmasq[0].server='/example.ts.net/100.100.100.100' '1.1.1.1'
					dhcp.@dnsmasq[0].rebind_domain='/example.ts.net/' '/custom.example/'
				EOT
			fi
			;;
		"-q get dhcp.@dnsmasq[0].address")
			[ "$state" = "initial" ] && printf '%s\n' '/legacy.ts.net/100.100.100.100'
			;;
		"-q get dhcp.@dnsmasq[0].server")
			if [ "$state" = "initial" ]; then
				printf '%s\n' '/stale.ts.net/100.100.100.100 1.1.1.1'
			else
				printf '%s\n' '/example.ts.net/100.100.100.100 1.1.1.1'
			fi
			;;
		"-q get dhcp.@dnsmasq[0].rebind_domain")
			if [ "$state" = "initial" ]; then
				printf '%s\n' '/legacy.ts.net/ /stale.ts.net/ /custom.example/'
			else
				printf '%s\n' '/example.ts.net/ /custom.example/'
			fi
			;;
		-q\ del_list*|-q\ add_list*)
			printf '%s\n' "$*" >>"$UCI_LOG"
			;;
	esac
EOF

chmod 755 "$TEST_DIR/tailscale" "$TEST_DIR/uci"

TAILSCALE_BIN="$TEST_DIR/tailscale"
TAILSCALE_FUNCTIONS_LIB=/dev/null
TAILSCALE_HELPER_LIBRARY_ONLY=1
PATH="$TEST_DIR:$PATH"
export TAILSCALE_BIN TAILSCALE_FUNCTIONS_LIB TAILSCALE_HELPER_LIBRARY_ONLY PATH

. "$(dirname "$0")/../root/usr/sbin/tailscale_helper"

MAGIC_DNS=1
configure_magicdns

grep -qxF -- '-q del_list dhcp.@dnsmasq[0].address=/legacy.ts.net/100.100.100.100' "$UCI_LOG"
grep -qxF -- '-q del_list dhcp.@dnsmasq[0].server=/stale.ts.net/100.100.100.100' "$UCI_LOG"
grep -qxF -- '-q del_list dhcp.@dnsmasq[0].rebind_domain=/legacy.ts.net/' "$UCI_LOG"
grep -qxF -- '-q del_list dhcp.@dnsmasq[0].rebind_domain=/stale.ts.net/' "$UCI_LOG"
grep -qxF -- '-q add_list dhcp.@dnsmasq[0].server=/example.ts.net/100.100.100.100' "$UCI_LOG"
grep -qxF -- '-q add_list dhcp.@dnsmasq[0].rebind_domain=/example.ts.net/' "$UCI_LOG"
if grep -qF -- 'rebind_domain=/custom.example/' "$UCI_LOG"; then
	echo 'MagicDNS cleanup must preserve unrelated rebind domains.' >&2
	exit 1
fi
if grep -qF -- 'add_list dhcp.@dnsmasq[0].address=' "$UCI_LOG"; then
	echo 'MagicDNS must use dnsmasq server entries, not address entries.' >&2
	exit 1
fi

: >"$UCI_LOG"
printf '%s\n' configured >"$UCI_STATE"
configure_magicdns
if [ -s "$UCI_LOG" ]; then
	echo 'An unchanged MagicDNS configuration must not rewrite dnsmasq settings.' >&2
	exit 1
fi

: >"$UCI_LOG"
MAGIC_DNS=0
configure_magicdns
grep -qxF -- '-q del_list dhcp.@dnsmasq[0].server=/example.ts.net/100.100.100.100' "$UCI_LOG"
grep -qxF -- '-q del_list dhcp.@dnsmasq[0].rebind_domain=/example.ts.net/' "$UCI_LOG"
if grep -qF -- 'add_list ' "$UCI_LOG"; then
	echo 'Disabled MagicDNS forwarding must not add a dnsmasq entry.' >&2
	exit 1
fi

echo 'helper MagicDNS tests passed'
