#!/bin/sh
# Isolated OpenWrt config generation. Never starts the generated core.
set -eu
PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPTS="$PACKAGE_ROOT/root/etc/sbproxy/scripts"
TEST_ROOT="$(mktemp -d /tmp/sbproxy-mode-test.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM
mkdir -p "$TEST_ROOT/uci" "$TEST_ROOT/save"
cp "$PACKAGE_ROOT/root/usr/share/sbproxy/defaults/sbproxy" "$TEST_ROOT/uci/sbproxy"
cfg() { uci -q -c "$TEST_ROOT/uci" -t "$TEST_ROOT/save" "$@"; }
cfg set sbproxy.config.dashboard_enabled=1
cfg set sbproxy.config.dashboard_port=19095
cfg set sbproxy.infra.clash_api_port=19090
cfg set sbproxy.infra.tailscale_api_port=19096
cfg set sbproxy.tailscale.enabled=1
cfg set sbproxy.tailscale.accept_routes=1
cfg add_list sbproxy.tailscale.advertise_routes=192.0.2.0/24
# Deliberately broken proxy-only settings must not stop Tailscale.
cfg set sbproxy.config.main_node=urltest
cfg set sbproxy.routing.default_outbound=missing
cfg set sbproxy.dns.default_server=missing
cfg set sbproxy.broken=domain_route
cfg set sbproxy.broken.enabled=1
cfg set sbproxy.broken.node=missing
cfg add_list sbproxy.broken.domain=example.com
cfg set sbproxy.control.ingress_enabled=1
cfg add_list sbproxy.control.ingress_bypass_devices=eth1
cfg set sbproxy.infra.ingress_dns_port=invalid
cfg commit sbproxy
SBPROXY_UCI_CONFIG_DIR="$TEST_ROOT/uci" ucode -S -L "$SCRIPTS" "$SCRIPTS/cleanup_urltest.uc"
test "$(cfg get sbproxy.config.main_node)" = urltest
for mode in disabled bypass_mainland_china; do
  cfg set sbproxy.config.routing_mode="$mode"
  [ "$mode" != bypass_mainland_china ] || cfg set sbproxy.config.main_node=nil
  for magic in 0 1; do
    cfg set sbproxy.tailscale.magic_dns="$magic"
    cfg commit sbproxy
    SBPROXY_UCI_CONFIG_DIR="$TEST_ROOT/uci" SBPROXY_CLIENT_CONFIG_PATH="$TEST_ROOT/config.json" \
      ucode -S -L "$SCRIPTS" "$SCRIPTS/generate_client.uc"
    ucode "$PACKAGE_ROOT/tests/check-proxy-disabled.uc" "$TEST_ROOT/config.json" "$magic" "$mode"
  done
done
cfg set sbproxy.config.routing_mode=disabled
cfg set sbproxy.config.main_node=nil
cfg commit sbproxy
SBPROXY_UCI_CONFIG_DIR="$TEST_ROOT/uci" SBPROXY_MIGRATION_SKIP_CLEANUP=1 \
  ucode -S -L "$SCRIPTS" "$SCRIPTS/migrate_config.uc"
test "$(cfg get sbproxy.config.routing_mode)" = disabled
test "$(cfg get sbproxy.tailscale.enabled)" = 1
test "$(cfg get sbproxy.config.dashboard_enabled)" = 1
echo 'Explicit off survives config migration; legacy main-node disable still supports Tailscale'
