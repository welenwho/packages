#!/usr/bin/env python3
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HelperTests(unittest.TestCase):
    def test_apply_refresh_failure_disable_and_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            runtime = base / 'run'
            bins = base / 'bin'
            bins.mkdir()
            rules = base / 'rules'
            rules.write_text('table bridge sbproxy_ingress {}\ntable inet sbproxy_ingress {}\n')
            def executable(path, content):
                path.write_text('#!/bin/sh\nset -eu\n' + content)
                path.chmod(0o755)
            executable(bins / 'flock', 'exit 0\n')
            executable(bins / 'ucode', 'cat "$MOCK_RULES"\n')
            executable(bins / 'nft', '''
echo "$*" >> "$MOCK_ROOT/calls"
case "$1" in
list) test -f "$MOCK_ROOT/$3.exists";;
delete) rm -f "$MOCK_ROOT/$3.exists";;
-c) [ "$MOCK_FAIL" != 1 ];;
-f) touch "$MOCK_ROOT/bridge.exists" "$MOCK_ROOT/inet.exists";;
*) exit 2;;
esac
''')
            source = (ROOT / 'root/usr/libexec/sbproxy-ingress').read_text()
            helper = base / 'helper'
            helper.write_text(source.replace('/var/run/sbproxy', str(runtime))
                              .replace('/var/lock', str(base / 'lock')))
            helper.chmod(0o755)
            env = dict(os.environ, PATH=str(bins) + ':' + os.environ['PATH'],
                       MOCK_ROOT=tmp, MOCK_RULES=str(rules), MOCK_FAIL='0')
            def run(action, fail=False):
                result = subprocess.run([str(helper), action], env=dict(env, MOCK_FAIL='1' if fail else '0'),
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode == 0, not fail, result.stderr)
            run('start')
            saved = (runtime / 'ingress.nft').read_text()
            calls = (base / 'calls').read_text().count('-f ')
            run('refresh')
            self.assertEqual(calls, (base / 'calls').read_text().count('-f '), 'Unchanged rules must not be reapplied')
            rules.write_text(saved + '# changed\n')
            run('refresh', fail=True)
            self.assertEqual((runtime / 'ingress.nft').read_text(), saved, 'Failed check must preserve installed rules')
            run('refresh')
            rules.write_text('')
            run('refresh')
            self.assertFalse((base / 'bridge.exists').exists())
            self.assertFalse((base / 'inet.exists').exists())
            run('stop')
            self.assertFalse((runtime / 'ingress.active').exists())
            run('refresh')
            self.assertFalse((runtime / 'ingress.active').exists(), 'A late refresh must not resurrect stopped policy')
            self.assertNotIn('flush ruleset', (base / 'calls').read_text())


if __name__ == '__main__':
    unittest.main()
