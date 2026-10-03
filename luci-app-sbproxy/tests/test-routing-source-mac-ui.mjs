import fs from 'node:fs';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const source = fs.readFileSync(fileURLToPath(new URL('../htdocs/luci-static/resources/view/sbproxy/client.js', import.meta.url)), 'utf8');
const start = source.indexOf("s.tab('routing_rule', _('Routing Rules'))");
const end = source.indexOf('/* Routing rules end */', start);
assert.ok(start >= 0 && end > start, 'Custom routing rule form missing');
const routing = source.slice(start, end);
assert.match(routing, /fwtool\.addMACOption\(ss, 'field_host', 'source_mac_address'/,
	'Source MAC selector must be in the routing rule Host/IP tab');
assert.match(routing, /<code>source_mac_address<\/code>/,
	'Default-rule matching description must mention the MAC constraint');
assert.match(source, /fwtool\.addMACOption\(ss, 'lan_ip_policy', 'lan_direct_mac_addrs'/,
	'Existing device-wide MAC policy must remain available');
console.log('Custom routing source MAC UI test passed');
