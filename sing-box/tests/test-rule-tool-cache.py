#!/usr/bin/env python3
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / '.github/scripts/prepare-rule-set-tool.sh'


class RuleToolCacheTests(unittest.TestCase):
    def test_cold_warm_and_corrupted_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            name = 'sing-box-1.14.0-linux-amd64'
            (root / 'sing-box').mkdir()
            (root / 'sing-box/Makefile').write_text('PKG_UPSTREAM_VERSION:=1.14.0\n')
            archive = root / 'upstream.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                folder = tarfile.TarInfo(name)
                folder.type = tarfile.DIRTYPE
                folder.mode = 0o755
                tar.addfile(folder)
                program = b'#!/bin/sh\necho "sing-box version 1.14.0"\n'
                member = tarfile.TarInfo(name + '/sing-box')
                member.size = len(program)
                member.mode = 0o755
                tar.addfile(member, io.BytesIO(program))
            sha = hashlib.sha256(archive.read_bytes()).hexdigest()
            metadata = root / 'metadata'
            metadata.write_text(json.dumps({'assets': [{'name': name + '.tar.gz',
                'browser_download_url': 'https://github.com/SagerNet/sing-box/releases/download/v1.14.0/' + name + '.tar.gz',
                'digest': 'sha256:' + sha}]}))
            bins = root / 'bin'
            bins.mkdir()
            def tool(name, body):
                path = bins / name
                path.write_text('#!/bin/sh\nset -eu\n' + body)
                path.chmod(0o755)
            tool('gh', 'cat "$MOCK_META"\n')
            tool('curl', 'echo download >> "$MOCK_COUNT"\nwhile [ "$1" != -o ]; do shift; done\ncp "$MOCK_ARCHIVE" "$2"\n')
            cache = root / 'cache'
            env = dict(os.environ, PATH=str(bins) + ':' + os.environ['PATH'],
                       RUNNER_TEMP=tmp, GITHUB_ENV=str(root / 'env'), GITHUB_OUTPUT=str(root / 'outputs'),
                       RULE_TOOL_CACHE=str(cache), MOCK_META=str(metadata), MOCK_ARCHIVE=str(archive), MOCK_COUNT=str(root / 'count'))
            def run(mode='prepare'):
                result = subprocess.run(['bash', str(SCRIPT), mode], cwd=root, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            run('resolve')
            self.assertIn('sha256=' + sha, (root / 'outputs').read_text())
            self.assertFalse((root / 'count').exists())
            run()
            run()
            self.assertEqual((root / 'count').read_text().count('download'), 1)
            (cache / (name + '.tar.gz')).write_bytes(b'corrupt')
            run()
            self.assertEqual((root / 'count').read_text().count('download'), 2)
            self.assertEqual(hashlib.sha256((cache / (name + '.tar.gz')).read_bytes()).hexdigest(), sha)


if __name__ == '__main__': unittest.main()
