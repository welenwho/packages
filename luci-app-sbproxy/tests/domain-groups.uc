import { normalizeGroupDomains, loadDomainGroups, domainGroupOverlap } from 'domain_groups';
function assert(ok, message) { if (!ok) die(message); }
assert(join(',', normalizeGroupDomains('Example.COM\n.example.com.\n#comment\nkeyword')) === 'example.com,keyword', 'Normalization failed');
let rejected = false;
try { normalizeGroupDomains('https://example.com/path'); } catch(e) { rejected = true; }
assert(rejected, 'URLs must not be accepted as domains');
let sections = [
	{ '.name': 'a', enabled: '1', label: 'child', node: '_main', domains: ['api.example.com'] },
	{ '.name': 'b', enabled: '1', label: 'parent', node: '_direct', domains: ['example.com'] },
	{ '.name': 'c', enabled: '0', node: 'missing', domains: ['ignored.example'] }
];
const uci = { foreach: (_c, _t, fn) => { for (let s in sections) fn(s); }, get: (_c, id) => id === 'realnode' ? 'node' : null };
const groups = loadDomainGroups(uci, 'sbproxy', 'bypass_mainland_china');
assert(length(groups) === 2 && groups[0].id === 'a', 'Disabled groups/order changed');
assert(domainGroupOverlap(groups), 'Parent/child overlap must warn without blocking');
assert(!length(loadDomainGroups(uci, 'sbproxy', 'custom')), 'Custom routing must remain isolated');
assert(!length(loadDomainGroups(uci, 'sbproxy', 'global')), 'Groups must not alter global mode');
sections = [{ '.name': 'bad', enabled: '1', node: 'missing', domains: ['example.com'] }];
rejected = false;
try { loadDomainGroups(uci, 'sbproxy', 'bypass_mainland_china'); } catch(e) { rejected = true; }
assert(rejected, 'Missing node must not silently change egress');
sections[0].missing_node_action = 'main';
assert(loadDomainGroups(uci, 'sbproxy', 'bypass_mainland_china')[0].node === '_main', 'Explicit fallback failed');
sections[0].missing_node_action = 'reject';
assert(loadDomainGroups(uci, 'sbproxy', 'bypass_mainland_china')[0].node === '_reject', 'Reject-only group must not stop the client');
print('Domain group tests passed\n');
