#!/bin/sh

set -eu

WORKER="${1:-/tmp/adaptive-ip-lru.uc}"
MODULE_DIR="${2:-/etc/sbproxy/scripts}"
TEST_ROOT='/tmp/sbproxy-adaptive-ip-lru-test'
UCI_DIR="$TEST_ROOT/uci"
RUN_DIR="$TEST_ROOT/run"

cleanup() {
	rm -rf "$TEST_ROOT"
}

trap cleanup EXIT INT TERM
rm -rf "$TEST_ROOT"
mkdir -p "$UCI_DIR" "$RUN_DIR"

cat >"$UCI_DIR/sbproxy" <<-'EOF'
config sbproxy 'config'
	option routing_mode 'custom'
config sbproxy 'routing'
	option default_outbound 'direct-out'
EOF

cat >"$UCI_DIR/sbproxy-adaptive" <<-'EOF'
config adaptive 'main'
	option enabled '1'
	option dry_run '0'
	option outbound 'proxy-test'
	option max_rules '100'
	option max_ip_rules '20'
EOF

printf '{"version":1,"entries":[' >"$TEST_ROOT/learned.json"
i=1
while [ "$i" -le 21 ]; do
	[ "$i" -eq 1 ] || printf ',' >>"$TEST_ROOT/learned.json"
	printf '{"target":"1.0.0.%d","target_type":"ipv4","added_at":%d,"last_seen":%d}' \
		"$i" "$i" "$i" >>"$TEST_ROOT/learned.json"
	i=$((i + 1))
done
printf ']}' >>"$TEST_ROOT/learned.json"

SBPROXY_UCI_CONFIG_DIR="$UCI_DIR" \
SBPROXY_ADAPTIVE_RUN_DIR="$RUN_DIR" \
SBPROXY_ADAPTIVE_RULES_PATH="$RUN_DIR/rules.json" \
SBPROXY_ADAPTIVE_LEARNED_PATH="$TEST_ROOT/learned.json" \
SBPROXY_ADAPTIVE_PREPARE='1' \
	/usr/bin/ucode -S -L "$MODULE_DIR" "$WORKER"

targets="$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[*].target')"
cidrs="$(jsonfilter -i "$RUN_DIR/rules.json" -e '@.rules[0].ip_cidr[*]')"
[ "$(printf '%s\n' "$targets" | wc -l)" -eq 20 ]
[ "$(printf '%s\n' "$cidrs" | wc -l)" -eq 20 ]
if printf '%s\n' "$targets" | grep -Fxq '1.0.0.1'; then
	exit 1
fi
printf '%s\n' "$targets" | grep -Fxq '1.0.0.21'

echo 'IP LRU test passed: 20-IP cap evicted the least recently used address'
