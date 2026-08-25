#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

mkdir -p "$TEST_ROOT/bin"

cat > "$TEST_ROOT/functions.sh" <<-'EOF'
	config_load() { :; }
	config_get_bool() {
		case "$2.$3" in
			tailscale.enabled) eval "$1=1" ;;
			tailscale.magic_dns|tailscale.accept_routes|tailscale.disable_snat_subnet_routes|tailscale.advertise_exit_node|config.dashboard_enabled) eval "$1=0" ;;
			*) eval "$1=\${4:-}" ;;
		esac
	}
	config_get() {
		case "$2.$3" in
			tailscale.system_interface_name) eval "$1=tailscale0" ;;
			infra.dns_port) eval "$1=5333" ;;
			infra.tailscale_api_port) eval "$1=9091" ;;
			*) eval "$1=\${4:-}" ;;
		esac
	}
EOF

cat > "$TEST_ROOT/bin/uci" <<-'EOF'
	#!/bin/sh
	[ "${1:-}" != '-q' ] || shift
	[ "${1:-}" = get ] || exit 1
	[ "${2:-}" = tailscale.settings.enabled ] || exit 1
	printf '%s\n' "${MOCK_STANDALONE_ENABLED:-0}"
EOF

cat > "$TEST_ROOT/bin/pidof" <<-'EOF'
	#!/bin/sh
	[ "${MOCK_STANDALONE_RUNNING:-0}" = 1 ]
EOF

cat > "$TEST_ROOT/bin/logger" <<-'EOF'
	#!/bin/sh
	:
EOF

chmod 755 "$TEST_ROOT/bin/uci" "$TEST_ROOT/bin/pidof" "$TEST_ROOT/bin/logger"

export PATH="$TEST_ROOT/bin:$PATH"
export SBPROXY_FUNCTIONS_LIB="$TEST_ROOT/functions.sh"
export SBPROXY_TAILSCALE_STANDALONE_INIT="$TEST_ROOT/tailscale.init"

MOCK_STANDALONE_ENABLED=0 \
	"$PACKAGE_ROOT/root/usr/sbin/sbproxy_tailscale_helper" check

# A configuration preserved by sysupgrade must not block SBProxy after the
# independent package and its init script have been removed.
MOCK_STANDALONE_ENABLED=1 \
	"$PACKAGE_ROOT/root/usr/sbin/sbproxy_tailscale_helper" check

: > "$TEST_ROOT/tailscale.init"
chmod 755 "$TEST_ROOT/tailscale.init"
if MOCK_STANDALONE_ENABLED=1 \
	"$PACKAGE_ROOT/root/usr/sbin/sbproxy_tailscale_helper" check; then
	echo 'Conflict check unexpectedly succeeded with independent Tailscale enabled' >&2
	exit 1
fi

rm -f "$TEST_ROOT/tailscale.init"
if MOCK_STANDALONE_ENABLED=0 MOCK_STANDALONE_RUNNING=1 \
	"$PACKAGE_ROOT/root/usr/sbin/sbproxy_tailscale_helper" check; then
	echo 'Conflict check unexpectedly succeeded while tailscaled is running' >&2
	exit 1
fi

echo 'Tailscale helper check test passed: stale config is ignored and installed or running services conflict'
