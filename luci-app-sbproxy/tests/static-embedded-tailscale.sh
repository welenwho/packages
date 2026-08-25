#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client.js"
GENERATOR="$PACKAGE_ROOT/root/etc/sbproxy/scripts/generate_client.uc"
HELPER="$PACKAGE_ROOT/root/usr/sbin/sbproxy_tailscale_helper"
RPC="$PACKAGE_ROOT/root/usr/share/rpcd/ucode/luci.sbproxy"
ACL="$PACKAGE_ROOT/root/usr/share/rpcd/acl.d/luci-app-sbproxy.json"
MENU="$PACKAGE_ROOT/root/usr/share/luci/menu.d/luci-app-sbproxy.json"
CONFIG="$PACKAGE_ROOT/root/usr/share/sbproxy/defaults/sbproxy"
MIGRATION="$PACKAGE_ROOT/root/etc/uci-defaults/00-luci-sbproxy-migrate"

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
test "$(readlink "$PACKAGE_ROOT/htdocs/luci-static/resources/sbproxy-adaptive-20260825-r1.js")" = \
	'sbproxy-adaptive.js'
test "$(readlink "$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client-20260825-r1.js")" = \
	'client.js'
grep -Fq "type: 'tailscale'" "$GENERATOR"
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
grep -Fq "return { enabled: false, running: false, code: 0, output: 'Disabled' }" "$RPC"

if grep -Fq 'set firewall.sbproxy_tszone.masq=' "$HELPER"; then
	echo 'Embedded Tailscale must not enable zone-wide masquerading' >&2
	exit 1
fi

echo 'Embedded Tailscale test passed: migration-safe SBProxy UI, endpoint, routing, status, and scoped SNAT are present'
