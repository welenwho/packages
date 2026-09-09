import fs from 'node:fs';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const file = fileURLToPath(new URL('../htdocs/luci-static/resources/view/sbproxy/client.js', import.meta.url));
const source = fs.readFileSync(file, 'utf8');
const helpers = source.slice(source.indexOf('/* Diversion helpers start'), source.indexOf('/* Diversion helpers end */'));
const { normalizeDiversionDomains: normalize, diversionOverlap: overlap } = Function(helpers + '\nreturn { normalizeDiversionDomains, diversionOverlap };')();
assert.deepEqual(normalize('news.example.com\nrouter.example.net'), ['news.example.com', 'router.example.net']);
assert.deepEqual(normalize('one.example\r\ntwo.example\rthree.example'), ['one.example', 'two.example', 'three.example']);
assert.deepEqual(normalize(' .Example.COM.\nexample.com\n# comment\nkeyword '), ['example.com', 'keyword']);
assert.deepEqual(normalize(['news.example.com', 'router.example.net']), ['news.example.com', 'router.example.net']);
assert.deepEqual(normalize('  \n# comment\n'), []);
const cfgStart = source.indexOf('go.cfgvalue = function(section_id)', source.indexOf("groups.option(form.TextValue, 'domains'"));
const cfgEnd = source.indexOf('\n\t\tgo.write', cfgStart);
const go = {};
Function('go', 'L', 'uci', source.slice(cfgStart, cfgEnd))(go, { toArray: (v) => v }, { get: () => ['news.example.com', 'router.example.net'] });
assert.equal(go.cfgvalue('test'), 'news.example.com\nrouter.example.net');
assert.deepEqual(normalize(go.cfgvalue('test')), ['news.example.com', 'router.example.net']);
const groups = [
  { id: 'a', label: 'Specific', enabled: true, domains: ['api.example.com'] },
  { id: 'b', label: 'Parent', enabled: true, domains: ['example.com'] }
];
assert.equal(overlap(groups).first, 'Specific');
assert.equal(overlap([...groups].reverse()).first, 'Parent');
assert.equal(overlap([groups[0], { ...groups[1], enabled: false }]), null);
assert.equal(overlap([{ ...groups[0], domains: ['keyword'] }, { ...groups[1], domains: ['api.keyword.example'] }]).first, 'Specific');
assert.equal(overlap([{ ...groups[0], domains: ['notexample.com'] }, groups[1]]), null);
assert.equal(overlap([{ ...groups[0], domains: Array.from({ length: 10000 }, (_, i) => `h${i}.example.com`) }]), null);
assert.match(source, /groups\.sortable = true/);
assert.match(source, /o\.retain = true;\s*groups\.anonymous/);
console.log('Diversion frontend regression tests passed: letters, newlines, round trip, overlaps and large lists');
