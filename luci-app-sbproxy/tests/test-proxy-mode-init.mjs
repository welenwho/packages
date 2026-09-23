import fs from 'node:fs';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
const root = new URL('../', import.meta.url);
const source = fs.readFileSync(new URL('root/etc/init.d/sbproxy', root), 'utf8');
const selection = source.slice(source.indexOf('\tlocal outbound_node\n'), source.indexOf('\n\tlocal server_enabled proxy_client_requested=0'));
assert(selection.includes('"disabled"'));
for (const [mode, main, custom, expected] of [
  ['disabled', 'node1', 'node2', 'nil'], ['disabled', 'urltest', 'reject', 'nil'],
  ['bypass_mainland_china', 'node1', 'node2', 'node1'], ['global', 'node1', 'node2', 'node1'],
  ['custom', 'node1', 'node2', 'node2'], ['bypass_mainland_china', 'nil', 'node2', 'nil']
]) {
  const result = spawnSync('sh', ['-c', `
config_get() {
  case "$2.$3" in
    config.main_node) eval "$1=\\\"\\$MAIN\\\"" ;;
    routing.default_outbound) eval "$1=\\\"\\$CUSTOM\\\"" ;;
    *) exit 98 ;;
  esac
}
run_test() {
 local routing_mode="$MODE"
 ${selection}
 printf '%s' "$outbound_node"
}
run_test
`], { env: { ...process.env, MODE: mode, MAIN: main, CUSTOM: custom }, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, expected, mode);
}
assert(source.includes('if [ "$outbound_node" != "nil" ] || [ "$tailscale_enabled" = "1" ]; then'));
assert.match(source, /procd_open_instance "tailscale-sync"/);
assert.match(source, /\[ "\$tailscale_enabled" = "0" \]; then\s+sync_subscription_cron[^\n]*\n\s+return 0/);
const rpc = fs.readFileSync(new URL('root/usr/share/rpcd/ucode/luci.sbproxy', root), 'utf8');
assert.match(rpc, /mode: 'disabled', proxy_enabled: false/);
console.log('Proxy mode startup tests passed: saved nodes ignored only when off, Tailscale startup remains independent');
