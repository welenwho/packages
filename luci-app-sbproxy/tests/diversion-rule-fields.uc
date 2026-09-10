import { buildGroupMatch, loadDomainGroups } from 'domain_groups';
import { renderRouteMatch } from 'route_match';
function assert(ok, text) { if (!ok) die(text); }
const uci = { get: (_c, id, option) => id === 'site_set' ? (option === 'enabled' ? '1' : 'ruleset') : null };
const ip = buildGroupMatch({ ip_cidr: ['1.1.1.1', '2001:db8::/32'] }, uci, 'sbproxy');
assert(ip.match.ip_cidr[0] === '1.1.1.1/32', 'Single IPv4 must be a host CIDR');
assert(ip.match.ip_cidr[1] === '2001:db8::/32', 'IPv6 CIDR lost');
assert(ip.dns_match === null, 'IP-only rule must not become a catch-all DNS rule');
const combined = buildGroupMatch({ domain: ['exact.example'], domain_suffix: ['example.org'], port: ['443'], network: 'tcp', source_ip_cidr: ['192.0.2.1'] }, uci, 'sbproxy');
assert(combined.match.domain[0] === 'exact.example' && combined.match.port[0] === 443, 'Destination and port fields missing');
assert(combined.match.type !== 'logical' && combined.match.network === 'tcp', 'Constraints must not be OR-ed independently');
assert(combined.dns_match === null, 'Connection port cannot be projected onto DNS port');
const sets = buildGroupMatch({ rule_set: ['site_set', 'site_set', 'builtin:geoip-cn'] }, uci, 'sbproxy');
assert(join(',', sets.match.rule_set) === 'cfg-site_set-rule,geoip-cn', 'Rule-set tag mapping/deduplication failed');
assert(sets.rule_set_refs[0] === 'site_set' && length(sets.rule_set_refs) === 1, 'Built-ins must not be resolved as UCI sections');
assert(sets.dns_match === null && sets.needs_sniff, 'Unknown rule-set contents must not widen DNS or bypass early');
const legacy = buildGroupMatch({ domains: ['News.Example.com', 'keyword'] }, uci, 'sbproxy');
assert(legacy.match.domain_suffix[0] === 'news.example.com' && legacy.match.domain_keyword[0] === 'keyword', 'Legacy data changed');
assert(legacy.dns_match !== null, 'Pure domain DNS behavior lost');
const inverted = buildGroupMatch({ domain_suffix: ['example.org'], invert: '1' }, uci, 'sbproxy');
assert(inverted.match.invert && inverted.needs_sniff, 'Inversion requires complete match and deferred sniff');
assert(buildGroupMatch({ invert: '1', rule_set_ip_cidr_match_source: '1' }, uci, 'sbproxy') === null, 'Empty flags must not become catch-all');
for (let bad in [{ ip_cidr: ['bad-address'] }, { port: ['0'] }, { port_range: ['443:80'] }, { rule_set: ['missing'] }, { rule_set: ['site_set'] }]) {
	let rejected = false;
	try { buildGroupMatch(bad, { get: () => null }, 'sbproxy'); } catch(e) { rejected = true; }
	assert(rejected, 'Invalid or missing match data was accepted');
}
const custom = renderRouteMatch({ domain_suffix: ['example.org'], ip_cidr: ['192.0.2.0/24'], port: ['443'], source_port_range: ['1000:2000'], invert: '1' }, ['cfg-site_set-rule']);
assert(custom.port[0] === 443 && custom.invert && custom.domain_suffix[0] === 'example.org', 'Shared custom-rule renderer changed types');
let sections = [{ '.name': 'ip_only', enabled: '1', node: '_main', ip_cidr: ['192.0.2.0/24'] }, { '.name': 'set_only', enabled: '1', node: '_direct', rule_set: ['site_set'] }];
const groupsUci = { get: uci.get, foreach: (_c, _t, fn) => { for (let s in sections) fn(s); } };
assert(length(loadDomainGroups(groupsUci, 'sbproxy', 'bypass_mainland_china')) === 2, 'Groups without legacy domains were skipped');
assert(!length(loadDomainGroups(groupsUci, 'sbproxy', 'custom')), 'Diversion leaked into custom mode');
print('Diversion rule field tests passed\n');
