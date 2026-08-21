#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/homeproxy/client.js"
GENERATOR="$PACKAGE_ROOT/root/etc/homeproxy/scripts/generate_client.uc"
FIREWALL="$PACKAGE_ROOT/root/etc/homeproxy/scripts/firewall_post.ut"
MODULE="$PACKAGE_ROOT/root/etc/homeproxy/scripts/homeproxy.uc"

grep -Fq "form.DynamicList, 'routing_port_extra'" "$CLIENT"
grep -Fq "o.depends('routing_port', 'common');" "$CLIENT"
grep -Fq 'Built-in common ports: %s.' "$CLIENT"
grep -Fq "common_routing_ports.replace(/,/g, ', ')" "$CLIENT"
grep -Fq 'export function resolveRoutingPorts' "$MODULE"
grep -Fq "uci.get(uciconfig, ucimain, 'routing_port_extra')" "$GENERATOR"
grep -Fq "uci.get(cfgname, 'config', 'routing_port_extra')" "$FIREWALL"

echo 'Routing port UI test passed: common ports are documented and extra ports share TUN/TProxy resolution'
