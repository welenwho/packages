import { readfile, writefile } from 'fs';
const c = json(readfile(ARGV[0]));
const mode = ARGV[1];
function assert(ok, message) { if (!ok) die(message); }
if (mode === 'bypass_mainland_china') {
	const ip = filter(c.route.rules, (r) => index(r.ip_cidr || [], '198.51.100.0/24') >= 0);
	assert(length(ip) === 1 && ip[0].action === 'route', 'IP-only group missing');
	const combined = filter(c.route.rules, (r) => index(r.domain || [], 'news.example.com') >= 0);
	assert(length(combined) === 1, 'Combined group missing or duplicated in pre-match');
	assert(combined[0].port[0] === 443 && combined[0].network === 'tcp' && combined[0].source_ip_cidr[0] === '192.0.2.7/32', 'Constraints lost');
	assert(combined[0].type !== 'logical', 'Top-level OR widens connection matching');
	const references = filter(c.route.rule_set, (r) => r.tag === 'cfg-local_test-rule' || r.tag === 'cfg-remote_test-rule');
	assert(length(references) === 2, 'Referenced rule sets must be emitted exactly once');
	assert(!length(filter(c.route.rule_set, (r) => r.tag === 'cfg-unused_test-rule')), 'Unreferenced custom rule set leaked into mainland mode');
	assert(filter(references, (r) => r.tag === 'cfg-remote_test-rule')[0].http_client.detour === 'main-out', 'Mainland download outbound not applied');
	assert(!length(filter(c.dns.rules, (r) => index(r.domain || [], 'news.example.com') >= 0 || r.ip_cidr || r.rule_set?.[0] === 'cfg-local_test-rule')), 'Connection constraints must not be widened into DNS');
	const legacy = filter(c.dns.rules, (r) => index(r.domain_suffix || [], 'dns-example.net') >= 0);
	assert(length(legacy) === 1 && legacy[0].server === 'main-dns', 'Legacy pure-domain DNS behavior lost');
} else if (mode === 'custom') {
	assert(!length(filter(c.route.rules, (r) => index(r.domain || [], 'news.example.com') >= 0)), 'Diversion leaked into custom routing');
	assert(length(filter(c.route.rule_set, (r) => r.tag === 'cfg-unused_test-rule')) === 1, 'Custom routing still needs all enabled custom rule sets');
}
for (let rule in c.route.rule_set || []) if (rule.tag === 'geoip-cn') rule.path = ARGV[2];
writefile(ARGV[0], sprintf('%J', c));
print(mode + ': extended diversion configuration passed\n');
