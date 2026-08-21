#!/bin/sh

set -eu

INIT_SCRIPT="$(dirname "$0")/../root/etc/init.d/tailscale"
FUNCTIONS="$(sed -n '/^normalize_wg_batch_size() {/,/^}/p' "$INIT_SCRIPT")"
[ -n "$FUNCTIONS" ] || {
	echo 'normalize_wg_batch_size function not found' >&2
	exit 1
}
eval "$FUNCTIONS"

assert_normalized() {
	input="$1"
	expected="$2"
	actual="$(normalize_wg_batch_size "$input")"
	[ "$actual" = "$expected" ] || {
		echo "normalize_wg_batch_size '$input': got '$actual', expected '$expected'" >&2
		exit 1
	}
}

assert_normalized '' ''
assert_normalized 1 1
assert_normalized 8 8
assert_normalized 16 16
assert_normalized 32 32
assert_normalized 64 64
assert_normalized 128 128
assert_normalized 7 7
assert_normalized 0 ''
assert_normalized 129 ''
assert_normalized invalid ''
assert_normalized -1 ''
assert_normalized 999999999999999999999999 ''

grep -q 'TS_DEBUG_WG_BATCH_SIZE=' "$INIT_SCRIPT"
grep -q 'wg_batch_size=%s' "$INIT_SCRIPT"

echo 'init batch-size tests passed'
