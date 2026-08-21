#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GENERATOR="$PACKAGE_ROOT/root/etc/homeproxy/scripts/generate_client.uc"
RUNTIME_INIT="$PACKAGE_ROOT/root/usr/libexec/homeproxy-runtime-init"
CONFIG="$PACKAGE_ROOT/root/etc/config/homeproxy-adaptive"

grep -Fq "tag: 'homeproxy-adaptive-direct-probe-in'" "$GENERATOR"
grep -Fq "tag: 'homeproxy-adaptive-proxy-probe-in'" "$GENERATOR"
grep -Fq "listen: '127.0.0.1'" "$GENERATOR"
grep -Fq 'outbound: adaptive_final_direct_tag' "$GENERATOR"
grep -Fq 'outbound: adaptive_proxy_tag' "$GENERATOR"
grep -Fq 'outbound: adaptive_target_tag' "$GENERATOR"
grep -Fq 'resolveAdaptivePolicy' "$GENERATOR"
grep -Fq "option direct_probe_port 'auto'" "$CONFIG"
grep -Fq "option proxy_probe_port 'auto'" "$CONFIG"
grep -Fq 'commit homeproxy-adaptive' "$RUNTIME_INIT"
grep -Fq 'homeproxy-adaptive.main.baseline_slow_ms' "$RUNTIME_INIT"
grep -Fq 'delete homeproxy-adaptive.main.direct_slow_ms' "$RUNTIME_INIT"

echo 'Adaptive probe test passed: loopback probes and learned rules use direction-aware paths'
