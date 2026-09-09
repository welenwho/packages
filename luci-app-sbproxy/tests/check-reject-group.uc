import { readfile, writefile } from 'fs';
const path = ARGV[0], config = json(readfile(path));
function assert(ok, text) { if (!ok) die(text); }
function matches(rule) { return index(rule.domain_suffix || [], 'reject-only.example') !== -1; }
assert(length(filter(config.dns.rules, (r) => matches(r) && r.action === 'predefined' && r.rcode === 'REFUSED')) === 1, 'Group DNS must refuse rather than fall back');
assert(length(filter(config.route.rules, (r) => matches(r) && r.action === 'reject')) === 1, 'Missing group business rejection');
assert(length(filter(config.dns.servers, (s) => s.detour === 'main-out')) === 1, 'Main DNS resolver duplicated');
assert(!length(filter(config.outbounds, (o) => o.tag === 'cfg-missing-out')), 'A missing node must never be emitted');
for (let rule in config.route.rule_set || []) if (rule.tag === 'geoip-cn') rule.path = ARGV[1];
writefile(path, sprintf('%J', config));
print('Reject-only group and DNS reuse configuration tests passed\n');
