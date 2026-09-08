#!/usr/bin/env python3
import importlib.util
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
MAKEFILE = (ROOT / 'sing-box/Makefile').read_text()
VERSION = re.search(r'^PKG_VERSION:=(.*)$', MAKEFILE, re.M)[1]
REVISION = int(re.search(r'^PKG_RELEASE:=(\d+)$', MAKEFILE, re.M)[1])
spec = importlib.util.spec_from_file_location('core_release', ROOT / '.github/scripts/core-release.py')
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


class CoreReleaseTests(unittest.TestCase):
    def test_fingerprint_excludes_generated_pin(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            shutil.copytree(ROOT / 'sing-box', target / 'sing-box')
            shutil.copytree(ROOT / '.github', target / '.github')
            with patch.object(core, 'ROOT', target):
                before = core.fingerprint()
                (target / 'sing-box/core-prebuilt.mk').write_text('CORE_PIN_VERSION:=1.14.0-r2\n')
                mf = target / 'sing-box/Makefile'
                mf.write_text(re.sub(r'^PKG_RELEASE:=.*$', 'PKG_RELEASE:=999', mf.read_text(), flags=re.M))
                self.assertEqual(before, core.fingerprint())
                p = target / 'sing-box/patches/test.patch'
                p.write_text('new patch')
                self.assertNotEqual(before, core.fingerprint())

    def test_first_release_does_not_reuse_firmware_version(self):
        upstream = dict(tag_name='v' + VERSION, draft=False, prerelease=False)
        with patch.object(core, 'api', return_value=upstream), \
             patch.object(core, 'releases', return_value=[]), \
             patch.object(core, 'output') as out:
            core.resolve()
            self.assertEqual(out.call_args.kwargs['revision'], REVISION + 1)
            self.assertEqual(out.call_args.kwargs['build'], 'true')

    def test_prerelease_is_rejected(self):
        with patch.object(core, 'api', return_value=dict(tag_name='v1.15.0-rc.1', draft=False, prerelease=True)):
            with self.assertRaises(ValueError):
                core.resolve()

    def test_pin_retry_reuses_published_artifact(self):
        release = dict(tag_name='sbproxy-core-v1.14.0-r2', draft=False, prerelease=False,
                       assets=[dict(name='core-manifest.json', browser_download_url='https://example.test')])
        real_check = subprocess.check_output
        def check(command, **kw):
            if command[0] == 'curl':
                return json.dumps(dict(fingerprint=core.fingerprint()))
            return real_check(command, **kw)
        with patch.object(core, 'api', return_value=dict(tag_name='v1.14.0', draft=False, prerelease=False)), \
             patch.object(core, 'releases', return_value=[release]), \
             patch.object(core.subprocess, 'check_output', side_effect=check), \
             patch.object(core, 'output') as out:
            core.resolve()
            self.assertEqual(out.call_args.kwargs['build'], 'false')
            self.assertEqual(out.call_args.kwargs['tag'], release['tag_name'])

    def make_values(self, arch='aarch64', variant='full', pinned=True, force=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'include').mkdir()
            (root / 'rules.mk').write_text('INCLUDE_DIR:=$(TOPDIR)/include\nBUILD_DIR:=$(TOPDIR)/build\n')
            (root / 'include/package.mk').write_text('')
            go = root / 'feeds/packages/lang/golang'
            go.mkdir(parents=True)
            (go / 'golang-package.mk').write_text('GO_ARCH_DEPENDS:=@aarch64||x86_64||mips\n')
            shutil.copyfile(ROOT / 'sing-box/Makefile', root / 'Makefile')
            (root / 'print.mk').write_text('show:\n\t@echo source=$(PKG_SOURCE) deps=$(PKG_BUILD_DEPENDS) prebuilt=$(CORE_PREBUILT)\n')
            if pinned:
                (root / 'core-prebuilt.mk').write_text(
                    f'CORE_PIN_VERSION:={VERSION}-r{REVISION}\nCORE_SHA256_arm64:=' + 'a'*64 +
                    '\nCORE_SHA256_amd64:=' + 'b'*64 + '\n')
            return subprocess.check_output(['make', '-s', '-f', 'Makefile', '-f', 'print.mk',
                                            f'TOPDIR={root}', f'ARCH={arch}', f'BUILD_VARIANT={variant}',
                                            'SBPROXY_CORE_SOURCE_BUILD=' + ('1' if force else '0'), 'show'],
                                           cwd=root, text=True)

    def test_prebuilt_skips_go_dependency(self):
        for arch, archive_arch in [('aarch64', 'arm64'), ('x86_64', 'amd64')]:
            values = self.make_values(arch)
            self.assertIn(f'linux-{archive_arch}.tar.gz', values)
            self.assertNotIn('golang/host', values)

    def test_fallbacks_compile_from_source(self):
        for options in [dict(pinned=False), dict(force=True), dict(variant='tiny'), dict(arch='mips')]:
            values = self.make_values(**options)
            self.assertIn(f'source=sing-box-{VERSION}.tar.gz', values)
            self.assertIn('deps=golang/host', values)


if __name__ == '__main__':
    unittest.main()
