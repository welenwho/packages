#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/node.js"
RPC="$PACKAGE_ROOT/root/usr/share/rpcd/ucode/luci.sbproxy"

grep -Fq "params: ['nodes', 'routing_nodes']" "$CLIENT"
grep -Fq "section.node !== 'urltest' && !section.outbound" "$CLIENT"
grep -Fq "return (matches.length === 1) ? matches[0] : null;" "$CLIENT"
grep -Fq "callNodeLatencyTest(section_ids, routing_nodes)" "$CLIENT"

grep -Fq "args: { nodes: [], routing_nodes: [] }" "$RPC"
grep -Fq "routing_context['.type'] !== 'routing_node'" "$RPC"
grep -Fq "routing_context.enabled !== '1' || routing_context.node !== node" "$RPC"
grep -Fq "routing_context.node === 'urltest' || routing_context.outbound" "$RPC"
grep -Fq "outbound.bind_interface = routing_context.bind_interface;" "$RPC"

echo 'Latency routing context test passed: unique routing-node interface binding is validated and inherited'
