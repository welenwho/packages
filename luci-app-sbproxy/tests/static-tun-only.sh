#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
gen="$root/root/etc/sbproxy/scripts/generate_client.uc"
test ! -f "$root/root/etc/sbproxy/scripts/firewall_post.ut"
! grep -Eq 'tproxy|proxy_mode|self_mark' "$gen"
! grep -Eq 'tproxy|proxy_mode|self_mark' "$root/root/etc/init.d/sbproxy"
grep -Fq '+kmod-nft-queue' "$root/Makefile"
grep -Fq '+ip-full' "$root/Makefile"
grep -Fq "o.value('custom', _('Custom routing'))" "$root/htdocs/luci-static/resources/view/sbproxy/client.js"
grep -Fq 'geoip_cn.srs' "$gen"
grep -Fq 'domain_groups' "$gen"
grep -Fq 'groups_need_sniff' "$gen"
grep -Fq 'has_required_hysteria_bandwidth' "$root/root/etc/sbproxy/scripts/update_subscriptions.uc"
echo 'TUN-only checks passed: custom routing and required integrations retained'
