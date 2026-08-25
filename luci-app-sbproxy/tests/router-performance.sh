#!/bin/sh

set -eu

WORKER="${1:-/tmp/adaptive.uc}"
MODULE_DIR="${2:-/etc/sbproxy/scripts}"
BENCH_DIR='/tmp/sbproxy-adaptive-bench'
PERF_RUN_DIR='/tmp/sbproxy-adaptive-perf'
UCI_DIR='/tmp/sbproxy-adaptive-perf-uci'
HTTP_PORT='45200'
MIXED_PORT='45201'
API_PORT='45202'
ITERATIONS='128'
PAYLOAD_MIB='32'

http_pid=''
core_pid=''
worker_pid=''

cleanup_case() {
	[ -z "$worker_pid" ] || kill "$worker_pid" 2>/dev/null || true
	[ -z "$core_pid" ] || kill "$core_pid" 2>/dev/null || true
	[ -z "$worker_pid" ] || wait "$worker_pid" 2>/dev/null || true
	[ -z "$core_pid" ] || wait "$core_pid" 2>/dev/null || true
	worker_pid=''
	core_pid=''
}

cleanup() {
	cleanup_case
	[ -z "$http_pid" ] || kill "$http_pid" 2>/dev/null || true
	[ -z "$http_pid" ] || wait "$http_pid" 2>/dev/null || true
}

wait_http() {
	local url="$1"
	local attempt
	for attempt in 1 2 3 4 5; do
		if curl -fsS --connect-timeout 1 --max-time 1 --range 0-0 "$url" >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
	done
	return 1
}

wait_proxy() {
	local attempt
	for attempt in 1 2 3 4 5; do
		if curl -fsS --connect-timeout 1 --max-time 2 --range 0-0 --noproxy '' \
		   --proxy "http://127.0.0.1:$MIXED_PORT" \
		   "http://127.0.0.1:$HTTP_PORT/payload.bin" >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
	done
	return 1
}

process_ticks() {
	awk '{ print $14 + $15 }' "/proc/$1/stat"
}

process_rss_kib() {
	awk '/^VmRSS:/ { print $2; exit }' "/proc/$1/status"
}

uptime_ms() {
	awk '{ printf "%.0f\n", $1 * 1000 }' /proc/uptime
}

run_case() {
	local label="$1"
	local config="$2"
	local with_worker="$3"
	local attempt start_ms end_ms elapsed_ms start_ticks end_ticks ticks rss worker_rss polls

	/usr/bin/sing-box run -c "$config" >/tmp/sbproxy-adaptive-perf-core.log 2>&1 &
	core_pid=$!
	wait_proxy || {
		cat /tmp/sbproxy-adaptive-perf-core.log >&2
		return 1
	}

	if [ "$with_worker" = '1' ]; then
		SBPROXY_UCI_CONFIG_DIR="$UCI_DIR" \
		SBPROXY_ADAPTIVE_RUN_DIR="$PERF_RUN_DIR" \
		SBPROXY_ADAPTIVE_RULES_PATH="$PERF_RUN_DIR/rules.json" \
		SBPROXY_ADAPTIVE_LEARNED_PATH="$PERF_RUN_DIR/learned.json" \
		SBPROXY_ADAPTIVE_CORE_LOG_PATH="$PERF_RUN_DIR/sing-box-c.log" \
			nice -n 10 /usr/bin/ucode -S -L "$MODULE_DIR" "$WORKER" \
			>/tmp/sbproxy-adaptive-perf-worker.log 2>&1 &
		worker_pid=$!
		sleep 6
	fi

	rss="$(process_rss_kib "$core_pid")"
	worker_rss='0'
	[ -z "$worker_pid" ] || worker_rss="$(process_rss_kib "$worker_pid")"
	start_ticks="$(process_ticks "$core_pid")"
	start_ms="$(uptime_ms)"

	attempt=0
	while [ "$attempt" -lt "$ITERATIONS" ]; do
		curl -fsS --noproxy '' --proxy "http://127.0.0.1:$MIXED_PORT" \
			"http://127.0.0.1:$HTTP_PORT/payload.bin" -o /dev/null
		attempt=$((attempt + 1))
	done

	end_ms="$(uptime_ms)"
	end_ticks="$(process_ticks "$core_pid")"
	elapsed_ms=$((end_ms - start_ms))
	ticks=$((end_ticks - start_ticks))
	polls='0'
	[ "$with_worker" != '1' ] || [ ! -s "$PERF_RUN_DIR/status.json" ] || \
		polls="$(jsonfilter -i "$PERF_RUN_DIR/status.json" -e '@.poll_count')"

	awk -v label="$label" -v elapsed="$elapsed_ms" -v ticks="$ticks" \
		-v iterations="$ITERATIONS" -v size="$PAYLOAD_MIB" -v rss="$rss" \
		-v worker_rss="$worker_rss" -v polls="$polls" 'BEGIN {
		printf "%s elapsed_ms=%d throughput_mib_s=%.2f core_cpu_pct=%.2f core_rss_kib=%d worker_rss_kib=%d polls=%d\n",
			label, elapsed, iterations * size * 1000 / elapsed,
			ticks * 1000 / elapsed, rss, worker_rss, polls
	}'

	cleanup_case
	sleep 2
}

trap cleanup EXIT INT TERM

mkdir -p "$BENCH_DIR" "$PERF_RUN_DIR" "$UCI_DIR"
rm -f "$PERF_RUN_DIR/status.json" "$PERF_RUN_DIR/write.lock"
dd if=/dev/zero of="$BENCH_DIR/payload.bin" bs=1M count="$PAYLOAD_MIB" 2>/dev/null
cp /etc/config/sbproxy "$UCI_DIR/sbproxy"
cp /tmp/sbproxy-adaptive.test "$UCI_DIR/sbproxy-adaptive"
uci -c "$UCI_DIR" -q batch <<-EOF
	set sbproxy.infra.clash_api_port='$API_PORT'
	set sbproxy-adaptive.main.enabled='1'
	set sbproxy-adaptive.main.dry_run='1'
	set sbproxy-adaptive.main.outbound='welen_urltest'
	set sbproxy-adaptive.main.poll_interval='10'
	set sbproxy-adaptive.main.max_load='0'
	commit sbproxy
	commit sbproxy-adaptive
EOF
cp /tmp/rules-empty.json "$PERF_RUN_DIR/rules.json"
cp /tmp/learned-empty.json "$PERF_RUN_DIR/learned.json"
: >"$PERF_RUN_DIR/sing-box-c.log"

/usr/sbin/uhttpd -f -D -S -N 8 -p "127.0.0.1:$HTTP_PORT" -h "$BENCH_DIR" \
	>/tmp/sbproxy-adaptive-perf-http.log 2>&1 &
http_pid=$!
wait_http "http://127.0.0.1:$HTTP_PORT/payload.bin"

run_case baseline-a /tmp/perf-baseline.json 0
run_case api-only /tmp/perf-adaptive.json 0
run_case api-worker /tmp/perf-adaptive.json 1
run_case baseline-b /tmp/perf-baseline.json 0
