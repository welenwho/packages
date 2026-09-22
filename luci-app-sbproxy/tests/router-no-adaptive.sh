#!/bin/sh
# Run inside an OpenWrt test container. All UCI/config output is temporary;
# no service is started, stopped or reconfigured by this test.
set -eu
PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPTS="$PACKAGE_ROOT/root/etc/sbproxy/scripts"
TEST_ROOT="$(mktemp -d /tmp/sbproxy-no-adaptive.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM
mkdir -p "$TEST_ROOT/uci"
cp "$PACKAGE_ROOT/root/usr/share/sbproxy/defaults/sbproxy" "$TEST_ROOT/uci/sbproxy"
cfg() { uci -q -c "$TEST_ROOT/uci" "$@"; }
cfg set sbproxy.infra.clash_api_port=19090
cfg set sbproxy.infra.tailscale_api_port=19096
cfg set sbproxy.fixture=node
cfg set sbproxy.fixture.type=socks
cfg set sbproxy.fixture.label=fixture-proxy
cfg set sbproxy.fixture.address=192.0.2.1
cfg set sbproxy.fixture.port=1080
cfg set sbproxy.fixture_route=routing_node
cfg set sbproxy.fixture_route.enabled=1
cfg set sbproxy.fixture_route.label=fixture-route
cfg set sbproxy.fixture_route.node=fixture
cfg set sbproxy.explicit=routing_rule
cfg set sbproxy.explicit.enabled=1
cfg set sbproxy.explicit.action=route
cfg set sbproxy.explicit.outbound=direct-out
cfg add_list sbproxy.explicit.domain=explicit.example
cfg add_list sbproxy.config.main_urltest_nodes=fixture
cfg commit sbproxy

generate() {
	SBPROXY_UCI_CONFIG_DIR="$TEST_ROOT/uci" SBPROXY_CLIENT_CONFIG_PATH="$1" \
		ucode -S -L "$SCRIPTS" "$SCRIPTS/generate_client.uc"
}

for mode in bypass_mainland_china global custom-direct custom-proxy custom-reject urltest tailscale-only; do
	cfg set sbproxy.tailscale.enabled=0
	cfg set sbproxy.config.main_node=fixture
	cfg set sbproxy.config.routing_mode=bypass_mainland_china
	case "$mode" in
		global) cfg set sbproxy.config.routing_mode=global ;;
		custom-*)
			cfg set sbproxy.config.routing_mode=custom
			case "$mode" in
				custom-direct) cfg set sbproxy.routing.default_outbound=direct-out ;;
				custom-proxy) cfg set sbproxy.routing.default_outbound=fixture_route ;;
				custom-reject) cfg set sbproxy.routing.default_outbound=reject ;;
			esac ;;
		urltest) cfg set sbproxy.config.main_node=urltest ;;
		tailscale-only) cfg set sbproxy.config.main_node=nil; cfg set sbproxy.tailscale.enabled=1 ;;
	esac
	cfg commit sbproxy
	rm -f "$TEST_ROOT/uci/sbproxy-adaptive"
	generate "$TEST_ROOT/clean.json"
	# A preserved old enabled config with a missing outbound must be ignored.
	printf '%s\n' "config adaptive 'main'" "option enabled '1'" "option dry_run '0'" \
		"option outbound 'missing-outbound'" > "$TEST_ROOT/uci/sbproxy-adaptive"
	generate "$TEST_ROOT/legacy.json"
	cmp "$TEST_ROOT/clean.json" "$TEST_ROOT/legacy.json"
	ucode "$PACKAGE_ROOT/tests/check-no-adaptive-config.uc" "$TEST_ROOT/clean.json" "$mode"
done

# Do not run the old one-time URLTest migration twice on an upgraded system.
cfg set sbproxy.migration=sbproxy
cfg set sbproxy.migration.adaptive_stability_defaults=1
cfg set sbproxy.config.main_urltest_interrupt_exist_connections=1
cfg set sbproxy.fixture_route.node=urltest
cfg add_list sbproxy.fixture_route.urltest_nodes=fixture
cfg set sbproxy.fixture_route.urltest_interval=60
cfg set sbproxy.fixture_route.urltest_interrupt_exist_connections=1
cfg commit sbproxy
for repeat in 1 2; do
	SBPROXY_UCI_CONFIG_DIR="$TEST_ROOT/uci" SBPROXY_MIGRATION_SKIP_CLEANUP=1 \
		ucode -S -L "$SCRIPTS" "$SCRIPTS/migrate_config.uc"
done
test "$(cfg get sbproxy.migration.urltest_stability_defaults)" = 1
test "$(cfg get sbproxy.config.main_urltest_interrupt_exist_connections)" = 1
test "$(cfg get sbproxy.fixture_route.urltest_interval)" = 60
test "$(cfg get sbproxy.fixture_route.urltest_interrupt_exist_connections)" = 1
if cfg get sbproxy.migration.adaptive_stability_defaults >/dev/null; then exit 1; fi
echo 'URLTest migration flag renamed without resetting user choices'
