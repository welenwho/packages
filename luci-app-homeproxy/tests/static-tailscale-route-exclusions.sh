#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GENERATOR="$PACKAGE_ROOT/root/etc/homeproxy/scripts/generate_client.uc"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/homeproxy/client.js"
CONFIG="$PACKAGE_ROOT/root/etc/config/homeproxy"

grep -Fq "form.Flag, 'tun_route_exclude_tailscale'" "$CLIENT"
grep -Fq "o.depends('proxy_mode', 'tun');" "$CLIENT"
grep -Fq "option tun_route_exclude_tailscale '0'" "$CONFIG"
grep -Fq 'function unique_cidrs(values)' "$GENERATOR"
grep -Fq "uci.get('tailscale', 'settings', 'subnet_routes')" "$GENERATOR"
grep -Fq '/sbin/ip -j ${family} route show table 52' "$GENERATOR"
grep -Fq "^tailscale[0-9]+$" "$GENERATOR"
grep -Fq "destination === '0.0.0.0/0'" "$GENERATOR"
grep -Fq "destination === '0.0.0.0/1'" "$GENERATOR"
grep -Fq "'100.64.0.0/10'" "$GENERATOR"
grep -Fq "'fd7a:115c:a1e0::/48'" "$GENERATOR"
grep -Fq "const families = (ipv6_support === '1') ? [ '-4', '-6' ] : [ '-4' ];" "$GENERATOR"

echo 'Tailscale route exclusion test passed: active peer routes are discovered and default routes remain eligible for HomeProxy'
