// Exercise live-upgrade control flow with fake procd/init commands and every
// filesystem path redirected to a temporary fixture. Never touch host services.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
const source = fs.readFileSync(new URL('../root/etc/uci-defaults/01-luci-sbproxy-retire-adaptive', import.meta.url), 'utf8');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sbproxy-retire-live-'));
try {
  for (const scenario of ['running', 'stopped', 'clean-core', 'stop-failed', 'restart-failed']) {
    const root = path.join(tmp, scenario);
    const write = (file, text, executable = false) => {
      const target = path.join(root, file);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, text, { mode: executable ? 0o700 : 0o600 });
    };
    write('etc/config/sbproxy-adaptive', 'old config');
    write('var/run/sbproxy/sing-box-c.json', scenario === 'clean-core' ? '{}' : '{"tag":"sbproxy-adaptive-out"}');
    write('etc/init.d/sbproxy', `#!/bin/sh
echo "$1" >> "$TEST_LOG"
case "$1" in
 running) test "$SCENARIO" != stopped ;;
 restart) test "$SCENARIO" != restart-failed ;;
 *) exit 99 ;;
esac
`, true);
    write('bin/ubus', `#!/bin/sh
case "$1 $2 $3" in
 'call service list') printf '%s\n' '{"sbproxy-adaptive":{"instances":{"worker":{}}}}' ;;
 'call service delete') echo stop-worker >> "$TEST_LOG"; test "$SCENARIO" != stop-failed ;;
 *) exit 99 ;;
esac
`, true);
    // Enable the live branches only inside this fully redirected test copy.
    write('retire.sh', source.replaceAll('[ -z "$ROOT" ]', '[ -n "$ROOT" ]')
      .replaceAll(' /var/run/sbproxy/sing-box-c.json', ' "$ROOT/var/run/sbproxy/sing-box-c.json"')
      .replaceAll('/etc/init.d/sbproxy ', '"$ROOT/etc/init.d/sbproxy" '));
    const result = spawnSync('sh', [path.join(root, 'retire.sh')], {
      env: { ...process.env, PATH: `${root}/bin:${process.env.PATH}`, SBPROXY_RETIRE_ROOT: root, TEST_LOG: `${root}/calls`, SCENARIO: scenario }, encoding: 'utf8'
    });
    const calls = fs.readFileSync(`${root}/calls`, 'utf8').trim().split('\n');
    assert.equal(calls[0], 'stop-worker');
    assert.equal(result.status, scenario.endsWith('failed') ? 1 : 0, `${scenario}: ${result.stderr}`);
    assert.equal(calls.includes('restart'), ['running', 'restart-failed'].includes(scenario));
    assert.equal(fs.existsSync(`${root}/etc/config/sbproxy-adaptive`), scenario === 'stop-failed');
    if (scenario !== 'stop-failed') {
      const backups = fs.readdirSync(`${root}/etc/sbproxy/retired-adaptive`);
      assert.equal(backups.length, 1);
      assert.equal(fs.readFileSync(`${root}/etc/sbproxy/retired-adaptive/${backups[0]}/config`, 'utf8'), 'old config');
    }
  }
  console.log('Live retirement fixtures passed: stop-before-archive, conditional restart, fail-safe stop and recoverable restart failure');
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
