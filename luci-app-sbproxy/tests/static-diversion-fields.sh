#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
view="$root/htdocs/luci-static/resources/view/sbproxy/client.js"
generator="$root/root/etc/sbproxy/scripts/generate_client.uc"
grep -Fq "s.tab('diversion', _('Rule Diversion'))" "$view"
grep -Fq "s.taboption('diversion', form.SectionValue, '_domain_groups'" "$view"
grep -Fq 'renderRouteMatch(cfg, get_ruleset(cfg.rule_set))' "$generator"
grep -Fq 'if (!group.dns_match) continue;' "$generator"
grep -Fq 'render_rule_set(cfg, outbound)' "$generator"
grep -Fq 'diversion_download_outbound' "$view"
grep -Fq 'diversion_download_outbound' "$generator"
echo 'Shared diversion fields and rule-set wiring checks passed'
