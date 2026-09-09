#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MANAGER="$PACKAGE_ROOT/root/usr/libexec/sbproxy-core-manager"
RPC="$PACKAGE_ROOT/root/usr/share/rpcd/ucode/luci.sbproxy"
ACL="$PACKAGE_ROOT/root/usr/share/rpcd/acl.d/luci-app-sbproxy.json"
MENU="$PACKAGE_ROOT/root/usr/share/luci/menu.d/luci-app-sbproxy.json"
CORE_VIEW="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/core.js"

test -x "$MANAGER"
sh -n "$MANAGER"

grep -Fq 'REPOSITORY="welenwho/packages"' "$MANAGER"
grep -Fq 'with_tailscale' "$MANAGER"
grep -Fq 'with_clash_api' "$MANAGER"
grep -Fq 'with_gvisor' "$MANAGER"
grep -Fq 'with_quic' "$MANAGER"
grep -Fq 'with_wireguard' "$MANAGER"
grep -Fq 'verify_digest "$candidate_apk"' "$MANAGER"
grep -Fq 'validate_configs "$extract_dir/usr/bin/sing-box"' "$MANAGER"
grep -Fq 'SBPROXY_CLIENT_CONFIG_PATH=' "$MANAGER"
grep -Fq 'SBPROXY_SERVER_CONFIG_PATH=' "$MANAGER"
grep -Fq 'restore_rollback "$was_running"' "$MANAGER"
grep -Fq 'running sing-box-c' "$MANAGER"
grep -Fq 'running sing-box-s' "$MANAGER"
grep -Fq 'capture_expected_cores' "$MANAGER"
grep -Fq 'health_signature' "$MANAGER"
grep -Fq '"$signature" = "$last_signature"' "$MANAGER"
grep -Fq 'apk add --allow-untrusted --upgrade --force-reinstall' "$MANAGER"
! grep -Eq '(^|[[:space:]])(cp|mv).*/usr/bin/sing-box' "$MANAGER"

grep -Fq 'core_status:' "$RPC"
grep -Fq 'core_check_update:' "$RPC"
grep -Fq 'core_upgrade:' "$RPC"
grep -Fq 'core_rollback:' "$RPC"
grep -Fq '"core_check_update", "core_status"' "$ACL"
grep -Fq '"core_rollback", "core_upgrade"' "$ACL"
grep -Fq '"path": "sbproxy/core-' "$MENU"
grep -Fq "method: 'core_upgrade'" "$CORE_VIEW"
grep -Fq "method: 'core_rollback'" "$CORE_VIEW"

echo 'SBProxy core management static checks passed'
