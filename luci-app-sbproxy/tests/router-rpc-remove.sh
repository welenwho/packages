#!/bin/sh

set -eu

RPC_PLUGIN="${1:-/tmp/luci-sbproxy-lru.uc}"
RPC_TEST="${2:-/tmp/router-rpc-remove.uc}"
MODULE_DIR="${3:-/etc/sbproxy/scripts}"
TEST_ROOT='/tmp/sbproxy-adaptive-rpc-test'
UCI_DIR="$TEST_ROOT/uci"
RUN_DIR="$TEST_ROOT/run"

cleanup() {
	rm -rf /tmp/sbproxy-adaptive-rpc-test
}

trap cleanup EXIT INT TERM
rm -rf /tmp/sbproxy-adaptive-rpc-test
mkdir -p "$UCI_DIR" "$RUN_DIR"

cat >"$UCI_DIR/sbproxy-adaptive" <<-'EOF'
config adaptive 'main'
	option enabled '1'
	option dry_run '0'
	option outbound 'proxy-test'
EOF
cat >"$UCI_DIR/sbproxy" <<-'EOF'
config sbproxy 'config'
	option routing_mode 'custom'
config sbproxy 'routing'
	option default_outbound 'direct-out'
EOF
cat >"$TEST_ROOT/learned.json" <<-'EOF'
{"version":2,"entries":[{"target":"1.1.1.1","target_type":"ipv4","added_at":1,"last_seen":10},{"domain":"keep.example","added_at":2,"last_seen":11},{"policy_id":"global|main:other|direct","domain":"inactive.example","added_at":3,"last_seen":12}]}
EOF
cat >"$RUN_DIR/status.json" <<-'EOF'
{"version":1,"learned":[{"target":"1.1.1.1","target_type":"ipv4","last_seen":19},{"target":"keep.example","target_type":"domain","last_seen":20}]}
EOF

SBPROXY_UCI_CONFIG_DIR="$UCI_DIR" \
SBPROXY_ADAPTIVE_LEARNED_PATH="$TEST_ROOT/learned.json" \
SBPROXY_ADAPTIVE_RULES_PATH="$RUN_DIR/rules.json" \
SBPROXY_ADAPTIVE_STATUS_PATH="$RUN_DIR/status.json" \
SBPROXY_ADAPTIVE_SERVICE='/bin/false' \
	/usr/bin/ucode -S -L "$MODULE_DIR" "$RPC_TEST" "$RPC_PLUGIN"

[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.version')" = '2' ]
[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[0].domain')" = 'keep.example' ]
[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[0].last_seen')" = '20' ]
[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[1].domain')" = 'inactive.example' ]
[ "$(jsonfilter -i "$RUN_DIR/rules.json" -e '@.rules[0].domain[*]')" = 'keep.example' ]
[ ! -e "$RUN_DIR/status.json" ]

echo 'RPC remove test passed: active policy updated and inactive policy state preserved'
