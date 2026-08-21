/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Copyright (C) 2022 ImmortalWrt.org
 * Copyright (C) 2024 asvow
 * Copyright (C) 2026 welenwho/packages contributors
 */

'use strict';
'require dom';
'require poll';
'require rpc';
'require view';

const callStatus = rpc.declare({
	object: 'luci.tailscale',
	method: 'status',
	expect: { '': {} }
});

function formatBytes(value) {
	const bytes = Number(value || 0);
	if (bytes < 1024)
		return `${bytes} B`;
	return '%1024mB'.format(bytes);
}

function valueOrDash(value) {
	if (Array.isArray(value))
		return value.length ? value.join(', ') : '-';
	return value === undefined || value === null || value === '' ? '-' : String(value);
}

function yesNo(value) {
	if (value === true)
		return _('Yes');
	if (value === false)
		return _('No');
	return '-';
}

function row(label, value) {
	return E('tr', { class: 'tr' }, [
		E('td', { class: 'td left', width: '32%' }, label),
		E('td', { class: 'td left' }, valueOrDash(value))
	]);
}

function section(title, content) {
	return E('div', { class: 'cbi-section' }, [
		E('h3', {}, title),
		content
	]);
}

function connectionPath(peer) {
	if (peer.CurAddr)
		return String.format(_('Direct: %s'), peer.CurAddr);
	if (peer.PeerRelay)
		return String.format(_('Peer Relay: %s'), peer.PeerRelay);
	if (peer.Relay)
		return String.format(_('DERP: %s'), peer.Relay);
	return '-';
}

function peerState(peer) {
	if (!peer.Online)
		return _('Offline');
	return peer.Active ? _('Active') : _('Online');
}

return view.extend({
	load() {
		return callStatus();
	},

	pollData(container) {
		poll.add(async () => {
			const data = await callStatus();
			dom.content(container, this.renderContent(data));
		});
	},

	renderOverview(status, prefs) {
		const self = status.Self || {};
		const selectedExitNode = Object.values(status.Peer || {}).find(peer => peer.ExitNode);
		const exitNode = status.ExitNodeStatus?.TailscaleIPs?.[0] || selectedExitNode?.HostName || _('None');
		return E('table', { class: 'table' }, [
			row(_('Backend State'), status.BackendState),
			row(_('Version'), status.Version),
			row(_('Tailnet'), status.CurrentTailnet?.Name),
			row(_('Hostname'), self.HostName),
			row(_('DNS Name'), self.DNSName),
			row(_('Tailscale Addresses'), self.TailscaleIPs || status.TailscaleIPs),
			row(_('MagicDNS Suffix'), status.MagicDNSSuffix),
			row(_('Home Relay'), self.Relay),
			row(_('Exit Node in Use'), exitNode),
			row(_('Advertised Routes'), prefs?.AdvertiseRoutes || self.PrimaryRoutes),
			row(_('ACL Tags'), prefs?.AdvertiseTags),
			row(_('Update Checks'), yesNo(prefs?.AutoUpdate?.Check)),
			row(_('Automatic Updates'), yesNo(prefs?.AutoUpdate?.Apply)),
			row(_('Native Web Client'), yesNo(prefs?.RunWebClient))
		]);
	},

	renderInterfaces(interfaces) {
		const tailscaleInterfaces = (interfaces || []).filter(iface => /^tailscale[0-9]+$/.test(iface.ifname));
		if (!tailscaleInterfaces.length)
			return E('em', {}, _('No interface online.'));

		const rows = [
			E('tr', { class: 'tr table-titles' }, [
				E('th', { class: 'th' }, _('Interface')),
				E('th', { class: 'th' }, _('Addresses')),
				E('th', { class: 'th' }, _('MTU')),
				E('th', { class: 'th' }, _('Received')),
				E('th', { class: 'th' }, _('Sent'))
			])
		];
		for (const iface of tailscaleInterfaces) {
			rows.push(E('tr', { class: 'tr' }, [
				E('td', { class: 'td' }, iface.ifname),
				E('td', { class: 'td' }, (iface.addr_info || []).map(addr => addr.local).join(', ') || '-'),
				E('td', { class: 'td' }, iface.mtu),
				E('td', { class: 'td' }, formatBytes(iface.stats64?.rx?.bytes)),
				E('td', { class: 'td' }, formatBytes(iface.stats64?.tx?.bytes))
			]));
		}
		return E('table', { class: 'table' }, rows);
	},

	renderRoutes(status, prefs) {
		const peers = Object.values(status.Peer || {}).filter(peer => (peer.PrimaryRoutes || []).length);
		if (!peers.length)
			return E('em', {}, _('No peer routes advertised.'));

		const rows = [ E('tr', { class: 'tr table-titles' }, [
			E('th', { class: 'th' }, _('Peer')),
			E('th', { class: 'th' }, _('Routes')),
			E('th', { class: 'th' }, _('State')),
			E('th', { class: 'th' }, _('Accepted'))
		]) ];
		for (const peer of peers) {
			rows.push(E('tr', { class: 'tr' }, [
				E('td', { class: 'td' }, peer.HostName || peer.DNSName),
				E('td', { class: 'td' }, peer.PrimaryRoutes.join(', ')),
				E('td', { class: 'td' }, peerState(peer)),
				E('td', { class: 'td' }, prefs?.RouteAll ? _('Yes') : _('No'))
			]));
		}
		return E('table', { class: 'table' }, rows);
	},

	renderPeers(status) {
		const peers = Object.values(status.Peer || {}).sort((a, b) => {
			if (a.Online !== b.Online)
				return a.Online ? -1 : 1;
			return (a.HostName || '').localeCompare(b.HostName || '');
		});
		if (!peers.length)
			return E('em', {}, _('No peers found.'));

		const rows = [ E('tr', { class: 'tr table-titles' }, [
			E('th', { class: 'th' }, _('Peer')),
			E('th', { class: 'th' }, _('Tailscale IP')),
			E('th', { class: 'th' }, _('OS')),
			E('th', { class: 'th' }, _('State')),
			E('th', { class: 'th' }, _('Connection')),
			E('th', { class: 'th' }, _('Traffic')),
			E('th', { class: 'th' }, _('Exit Node'))
		]) ];
		for (const peer of peers) {
			rows.push(E('tr', { class: 'tr' }, [
				E('td', { class: 'td' }, peer.HostName || peer.DNSName || '-'),
				E('td', { class: 'td' }, peer.TailscaleIPs?.[0] || '-'),
				E('td', { class: 'td' }, peer.OS || '-'),
				E('td', { class: 'td' }, peerState(peer)),
				E('td', { class: 'td' }, connectionPath(peer)),
				E('td', { class: 'td' }, `${formatBytes(peer.RxBytes)} / ${formatBytes(peer.TxBytes)}`),
				E('td', { class: 'td' }, peer.ExitNode ? _('In use') : (peer.ExitNodeOption ? _('Available') : '-'))
			]));
		}
		return E('div', { style: 'overflow-x:auto' }, E('table', { class: 'table' }, rows));
	},

	renderHealth(health) {
		if (!Array.isArray(health) || !health.length)
			return E('span', { style: 'color:green' }, _('No health warnings.'));
		return E('ul', {}, health.map(message => E('li', {}, message)));
	},

	renderContent(data) {
		const status = data?.status;
		if (!status) {
			return E('div', { class: 'alert-message warning' },
				_('Unable to read Tailscale status. Verify that the service is enabled and running.'));
		}

		const content = [
			section(_('Node Overview'), this.renderOverview(status, data.prefs)),
			section(_('Health'), this.renderHealth(status.Health)),
			section(_('Interfaces'), this.renderInterfaces(data.interfaces)),
			section(_('Route Status'), this.renderRoutes(status, data.prefs)),
			section(_('Peers'), this.renderPeers(status))
		];
		if (data.app_connector && !/not (?:enabled|configured)/i.test(data.app_connector)) {
			content.push(section(_('App Connector Routes'),
				E('pre', { style: 'max-height:20rem;overflow:auto' }, data.app_connector)));
		}
		return E([], content);
	},

	render(data) {
		const content = E([], [
			E('h2', {}, _('Tailscale Status')),
			E('div')
		]);
		const container = content.lastElementChild;
		dom.content(container, this.renderContent(data));
		this.pollData(container);
		return content;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
