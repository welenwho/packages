#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client.js"

tailscale_form="$(sed -n '/Embedded Tailscale start/,/Embedded Tailscale end/p' "$CLIENT")"

printf '%s\n' "$tailscale_form" | grep -Fq 'ss.hidetitle = true;'

for tab in general routing dns security relay authentication advanced status; do
	test "$(printf '%s\n' "$tailscale_form" | grep -Fc "ss.tab('$tab'")" -eq 1
done

test "$(printf '%s\n' "$tailscale_form" | grep -Fc 'ss.tab(')" -eq 8

previous_line=0
for tab in general routing dns security relay authentication advanced status; do
	current_line="$(printf '%s\n' "$tailscale_form" | grep -n "ss.tab('$tab'" | head -n1 | cut -d: -f1)"
	test "$current_line" -gt "$previous_line"
	previous_line="$current_line"
done

if printf '%s\n' "$tailscale_form" | grep -Fq 'ss.option('; then
	echo 'Embedded Tailscale fields must use taboption()' >&2
	exit 1
fi

printf '%s\n' "$tailscale_form" | grep -Eq "ss\.taboption\('status', [^,]+, '_status'"
printf '%s\n' "$tailscale_form" | grep -Fq 'so.render = function()'

for field in enabled _account hostname; do
	printf '%s\n' "$tailscale_form" | grep -Eq "ss\.taboption\('general', [^,]+, '$field'"
done
enabled_line="$(printf '%s\n' "$tailscale_form" | grep -n "form.Flag, 'enabled'" | head -n1 | cut -d: -f1)"
account_line="$(printf '%s\n' "$tailscale_form" | grep -n "form.DummyValue, '_account'" | head -n1 | cut -d: -f1)"
hostname_line="$(printf '%s\n' "$tailscale_form" | grep -n "form.Value, 'hostname'" | head -n1 | cut -d: -f1)"
test "$enabled_line" -lt "$account_line"
test "$account_line" -lt "$hostname_line"
printf '%s\n' "$tailscale_form" | grep -Fq 'renderTailscaleAccountControl(tailscaleStatus)'

status_renderer="$(sed -n '/^function renderTailscaleStatus(status)/,/^function renderStatus(/p' "$CLIENT")"
if printf '%s\n' "$status_renderer" | grep -Eq 'renderTailscaleAccount|callTailscaleLogout|<button|<a'; then
	echo 'Embedded Tailscale status must remain read-only' >&2
	exit 1
fi
printf '%s\n' "$status_renderer" | grep -Fq "interfaceStatus.up ? _('Available')"

for field in accept_routes subnet_routes advertise_routes advertise_exit_node disable_snat_subnet_routes exit_node exit_node_allow_lan_access access; do
	printf '%s\n' "$tailscale_form" | grep -Eq "ss\.taboption\('routing', [^,]+, '$field'"
done
printf '%s\n' "$tailscale_form" | grep -Fq "ss.taboption('routing', form.ListValue, 'exit_node'"
printf '%s\n' "$tailscale_form" | grep -Fq "exit_node: /.+/"
printf '%s\n' "$tailscale_form" | grep -Fq "tailscaleStatus.peer_routes"
printf '%s\n' "$tailscale_form" | grep -Fq "tailscaleStatus.peer_routes_available"
printf '%s\n' "$tailscale_form" | grep -Fq "localAdvertiseSubnets"
printf '%s\n' "$tailscale_form" | grep -Fq "configuredPeerRoutes"
printf '%s\n' "$tailscale_form" | grep -Fq "configuredAdvertiseRoutes"
printf '%s\n' "$tailscale_form" | grep -Fq "configured; backend status unavailable"
printf '%s\n' "$tailscale_form" | grep -Fq "configured; not currently advertised"
printf '%s\n' "$tailscale_form" | grep -Fq "manually configured; no local interface match"
printf '%s\n' "$tailscale_form" | grep -Fq "peer offline"
printf '%s\n' "$tailscale_form" | grep -Fq "so.depends({ enabled: '1', advertise_exit_node: '0' });"
if printf '%s\n' "$tailscale_form" | grep -Fq "this.section.formvalue(sectionId, 'advertise_exit_node')"; then
	echo 'Embedded Tailscale flags must not use cross-validation through a nested SectionValue' >&2
	exit 1
fi

for field in magic_dns accept_search_domain; do
	printf '%s\n' "$tailscale_form" | grep -Eq "ss\.taboption\('dns', [^,]+, '$field'"
done

for field in ssh_server ssh_disable_pty ssh_disable_sftp ssh_disable_forwarding taildrop_enabled taildrop_directory; do
	printf '%s\n' "$tailscale_form" | grep -Eq "ss\.taboption\('security', [^,]+, '$field'"
done

for field in relay_server_enabled relay_server_port relay_server_static_endpoints; do
	printf '%s\n' "$tailscale_form" | grep -Eq "ss\.taboption\('relay', [^,]+, '$field'"
done

for field in control_url auth_key auth_key_file ephemeral advertise_tags; do
	printf '%s\n' "$tailscale_form" | grep -Eq "ss\.taboption\('authentication', [^,]+, '$field'"
done
for field in _ping_target _ping state_directory system_interface_name system_interface_mtu listen_port bind_interface udp_timeout; do
	printf '%s\n' "$tailscale_form" | grep -Eq "ss\.taboption\('advanced', [^,]+, '$field'"
done

echo 'Tailscale tabs test passed: settings lead, account actions stay in general, and trailing status is read-only'
