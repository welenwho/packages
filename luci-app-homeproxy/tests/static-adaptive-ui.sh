#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/homeproxy/client.js"
ADAPTIVE="$PACKAGE_ROOT/htdocs/luci-static/resources/homeproxy-adaptive.js"
OLD_VIEW="$PACKAGE_ROOT/htdocs/luci-static/resources/view/homeproxy/adaptive.js"
MENU="$PACKAGE_ROOT/root/usr/share/luci/menu.d/luci-app-homeproxy.json"

test -f "$ADAPTIVE"
test ! -e "$OLD_VIEW"

grep -Fq "'require homeproxy-adaptive as adaptive';" "$CLIENT"
grep -Fq 'adaptive.addForm(m, s, data[3]);' "$CLIENT"
grep -Fq "map.chain('homeproxy-adaptive');" "$ADAPTIVE"
grep -Fq "parentSection.tab('adaptive', _('Adaptive Routing'));" "$ADAPTIVE"
grep -Fq "o.depends('routing_mode', 'custom');" "$ADAPTIVE"
grep -Fq "s.uciconfig = 'homeproxy-adaptive';" "$ADAPTIVE"
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

if grep -Fq 'admin/services/homeproxy/adaptive' "$MENU"; then
	echo 'Adaptive Routing must not be exposed as a top-level menu item' >&2
	exit 1
fi

echo 'Adaptive UI test passed: custom-mode secondary tab uses its own UCI config'
