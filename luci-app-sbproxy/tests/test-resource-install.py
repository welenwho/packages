#!/usr/bin/env python3
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / 'root/etc/sbproxy/scripts/update_resources.sh').read_text()
FUNCTION = SCRIPT[SCRIPT.index('install_rule_set() {'):SCRIPT.index('\nexec 9>')]


class ResourceInstallTests(unittest.TestCase):
    def run_install(self, previous, fail):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            resources = base / 'resources'
            resources.mkdir()
            source = base / 'source'
            source.write_bytes(b'new-rules')
            if previous:
                (resources / 'geoip_cn.srs').write_bytes(b'old-rules')
                (resources / 'geoip_cn.ver').write_text('old-version')
            bins = base / 'bin'
            bins.mkdir()
            mv = bins / 'mv'
            mv.write_text('#!/bin/sh\ncase "$2" in */geoip_cn.ver) [ "$FAIL" != 1 ] || exit 1;; esac\nexec /bin/mv "$@"\n')
            mv.chmod(0o755)
            env = dict(os.environ, RESOURCES_DIR=str(resources), SOURCE=str(source),
                       PATH=str(bins) + ':' + os.environ['PATH'], FAIL='1' if fail else '0')
            r = subprocess.run(['sh', '-c', FUNCTION + '\ninstall_rule_set "$SOURCE" new-version geoip_cn'],
                               env=env, text=True, capture_output=True)
            self.assertEqual(r.returncode == 0, not fail, r.stderr)
            if fail and not previous:
                self.assertFalse((resources / 'geoip_cn.srs').exists())
                self.assertFalse((resources / 'geoip_cn.ver').exists())
            else:
                self.assertEqual((resources / 'geoip_cn.srs').read_bytes(), b'old-rules' if fail else b'new-rules')
                self.assertEqual((resources / 'geoip_cn.ver').read_text().strip(), 'old-version' if fail else 'new-version')

    def test_success(self): self.run_install(True, False)
    def test_restore_old_pair(self): self.run_install(True, True)
    def test_failed_first_install_leaves_no_half_pair(self): self.run_install(False, True)


if __name__ == '__main__': unittest.main()
