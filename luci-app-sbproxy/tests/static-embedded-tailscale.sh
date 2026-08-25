#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client.js"
GENERATOR="$PACKAGE_ROOT/root/etc/sbproxy/scripts/generate_client.uc"
INIT="$PACKAGE_ROOT/root/etc/init.d/sbproxy"
HELPER="$PACKAGE_ROOT/root/usr/sbin/sbproxy_tailscale_helper"
RPC="$PACKAGE_ROOT/root/usr/share/rpcd/ucode/luci.sbproxy"
ACL="$PACKAGE_ROOT/root/usr/share/rpcd/acl.d/luci-app-sbproxy.json"
MENU="$PACKAGE_ROOT/root/usr/share/luci/menu.d/luci-app-sbproxy.json"
CONFIG="$PACKAGE_ROOT/root/usr/share/sbproxy/defaults/sbproxy"
MIGRATION="$PACKAGE_ROOT/root/etc/uci-defaults/00-luci-sbproxy-migrate"
MAKEFILE="$PACKAGE_ROOT/Makefile"

pkg_version="$(sed -n 's/^PKG_VERSION:=//p' "$MAKEFILE")"
pkg_release="$(sed -n 's/^PKG_RELEASE:=//p' "$MAKEFILE")"
cache_version="$(printf '%s\n' "$pkg_version" | sed 's/[^A-Za-z0-9_-]/-/g')"
cache_key="${cache_version}-r${pkg_release}"
versioned_adaptive="$PACKAGE_ROOT/htdocs/luci-static/resources/sbproxy-adaptive-${cache_key}.js"
versioned_client="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client-${cache_key}.js"

grep -Fq '"admin/vpn/sbproxy"' "$MENU"
grep -Fq 'PKG_NAME:=luci-app-sbproxy' "$PACKAGE_ROOT/Makefile"
grep -Fq "config sbproxy 'tailscale'" "$CONFIG"
grep -Fq 'NEW_CONFIG="$MIGRATION_ROOT/etc/config/sbproxy"' "$MIGRATION"
grep -Fq 'MIGRATE_FROM_LEGACY=1' "$MIGRATION"

for view in "$PACKAGE_ROOT"/htdocs/luci-static/resources/view/sbproxy/*.js; do
	if grep -Eq "require sbproxy as hp|(^|[^A-Za-z0-9_])hp[A-Za-z0-9_-]" "$view"; then
		echo "Legacy identifier remains in $view" >&2
		exit 1
	fi
done
grep -Fq "'require sbproxy as sb';" \
	"$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client.js"
grep -Fq "'require sbproxy as sb';" \
	"$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/node.js"
grep -Fq "'require sbproxy as sb';" \
	"$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/server.js"
test "$(readlink "$versioned_adaptive")" = \
	'sbproxy-adaptive.js'
test "$(readlink "$versioned_client")" = \
	'client.js'
grep -Fq "type: 'tailscale'" "$GENERATOR"
grep -A12 "const tailscale_endpoint = tailscale_enabled" "$GENERATOR" | grep -Fq "domain_resolver: {"
grep -A14 "const tailscale_endpoint = tailscale_enabled" "$GENERATOR" | grep -Fq "server: 'default-dns'"
grep -Fq "system_interface: true" "$GENERATOR"
grep -Fq "inbound: tailscale_endpoint_tag" "$GENERATOR"
grep -Fq "invert: true" "$GENERATOR"
grep -Fq "form.Flag, 'disable_snat_subnet_routes'" "$CLIENT"
grep -Fq "form.Flag, 'ssh_disable_forwarding'" "$CLIENT"
grep -Fq "method: 'tailscale_ping'" "$CLIENT"
grep -Fq '"tailscale"' "$ACL"
grep -Fq 'dashboard/index.html' "$HELPER"
grep -Fq 'firewall.sbproxy_tszone.masq 0' "$HELPER"
grep -Fq 'iifname \"$INTERFACE_NAME\" oifname != \"$INTERFACE_NAME\" masquerade' "$HELPER"
grep -Fq 'FIREWALL_RUNTIME_CHANGED' "$HELPER"
grep -Fq 'uci_set_if_changed' "$HELPER"
grep -Fq 'standalone_conflict && fail "Independent Tailscale is enabled, running, or owns $INTERFACE_NAME."' "$HELPER"
grep -A2 '^[[:space:]]*check)' "$HELPER" | grep -Fq 'exit 0'
grep -Fq "backend_state: 'Disabled'" "$RPC"
grep -Fq "parseTailscaleExitNodes" "$RPC"
grep -Fq "[ 'tailscale', 'exit-node', 'list' ]" "$RPC"
grep -Fq 'local routing_mode proxy_mode tailscale_enabled' "$INIT"
grep -Fq '[ "$outbound_node" = "nil" ] || proxy_client_requested=1' "$INIT"
grep -Fq '[ "$tailscale_enabled" = "0" ]; then' "$INIT"
grep -Fq '[ "$outbound_node" != "nil" ] || [ "$tailscale_enabled" = "1" ]; then' "$INIT"
grep -Fq '} else if (tailscale_enabled) {' "$GENERATOR"
grep -A6 '} else if (tailscale_enabled) {' "$GENERATOR" | grep -Fq 'config.route.default_domain_resolver = {'
grep -Fq "config.route.final = 'direct-out';" "$GENERATOR"

if grep -Fq 'set firewall.sbproxy_tszone.masq=' "$HELPER"; then
	echo 'Embedded Tailscale must not enable zone-wide masquerading' >&2
	exit 1
fi

echo 'Embedded Tailscale test passed: migration-safe SBProxy UI, endpoint, routing, status, and scoped SNAT are present'
