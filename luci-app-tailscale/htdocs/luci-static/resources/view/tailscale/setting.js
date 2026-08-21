/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Copyright (C) 2024 asvow
 * Copyright (C) 2026 welenwho/packages contributors
 */

'use strict';
'require dom';
'require form';
'require network';
'require poll';
'require rpc';
'require uci';
'require view';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

const callTailscaleStatus = rpc.declare({
	object: 'luci.tailscale',
	method: 'summary',
	expect: { '': {} }
});

const callTailscaleLogout = rpc.declare({
	object: 'luci.tailscale',
	method: 'logout',
	expect: { '': {} }
});

async function getInterfaceSubnets(interfaces = [ 'lan', 'wan' ]) {
	const networks = await network.getNetworks();
	return [ ...new Set(networks
		.filter(ifc => interfaces.includes(ifc.getName()))
		.flatMap(ifc => ifc.getIPAddrs())
		.filter(addr => addr.includes('/') && !addr.includes(':'))
		.map(addr => {
			const [ ip, cidrValue ] = addr.split('/');
			const cidr = Number(cidrValue);
			const ipParts = ip.split('.').map(Number);
			const mask = cidr === 0 ? 0 : (0xffffffff << (32 - cidr));
			const subnetParts = ipParts.map((part, i) => (part & (mask >>> (24 - i * 8))) & 255);
			return `${subnetParts.join('.')}/${cidr}`;
		})) ];
}

async function getStatus() {
	const result = {
		isRunning: false,
		backendState: undefined,
		authURL: undefined,
		displayName: undefined,
		onlineExitNodes: [],
		subnetRoutes: []
	};
	const [ service, data ] = await Promise.all([
		callServiceList('tailscale'),
		callTailscaleStatus()
	]);
	const instances = service?.tailscale?.instances || {};
	result.isRunning = instances.daemon?.running === true;

	const status = data?.status;
	if (!status)
		return result;

	result.isRunning ||= status.BackendState === 'Running';
	result.backendState = status.BackendState;
	result.authURL = status.AuthURL;
	result.displayName = status.CurrentTailnet?.Name || status.User?.[status.Self?.UserID]?.DisplayName;
	for (const peer of Object.values(status.Peer || {})) {
		if (peer.ExitNodeOption && peer.Online && peer.TailscaleIPs?.[0]) {
			result.onlineExitNodes.push({
				value: peer.TailscaleIPs[0],
				label: `${peer.HostName || peer.DNSName || peer.TailscaleIPs[0]} (${peer.TailscaleIPs[0]})`
			});
		}
		for (const route of (peer.PrimaryRoutes || []))
			result.subnetRoutes.push(route);
	}
	result.subnetRoutes = [ ...new Set(result.subnetRoutes) ];
	return result;
}

function renderStatus(isRunning) {
	const colour = isRunning ? 'green' : 'red';
	const state = isRunning ? _('RUNNING') : _('NOT RUNNING');
	return E('em', {}, E('span', { style: `color:${colour}` },
		E('strong', {}, `${_('Tailscale')} ${state}`)));
}

function renderLogin(loginStatus, authURL, displayName) {
	if (loginStatus === 'NeedsLogin') {
		return authURL && /^https?:\/\//i.test(authURL)
			? E('a', { href: authURL, target: '_blank', rel: 'noreferrer noopener' }, _('Need to log in'))
			: E('span', { style: 'color:orange' }, _('Waiting for login URL'));
	}
	if (loginStatus === 'NeedsMachineAuth')
		return E('span', { style: 'color:orange' }, _('Waiting for machine approval'));
	if (loginStatus === 'Running') {
		return E('div', {}, [
			E('a', { href: 'https://login.tailscale.com/admin/machines', target: '_blank', rel: 'noreferrer noopener' }, displayName || _('Connected')),
			E('br'),
			E('button', { type: 'button', class: 'btn cbi-button cbi-button-negative', id: 'logout_button' }, _('Log out and Unbind'))
		]);
	}
	return E('span', { style: 'color:orange' }, loginStatus || _('NOT RUNNING'));
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('tailscale'),
			getStatus(),
			getInterfaceSubnets()
		]);
	},

	render(data) {
		let m, s, o;
		const statusData = data[1];
		const interfaceSubnets = data[2];
		const configuredExitNode = uci.get('tailscale', 'settings', 'exit_node') || '';

		m = new form.Map('tailscale', _('Tailscale'), _('Tailscale is a cross-platform and easy to use virtual LAN.'));

		s = m.section(form.TypedSection);
		s.anonymous = true;
		s.render = function() {
			poll.add(async () => {
				const res = await getStatus();
				const serviceView = document.getElementById('service_status');
				const loginView = document.getElementById('login_status_div');
				if (serviceView)
					dom.content(serviceView, renderStatus(res.isRunning));
				if (loginView)
					dom.content(loginView, renderLogin(res.backendState, res.authURL, res.displayName));
				const logoutButton = document.getElementById('logout_button');
				if (logoutButton) {
					logoutButton.onclick = async () => {
						if (confirm(_('Are you sure you want to log out and unbind the current device?')))
							await callTailscaleLogout();
					};
				}
			});

			return E('div', { class: 'cbi-section', id: 'status_bar' }, [
				E('p', { id: 'service_status' }, renderStatus(statusData.isRunning))
			]);
		};

		s = m.section(form.NamedSection, 'settings', 'config');
		s.tab('basic', _('Basic Settings'));
		s.tab('routing', _('Routing'));
		s.tab('security', _('Security'));
		s.tab('relay', _('Peer Relay'));
		s.tab('authentication', _('Authentication'));
		s.tab('extra', _('Extra Settings'));

		o = s.taboption('basic', form.Flag, 'enabled', _('Enable'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('basic', form.DummyValue, 'login_status', _('Login Status'));
		o.depends('enabled', '1');
		o.renderWidget = function() {
			return E('div', { id: 'login_status_div' }, renderLogin(statusData.backendState, statusData.authURL, statusData.displayName));
		};

		o = s.taboption('basic', form.Value, 'port', _('UDP Port'), _('Listening port for direct Tailscale connections.'));
		o.datatype = 'port';
		o.default = '41641';
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'config_path', _('State Directory'), _('Directory containing the persistent tailscaled state file.'));
		o.default = '/etc/tailscale';
		o.rmempty = false;
		o.validate = function(sectionId, value) {
			return value?.startsWith('/') ? true : _('The state directory must be an absolute path.');
		};

		o = s.taboption('basic', form.ListValue, 'fw_mode', _('Firewall Backend'), _('Select the firewall implementation used internally by tailscaled.'));
		o.value('auto', _('Auto'));
		o.value('nftables', 'nftables');
		o.value('iptables', 'iptables');
		o.default = 'auto';
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'hostname', _('Device Name'), _("Leave blank to use the device's hostname."));
		o.rmempty = true;

		o = s.taboption('basic', form.Flag, 'accept_dns', _('Accept DNS'), _('Accept DNS configuration from the Tailscale admin console.'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.taboption('basic', form.Flag, 'report_posture', _('Device Posture Reporting'), _('Allow the management plane to gather device posture information.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('basic', form.Flag, 'log_stdout', _('StdOut Log'), _('Logging program activities.'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.taboption('basic', form.Flag, 'log_stderr', _('StdErr Log'), _('Logging program errors and exceptions.'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.taboption('routing', form.Flag, 'accept_routes', _('Accept Routes'), _('Accept subnet routes that other nodes advertise.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('routing', form.Flag, 'advertise_exit_node', _('Advertise Exit Node'), _('Offer this device as an exit node for the tailnet.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('routing', form.ListValue, 'exit_node', _('Use Exit Node'), _('Select a specific online exit node or let Tailscale choose automatically.'));
		o.value('', _('None'));
		o.value('auto:any', _('Automatic (any)'));
		for (const node of statusData.onlineExitNodes)
			o.value(node.value, node.label);
		if (configuredExitNode && configuredExitNode !== 'auto:any' && !statusData.onlineExitNodes.some(node => node.value === configuredExitNode))
			o.value(configuredExitNode, `${configuredExitNode} (${_('offline or unavailable')})`);
		o.default = '';
		o.depends('advertise_exit_node', '0');
		o.rmempty = true;

		o = s.taboption('routing', form.Flag, 'exit_node_allow_lan_access', _('Allow LAN Access with Exit Node'), _('Keep direct access to local LAN subnets while using an exit node.'));
		o.default = o.disabled;
		o.depends({ advertise_exit_node: '0', exit_node: 'auto:any' });
		for (const node of statusData.onlineExitNodes)
			o.depends({ advertise_exit_node: '0', exit_node: node.value });
		if (configuredExitNode && configuredExitNode !== 'auto:any')
			o.depends({ advertise_exit_node: '0', exit_node: configuredExitNode });
		o.rmempty = false;

		o = s.taboption('routing', form.DynamicList, 'advertise_routes', _('Advertise Subnets'), _('Expose physical network routes into Tailscale, e.g. <code>10.0.0.0/8</code>.'));
		for (const subnet of interfaceSubnets)
			o.value(subnet, subnet);
		o.datatype = 'cidr';
		o.rmempty = true;

		o = s.taboption('routing', form.Flag, 'disable_snat_subnet_routes', _('Site To Site'), _('Disable source NAT for advertised subnet routes.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('routing', form.DynamicList, 'subnet_routes', _('Static Peer Routes'), _('Install explicit OpenWrt routes through tailscale0 for selected peer subnets.'));
		for (const route of statusData.subnetRoutes)
			o.value(route, route);
		o.datatype = 'cidr';
		o.depends('accept_routes', '1');
		o.rmempty = true;

		o = s.taboption('routing', form.Flag, 'advertise_connector', _('App Connector'), _('Offer this device as an app connector for domain-specific routes.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('routing', form.MultiValue, 'access', _('OpenWrt Forwarding'));
		o.value('ts_ac_lan', _('Tailscale access LAN'));
		o.value('ts_ac_wan', _('Tailscale access WAN'));
		o.value('lan_ac_ts', _('LAN access Tailscale'));
		o.value('wan_ac_ts', _('WAN access Tailscale'));
		o.default = 'ts_ac_lan ts_ac_wan lan_ac_ts';
		o.rmempty = true;

		o = s.taboption('security', form.ListValue, 'netfilter_mode', _('Netfilter Mode'), _('Control how Tailscale installs packet-filtering rules.'));
		o.value('on', _('On'));
		o.value('nodivert', _('No divert'));
		o.value('off', _('Off'));
		o.default = 'on';
		o.rmempty = false;

		o = s.taboption('security', form.Flag, 'stateful_filtering', _('Stateful Filtering'), _('Apply stateful filtering to packets forwarded by this router.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('security', form.Flag, 'shields_up', _('Shields Up'), _('Block incoming Tailscale connections to this device.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('security', form.Flag, 'tailscale_ssh', _('Tailscale SSH'), _('Run the Tailscale SSH server. Ensure it does not conflict with Dropbear on tailscale0 port 22.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('relay', form.Flag, 'relay_server_enabled', _('Enable Peer Relay'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('relay', form.Value, 'relay_server_port', _('Relay UDP Port'), _('Use 0 to let Tailscale select a random available port.'));
		o.datatype = 'range(0,65535)';
		o.default = '0';
		o.depends('relay_server_enabled', '1');
		o.rmempty = false;

		o = s.taboption('relay', form.DynamicList, 'relay_server_static_endpoints', _('Static Relay Endpoints'), _('Public IP:port endpoints advertised to relay clients.'));
		o.depends('relay_server_enabled', '1');
		o.rmempty = true;
		o.validate = function(sectionId, value) {
			return !value || /^(?:[0-9.]+|\[[0-9A-Fa-f:]+\]):[0-9]+$/.test(value)
				? true : _('Use IPv4:port or [IPv6]:port format.');
		};

		o = s.taboption('authentication', form.Value, 'login_server', _('Control Server'), _('Changes apply on the next login.'));
		o.placeholder = 'https://controlplane.tailscale.com';
		o.rmempty = true;

		o = s.taboption('authentication', form.Value, 'authkey', _('Auth Key'), _('Used only while registering a logged-out node.'));
		o.password = true;
		o.rmempty = true;

		o = s.taboption('authentication', form.Value, 'auth_key_file', _('Auth Key File'), _('Absolute path to a file containing the authentication key. This takes precedence over Auth Key.'));
		o.placeholder = '/etc/tailscale/auth.key';
		o.rmempty = true;
		o.validate = function(sectionId, value) {
			return !value || value.startsWith('/') ? true : _('The auth key file must use an absolute path.');
		};

		o = s.taboption('authentication', form.DynamicList, 'advertise_tags', _('ACL Tags'), _('Registration tags such as <code>tag:router</code>. Changes apply on the next login.'));
		o.placeholder = 'tag:router';
		o.rmempty = true;
		o.validate = function(sectionId, value) {
			return !value || /^tag:[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value)
				? true : _('Tags must use the tag:name format.');
		};

		o = s.taboption('extra', form.Value, 'wg_batch_size', _('WireGuard Batch Size'),
			_('Controls Linux packet batching. Smaller values reduce memory usage but may lower throughput.'));
		o.value('', _('Default (128)'));
		for (const size of [ 1, 8, 16, 32, 64, 128 ])
			o.value(String(size));
		o.datatype = 'range(1,128)';
		o.default = '';
		o.rmempty = true;

		o = s.taboption('extra', form.DynamicList, 'flags', _('Additional Login Flags'),
		String.format(_('Compatibility flags used only during initial login. Prefer the dedicated settings above. See %s.'),
			'<a href="https://tailscale.com/kb/1241/tailscale-up" target="_blank" rel="noreferrer noopener">' + _('tailscale up flags') + '</a>'));
		o.rmempty = true;

		return m.render();
	}
});
