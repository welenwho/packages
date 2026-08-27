#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client.js"
TAILSCALE="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/tailscale.js"

tailscale_form="$(cat "$TAILSCALE")"

printf '%s\n' "$tailscale_form" | grep -Fq 's.hidetitle = true;'
if grep -Fq "s.tab('tailscale'" "$CLIENT"; then
	echo 'Client settings must not contain a nested Tailscale tab' >&2
	exit 1
fi

for tab in general routing dns security relay authentication advanced status; do
	test "$(printf '%s\n' "$tailscale_form" | grep -Fc "s.tab('$tab'")" -eq 1
done

test "$(printf '%s\n' "$tailscale_form" | grep -Fc 's.tab(')" -eq 8

previous_line=0
for tab in general routing dns security relay authentication advanced status; do
	current_line="$(printf '%s\n' "$tailscale_form" | grep -n "s.tab('$tab'" | head -n1 | cut -d: -f1)"
	test "$current_line" -gt "$previous_line"
	previous_line="$current_line"
done

if printf '%s\n' "$tailscale_form" | grep -Fq 's.option('; then
	echo 'Tailscale fields must use taboption()' >&2
	exit 1
fi

printf '%s\n' "$tailscale_form" | grep -Eq "s\.taboption\('status', [^,]+, '_status'"
printf '%s\n' "$tailscale_form" | grep -Fq 'o.render = function()'

for field in enabled _account hostname; do
	printf '%s\n' "$tailscale_form" | grep -Eq "s\.taboption\('general', [^,]+, '$field'"
done
enabled_line="$(printf '%s\n' "$tailscale_form" | grep -n "form.Flag, 'enabled'" | head -n1 | cut -d: -f1)"
account_line="$(printf '%s\n' "$tailscale_form" | grep -n "form.DummyValue, '_account'" | head -n1 | cut -d: -f1)"
hostname_line="$(printf '%s\n' "$tailscale_form" | grep -n "form.Value, 'hostname'" | head -n1 | cut -d: -f1)"
test "$enabled_line" -lt "$account_line"
test "$account_line" -lt "$hostname_line"
printf '%s\n' "$tailscale_form" | grep -Fq 'renderTailscaleAccountControl(tailscaleStatus)'
printf '%s\n' "$tailscale_form" | grep -Fq 'https://login.tailscale.com/admin/machines'
printf '%s\n' "$tailscale_form" | grep -Fq "status?.self?.user || status?.network_name"

status_renderer="$(sed -n '/^function renderTailscaleStatus(status)/,/^return view.extend/p' "$TAILSCALE")"
if printf '%s\n' "$status_renderer" | grep -Eq 'renderTailscaleAccount|callTailscaleLogout|<button|<a'; then
	echo 'Embedded Tailscale status must remain read-only' >&2
	exit 1
fi
printf '%s\n' "$tailscale_form" | grep -Fq "interfaceStatus.up ? _('Available')"
for section in 'Node Overview' 'Health Status' 'Interface' 'Route Status' 'Peers'; do
	printf '%s\n' "$tailscale_form" | grep -Fq "_('$section')"
done
printf '%s\n' "$tailscale_form" | grep -Fq 'showTailscalePeerDetails'
printf '%s\n' "$tailscale_form" | grep -Fq 'probeTailscalePeerPath'

for field in accept_routes subnet_routes advertise_routes advertise_exit_node disable_snat_subnet_routes exit_node exit_node_allow_lan_access access; do
	printf '%s\n' "$tailscale_form" | grep -Eq "s\.taboption\('routing', [^,]+, '$field'"
done
printf '%s\n' "$tailscale_form" | grep -Fq "s.taboption('routing', form.ListValue, 'exit_node'"
printf '%s\n' "$tailscale_form" | grep -Fq "exit_node: /.+/"
printf '%s\n' "$tailscale_form" | grep -Fq "tailscaleStatus.peer_routes"
printf '%s\n' "$tailscale_form" | grep -Fq "localAdvertiseSubnets"
printf '%s\n' "$tailscale_form" | grep -Fq "configuredPeerRoutes"
printf '%s\n' "$tailscale_form" | grep -Fq "configuredAdvertiseRoutes"
printf '%s\n' "$tailscale_form" | grep -Fq "o.value(route.route, route.route)"
printf '%s\n' "$tailscale_form" | grep -Fq "o.value(route.value, route.value)"
printf '%s\n' "$tailscale_form" | grep -Fq "o.depends({ enabled: '1', advertise_exit_node: '0' });"
if printf '%s\n' "$tailscale_form" | grep -Fq "this.section.formvalue(sectionId, 'advertise_exit_node')"; then
	echo 'Embedded Tailscale flags must not use cross-validation through a nested SectionValue' >&2
	exit 1
fi

for field in magic_dns accept_search_domain; do
	printf '%s\n' "$tailscale_form" | grep -Eq "s\.taboption\('dns', [^,]+, '$field'"
done

for field in ssh_server ssh_disable_pty ssh_disable_sftp ssh_disable_forwarding taildrop_enabled taildrop_directory; do
	printf '%s\n' "$tailscale_form" | grep -Eq "s\.taboption\('security', [^,]+, '$field'"
done

for field in relay_server_enabled relay_server_port relay_server_static_endpoints; do
	printf '%s\n' "$tailscale_form" | grep -Eq "s\.taboption\('relay', [^,]+, '$field'"
done

for field in control_url auth_key auth_key_file ephemeral advertise_tags; do
	printf '%s\n' "$tailscale_form" | grep -Eq "s\.taboption\('authentication', [^,]+, '$field'"
done
for field in _ping_target _ping state_directory system_interface_name system_interface_mtu listen_port bind_interface udp_timeout; do
	printf '%s\n' "$tailscale_form" | grep -Eq "s\.taboption\('advanced', [^,]+, '$field'"
done

echo 'Tailscale tabs test passed: settings lead, account actions stay in general, and trailing status is read-only'
