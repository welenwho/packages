#!/bin/sh

set -eu

RPC_PLUGIN="${1:-/tmp/luci-homeproxy-lru.uc}"
RPC_TEST="${2:-/tmp/router-rpc-remove.uc}"
MODULE_DIR="${3:-/etc/homeproxy/scripts}"
TEST_ROOT='/tmp/homeproxy-adaptive-rpc-test'
UCI_DIR="$TEST_ROOT/uci"
RUN_DIR="$TEST_ROOT/run"

cleanup() {
	rm -rf /tmp/homeproxy-adaptive-rpc-test
}

trap cleanup EXIT INT TERM
rm -rf /tmp/homeproxy-adaptive-rpc-test
mkdir -p "$UCI_DIR" "$RUN_DIR"

cat >"$UCI_DIR/homeproxy-adaptive" <<-'EOF'
config adaptive 'main'
	option enabled '1'
	option dry_run '0'
EOF
cat >"$TEST_ROOT/learned.json" <<-'EOF'
{"version":1,"entries":[{"target":"1.1.1.1","target_type":"ipv4","added_at":1,"last_seen":10},{"domain":"keep.example","added_at":2,"last_seen":11}]}
EOF
cat >"$RUN_DIR/status.json" <<-'EOF'
{"version":1,"learned":[{"target":"1.1.1.1","target_type":"ipv4","last_seen":19},{"target":"keep.example","target_type":"domain","last_seen":20}]}
EOF

HOMEPROXY_UCI_CONFIG_DIR="$UCI_DIR" \
HOMEPROXY_ADAPTIVE_LEARNED_PATH="$TEST_ROOT/learned.json" \
HOMEPROXY_ADAPTIVE_RULES_PATH="$RUN_DIR/rules.json" \
HOMEPROXY_ADAPTIVE_STATUS_PATH="$RUN_DIR/status.json" \
HOMEPROXY_ADAPTIVE_SERVICE='/bin/false' \
	/usr/bin/ucode -S -L "$MODULE_DIR" "$RPC_TEST" "$RPC_PLUGIN"

[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[*].domain')" = 'keep.example' ]
[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[0].last_seen')" = '20' ]
[ "$(jsonfilter -i "$RUN_DIR/rules.json" -e '@.rules[0].domain[*]')" = 'keep.example' ]
[ ! -e "$RUN_DIR/status.json" ]

echo 'RPC remove state/rule-set hot update test passed'
