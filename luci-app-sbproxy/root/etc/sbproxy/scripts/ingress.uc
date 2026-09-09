// Optional ingress bypass policy. No routing decision is made for unselected
// interfaces; existing SBProxy listen interfaces and routing rules still apply.
export function ingressEnabled(control) {
	return control?.ingress_enabled === '1' &&
		(length(control.ingress_bypass_devices || []) || length(control.ingress_bypass_wifi || []));
}

function list(value) {
	return type(value) === 'array' ? [...value] : (value ? [value] : []);
}

export function ingressDevices(control, wireless) {
	let devices = list(control.ingress_bypass_devices);
	const sections = list(control.ingress_bypass_wifi);
	for (let radio, status in wireless || {})
		for (let iface in status.interfaces || [])
			if (index(sections, iface.section) !== -1 && iface.ifname)
				push(devices, iface.ifname);
	devices = uniq(devices);
	for (let dev in devices)
		if (!match(dev, /^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,14}$/) || dev === 'lo')
			die('Invalid ingress device: ' + dev);
	return devices;
}

export function ingressNft(control, wireless, dns_port) {
	if (!ingressEnabled(control))
		return '';
	if (!match('' + dns_port, /^[0-9]+$/) || int(dns_port) < 1 || int(dns_port) > 65535)
		die('Invalid ingress runtime parameters');
	const devices = ingressDevices(control, wireless);
	const device_set = '{ ' + join(', ', map(devices, (dev) => sprintf('%J', dev))) + ' }';
	const mark = '0x2024';
	// This bit only carries the bridge-port decision to inet prerouting. It is
	// cleared before normal routing; never save it into the connection mark.
	const bit = '0x40000000';
	const clear = '0xbfffffff';
	let rules = [
		'table bridge sbproxy_ingress {',
		' chain classify {',
		'  type filter hook prerouting priority -300; policy accept;'
	];
	if (length(devices))
		push(rules, `  iifname ${device_set} ether type { ip, ip6 } meta mark set meta mark | ${bit} counter`);
	push(rules, ' }', '}', 'table inet sbproxy_ingress {', ' chain classify {',
		'  type filter hook prerouting priority -170; policy accept;',
		`  ct direction reply meta mark set meta mark & ${clear} return`,
		`  ct status dnat meta mark set meta mark & ${clear} return`);
	if (length(devices))
		push(rules, `  iifname ${device_set} meta mark set meta mark | ${bit} counter`);
	push(rules, ' }', ' chain dns {',
		'  type nat hook prerouting priority -165; policy accept;',
		`  meta mark & ${bit} != 0 meta l4proto { tcp, udp } th dport 53 counter redirect to :${dns_port}`,
		' }', ' chain bypass {',
		'  type filter hook prerouting priority -160; policy accept;');
	push(rules, `  meta mark & ${bit} != 0 meta mark set ${mark} ct mark set meta mark counter`);
	push(rules, ' }', '}');
	return join('\n', rules) + '\n';
}
