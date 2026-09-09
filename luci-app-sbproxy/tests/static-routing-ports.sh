#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client.js"
GENERATOR="$PACKAGE_ROOT/root/etc/sbproxy/scripts/generate_client.uc"
MODULE="$PACKAGE_ROOT/root/etc/sbproxy/scripts/sbproxy.uc"

grep -Fq "form.DynamicList, 'routing_port_extra'" "$CLIENT"
grep -Fq "o.depends('routing_port', 'common');" "$CLIENT"
grep -Fq 'Built-in common ports: %s.' "$CLIENT"
grep -Fq "common_routing_ports.replace(/,/g, ', ')" "$CLIENT"
grep -Fq 'export function resolveRoutingPorts' "$MODULE"
grep -Fq "uci.get(uciconfig, ucimain, 'routing_port_extra')" "$GENERATOR"

echo 'Routing port UI test passed: common ports are documented and extra ports use TUN pre-match resolution'
