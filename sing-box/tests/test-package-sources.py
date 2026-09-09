#!/usr/bin/env python3
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PackageSourcesTests(unittest.TestCase):
    def test_binary_packages_use_own_release_repository(self):
        for package in ('gecoosac',):
            makefile = (ROOT / package / 'Makefile').read_text()
            source = next(line for line in makefile.splitlines() if line.startswith('PKG_SOURCE_URL:='))
            self.assertIn('https://github.com/welenwho/packages/releases/download/', source)


if __name__ == '__main__':
    unittest.main()
