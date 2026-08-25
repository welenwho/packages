#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SBPROXY="$PACKAGE_ROOT/htdocs/luci-static/resources/sbproxy.js"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client.js"

grep -Fq 'CBIEmptySafeMultiValue: form.MultiValue.extend({' "$SBPROXY"
grep -Fq 'return form.MultiValue.prototype.transformChoices.apply(this, arguments) || {};' "$SBPROXY"
test "$(grep -Fc "sb.CBIEmptySafeMultiValue, 'main_urltest_subscriptions'" "$CLIENT")" -eq 1
test "$(grep -Fc "sb.CBIEmptySafeMultiValue, 'urltest_subscriptions'" "$CLIENT")" -eq 1

service_guard="$(sed -n "/let view = document.getElementById('service_status');/,+2p" "$CLIENT")"
printf '%s\n' "$service_guard" | grep -Fq 'if (view)'

echo 'LuCI empty choices test passed: URLTest subscription controls and detached status polling are null-safe'
