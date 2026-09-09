export function requiredPorts(config) {
	let ports = [], seen = {};
	function add(port, protocol) {
		port = int(port);
		if (port < 1 || port > 65535) return;
		const key = protocol + ':' + port;
		if (!seen[key]) { seen[key] = true; push(ports, key); }
	}
	for (let inbound in config.inbounds || []) {
		if (!inbound.listen_port) continue;
		let protocols;
		if (inbound.type in ['hysteria', 'hysteria2', 'tuic'] || inbound.transport?.type === 'quic') protocols = ['udp'];
		else if (inbound.network) protocols = type(inbound.network) === 'array' ? inbound.network : [inbound.network];
		else if (inbound.type in ['direct', 'shadowsocks', 'naive']) protocols = ['tcp', 'udp'];
		else protocols = ['tcp'];
		for (let protocol in protocols) add(inbound.listen_port, protocol);
	}
	for (let service in config.services || []) {
		add(service.listen_port, 'tcp');
		if (service.stun?.enabled) add(service.stun.listen_port, 'udp');
	}
	return ports;
}

export function coreHealthPlan(instances, configs) {
	let required = [];
	for (let name in ['sing-box-c', 'sing-box-s']) {
		if (!instances[name]) continue;
		if (!configs[name]) die('Missing running core configuration: ' + name);
		push(required, { name, config: '/var/run/sbproxy/' + name + '.json', ports: requiredPorts(configs[name]) });
	}
	return { instances: required };
}

export function assessCoreHealth(plan, instances, inspect) {
	if (!length(plan.instances || [])) return { ok: false, error: 'No expected core instances' };
	let signature = [];
	for (let expected in plan.instances) {
		const instance = instances[expected.name];
		if (!instance?.running || int(instance.pid) <= 0)
			return { ok: false, error: expected.name + ' is not running' };
		const process = inspect(int(instance.pid), expected.config);
		if (!process) return { ok: false, error: expected.name + ' has no matching live core process' };
		for (let port in expected.ports)
			if (index(process.ports, port) === -1)
				return { ok: false, error: expected.name + ' has not opened ' + port };
		push(signature, expected.name + ':' + process.pid + ':' + process.start);
	}
	return { ok: true, signature: join(',', signature) };
}
