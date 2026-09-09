#!/usr/bin/env python3
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PackageSourcesTests(unittest.TestCase):
    def test_binary_packages_use_own_release_repository(self):
        for package in ('axonhub', 'gecoosac'):
            makefile = (ROOT / package / 'Makefile').read_text()
            source = next(line for line in makefile.splitlines() if line.startswith('PKG_SOURCE_URL:='))
            self.assertIn('https://github.com/welenwho/packages/releases/download/', source)

    def test_axonhub_history_is_not_pruned(self):
        workflow = (ROOT / '.github/workflows/Update-AxonHub.yml').read_text()
        self.assertNotIn('ci_prune_releases', workflow)

    def test_removed_luci_package_does_not_return(self):
        self.assertFalse((ROOT / 'luci-app-axonhub/Makefile').exists())
        self.assertNotIn('luci-app-axonhub', (ROOT / '.github/scripts/generate-readme.sh').read_text())


if __name__ == '__main__':
    unittest.main()
