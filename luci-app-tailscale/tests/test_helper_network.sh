#!/bin/sh

set -eu

TEST_DIR="$(mktemp -d)"
UCI_LOG="$TEST_DIR/uci.log"
export UCI_LOG
trap 'rm -rf "$TEST_DIR"' EXIT

cat >"$TEST_DIR/ls" <<-'EOF'
	#!/bin/sh
	if [ "$*" = "/sys/class/net" ]; then
		printf '%s\n' tailscale0
	else
		/bin/ls "$@"
	fi
EOF

cat >"$TEST_DIR/tailscale" <<-'EOF'
	#!/bin/sh
	case "$*" in
		"ip -4") printf '%s\n' 100.87.146.89 ;;
		"ip -6") printf '%s\n' fd7a:115c:a1e0::1234 ;;
	esac
EOF

cat >"$TEST_DIR/uci" <<-'EOF'
	#!/bin/sh
	printf 'CALL %s\n' "$*" >>"$UCI_LOG"
	case "$*" in
		"-q batch") cat >>"$UCI_LOG" ;;
		"show network")
			printf '%s\n' \
				'network.ts_subnet1=route' \
				'network.ts_subnet2=route' \
				'network.ts_subnet3=route'
			;;
	esac
EOF

chmod 755 "$TEST_DIR/ls" "$TEST_DIR/tailscale" "$TEST_DIR/uci"

TAILSCALE_BIN="$TEST_DIR/tailscale"
TAILSCALE_FUNCTIONS_LIB=/dev/null
TAILSCALE_HELPER_LIBRARY_ONLY=1
PATH="$TEST_DIR:$PATH"
export TAILSCALE_BIN TAILSCALE_FUNCTIONS_LIB TAILSCALE_HELPER_LIBRARY_ONLY PATH

. "$(dirname "$0")/../root/usr/sbin/tailscale_helper"

SUBNET_ROUTES='192.168.7.0/24 192.168.9.0/24'
configure_network

grep -qF "set network.ts_subnet1.target='192.168.7.0/24'" "$UCI_LOG"
grep -qF "set network.ts_subnet2.target='192.168.9.0/24'" "$UCI_LOG"
grep -qxF 'CALL -q delete network.ts_subnet1.gateway' "$UCI_LOG"
grep -qxF 'CALL -q delete network.ts_subnet2.gateway' "$UCI_LOG"
grep -qxF 'CALL -q delete network.ts_subnet3' "$UCI_LOG"
if grep -qF 'set network.ts_subnet1.gateway=' "$UCI_LOG"; then
	echo 'peer routes must not use the local Tailscale address as a gateway' >&2
	exit 1
fi

ACCESS='ts_ac_lan ts_ac_wan lan_ac_ts'
: >"$UCI_LOG"
DISABLE_SNAT_SUBNET_ROUTES=1
configure_firewall
grep -qF "set firewall.tszone.masq='0'" "$UCI_LOG"

: >"$UCI_LOG"
DISABLE_SNAT_SUBNET_ROUTES=0
configure_firewall
grep -qF "set firewall.tszone.masq='1'" "$UCI_LOG"

echo 'helper network tests passed: peer routes are device routes and firewall masquerade follows Tailscale SNAT'
