#!/bin/sh
# Run in an isolated OpenWrt container; never modifies or starts the router's service.
set -eu
PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPTS="$PACKAGE_ROOT/root/etc/sbproxy/scripts"
TEST_ROOT="$(mktemp -d /tmp/sbproxy-egress.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM
mkdir -p "$TEST_ROOT/uci" "$TEST_ROOT/save"
cp "$PACKAGE_ROOT/root/usr/share/sbproxy/defaults/sbproxy" "$TEST_ROOT/uci/sbproxy"
cfg() { uci -q -c "$TEST_ROOT/uci" -t "$TEST_ROOT/save" "$@"; }
generate() {
	SBPROXY_UCI_CONFIG_DIR="$TEST_ROOT/uci" SBPROXY_CLIENT_CONFIG_PATH="$TEST_ROOT/config.json" \
		ucode -S -L "$SCRIPTS" "$SCRIPTS/generate_client.uc"
}
verify() { ucode "$PACKAGE_ROOT/tests/check-node-egress-config.uc" "$TEST_ROOT/config.json" "$1"; }

cfg set sbproxy.infra.clash_api_port=19090
cfg set sbproxy.infra.tailscale_api_port=19096
cfg set sbproxy.wg=node
cfg set sbproxy.wg.type=wireguard
cfg set sbproxy.wg.label=test-wg
cfg set sbproxy.wg.address=192.0.2.17
cfg set sbproxy.wg.port=51820
cfg set sbproxy.wg.wireguard_local_address=10.77.0.4/32
cfg set sbproxy.wg.wireguard_mtu=1180
cfg set sbproxy.wg.wireguard_private_key=test-private-key
cfg set sbproxy.wg.wireguard_peer_public_key=test-public-key
cfg set sbproxy.wg.bind_interface=tailscale0
cfg set sbproxy.wg.grouphash=test-subscription
cfg set sbproxy.socks=node
cfg set sbproxy.socks.type=socks
cfg set sbproxy.socks.label=test-socks
cfg set sbproxy.socks.address=192.0.2.18
cfg set sbproxy.socks.port=1080
cfg set sbproxy.config.main_node=wg
cfg set sbproxy.config.routing_mode=bypass_mainland_china
cfg commit sbproxy
generate
verify main

cfg set sbproxy.config.main_node=urltest
cfg add_list sbproxy.config.main_urltest_nodes=wg
cfg add_list sbproxy.config.main_urltest_nodes=socks
cfg commit sbproxy
generate
verify urltest

cfg set sbproxy.config.routing_mode=custom
cfg set sbproxy.routing.default_outbound=direct-out
cfg set sbproxy.direct=routing_node
cfg set sbproxy.direct.enabled=1
cfg set sbproxy.direct.node=wg
cfg set sbproxy.group=routing_node
cfg set sbproxy.group.enabled=1
cfg set sbproxy.group.node=urltest
cfg add_list sbproxy.group.urltest_subscriptions=test-subscription
cfg add_list sbproxy.group.urltest_nodes=socks
cfg set sbproxy.test_dns=dns_server
cfg set sbproxy.test_dns.enabled=1
cfg set sbproxy.test_dns.type=udp
cfg set sbproxy.test_dns.server=1.1.1.1
cfg set sbproxy.wg.domain_resolver=test_dns
cfg set sbproxy.wg.domain_strategy=ipv4_only
cfg commit sbproxy
generate
verify custom

# A strategy-only node uses the custom mode's default outbound DNS server.
cfg delete sbproxy.wg.domain_resolver
cfg set sbproxy.routing.default_outbound_dns=test_dns
cfg commit sbproxy
generate
verify custom
cfg set sbproxy.wg.domain_resolver=test_dns
cfg commit sbproxy

# Old route-only dial fields apply to URLTest members before migration, and
# promotion to the node is idempotent without deleting the historical values.
cfg delete sbproxy.wg.bind_interface
cfg delete sbproxy.wg.domain_resolver
cfg delete sbproxy.wg.domain_strategy
cfg set sbproxy.direct.bind_interface=tailscale0
cfg set sbproxy.direct.domain_resolver=test_dns
cfg set sbproxy.direct.domain_strategy=ipv4_only
cfg commit sbproxy
generate
verify custom
SBPROXY_UCI_CONFIG_DIR="$TEST_ROOT/uci" SBPROXY_MIGRATION_SKIP_CLEANUP=1 \
	ucode -S -L "$SCRIPTS" "$SCRIPTS/migrate_config.uc"
test "$(cfg get sbproxy.wg.bind_interface)" = tailscale0
test "$(cfg get sbproxy.wg.domain_resolver)" = test_dns
test "$(cfg get sbproxy.direct.bind_interface)" = tailscale0
cp "$TEST_ROOT/uci/sbproxy" "$TEST_ROOT/migrated"
SBPROXY_UCI_CONFIG_DIR="$TEST_ROOT/uci" SBPROXY_MIGRATION_SKIP_CLEANUP=1 \
	ucode -S -L "$SCRIPTS" "$SCRIPTS/migrate_config.uc"
cmp "$TEST_ROOT/migrated" "$TEST_ROOT/uci/sbproxy"
generate
verify custom

# Multiple direct references may not silently choose the first old interface.
cfg delete sbproxy.wg.bind_interface
cfg set sbproxy.other=routing_node
cfg set sbproxy.other.enabled=1
cfg set sbproxy.other.node=wg
cfg set sbproxy.other.bind_interface=eth9
cfg commit sbproxy
if generate >"$TEST_ROOT/log" 2>&1; then
	echo 'conflicting legacy interfaces unexpectedly generated successfully' >&2
	exit 1
fi
grep -Fq 'Conflicting legacy bind_interface' "$TEST_ROOT/log"

# An upstream detour with the same node tag but different dial semantics must
# fail explicitly instead of depending on traversal order.
cfg set sbproxy.wg.bind_interface=tailscale0
cfg delete sbproxy.other.bind_interface
cfg set sbproxy.other.outbound=direct-out
cfg commit sbproxy
if generate >"$TEST_ROOT/log" 2>&1; then
	echo 'conflicting detour unexpectedly generated successfully' >&2
	exit 1
fi
grep -Fq 'conflicting routing contexts' "$TEST_ROOT/log"

# A single detoured direct route may not secretly change the shared URLTest
# member either; both references use the same tag.
cfg set sbproxy.other.enabled=0
cfg set sbproxy.direct.outbound=direct-out
cfg commit sbproxy
if generate >"$TEST_ROOT/log" 2>&1; then
	echo 'URLTest reused a detoured direct route without checking its dial settings' >&2
	exit 1
fi
grep -Fq 'conflicting routing contexts' "$TEST_ROOT/log"
echo 'Node-level dial settings, legacy migration, subscription URLTest, and conflict tests passed'
