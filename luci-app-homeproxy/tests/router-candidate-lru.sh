#!/bin/sh

set -eu

WORKER="${1:-/tmp/adaptive-candidate-lru.uc}"
MODULE_DIR="${2:-/etc/homeproxy/scripts}"
TEST_ROOT='/tmp/homeproxy-adaptive-candidate-lru-test'
UCI_DIR="$TEST_ROOT/uci"
RUN_DIR="$TEST_ROOT/run"
API_DIR="$TEST_ROOT/api"
CORE_LOG="$TEST_ROOT/sing-box-c.log"
API_PORT='45214'
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
mkdir -p "$UCI_DIR" "$RUN_DIR" "$API_DIR"

grep -Fq 'const MAX_CANDIDATES = 256;' "$WORKER"
grep -Fq 'const MAX_UNSUCCESSFUL_PROBES = 3;' "$WORKER"
grep -Fq 'const CANDIDATE_MAX_IDLE = 86400;' "$WORKER"

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
		option dry_run '1'
		option outbound 'proxy-test'
		option poll_interval '10'
		option min_observations '1'
		option probe_interval '30'
		option probe_timeout '1000'
		option probe_samples '1'
		option max_rules '100'
		option max_load '0'
EOF

printf '%s\n' '{"connections":[]}' >"$API_DIR/connections"
printf '%s\n' '{"version":1,"entries":[]}' >"$TEST_ROOT/learned.json"
: >"$CORE_LOG"

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
i=0
while [ "$i" -lt 256 ]; do
	printf 'ERROR test: open connection to candidate-%03d.example:443 using outbound/direct[homeproxy-adaptive-final-direct-out]: failed\n' \
		"$i" >>"$CORE_LOG"
	i=$((i + 1))
done

sleep 11
kill -0 "$worker_pid" 2>/dev/null || {
	cat "$TEST_ROOT/worker.log" >&2
	exit 1
}

printf '%s\n' \
	'ERROR refresh: open connection to candidate-000.example:443 using outbound/direct[homeproxy-adaptive-final-direct-out]: failed' \
	'ERROR insert: open connection to candidate-256.example:443 using outbound/direct[homeproxy-adaptive-final-direct-out]: failed' \
	>>"$CORE_LOG"

sleep 11
kill -0 "$worker_pid" 2>/dev/null || {
	cat "$TEST_ROOT/worker.log" >&2
	exit 1
}
kill "$worker_pid"
wait "$worker_pid" 2>/dev/null || true
worker_pid=''

targets="$(jsonfilter -i "$RUN_DIR/status.json" -e '@.candidates[*].target')"
count="$(printf '%s\n' "$targets" | sed '/^$/d' | wc -l)"
[ "$count" -eq 256 ]
printf '%s\n' "$targets" | grep -Fqx 'candidate-000.example'
if printf '%s\n' "$targets" | grep -Fqx 'candidate-001.example'; then
	echo 'Oldest candidate was not evicted' >&2
	exit 1
fi
printf '%s\n' "$targets" | grep -Fqx 'candidate-256.example'

echo 'Candidate LRU test passed: refreshed and new targets retained, oldest target evicted at 256'
