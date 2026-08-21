#!/bin/sh

set -eu

TEST_DIR="$(mktemp -d)"
UCI_LOG="$TEST_DIR/uci.log"
export UCI_LOG
trap 'rm -rf "$TEST_DIR"' EXIT

cat >"$TEST_DIR/tailscale" <<-'EOF'
	#!/bin/sh
	if [ "${1:-}" = "status" ]; then
		printf '%s\n' '{"MagicDNSSuffix":"example.ts.net"}'
	fi
EOF

cat >"$TEST_DIR/uci" <<-'EOF'
	#!/bin/sh
	case "$*" in
		"show dhcp")
			cat <<-'EOT'
				dhcp.@dnsmasq[0]=dnsmasq
				dhcp.@dnsmasq[0].address='/legacy.ts.net/100.100.100.100'
				dhcp.@dnsmasq[0].server='/stale.ts.net/100.100.100.100'
				dhcp.@dnsmasq[0].server='1.1.1.1'
			EOT
			;;
		"-q get dhcp.@dnsmasq[0].address")
			printf '%s\n' '/legacy.ts.net/100.100.100.100'
			;;
		"-q get dhcp.@dnsmasq[0].server")
			printf '%s\n' '/stale.ts.net/100.100.100.100 1.1.1.1'
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
grep -qxF -- '-q add_list dhcp.@dnsmasq[0].server=/example.ts.net/100.100.100.100' "$UCI_LOG"
if grep -qF -- 'add_list dhcp.@dnsmasq[0].address=' "$UCI_LOG"; then
	echo 'MagicDNS must use dnsmasq server entries, not address entries.' >&2
	exit 1
fi

: >"$UCI_LOG"
MAGIC_DNS=0
configure_magicdns
if grep -qF -- 'add_list ' "$UCI_LOG"; then
	echo 'Disabled MagicDNS forwarding must not add a dnsmasq entry.' >&2
	exit 1
fi

echo 'helper MagicDNS tests passed'
