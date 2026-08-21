#!/bin/sh

set -eu

WORKER="${1:-/tmp/adaptive-ip.uc}"
MODULE_DIR="${2:-/tmp}"
TEST_ROOT='/tmp/homeproxy-adaptive-ip-test'
UCI_DIR="$TEST_ROOT/uci"
RUN_DIR="$TEST_ROOT/run"
CORE_LOG="$TEST_ROOT/sing-box.log"
DIRECT_PORT='45231'
PROXY_PORT='45232'
API_PORT='45233'
core_pid=''
worker_pid=''

cleanup() {
	[ -z "$worker_pid" ] || kill "$worker_pid" 2>/dev/null || true
	[ -z "$core_pid" ] || kill "$core_pid" 2>/dev/null || true
	[ -z "$worker_pid" ] || wait "$worker_pid" 2>/dev/null || true
	[ -z "$core_pid" ] || wait "$core_pid" 2>/dev/null || true
	rm -rf "$TEST_ROOT"
}

trap cleanup EXIT INT TERM
rm -rf "$TEST_ROOT"
mkdir -p "$UCI_DIR" "$RUN_DIR"

cat >"$UCI_DIR/homeproxy" <<-EOF
	config homeproxy 'config'
		option routing_mode 'custom'
	config homeproxy 'routing'
		option default_outbound 'direct-out'

	config homeproxy 'infra'
		option clash_api_port '$API_PORT'
EOF

cat >"$UCI_DIR/homeproxy-adaptive" <<-EOF
	config adaptive 'main'
		option enabled '1'
		option dry_run '0'
		option outbound 'proxy-test'
		option direct_probe_port '$DIRECT_PORT'
		option proxy_probe_port '$PROXY_PORT'
		option poll_interval '10'
		option slow_seconds '5'
		option slow_bytes '65536'
		option min_observations '2'
		option probe_interval '30'
		option probe_timeout '1000'
		option probe_samples '1'
		option baseline_slow_ms '100'
		option min_improvement_ms '50'
		option min_improvement_percent '10'
		option max_rules '100'
		option max_ip_rules '20'
		option max_load '0'
EOF

cat >"$TEST_ROOT/sing-box.json" <<-EOF
{
  "log": { "level": "error", "output": "$CORE_LOG" },
  "inbounds": [
    { "type": "socks", "tag": "homeproxy-adaptive-direct-probe-in", "listen": "127.0.0.1", "listen_port": $DIRECT_PORT },
    { "type": "socks", "tag": "homeproxy-adaptive-proxy-probe-in", "listen": "127.0.0.1", "listen_port": $PROXY_PORT }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct-out", "routing_mark": 100 },
    { "type": "direct", "tag": "homeproxy-adaptive-out", "routing_mark": 100 }
  ],
  "route": {
    "rules": [
      { "inbound": "homeproxy-adaptive-direct-probe-in", "action": "route", "outbound": "direct-out", "override_address": "192.0.2.1", "override_port": 443 },
      { "inbound": "homeproxy-adaptive-proxy-probe-in", "action": "route", "outbound": "homeproxy-adaptive-out" }
    ],
    "final": "direct-out"
  },
  "experimental": { "clash_api": { "external_controller": "127.0.0.1:$API_PORT" } }
}
EOF

printf '%s\n' '{"version":1,"entries":[]}' >"$TEST_ROOT/learned.json"
: >"$CORE_LOG"

/usr/bin/sing-box check -c "$TEST_ROOT/sing-box.json"
/usr/bin/sing-box run -c "$TEST_ROOT/sing-box.json" >"$TEST_ROOT/core.stdout" 2>&1 &
core_pid=$!
sleep 2
kill -0 "$core_pid"

HOMEPROXY_UCI_CONFIG_DIR="$UCI_DIR" \
HOMEPROXY_ADAPTIVE_RUN_DIR="$RUN_DIR" \
HOMEPROXY_ADAPTIVE_RULES_PATH="$RUN_DIR/rules.json" \
HOMEPROXY_ADAPTIVE_LEARNED_PATH="$TEST_ROOT/learned.json" \
HOMEPROXY_ADAPTIVE_CORE_LOG_PATH="$CORE_LOG" \
HOMEPROXY_ADAPTIVE_STATUS_INTERVAL='1' \
	/usr/bin/ucode -S -L "$MODULE_DIR" "$WORKER" >"$TEST_ROOT/worker.log" 2>&1 &
worker_pid=$!

sleep 6
printf '%s\n' \
	'ERROR final-ip: open connection to 223.5.5.5:443 using outbound/direct[homeproxy-adaptive-final-direct-out]: failed' \
	'ERROR private-ip: open connection to 192.168.8.1:443 using outbound/direct[homeproxy-adaptive-final-direct-out]: failed' \
	>>"$CORE_LOG"

sleep 16
kill -0 "$worker_pid" 2>/dev/null || {
	cat "$TEST_ROOT/worker.log" >&2
	exit 1
}

[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[0].target')" = '223.5.5.5' ]
[ "$(jsonfilter -i "$TEST_ROOT/learned.json" -e '@.entries[0].target_type')" = 'ipv4' ]
[ "$(jsonfilter -i "$RUN_DIR/rules.json" -e '@.rules[0].ip_cidr[0]')" = '223.5.5.5/32' ]
[ "$(jsonfilter -i "$RUN_DIR/status.json" -e '@.failure_count')" -eq 1 ]

echo 'IP learning test passed: final public IP promoted to /32, private IP ignored'
