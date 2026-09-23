import fs from 'node:fs';
import assert from 'node:assert/strict';
const client = fs.readFileSync(new URL('../htdocs/luci-static/resources/view/sbproxy/client.js', import.meta.url), 'utf8');
const helper = client.slice(client.indexOf('function proxyModeDepends('), client.indexOf('function renderStatus('));
const fields = [];
const s = { taboption(tab, type, name, label) {
  const o = { name, label, dependencies: [], values: [],
    depends(a, b) { this.dependencies.push(typeof a === 'string' ? { [a]: b } : a); },
    value(value, label) { this.values.push([value, label]); }
  };
  fields.push(o);
  return o;
} };
const start = client.indexOf("o = s.taboption('routing', form.ListValue, 'routing_mode'");
const end = client.indexOf("o = s.taboption('dashboard'", start);
assert(start > 0 && end > start);
const oldFormat = String.prototype.format;
String.prototype.format = function(...args) { let i = 0; return this.replace(/%[sh]/g, () => String(args[i++])); };
try {
  Function('s', 'form', 'sb', '_', 'features', 'proxy_nodes', 'subscription_sources', 'common_routing_ports',
    helper + '\nlet o;\n' + client.slice(start, end))(
    s, {}, {}, s => s, { with_gvisor: true }, { node1: 'Test node' }, [], '80,443'
  );
} finally {
  if (oldFormat) String.prototype.format = oldFormat;
  else delete String.prototype.format;
}
assert.equal((client.match(/form.ListValue, 'routing_mode'/g) || []).length, 1);
assert.equal(fields[0].name, 'routing_mode');
assert.equal(fields[0].label, 'Proxy mode');
assert.deepEqual(fields[0].values.map(v => v[0]), ['disabled', 'bypass_mainland_china', 'custom', 'global']);
assert.equal(fields[0].default, 'disabled');
assert.equal(fields[0].dependencies.length, 0);
assert.equal(fields.find(f => f.name === 'routing_port').label, 'Proxy ports');
function visible(field, state) {
  return !field.dependencies.length || field.dependencies.some(d => Object.entries(d).every(([k, v]) => state[k] === v));
}
for (const mode of ['disabled', 'bypass_mainland_china', 'custom', 'global']) {
  const state = { routing_mode: mode, main_node: 'urltest', routing_port: 'common', ipv6_support: '1' };
  const shown = fields.filter(f => visible(f, state));
  assert.equal(shown[0].name, 'routing_mode');
  if (mode === 'disabled') {
    // IPv6 resolution preference also applies to the independent Tailscale endpoint.
    assert.deepEqual(shown.map(f => f.name), ['routing_mode', 'ipv6_support']);
    for (const field of fields.filter(f => !visible(f, state))) assert.equal(field.retain, true, field.name);
  }
  if (mode === 'custom') assert(!shown.some(f => f.name.startsWith('main_urltest_')));
}
assert(fields.find(f => f.name === 'main_node').values.some(v => v[0] === 'nil'));
assert.match(client, /current\?\.proxy_enabled === false/);
console.log('Proxy mode UI tests passed: stable first position, off hides proxy-only controls, saved values retained');
