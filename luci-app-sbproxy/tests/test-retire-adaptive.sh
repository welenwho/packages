#!/bin/sh
set -eu
PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$PACKAGE_ROOT/root/etc/uci-defaults/01-luci-sbproxy-retire-adaptive"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sbproxy-retirement-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM

mkdir -p "$TEST_ROOT/etc/config" "$TEST_ROOT/etc/sbproxy/adaptive" \
	"$TEST_ROOT/etc/sbproxy/scripts" "$TEST_ROOT/etc/rc.d" \
	"$TEST_ROOT/etc/init.d" "$TEST_ROOT/var/run/sbproxy-adaptive"
printf '%s\n' 'main config unchanged' > "$TEST_ROOT/etc/config/sbproxy"
printf '%s\n' 'old enabled config' > "$TEST_ROOT/etc/config/sbproxy-adaptive"
printf '%s\n' '{"entries":[{"domain":"example.com"}]}' > "$TEST_ROOT/etc/sbproxy/adaptive/learned.json"
printf '%s\n' 'old worker' > "$TEST_ROOT/etc/sbproxy/scripts/adaptive.uc"
printf '%s\n' 'old init' > "$TEST_ROOT/etc/init.d/sbproxy-adaptive"
printf '%s\n' '{}' > "$TEST_ROOT/var/run/sbproxy-adaptive/rules.json"
printf '%s\n' '{}' > "$TEST_ROOT/var/run/sbproxy-adaptive/status.json"
printf '%s\n' 'unknown file must survive' > "$TEST_ROOT/var/run/sbproxy-adaptive/user-note"
ln -s ../init.d/sbproxy-adaptive "$TEST_ROOT/etc/rc.d/S98sbproxy-adaptive"
ln -s ../init.d/sbproxy-adaptive "$TEST_ROOT/etc/rc.d/K11sbproxy-adaptive"
ln -s ../init.d/sbproxy "$TEST_ROOT/etc/rc.d/S99sbproxy"

SBPROXY_RETIRE_ROOT="$TEST_ROOT" sh "$SCRIPT"
test ! -e "$TEST_ROOT/etc/config/sbproxy-adaptive"
test ! -e "$TEST_ROOT/etc/sbproxy/adaptive"
test ! -e "$TEST_ROOT/etc/sbproxy/scripts/adaptive.uc"
test ! -L "$TEST_ROOT/etc/rc.d/S98sbproxy-adaptive"
test ! -L "$TEST_ROOT/etc/rc.d/K11sbproxy-adaptive"
test -L "$TEST_ROOT/etc/rc.d/S99sbproxy"
test ! -e "$TEST_ROOT/var/run/sbproxy-adaptive/rules.json"
test -f "$TEST_ROOT/var/run/sbproxy-adaptive/user-note"
grep -Fq 'main config unchanged' "$TEST_ROOT/etc/config/sbproxy"
set -- "$TEST_ROOT/etc/sbproxy/retired-adaptive"/backup.*
test "$#" -eq 1
backup="$1"
grep -Fq 'old enabled config' "$backup/config"
grep -Fq 'example.com' "$backup/data/learned.json"
grep -Fq 'old worker' "$backup/worker.uc"
grep -Fq 'old init' "$backup/init-script"
SBPROXY_RETIRE_ROOT="$TEST_ROOT" sh "$SCRIPT"
set -- "$TEST_ROOT/etc/sbproxy/retired-adaptive"/backup.*
test "$#" -eq 1

# Restored old settings must get a separate archive, not overwrite a backup.
printf '%s\n' 'second old config' > "$TEST_ROOT/etc/config/sbproxy-adaptive"
SBPROXY_RETIRE_ROOT="$TEST_ROOT" sh "$SCRIPT"
grep -Fq 'old enabled config' "$backup/config"
set -- "$TEST_ROOT/etc/sbproxy/retired-adaptive"/backup.*
test "$#" -eq 2

mkdir -p "$TEST_ROOT/fresh"
SBPROXY_RETIRE_ROOT="$TEST_ROOT/fresh" sh "$SCRIPT"
test ! -e "$TEST_ROOT/fresh/etc/sbproxy/retired-adaptive"
if SBPROXY_RETIRE_ROOT=relative sh "$SCRIPT" 2>/dev/null; then
	echo 'Relative root incorrectly accepted' >&2
	exit 1
fi
echo 'Retirement tests passed: archives, idempotence, fresh install and unrelated data preservation'
