#!/bin/sh

set -eu

WORKER="${1:-/tmp/adaptive-lru.uc}"
MODULE_DIR="${2:-/etc/sbproxy/scripts}"
TEST_ROOT='/tmp/sbproxy-adaptive-lru-test'
UCI_DIR="$TEST_ROOT/uci"
RUN_DIR="$TEST_ROOT/run"
API_DIR="$TEST_ROOT/api"
CORE_LOG="$TEST_ROOT/sing-box-c.log"
API_PORT='45212'
api_pid=''
worker_pid=''

cleanup() {
	[ -z "$worker_pid" ] || kill "$worker_pid" 2>/dev/null || true
	[ -z "$api_pid" ] || kill "$api_pid" 2>/dev/null || true
	[ -z "$worker_pid" ] || wait "$worker_pid" 2>/dev/null || true
	[ -z "$api_pid" ] || wait "$api_pid" 2>/dev/null || true
	rm -rf /tmp/sbproxy-adaptive-lru-test
}

trap cleanup EXIT INT TERM
rm -rf /tmp/sbproxy-adaptive-lru-test
mkdir -p "$UCI_DIR" "$RUN_DIR" "$API_DIR/proxies/sbproxy-adaptive-final-direct-out" \
	"$API_DIR/proxies/sbproxy-adaptive-out"

cat >"$UCI_DIR/sbproxy" <<-EOF
	config sbproxy 'config'
		option routing_mode 'custom'
	config sbproxy 'routing'
		option default_outbound 'direct-out'

	config sbproxy 'infra'
		option clash_api_port '$API_PORT'
EOF

cat >"$UCI_DIR/sbproxy-adaptive" <<-EOF
	config adaptive 'main'
		option enabled '1'
		option dry_run '0'
		option outbound 'proxy-test'
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
{"connections":[{"id":"old-hit","metadata":{"host":"oldest.example","network":"tcp","destinationPort":"443"},"chains":["direct-out"],"rule":"final","download":0},{"id":"new-candidate","metadata":{"host":"new-entry.example","network":"tcp","destinationPort":"443"},"chains":["direct-out"],"rule":"final","download":0}]}
EOF
cat >"$API_DIR/proxies/sbproxy-adaptive-final-direct-out/delay" <<-'EOF'
{"delay":2000}
EOF
cat >"$API_DIR/proxies/sbproxy-adaptive-out/delay" <<-'EOF'
{"delay":200}
EOF

printf '{"version":1,"entries":[' >"$TEST_ROOT/learned.json"
printf '{"domain":"oldest.example","added_at":1,"last_seen":1,"direct_ms":2000,"proxy_ms":200,"observations":3,"reason":"proxy_faster"}' >>"$TEST_ROOT/learned.json"
i=1
while [ "$i" -lt 100 ]; do
	printf ',{"domain":"entry-%03d.example","added_at":%d,"last_seen":%d,"direct_ms":2000,"proxy_ms":200,"observations":3,"reason":"proxy_faster"}' \
		"$i" "$((1000 + i))" "$((1000 + i))" >>"$TEST_ROOT/learned.json"
	i=$((i + 1))
done
printf ']}\n' >>"$TEST_ROOT/learned.json"
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

domains="$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[*].target')"
rules="$(jsonfilter -i "$RUN_DIR/rules.json" -e '@.rules[0].domain[*]')"
count="$(printf '%s\n' "$domains" | wc -l)"
rule_count="$(printf '%s\n' "$rules" | wc -l)"

[ "$count" -eq 100 ]
[ "$rule_count" -eq 100 ]
case "$domains" in *oldest.example*) ;; *) exit 1 ;; esac
case "$domains" in *new-entry.example*) ;; *) exit 1 ;; esac
case "$domains" in *entry-001.example*) exit 1 ;; esac
case "$domains" in *entry-099.example*) ;; *) exit 1 ;; esac

echo 'LRU test passed: touched oldest retained, next oldest evicted, 100-rule cap preserved'
