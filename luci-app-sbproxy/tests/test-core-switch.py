#!/usr/bin/env python3
"""Exercise transaction ordering with fake package/network/service operations.

Nothing is installed and no real router paths are accessed.
"""
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

MANAGER = Path(__file__).resolve().parents[1] / 'root/usr/libexec/sbproxy-core-manager'


class CoreSwitchTests(unittest.TestCase):
    def run_switch(self, target='1.14.0-r2', current='1.14.0-r3', failure=''):
        with tempfile.TemporaryDirectory() as tmp:
            prefix = MANAGER.read_text().split('action="${1:-status}"')[0]
            directory = shlex.quote(tmp)
            setup = f'''
STATE_DIR={directory}
ROLLBACK_APK="$STATE_DIR/rollback.apk"
ROLLBACK_META="$STATE_DIR/rollback.meta"
LOG_FILE="$STATE_DIR/test.log"
work_dir="$STATE_DIR/work"
mkdir -p "$work_dir"
CURRENT_VERSION={shlex.quote(current)}
TARGET_VERSION={shlex.quote(target)}
FAILURE={shlex.quote(failure)}
action=rollback
fetch_assets() {{ assets_file="$work_dir/assets"; : > "$assets_file"; }}
asset_by_name() {{ printf '%s\\t%s\\tsha256:abc\\t123\\t2026-09-08\\n' "$1" "$1"; }}
find_recovery_asset() {{ [ "$FAILURE" != recovery_missing ] && asset_by_name "$1"; }}
package_version() {{ printf '%s\\n' "$CURRENT_VERSION"; }}
ensure_persistent_storage() {{ [ "$FAILURE" != storage ]; }}
curl_to_file() {{ echo "download:$1"; : > "$2"; }}
verify_digest() {{ [ "$FAILURE" != checksum ]; }}
validate_apk() {{ [ "$FAILURE" != config ]; }}
validate_binary() {{ return 0; }}
service_running() {{ return 0; }}
install_apk() {{
    echo "install:$TARGET_VERSION"
    test -f "$ROLLBACK_APK" && test -f "$ROLLBACK_META" || exit 92
    [ "$FAILURE" != install ] || return 1
    CURRENT_VERSION="$TARGET_VERSION"
}}
restart_if_needed() {{ echo restart; [ "$FAILURE" != restart ]; }}
restore_rollback() {{ echo recovered; [ "$FAILURE" != recovery ]; }}
'''
            if failure == 'recovery':
                setup += 'install_apk() { return 1; }\n'
            script = prefix + setup + '\nupgrade_core "sing-box-$TARGET_VERSION.apk"\n'
            return subprocess.run(['sh', '-c', script], text=True, capture_output=True)

    def test_online_downgrade_without_local_backup(self):
        result = self.run_switch()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('rolled_back=1', result.stdout)
        self.assertLess(result.stdout.index('download:sing-box-1.14.0-r3.apk'),
                        result.stdout.index('install:1.14.0-r2'))

    def test_reinstall_and_upgrade_use_same_transaction(self):
        for target in ('1.14.0-r3', '1.14.0-r4'):
            result = self.run_switch(target=target)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rejection_does_not_install(self):
        for failure, code in [('checksum', 'checksum_mismatch'), ('config', 'candidate_rejected'),
                              ('storage', 'insufficient_storage')]:
            result = self.run_switch(failure=failure)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('error_code=' + code, result.stdout)
            self.assertNotIn('install:', result.stdout)

    def test_install_or_start_failure_restores_before_returning(self):
        for failure in ('install', 'restart'):
            result = self.run_switch(failure=failure)
            self.assertIn('recovered', result.stdout)
            self.assertIn('automatic_rollback=1', result.stdout)
            self.assertIn('error_code=upgrade_failed_rolled_back', result.stdout)

    def test_recovery_failure_is_reported(self):
        result = self.run_switch(failure='recovery')
        self.assertIn('automatic_rollback=0', result.stdout)
        self.assertIn('error_code=upgrade_and_rollback_failed', result.stdout)

    def test_missing_recovery_blocks_switch(self):
        result = self.run_switch(failure='recovery_missing')
        self.assertIn('error_code=rollback_source_unavailable', result.stdout)
        self.assertNotIn('install:', result.stdout)

    def test_invalid_target_is_rejected_before_download(self):
        result = self.run_switch(target='../../untrusted')
        self.assertIn('error_code=invalid_target', result.stdout)
        self.assertNotIn('download:', result.stdout)


if __name__ == '__main__':
    unittest.main()
