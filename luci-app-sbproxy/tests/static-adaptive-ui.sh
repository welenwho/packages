#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client.js"
ADAPTIVE="$PACKAGE_ROOT/htdocs/luci-static/resources/sbproxy-adaptive.js"
OLD_VIEW="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/adaptive.js"
MENU="$PACKAGE_ROOT/root/usr/share/luci/menu.d/luci-app-sbproxy.json"
MAKEFILE="$PACKAGE_ROOT/Makefile"

test -f "$ADAPTIVE"
test ! -e "$OLD_VIEW"

pkg_version="$(sed -n 's/^PKG_VERSION:=//p' "$MAKEFILE")"
pkg_release="$(sed -n 's/^PKG_RELEASE:=//p' "$MAKEFILE")"
versioned_client="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client-${pkg_version}-r${pkg_release}.js"
versioned_adaptive="$PACKAGE_ROOT/htdocs/luci-static/resources/sbproxy-adaptive-${pkg_version}-r${pkg_release}.js"
test -L "$versioned_client"
test "$(readlink "$versioned_client")" = 'client.js'
test -L "$versioned_adaptive"
test "$(readlink "$versioned_adaptive")" = 'sbproxy-adaptive.js'
grep -Fq '"path": "sbproxy/client-'"${pkg_version}"'-r'"${pkg_release}"'"' "$MENU"
grep -Fq "'require sbproxy-adaptive-${pkg_version}-r${pkg_release} as adaptive';" "$CLIENT"
grep -Fq 'adaptive.addForm(m, s, data[3]);' "$CLIENT"
grep -Fq "map.chain('sbproxy-adaptive');" "$ADAPTIVE"
grep -Fq "parentSection.tab('adaptive', _('Adaptive Routing'));" "$ADAPTIVE"
grep -Fq "o.depends('routing_mode', 'custom');" "$ADAPTIVE"
grep -Fq "o.depends('routing_mode', 'bypass_mainland_china');" "$ADAPTIVE"
grep -Fq "o.depends('routing_mode', 'global');" "$ADAPTIVE"
grep -Fq "form.Flag, 'allow_global'" "$ADAPTIVE"
grep -Fq "form.ListValue, 'candidate_trigger'" "$ADAPTIVE"
grep -Fq "o.value('failure_only', _('Failures only'));" "$ADAPTIVE"
grep -Fq "const routingMode = parentSection.formvalue('config', 'routing_mode');" "$ADAPTIVE"
grep -Fq "const enabled = this.section.formvalue(sectionId, 'enabled');" "$ADAPTIVE"
grep -Fq "const defaultOption = map.lookupOption('default_outbound', 'routing')?.[0];" "$ADAPTIVE"
grep -Fq "if (routingMode === 'custom' && defaultOutbound === 'direct-out' &&" "$ADAPTIVE"
if grep -Fq "uci.get('sbproxy-adaptive', sectionId, 'enabled')" "$ADAPTIVE"; then
	echo 'Adaptive outbound validation must use the pending form state' >&2
	exit 1
fi
grep -Fq "s.uciconfig = 'sbproxy-adaptive';" "$ADAPTIVE"
grep -Fq "s.tab('learned', _('Learned Rules'));" "$ADAPTIVE"
grep -Fq "s.tab('candidates', _('Pending Candidates'));" "$ADAPTIVE"
grep -Fq "id: 'adaptive_learned'" "$ADAPTIVE"
grep -Fq "id: 'adaptive_candidates'" "$ADAPTIVE"

tab_order="$(sed -n \
	-e "/^[[:space:]]*s\.tab('dashboard'/=" \
	-e '/^[[:space:]]*adaptive\.addForm/=' \
	-e "/^[[:space:]]*s\.tab('routing_node'/=" \
	-e "/^[[:space:]]*s\.tab('routing_rule'/=" \
	-e "/^[[:space:]]*s\.tab('dns'/=" \
	"$CLIENT" | paste -sd ' ' -)"
set -- $tab_order
test "$#" -eq 5
test "$1" -lt "$2"
test "$2" -lt "$3"
test "$3" -lt "$4"
test "$4" -lt "$5"

if grep -Fq 'admin/services/sbproxy/adaptive' "$MENU"; then
	echo 'Adaptive Routing must not be exposed as a top-level menu item' >&2
	exit 1
fi

echo 'Adaptive UI test passed: all routing modes, global opt-in, failure-only trigger, and pending-form validation exposed'
