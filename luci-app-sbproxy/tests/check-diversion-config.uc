import { readfile, writefile } from 'fs';
const path = ARGV[0], mode = ARGV[1], geoip = ARGV[2];
const c = json(readfile(path));
function assert(ok, message) { if (!ok) die(message); }
assert(!length(filter(c.inbounds, (i) => i.type === 'tproxy')), 'TProxy inbound remains');
assert(length(filter(c.inbounds, (i) => i.type === 'tun')) === 1, 'TUN inbound missing');
const group_dns = filter(c.dns.servers, (s) => index(s.tag, 'diversion-') === 0);
if (mode === 'custom' || mode === 'global') assert(!length(group_dns), 'Groups leaked into other routing modes');
else {
	assert(length(group_dns) === 1, 'Main DNS must be reused; only the other outbound needs a resolver');
	const tags = map([...c.outbounds, ...(c.endpoints || [])], (o) => o.tag);
	for (let s in group_dns) assert(index(tags, s.detour) !== -1, 'DNS detour target missing');
	assert(!c.inbounds[length(c.inbounds)-1].route_exclude_address_set, 'Fast CIDR bypass hides explicit group rules');
	const sniff = index(map(c.route.rules, (r) => r.action), 'sniff');
	assert(sniff >= 0, 'Missing sniff for keyword groups');
	function hasKeyword(r) {
		return r.domain_keyword?.[0] === 'testkeyword' || length(filter(r.rules || [], hasKeyword)) > 0;
	}
	const keyword = filter(c.route.rules, hasKeyword);
	assert(length(keyword) === 1, 'Keyword must not be prematurely routed in native pre-match');
	assert(index(c.route.rules, keyword[0]) > sniff, 'Keyword rule must follow sniff');
}
// Only the fixture path changes. No production resource is written.
for (let r in c.route.rule_set || [])
	if (r.tag === 'geoip-cn') r.path = geoip;
writefile(path, sprintf('%J', c));
print(mode + ': generated configuration assertions passed\n');
