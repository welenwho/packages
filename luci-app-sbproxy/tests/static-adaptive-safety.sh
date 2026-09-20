#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
worker="$root/root/etc/sbproxy/scripts/adaptive.uc"
generator="$root/root/etc/sbproxy/scripts/generate_client.uc"
firewall="$root/root/etc/sbproxy/scripts/firewall_pre.uc"
grep -Fq 'domainDelay(PROBE_DIRECT_TAG' "$worker"
grep -Fq 'candidate.next_probe = time() + PROBE_COOLDOWN' "$worker"
grep -Fq 'int(settings.probe_samples / 2) + 1' "$worker"
grep -Fq "{ rule_set: ['geoip-cn', 'geosite-cn'], invert: true }" "$generator"
grep -Fq "network: 'tcp', port: 443" "$root/root/etc/sbproxy/scripts/sbproxy.uc"
grep -Fq 'iifname != { ${allowed} }' "$firewall"
grep -Fq 'input = [' "$firewall"
echo 'Adaptive safety and dashboard interface scope checks passed'
