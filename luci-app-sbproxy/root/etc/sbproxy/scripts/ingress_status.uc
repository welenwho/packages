#!/usr/bin/ucode
import { cursor } from 'uci';
import { connect } from 'ubus';
import { readfile, lstat, popen } from 'fs';
import { ingressEnabled, ingressDevices, ingressNft } from 'ingress';

const config_dir = getenv('SBPROXY_UCI_CONFIG_DIR');
const uci = config_dir ? cursor(config_dir) : cursor();
const control = uci.get_all('sbproxy', 'control') || {};
function list(value) { return type(value) === 'array' ? value : (value ? [value] : []); }
function table(family) {
	const fd = popen('nft -j list table ' + family + ' sbproxy_ingress 2>/dev/null', 'r');
	if (!fd) return null;
	const output = fd.read('all');
	const code = fd.close();
	if (code) return null;
	try { return json(output); } catch(e) { return null; }
}
function count(data, chain) {
	let packets = 0;
	for (let entry in data?.nftables || [])
		if (entry.rule?.chain === chain)
			for (let expression in entry.rule.expr || []) packets += expression.counter?.packets || 0;
	return packets;
}
let status = { enabled: !!ingressEnabled(control), active: !!lstat('/var/run/sbproxy/ingress.active'),
	applied: false, sources: [], last_applied: int(trim(readfile('/var/run/sbproxy/ingress.applied_at') || '0')),
	last_error: substr(trim(readfile('/var/run/sbproxy/ingress.error') || ''), 0, 2048) };
try {
	const selected_wifi = list(control.ingress_bypass_wifi);
	let wireless = {};
	if (length(selected_wifi)) {
		wireless = connect()?.call('network.wireless', 'status', {});
		if (!wireless) status.error = 'Wireless status is unavailable';
	}
	// Validate device names before using them as sysfs paths.
	ingressDevices(control, wireless);
	function append(kind, id, label, device) {
		const present = device && !!lstat('/sys/class/net/' + device);
		const state = present ? trim(readfile('/sys/class/net/' + device + '/operstate') || '') : '';
		push(status.sources, { kind, id, label, device, present: !!present, online: state === 'up' || state === 'unknown' });
	}
	for (let dev in list(control.ingress_bypass_devices)) append('device', dev, dev, dev);
	for (let section in selected_wifi) {
		let found = false;
		const label = (uci.get('wireless', section, 'ssid') || section) + ' (' + section + ')';
		for (let radio, details in wireless || {})
			for (let iface in details.interfaces || [])
				if (iface.section === section && iface.ifname) { append('wifi', section, label, iface.ifname); found = true; }
		if (!found) append('wifi', section, label, null);
	}
	const bridge = table('bridge'), inet = table('inet');
	const expected = status.enabled ? ingressNft(control, wireless, uci.get('sbproxy', 'infra', 'ingress_dns_port')) : '';
	status.configuration_matches = status.enabled && expected === readfile('/var/run/sbproxy/ingress.nft');
	status.applied = status.active && !!bridge && !!inet && status.configuration_matches;
	status.bridge_packets = count(bridge, 'classify');
	status.bypassed_packets = count(inet, 'bypass');
	status.dns_redirections = count(inet, 'dns');
} catch(e) { status.error = '' + e; }
print(sprintf('%J', status));
