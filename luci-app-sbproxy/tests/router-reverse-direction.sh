#!/bin/sh

set -eu

WORKER="${1:-/tmp/adaptive-reverse.uc}"
MODULE_DIR="${2:-/etc/sbproxy/scripts}"
TEST_ROOT='/tmp/sbproxy-adaptive-reverse-test'
UCI_DIR="$TEST_ROOT/uci"
RUN_DIR="$TEST_ROOT/run"
API_DIR="$TEST_ROOT/api"
CORE_LOG="$TEST_ROOT/sing-box-c.log"
API_PORT='45215'
api_pid=''
worker_pid=''

cleanup() {
	[ -z "$worker_pid" ] || kill "$worker_pid" 2>/dev/null || true
	[ -z "$api_pid" ] || kill "$api_pid" 2>/dev/null || true
	[ -z "$worker_pid" ] || wait "$worker_pid" 2>/dev/null || true
	[ -z "$api_pid" ] || wait "$api_pid" 2>/dev/null || true
	rm -rf "$TEST_ROOT"
}

trap cleanup EXIT INT TERM
rm -rf "$TEST_ROOT"
mkdir -p "$UCI_DIR" "$RUN_DIR" \
	"$API_DIR/proxies/sbproxy-adaptive-final-direct-out" \
	"$API_DIR/proxies/sbproxy-adaptive-out"

cat >"$UCI_DIR/sbproxy" <<-EOF
config sbproxy 'config'
	option routing_mode 'custom'
config sbproxy 'routing'
	option default_outbound 'proxy-route'
config sbproxy 'infra'
	option clash_api_port '$API_PORT'
EOF

cat >"$UCI_DIR/sbproxy-adaptive" <<-'EOF'
config adaptive 'main'
	option enabled '1'
	option dry_run '0'
	option candidate_trigger 'slow_or_failure'
	option poll_interval '10'
	option slow_seconds '5'
	option slow_bytes '65536'
	option min_observations '1'
	option probe_interval '30'
	option probe_timeout '1000'
	option probe_samples '1'
	option baseline_slow_ms '100'
	option min_improvement_ms '50'
	option min_improvement_percent '10'
	option max_rules '100'
	option max_load '0'
EOF

cat >"$API_DIR/connections" <<-'EOF'
{"connections":[{"id":"reverse","metadata":{"host":"reverse.example","network":"tcp","destinationPort":"443"},"chains":["sbproxy-adaptive-out"],"rule":"final","download":0}]}
EOF
printf '%s\n' '{"delay":200}' >"$API_DIR/proxies/sbproxy-adaptive-final-direct-out/delay"
printf '%s\n' '{"delay":2000}' >"$API_DIR/proxies/sbproxy-adaptive-out/delay"
printf '%s\n' '{"version":2,"entries":[]}' >"$TEST_ROOT/learned.json"
: >"$CORE_LOG"

/usr/sbin/uhttpd -f -D -S -N 2 -p "127.0.0.1:$API_PORT" -h "$API_DIR" \
	>"$TEST_ROOT/api.log" 2>&1 &
api_pid=$!

SBPROXY_UCI_CONFIG_DIR="$UCI_DIR" \
SBPROXY_ADAPTIVE_RUN_DIR="$RUN_DIR" \
SBPROXY_ADAPTIVE_RULES_PATH="$RUN_DIR/rules.json" \
SBPROXY_ADAPTIVE_LEARNED_PATH="$TEST_ROOT/learned.json" \
SBPROXY_ADAPTIVE_CORE_LOG_PATH="$CORE_LOG" \
SBPROXY_ADAPTIVE_STATUS_INTERVAL='1' \
	/usr/bin/ucode -S -L "$MODULE_DIR" "$WORKER" \
	>"$TEST_ROOT/worker.log" 2>&1 &
worker_pid=$!

sleep 18
kill -0 "$worker_pid" 2>/dev/null || {
	cat "$TEST_ROOT/worker.log" >&2
	exit 1
}
kill "$worker_pid"
wait "$worker_pid" 2>/dev/null || true
worker_pid=''

[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[0].target')" = 'reverse.example' ]
[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[0].policy_id')" = 'custom|routing:proxy-route|direct' ]
[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[0].direct_ms')" = '200' ]
[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[0].proxy_ms')" = '2000' ]
[ "$(jsonfilter -i "$RUN_DIR/rules.json" -e '@.rules[0].domain[0]')" = 'reverse.example' ]

echo 'Reverse-direction test passed: proxy-default traffic learned a direct exception'
