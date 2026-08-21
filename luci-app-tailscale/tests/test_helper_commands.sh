#!/bin/sh

set -eu

TEST_DIR="$(mktemp -d)"
CAPTURE="$TEST_DIR/args"
HELP_FLAGS="$TEST_DIR/set-help"
export CAPTURE HELP_FLAGS
trap 'rm -rf "$TEST_DIR"' EXIT

cat >"$TEST_DIR/tailscale" <<-'EOF'
	#!/bin/sh
	if [ "${1:-}" = "set" ] && [ "${2:-}" = "--help" ]; then
		cat "$HELP_FLAGS"
		exit 0
	fi
	printf '%s\n' "$@" >"$CAPTURE"
EOF
chmod 755 "$TEST_DIR/tailscale"

cat >"$HELP_FLAGS" <<-'EOF'
	  --auto-update, --auto-update=false
	  --update-check, --update-check=false
	  --webclient, --webclient=false
EOF

TAILSCALE_BIN="$TEST_DIR/tailscale"
TAILSCALE_FUNCTIONS_LIB=/dev/null
TAILSCALE_HELPER_LIBRARY_ONLY=1
export TAILSCALE_BIN TAILSCALE_FUNCTIONS_LIB TAILSCALE_HELPER_LIBRARY_ONLY

. "$(dirname "$0")/../root/usr/sbin/tailscale_helper"

assert_arg() {
	grep -qxF -- "$1" "$CAPTURE" || {
		echo "missing argument: $1" >&2
		exit 1
	}
}

assert_no_arg() {
	if grep -qxF -- "$1" "$CAPTURE"; then
		echo "unexpected argument: $1" >&2
		exit 1
	fi
}

ACCEPT_ROUTES=1
ACCEPT_DNS=0
UPDATE_CHECK=1
AUTO_UPDATE=1
WEBCLIENT=1
ADVERTISE_EXIT_NODE=1
ADVERTISE_ROUTES='192.168.7.0/24 192.168.9.0/24'
DISABLE_SNAT_SUBNET_ROUTES=1
EXIT_NODE='auto:any'
EXIT_NODE_ALLOW_LAN_ACCESS=1
HOSTNAME='openwrt-router'
NETFILTER_MODE='nodivert'
STATEFUL_FILTERING=1
SHIELDS_UP=0
ADVERTISE_CONNECTOR=1
TAILSCALE_SSH=0
REPORT_POSTURE=1
RELAY_SERVER_ENABLED=1
RELAY_SERVER_PORT=0
RELAY_SERVER_STATIC_ENDPOINTS='192.0.2.1:40000 [2001:db8::1]:40000'

if validate_settings; then
	echo 'exit node advertising and subnet source preservation must be rejected together' >&2
	exit 1
fi
ADVERTISE_EXIT_NODE=0
validate_settings
sync_preferences
assert_arg set
assert_arg '--accept-routes=true'
assert_arg '--accept-dns=false'
assert_arg '--advertise-exit-node=false'
assert_arg '--advertise-routes=192.168.7.0/24,192.168.9.0/24'
assert_arg '--snat-subnet-routes=false'
assert_arg '--exit-node=auto:any'
assert_arg '--exit-node-allow-lan-access=true'
assert_arg '--netfilter-mode=nodivert'
assert_arg '--stateful-filtering=true'
assert_arg '--advertise-connector=true'
assert_arg '--relay-server-port=0'
assert_arg '--relay-server-static-endpoints=192.0.2.1:40000,[2001:db8::1]:40000'
assert_arg '--update-check=true'
assert_arg '--auto-update=true'
assert_arg '--webclient=true'
assert_no_arg '--reset'

ADVERTISE_EXIT_NODE=1
DISABLE_SNAT_SUBNET_ROUTES=0
validate_settings
sync_preferences
assert_arg '--advertise-exit-node=true'
assert_arg '--snat-subnet-routes=true'

RELAY_SERVER_ENABLED=0
sync_preferences
assert_arg '--relay-server-port='
assert_arg '--relay-server-static-endpoints='

cat >"$HELP_FLAGS" <<-'EOF'
	  --update-check, --update-check=false
EOF
TAILSCALE_SET_HELP_LOADED=0
sync_preferences
assert_arg '--update-check=true'
assert_no_arg '--auto-update=true'
assert_no_arg '--auto-update=false'
assert_no_arg '--webclient=true'
assert_no_arg '--webclient=false'

cat >"$HELP_FLAGS" <<-'EOF'
	  --auto-update, --auto-update=false
	  --update-check, --update-check=false
EOF
TAILSCALE_SET_HELP_LOADED=0
UPDATE_CHECK=0
AUTO_UPDATE=1
sync_preferences
assert_arg '--update-check=false'
assert_arg '--auto-update=false'

AUTH_KEY_FILE='/etc/tailscale/auth.key'
AUTHKEY='ignored-literal-key'
LOGIN_SERVER='https://headscale.example.com'
ADVERTISE_TAGS='tag:router tag:openwrt'
FLAGS='--operator=root'
login_if_needed NeedsLogin
assert_arg up
assert_arg '--auth-key=file:/etc/tailscale/auth.key'
assert_arg '--login-server=https://headscale.example.com'
assert_arg '--advertise-tags=tag:router,tag:openwrt'
assert_arg '--operator=root'
assert_no_arg '--reset'

echo 'helper command tests passed'
