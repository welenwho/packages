#!/bin/sh

set -eu

WORKER="${1:-/tmp/adaptive-fast-failure.uc}"
MODULE_DIR="${2:-/etc/homeproxy/scripts}"
TEST_ROOT='/tmp/homeproxy-adaptive-fast-failure-test'
UCI_DIR="$TEST_ROOT/uci"
RUN_DIR="$TEST_ROOT/run"
API_DIR="$TEST_ROOT/api"
CORE_LOG="$TEST_ROOT/sing-box-c.log"
API_PORT='45213'
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
mkdir -p "$UCI_DIR" "$RUN_DIR" "$API_DIR/proxies/direct-out" \
	"$API_DIR/proxies/homeproxy-adaptive-out"

cat >"$UCI_DIR/homeproxy" <<-EOF
	config homeproxy 'config'
		option routing_mode 'custom'
	config homeproxy 'routing'
		option default_outbound 'direct-out'

	config homeproxy 'infra'
		option clash_api_port '$API_PORT'
EOF

cat >"$UCI_DIR/homeproxy-adaptive" <<-'EOF'
	config adaptive 'main'
		option enabled '1'
		option dry_run '0'
		option outbound 'proxy-test'
		option candidate_trigger 'failure_only'
		option poll_interval '10'
		option slow_seconds '5'
		option slow_bytes '65536'
		option min_observations '10'
		option probe_interval '30'
		option probe_timeout '1000'
		option probe_samples '1'
		option baseline_slow_ms '100'
		option min_improvement_ms '50'
		option min_improvement_percent '10'
		option max_rules '100'
		option max_load '0'
EOF

printf '%s\n' \
	'ERROR stale: open connection to stale.example:443 using outbound/direct[homeproxy-adaptive-final-direct-out]: failed' \
	>"$CORE_LOG"
cat >"$API_DIR/connections" <<-'EOF'
{"connections":[{"id":"slow-ignored","metadata":{"host":"slow-ignored.example","network":"tcp","destinationPort":"443"},"chains":["direct-out"],"rule":"final","download":0}]}
EOF
printf '%s\n' '{"delay":200}' >"$API_DIR/proxies/homeproxy-adaptive-out/delay"
printf '%s\n' '{"version":1,"entries":[]}' >"$TEST_ROOT/learned.json"

/usr/sbin/uhttpd -f -D -S -N 2 -p "127.0.0.1:$API_PORT" -h "$API_DIR" \
	>"$TEST_ROOT/api.log" 2>&1 &
api_pid=$!

HOMEPROXY_UCI_CONFIG_DIR="$UCI_DIR" \
HOMEPROXY_ADAPTIVE_RUN_DIR="$RUN_DIR" \
HOMEPROXY_ADAPTIVE_RULES_PATH="$RUN_DIR/rules.json" \
HOMEPROXY_ADAPTIVE_LEARNED_PATH="$TEST_ROOT/learned.json" \
HOMEPROXY_ADAPTIVE_CORE_LOG_PATH="$CORE_LOG" \
HOMEPROXY_ADAPTIVE_STATUS_INTERVAL='1' \
	/usr/bin/ucode -S -L "$MODULE_DIR" "$WORKER" \
	>"$TEST_ROOT/worker.log" 2>&1 &
worker_pid=$!

sleep 6
printf '%s\n' \
	'ERROR explicit: open connection to explicit.example:443 using outbound/direct[direct-out]: failed' \
	'ERROR final: open connection to final-fail.example:443 using outbound/direct[homeproxy-adaptive-final-direct-out]: failed' \
	'ERROR final-ip: open connection to 1.1.1.1:443 using outbound/direct[homeproxy-adaptive-final-direct-out]: failed' \
	'ERROR private-ip: open connection to 192.168.8.1:443 using outbound/direct[homeproxy-adaptive-final-direct-out]: failed' \
	>"$CORE_LOG"

sleep 12
kill -0 "$worker_pid" 2>/dev/null || {
	cat "$TEST_ROOT/worker.log" >&2
	exit 1
}
kill "$worker_pid"
wait "$worker_pid" 2>/dev/null || true
worker_pid=''

targets="$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[*].target')"
[ "$targets" = 'final-fail.example' ]

status_failures="$(jsonfilter -i "$RUN_DIR/status.json" -e '@.failure_count')"
[ "$status_failures" -eq 2 ]
[ "$(jsonfilter -i "$RUN_DIR/status.json" -e '@.candidates[0].target')" = '1.1.1.1' ]
[ "$(jsonfilter -i "$RUN_DIR/status.json" -e '@.candidates[0].target_type')" = 'ipv4' ]
if jsonfilter -i "$RUN_DIR/status.json" -e '@.candidates[*].target' | grep -Fqx 'slow-ignored.example'; then
	echo 'Failure-only mode incorrectly observed a slow connection' >&2
	exit 1
fi

echo 'Fast-failure test passed: failure-only mode detected final failures and ignored slow/explicit/private targets'
