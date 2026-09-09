#!/usr/bin/ucode
import { readfile, readlink, glob } from 'fs';
import { connect } from 'ubus';
import { coreHealthPlan, assessCoreHealth } from 'core_health';

const service = connect()?.call('service', 'list', { name: 'sbproxy' });
if (type(service) !== 'object') die('Unable to read core service instances');
const instances = service.sbproxy?.instances || {};
if (ARGV[0] === 'snapshot') {
	let configs = {};
	for (let name in ['sing-box-c', 'sing-box-s']) {
		const file = readfile('/var/run/sbproxy/' + name + '.json');
		if (file) configs[name] = json(file);
	}
	print(sprintf('%J', coreHealthPlan(instances, configs)));
	exit(0);
}

function inspect(root, config) {
	// ujail may own the procd PID. Inspect its descendants, but accept only a
	// sing-box executable running the expected config, never auxiliary workers.
	let pending = [root], seen = {};
	for (let count = 0; count < 64 && length(pending); count++) {
		const pid = shift(pending);
		if (seen[pid]) continue;
		seen[pid] = true;
		const prefix = '/proc/' + pid;
		const exe = readlink(prefix + '/exe') || '';
		const args = split(readfile(prefix + '/cmdline') || '', '\x00');
		if (match(exe, /\/sing-box$/) && index(args, config) !== -1) {
			let inodes = {}, ports = [];
			for (let fd in glob(prefix + '/fd/*')) {
				const socket = match(readlink(fd) || '', /^socket:\[([0-9]+)\]$/);
				if (socket) inodes[socket[1]] = true;
			}
			for (let protocol in ['tcp', 'tcp6', 'udp', 'udp6']) {
				for (let line in split(readfile(prefix + '/net/' + protocol) || '', '\n')) {
					const fields = split(trim(line), /\s+/);
					if (length(fields) < 10 || !inodes[fields[9]]) continue;
					const tcp = substr(protocol, 0, 3) === 'tcp';
					if (tcp && fields[3] !== '0A') continue;
					const port = match(fields[1], /:([0-9A-Fa-f]+)$/);
					if (port) push(ports, (tcp ? 'tcp:' : 'udp:') + int(port[1], 16));
				}
			}
			const stat = readfile(prefix + '/stat') || '';
			const fields = split(trim(substr(stat, rindex(stat, ')') + 1)), /\s+/);
			if (!fields[19]) return null;
			return { pid, start: fields[19], ports };
		}
		for (let child in split(trim(readfile(prefix + '/task/' + pid + '/children') || ''), /\s+/))
			if (int(child) > 0) push(pending, int(child));
	}
	return null;
}

const plan = json(readfile(ARGV[1]));
const result = assessCoreHealth(plan, instances, inspect);
if (!result.ok) die(result.error);
print(result.signature);
