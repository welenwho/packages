/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require dom';
'require form';
'require network';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

'require sbproxy as sb';
'require tools.widgets as widgets';

const callTailscaleStatus = rpc.declare({
	object: 'luci.sbproxy',
	method: 'tailscale_status',
	expect: { '': {} }
});

const callTailscaleLogout = rpc.declare({
	object: 'luci.sbproxy',
	method: 'tailscale_logout',
	expect: { '': {} }
});

const callTailscalePing = rpc.declare({
	object: 'luci.sbproxy',
	method: 'tailscale_ping',
	params: [ 'target' ],
	expect: { '': {} }
});

function ipv4Subnet(address) {
	const parts = (address || '').split('/');
	const cidr = Number(parts[1]);
	const octets = parts[0]?.split('.').map(Number);
	if (parts.length !== 2 || !Number.isInteger(cidr) || cidr < 1 || cidr >= 32 ||
	    octets?.length !== 4 || octets.some(octet => !Number.isInteger(octet) || octet < 0 || octet > 255))
		return null;

	const mask = (0xffffffff << (32 - cidr)) >>> 0;
	const numeric = octets.reduce((value, octet) => ((value << 8) | octet) >>> 0, 0);
	const subnet = (numeric & mask) >>> 0;
	return [ 24, 16, 8, 0 ].map(shift => (subnet >>> shift) & 255).join('.') + '/' + cidr;
}

async function getLocalAdvertiseSubnets() {
	const ignored = [ 'loopback', 'tailscale', 'sbproxy_ts' ];
	const networks = await network.getNetworks();
	const candidates = [], seen = new Set();

	for (const iface of networks) {
		const name = iface.getName();
		if (ignored.includes(name) || /^tailscale\d*$/.test(name) || /^singtun\d*$/.test(name))
			continue;
		for (const address of (iface.getIPAddrs() || [])) {
			const subnet = ipv4Subnet(address);
			if (!subnet || seen.has(subnet) || subnet.startsWith('127.') || subnet.startsWith('169.254.'))
				continue;
			seen.add(subnet);
			candidates.push({ value: subnet, network: name });
		}
	}
	return candidates;
}

function tailscaleStatusRow(label, value) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '32%' }, label),
		E('td', { 'class': 'td left' }, value || '-')
	]);
}

function formatTailscaleBytes(value) {
	const bytes = Number(value);
	return Number.isFinite(bytes) && bytes >= 0 ? '%1024mB'.format(bytes) : '-';
}

function renderTailscaleRouteDiscovery(status) {
	if (status?.peer_routes_available === true)
		return E('span', { 'style': 'color:green' }, _('Available'));
	if (status?.peer_routes_available === false)
		return E('span', {
			'style': 'color:orange',
			'title': status.peer_routes_error || ''
		}, _('Unavailable; configured routes are kept'));
	return '-';
}

function renderTailscaleAccountControl(status) {
	const backendState = status?.backend_state;
	if (backendState === 'Running') {
		const button = E('button', {
			'type': 'button',
			'class': 'btn cbi-button cbi-button-negative'
		}, _('Log out'));
		button.onclick = async function() {
			if (!confirm(_('Are you sure you want to log out of Tailscale on this device?')))
				return;
			button.disabled = true;
			const result = await callTailscaleLogout();
			ui.addNotification(null, E('p', {}, [
				result.code === 0 ? _('Tailscale logged out.') : (result.output || _('Logout failed.'))
			]), result.code === 0 ? 'info' : 'error');
			button.disabled = false;
			if (result.code === 0)
				window.setTimeout(() => window.location.reload(), 500);
		};
		return E('div', {}, [
			E('span', { 'style': 'color:green;margin-right:1rem' }, _('Connected')),
			button
		]);
	}
	if (backendState === 'NeedsLogin') {
		return status?.auth_url && /^https?:\/\//i.test(status.auth_url)
			? E('a', {
				'href': status.auth_url,
				'target': '_blank',
				'rel': 'noreferrer noopener'
			}, _('Open login page'))
			: E('span', { 'style': 'color:orange' }, _('Waiting for login URL'));
	}
	if (backendState === 'NeedsMachineAuth')
		return E('span', { 'style': 'color:orange' }, _('Waiting for machine approval'));
	return _('Not logged in');
}

function formatTailscaleBackendState(status) {
	const backendState = status?.backend_state;
	if (!backendState)
		return status?.enabled ? _('Not running') : _('Disabled');
	switch (backendState) {
	case 'Running':
		return _('Connected');
	case 'NeedsLogin':
	case 'NoState':
		return _('Not logged in');
	case 'NeedsMachineAuth':
		return _('Waiting for machine approval');
	case 'Disabled':
		return _('Disabled');
	default:
		return backendState;
	}
}

function renderTailscaleStatus(status) {
	const selectedExitNode = (status?.exit_nodes || []).find(node => node.selected);
	const interfaceStatus = status?.interface || {};
	const interfaceState = interfaceStatus.present ?
		(interfaceStatus.up ? _('Available') : _('Present but down')) : _('Unavailable');
	const content = [
		E('table', { 'class': 'table' }, [
			tailscaleStatusRow(_('Backend State'), formatTailscaleBackendState(status)),
			tailscaleStatusRow(_('Tailnet'), status?.network_name),
			tailscaleStatusRow(_('Exit Node in Use'), selectedExitNode ?
				`${selectedExitNode.name} (${selectedExitNode.address})` : _('None')),
			tailscaleStatusRow(_('System interface'), interfaceStatus.name),
			tailscaleStatusRow(_('Interface Management'), _('Managed by sing-box')),
			tailscaleStatusRow(_('Interface State'), interfaceState),
			tailscaleStatusRow(_('Tailscale IPv4'), (interfaceStatus.ipv4 || []).join(', ')),
			tailscaleStatusRow(_('Tailscale IPv6'), (interfaceStatus.ipv6 || []).join(', ')),
			tailscaleStatusRow(_('Interface MTU'), interfaceStatus.mtu),
			tailscaleStatusRow(_('Received / Sent'), `${formatTailscaleBytes(interfaceStatus.rx_bytes)} / ${formatTailscaleBytes(interfaceStatus.tx_bytes)}`),
			tailscaleStatusRow(_('Peer Route Discovery'), renderTailscaleRouteDiscovery(status))
		])
	];
	if (status?.enabled && status?.code !== 0) {
		content.push(E('div', { 'class': 'alert-message warning' },
			(status.output || _('Waiting for the embedded backend...')).trim()));
	}
	return E('div', {}, content);
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('sbproxy'),
			sb.getBuiltinFeatures(),
			L.resolveDefault(uci.load('tailscale'), null),
			L.resolveDefault(callTailscaleStatus(), {}),
			L.resolveDefault(getLocalAdvertiseSubnets(), [])
		]);
	},

	render(data) {
		let m, s, o;
		const features = data[1];
		const tailscaleStatus = data[3] || {};
		const standaloneTailscaleEnabled = tailscaleStatus.standalone_installed === true &&
			uci.get('tailscale', 'settings', 'enabled') === '1';
		const configuredExitNode = uci.get(data[0], 'tailscale', 'exit_node') || '';
		const configuredPeerRoutes = L.toArray(uci.get(data[0], 'tailscale', 'subnet_routes'));
		const configuredAdvertiseRoutes = L.toArray(uci.get(data[0], 'tailscale', 'advertise_routes'));
		const localAdvertiseSubnets = data[4] || [];

		m = new form.Map('sbproxy', _('Tailscale'),
			_('Runs Tailscale inside the SBProxy sing-box process. It can run without a proxy node; the independent Tailscale service must be disabled first.'));

		s = m.section(form.NamedSection, 'tailscale', 'sbproxy');
		s.hidetitle = true;
		s.tab('general', _('General Settings'));
		s.tab('routing', _('Routing Settings'));
		s.tab('dns', _('DNS Settings'));
		s.tab('security', _('Security'));
		s.tab('relay', _('Peer Relay'));
		s.tab('authentication', _('Authentication'));
		s.tab('advanced', _('Extra Settings'),
			_('tailscale0 is the standard Tailscale kernel device; sbproxy_ts is the OpenWrt logical interface used by netifd and firewall integration.'));
		s.tab('status', _('Status'));

		o = s.taboption('general', form.Flag, 'enabled', _('Enable embedded Tailscale'),
			_('Runs Tailscale inside the SBProxy sing-box process. It can run without a proxy node; the independent Tailscale service must be disabled first.'));
		o.default = o.disabled;
		o.rmempty = false;
		o.validate = function(sectionId, value) {
			if (value !== '1')
				return true;
			if (!features.with_tailscale)
				return _('The installed sing-box build does not include Tailscale support.');
			if (standaloneTailscaleEnabled)
				return _('Disable the independent Tailscale service before enabling the embedded backend.');
			return true;
		};

		o = s.taboption('general', form.DummyValue, '_account', _('Account'));
		o.depends('enabled', '1');
		o.renderWidget = function() {
			return E('div', { 'id': 'tailscale_account' }, renderTailscaleAccountControl(tailscaleStatus));
		};

		o = s.taboption('general', form.Value, 'hostname', _('Device name'));
		o.depends('enabled', '1');
		o.rmempty = true;

		o = s.taboption('routing', form.Flag, 'accept_routes', _('Accept routes'));
		o.default = o.disabled;
		o.depends('enabled', '1');
		o.rmempty = false;

		o = s.taboption('routing', form.DynamicList, 'subnet_routes', _('Static peer routes'),
			_('Select subnets advertised by peers after login. Custom CIDR values remain supported.'));
		const peerRouteValues = [];
		for (const route of (tailscaleStatus.peer_routes || [])) {
			if (!route.route || peerRouteValues.includes(route.route))
				continue;
			peerRouteValues.push(route.route);
			o.value(route.route, route.route + ' - ' + (route.name || route.address) +
				(route.online ? '' : ' (' + _('peer offline') + ')'));
		}
		for (const route of configuredPeerRoutes) {
			if (!peerRouteValues.includes(route)) {
				peerRouteValues.push(route);
				o.value(route, route + ' (' + (tailscaleStatus.peer_routes_available === true ?
					_('configured; not currently advertised') :
					_('configured; backend status unavailable')) + ')');
			}
		}
		o.datatype = 'or(cidr4,cidr6)';
		o.validate = function(sectionId, value) {
			return !value.endsWith('/0') || _('The default route must be configured as an exit node.');
		};
		o.depends({ enabled: '1', accept_routes: '1' });
		o.rmempty = true;

		o = s.taboption('routing', form.DynamicList, 'advertise_routes', _('Advertise subnets'),
			_('Select local interface subnets to publish. Custom CIDR values remain supported.'));
		const advertiseRouteValues = [];
		for (const route of localAdvertiseSubnets) {
			if (!route.value || advertiseRouteValues.includes(route.value))
				continue;
			advertiseRouteValues.push(route.value);
			o.value(route.value, route.value + ' (' + route.network + ')');
		}
		for (const route of configuredAdvertiseRoutes) {
			if (!advertiseRouteValues.includes(route)) {
				advertiseRouteValues.push(route);
				o.value(route, route + ' (' + _('manually configured; no local interface match') + ')');
			}
		}
		o.datatype = 'or(cidr4,cidr6)';
		o.depends('enabled', '1');
		o.rmempty = true;

		o = s.taboption('routing', form.Flag, 'advertise_exit_node', _('Advertise exit node'));
		o.default = o.disabled;
		o.depends('enabled', '1');
		o.rmempty = false;

		o = s.taboption('routing', form.Flag, 'disable_snat_subnet_routes', _('Preserve subnet source addresses'),
			_('Disable SNAT for traffic forwarded from Tailscale. LAN devices must have a return route to the Tailnet address ranges.'));
		o.default = o.disabled;
		o.depends({ enabled: '1', advertise_exit_node: '0' });
		o.rmempty = false;

		o = s.taboption('routing', form.ListValue, 'exit_node', _('Use exit node'),
			_('Select an online Tailscale exit node.'));
		o.value('', _('None'));
		const exitNodeValues = [];
		for (const node of (tailscaleStatus.exit_nodes || [])) {
			if (!node.address || (!node.online && !node.selected) || exitNodeValues.includes(node.address))
				continue;
			exitNodeValues.push(node.address);
			o.value(node.address, (node.name || node.address) + ' (' + node.address + ')');
		}
		if (configuredExitNode && !exitNodeValues.includes(configuredExitNode)) {
			exitNodeValues.push(configuredExitNode);
			o.value(configuredExitNode, configuredExitNode + ' (' + _('offline or unavailable') + ')');
		}
		o.depends({ enabled: '1', advertise_exit_node: '0' });
		o.default = '';
		o.rmempty = true;

		o = s.taboption('routing', form.Flag, 'exit_node_allow_lan_access', _('Allow LAN access with exit node'),
			_('Keep direct access to local LAN subnets while using an exit node.'));
		o.default = o.disabled;
		o.depends({ enabled: '1', advertise_exit_node: '0', exit_node: /.+/ });
		o.rmempty = false;

		o = s.taboption('routing', form.MultiValue, 'access', _('OpenWrt forwarding'));
		o.value('ts_ac_lan', _('Tailscale access LAN'));
		o.value('ts_ac_wan', _('Tailscale access WAN'));
		o.value('lan_ac_ts', _('LAN access Tailscale'));
		o.value('wan_ac_ts', _('WAN access Tailscale'));
		o.depends('enabled', '1');
		o.rmempty = true;

		o = s.taboption('dns', form.Flag, 'magic_dns', _('Forward MagicDNS'),
			_('Forward Tailnet DNS names through the sing-box Tailscale DNS transport without replacing OpenWrt system DNS.'));
		o.default = o.enabled;
		o.depends('enabled', '1');
		o.rmempty = false;

		o = s.taboption('dns', form.Flag, 'accept_search_domain', _('Accept search domain'));
		o.default = o.enabled;
		o.depends({ enabled: '1', magic_dns: '1' });
		o.rmempty = false;

		o = s.taboption('security', form.Flag, 'ssh_server', _('Tailscale SSH'));
		o.default = o.disabled;
		o.depends('enabled', '1');
		o.rmempty = false;

		o = s.taboption('security', form.Flag, 'ssh_disable_pty', _('Disable SSH PTY'));
		o.default = o.disabled;
		o.depends({ enabled: '1', ssh_server: '1' });
		o.rmempty = false;

		o = s.taboption('security', form.Flag, 'ssh_disable_sftp', _('Disable SFTP'));
		o.default = o.disabled;
		o.depends({ enabled: '1', ssh_server: '1' });
		o.rmempty = false;

		o = s.taboption('security', form.Flag, 'ssh_disable_forwarding', _('Disable SSH forwarding'));
		o.default = o.disabled;
		o.depends({ enabled: '1', ssh_server: '1' });
		o.rmempty = false;

		o = s.taboption('security', form.Flag, 'taildrop_enabled', _('Taildrop'));
		o.default = o.disabled;
		o.depends('enabled', '1');
		o.rmempty = false;

		o = s.taboption('security', form.Value, 'taildrop_directory', _('Taildrop directory'));
		o.default = '/etc/sbproxy/tailscale/Taildrop';
		o.depends({ enabled: '1', taildrop_enabled: '1' });
		o.rmempty = false;
		o.validate = function(sectionId, value) {
			return value?.startsWith('/') ? true : _('Expecting: %s').format(_('absolute path'));
		};

		o = s.taboption('relay', form.Flag, 'relay_server_enabled', _('Enable peer relay'));
		o.default = o.disabled;
		o.depends('enabled', '1');
		o.rmempty = false;

		o = s.taboption('relay', form.Value, 'relay_server_port', _('Peer relay UDP port'));
		o.default = '0';
		o.datatype = 'range(0,65535)';
		o.depends({ enabled: '1', relay_server_enabled: '1' });
		o.rmempty = false;

		o = s.taboption('relay', form.DynamicList, 'relay_server_static_endpoints', _('Static relay endpoints'));
		o.placeholder = '192.0.2.1:40000';
		o.depends({ enabled: '1', relay_server_enabled: '1' });
		o.rmempty = true;

		o = s.taboption('authentication', form.Value, 'control_url', _('Control server'),
			_('Leave blank for the official Tailscale control plane, or enter a Headscale URL.'));
		o.placeholder = 'https://controlplane.tailscale.com';
		o.depends('enabled', '1');
		o.rmempty = true;
		o.validate = function(sectionId, value) {
			if (!value)
				return true;
			try {
				const url = new URL(value);
				return [ 'http:', 'https:' ].includes(url.protocol) && !!url.hostname ? true :
					_('Expecting: %s').format(_('valid URL'));
			} catch (e) {
				return _('Expecting: %s').format(_('valid URL'));
			}
		};

		o = s.taboption('authentication', form.Value, 'auth_key', _('Auth key'));
		o.password = true;
		o.depends('enabled', '1');
		o.rmempty = true;

		o = s.taboption('authentication', form.Value, 'auth_key_file', _('Auth key file'));
		o.placeholder = '/etc/sbproxy/tailscale/auth.key';
		o.depends('enabled', '1');
		o.rmempty = true;
		o.validate = function(sectionId, value) {
			return !value || value.startsWith('/') ? true : _('Expecting: %s').format(_('absolute path'));
		};

		o = s.taboption('authentication', form.Flag, 'ephemeral', _('Ephemeral node'));
		o.default = o.disabled;
		o.depends('enabled', '1');
		o.rmempty = false;

		o = s.taboption('authentication', form.DynamicList, 'advertise_tags', _('ACL tags'));
		o.placeholder = 'tag:router';
		o.depends('enabled', '1');
		o.rmempty = true;

		o = s.taboption('advanced', form.Value, '_ping_target', _('Peer test target'),
			_('Enter a Tailscale IP address, machine name, or MagicDNS name.'));
		o.depends('enabled', '1');
		o.rmempty = true;
		o.validate = function(sectionId, value) {
			return !value || /^[A-Za-z0-9_.:-]+$/.test(value) ? true :
				_('Expecting: %s').format(_('valid host name or IP address'));
		};

		o = s.taboption('advanced', form.Button, '_ping', _('Peer connectivity'));
		o.inputtitle = _('Ping peer');
		o.inputstyle = 'action';
		o.depends('enabled', '1');
		o.onclick = async function(sectionId) {
			const target = this.section.formvalue(sectionId, '_ping_target');
			if (!target) {
				ui.addNotification(null, E('p', {}, _('Enter a peer test target first.')), 'warning');
				return;
			}
			const result = await callTailscalePing(target);
			ui.addNotification(null, E('pre', { 'style': 'white-space:pre-wrap' },
				(result.output || (result.code === 0 ? _('Peer is reachable.') : _('Peer test failed.'))).trim()),
				result.code === 0 ? 'info' : 'error');
		};

		o = s.taboption('advanced', form.Value, 'state_directory', _('State directory'));
		o.default = '/etc/sbproxy/tailscale';
		o.depends('enabled', '1');
		o.rmempty = false;
		o.validate = function(sectionId, value) {
			return value?.startsWith('/') ? true : _('Expecting: %s').format(_('absolute path'));
		};

		o = s.taboption('advanced', form.Value, 'system_interface_name', _('System interface'),
			_('Keep tailscale0 unless another Tailscale-compatible device name is explicitly required.'));
		o.default = 'tailscale0';
		o.depends('enabled', '1');
		o.rmempty = false;
		o.validate = function(sectionId, value) {
			return /^[A-Za-z0-9_.-]+$/.test(value || '') ? true : _('Expecting: %s').format(_('valid interface name'));
		};

		o = s.taboption('advanced', form.Value, 'system_interface_mtu', _('Interface MTU'));
		o.default = '1280';
		o.datatype = 'range(1280,9000)';
		o.depends('enabled', '1');
		o.rmempty = false;

		o = s.taboption('advanced', form.Value, 'listen_port', _('UDP port'));
		o.default = '41641';
		o.datatype = 'port';
		o.depends('enabled', '1');
		o.rmempty = false;

		o = s.taboption('advanced', widgets.DeviceSelect, 'bind_interface', _('Underlay interface'));
		o.multiple = false;
		o.noaliases = true;
		o.depends('enabled', '1');

		o = s.taboption('advanced', form.Value, 'udp_timeout', _('UDP NAT expiration time'));
		o.default = '300';
		o.datatype = 'uinteger';
		o.depends('enabled', '1');
		o.rmempty = false;

		o = s.taboption('status', form.DummyValue, '_status');
		o.render = function() {
			return E('div', { 'id': 'tailscale_status', 'class': 'cbi-section' },
				renderTailscaleStatus(tailscaleStatus));
		};

		poll.add(function() {
			return L.resolveDefault(callTailscaleStatus(), {}).then((status) => {
				const account = document.getElementById('tailscale_account');
				const statusView = document.getElementById('tailscale_status');
				if (account)
					dom.content(account, renderTailscaleAccountControl(status));
				if (statusView)
					dom.content(statusView, renderTailscaleStatus(status));
			});
		});

		return m.render();
	}
});
