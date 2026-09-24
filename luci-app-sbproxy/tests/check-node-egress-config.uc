import { readfile } from 'fs';

const config = json(readfile(ARGV[0]));
const scenario = ARGV[1];
function assert(ok, message) { if (!ok) die(`${scenario}: ${message}`); }
const members = [...(config.outbounds || []), ...(config.endpoints || [])];
const wg = filter(members, (member) => member.type === 'wireguard');
const groups = filter(members, (member) => member.type === 'urltest');

assert(length(wg) === 1, 'WireGuard node must be emitted exactly once');
assert(wg[0].mtu === 1180, 'WireGuard MTU must not be changed by egress binding');
assert(wg[0].bind_interface === 'tailscale0', 'WireGuard egress must bind tailscale0');

if (scenario === 'main')
	assert(wg[0].tag === 'main-out', 'direct main node tag changed');
else {
	assert(length(groups) === 1, 'URLTest group is missing');
	assert(index(groups[0].outbounds, wg[0].tag) >= 0, 'URLTest does not reference the bound endpoint');
}

if (scenario === 'custom') {
	assert(wg[0].domain_resolver?.server === 'cfg-test_dns-dns', 'node DNS server is missing');
	assert(wg[0].domain_resolver?.strategy === 'ipv4_only', 'node DNS strategy is missing');
	assert(length(filter(config.dns.servers, (server) => server.tag === 'cfg-test_dns-dns')) === 1,
		'custom DNS server not generated');
	assert(length(filter(members, (member) => member.type === 'socks' && member.bind_interface)) === 0,
		'unbound sibling must not inherit the WireGuard interface');
}

printf('Node egress passed: %s\n', scenario);
