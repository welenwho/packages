import { readfile } from 'fs';
const text = readfile(ARGV[0]), mode = ARGV[1], c = json(text);
function assert(ok, message) { if (!ok) die(mode + ': ' + message); }
assert(index(text, 'adaptive') < 0, 'Retired feature leaked into generated configuration');
assert(!length(filter(c.inbounds, (i) => i.type === 'socks')), 'Probe listeners remain');
if (mode === 'tailscale-only') {
	assert(c.route.final === 'direct-out', 'Standalone Tailscale final route changed');
	assert(length(filter(c.endpoints || [], (e) => e.type === 'tailscale')) === 1, 'Tailscale endpoint missing');
} else {
	assert(length(filter(c.inbounds, (i) => i.type === 'tun')) === 1, 'TUN missing');
	if (mode === 'custom-direct') assert(c.route.final === 'direct-out', 'Direct default changed');
	else if (mode === 'custom-proxy') assert(c.route.final === 'fixture-proxy', 'Proxy default changed');
	else if (mode === 'custom-reject') assert(c.route.rules[length(c.route.rules)-1].action === 'reject', 'Reject default changed');
	else assert(c.route.final === 'main-out', 'Main default changed');
}
if (index(mode, 'custom-') === 0) {
	const explicit = filter(c.route.rules, (r) => r.domain?.[0] === 'explicit.example' && r.outbound === 'direct-out');
	assert(length(explicit) === 1, 'Explicit routing rule missing');
	assert(explicit[0].source_mac_address?.[0] === '40:24:B2:FE:01:4D', 'Source MAC lost from route rule');
	const block = filter(c.route.rules, (r) => r.action === 'reject' &&
		r.source_mac_address?.[0] === '40:24:B2:FE:01:4D' &&
		r.rule_set?.[0] === 'cfg-site_set-rule');
	assert(length(block) === 1, 'MAC and rule-set reject condition missing');
}
if (mode === 'urltest') {
	assert(length(filter(c.outbounds, (o) => o.type === 'urltest')) === 1, 'URLTest removed');
	assert(c.experimental?.clash_api?.external_controller === '127.0.0.1:19090', 'URLTest API removed');
} else assert(!c.experimental?.clash_api, 'Unused probe API remains');
printf('Generated configuration passed: %s\n', mode);
