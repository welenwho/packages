#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/node.js"
RPC="$PACKAGE_ROOT/root/usr/share/rpcd/ucode/luci.sbproxy"
GENERATOR="$PACKAGE_ROOT/root/etc/sbproxy/scripts/generate_client.uc"
COMMON="$PACKAGE_ROOT/root/etc/sbproxy/scripts/sbproxy.uc"
SUBSCRIPTIONS="$PACKAGE_ROOT/root/etc/sbproxy/scripts/update_subscriptions.uc"

grep -Fq "params: ['nodes']" "$CLIENT"
grep -Fq 'callNodeLatencyTest(section_ids)' "$CLIENT"
! grep -Fq 'getNodeLatencyRoutingContext' "$CLIENT"
grep -Fq "'bind_interface', _('Bind interface')" "$CLIENT"
grep -Fq "'domain_resolver', _('Domain resolver')" "$CLIENT"
grep -Fq "'domain_strategy', _('Domain strategy')" "$CLIENT"

grep -Fq 'args: { nodes: [] }' "$RPC"
grep -Fq 'resolveNodeDialFields(sbpuci' "$RPC"
grep -Fq 'renderNodeDomainResolver(effective' "$RPC"
grep -Fq 'Bound interface %s does not exist.' "$RPC"
grep -Fq 'resolveNodeDialFields(uci' "$GENERATOR"
grep -Fq 'emit_node(endpoint, true)' "$GENERATOR"
grep -Fq 'emit_node(routed_outbound, false)' "$GENERATOR"
grep -Fq 'export function resolveNodeDialFields' "$COMMON"
grep -Fq 'export function renderNodeDomainResolver' "$COMMON"
grep -Fq "!(option in ['bind_interface', 'domain_resolver', 'domain_strategy'])" "$SUBSCRIPTIONS"

echo 'Node dial fields are shared by URLTest, direct routing, subscriptions, and isolated latency tests'
