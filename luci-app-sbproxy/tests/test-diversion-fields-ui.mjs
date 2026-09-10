import fs from 'node:fs';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const source = fs.readFileSync(fileURLToPath(new URL('../htdocs/luci-static/resources/view/sbproxy/client.js', import.meta.url)), 'utf8');
const helperCode = source.slice(source.indexOf('/* Diversion helpers start'), source.indexOf('/* Diversion helpers end */'));
const helpers = Function(helperCode + '; return {normalizeDiversionDomains, diversionOverlap};')();
const start = source.indexOf("o = s.taboption('diversion'");
const block = source.slice(start, source.indexOf('/* Custom routing settings start */', start));
assert.ok(start >= 0, 'Diversion must be a top-level tab');
const options = {}, tabs = [];
const values = { group: { enabled: '1', domains: ['news.example.com'] }, available: { enabled: '1' }, disabled: { enabled: '0' } };
const uci = {
  get: (_c, section, field) => field ? values[section]?.[field] : (['available', 'disabled'].includes(section) ? 'ruleset' : 'domain_route'),
  set: (_c, section, field, value) => { values[section] ??= {}; values[section][field] = value; },
  sections: (_c, type, callback) => { if (type === 'ruleset') callback({ '.name': 'available', enabled: '1', label: 'Available' }); }
};
const groups = {
  tab: (id) => tabs.push(id),
  formvalue: (id, field) => values[id]?.[field],
  cfgsections: () => ['group'],
  taboption(tab, kind, name) {
    return options[name] = { tab, kind, name, section: groups, map: { lookupOption: () => [] },
      choices: [], value(value) { this.choices.push(value); }, super() {} };
  }
};
let groupTab;
const s = { taboption(tab) { groupTab = tab; return { subsection: groups, depends() {} }; } };
const form = Object.fromEntries(['SectionValue','GridSection','Flag','Value','ListValue','TextValue','DummyValue','DynamicList'].map((v) => [v,v]));
const sb = { CBIStaticList: 'StaticList', validatePortRange: () => true };
// LuCI's translation strings use this formatter; no browser is needed here.
String.prototype.format = function(...args) { let i = 0; return this.replace(/%s/g, () => args[i++]); };
Function('s','form','sb','uci','data','proxy_nodes','L','stubValidator','document','E','normalizeDiversionDomains','diversionOverlap','_',
  'let o; ' + block)(s,form,sb,uci,['sbproxy'],{}, { toArray: (v) => v || [] }, {apply: () => true},
  {querySelectorAll: () => []}, () => null,helpers.normalizeDiversionDomains,helpers.diversionOverlap,(v) => v);
assert.equal(groupTab, 'diversion');
assert.deepEqual(tabs, ['general','domains','addresses','ports','other']);
for (const field of ['rule_set','domain','domain_suffix','domain_keyword','domain_regex','ip_cidr','source_ip_cidr','port','source_port','port_range','source_port_range','network','ip_version','protocol','invert'])
  assert.ok(options[field], field + ' missing');
assert.equal(options.ip_cidr.datatype, 'or(cidr, ipaddr)');
assert.equal(options.port.datatype, 'port');
assert.equal(options.port_range.validate, sb.validatePortRange);
options.domains.write('group', 'news.example.com\nrouter.example.com');
assert.deepEqual(values.group.domains, ['news.example.com','router.example.com']);
assert.equal(options.domains.cfgvalue('group'), 'news.example.com\nrouter.example.com');
options.rule_set.load('group');
assert.deepEqual(options.rule_set.choices, ['builtin:geoip-cn','builtin:geosite-cn','available']);
assert.equal(options.rule_set.validate('group', 'available'), true);
assert.notEqual(options.rule_set.validate('group', 'disabled'), true);
assert.equal(options.domains.validate('group', ''), true, 'IP-only groups must not require legacy domains');
assert.match(source, /'diversion_download_outbound'/);
console.log('Diversion UI field, tab, reference validation and legacy save/read tests passed');
