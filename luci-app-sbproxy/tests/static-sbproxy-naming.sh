#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
legacy_word='home''proxy'

references="$(grep -Ril "$legacy_word" "$PACKAGE_ROOT" || true)"

for reference in $references; do
	relative="${reference#"$PACKAGE_ROOT/"}"
	case "$relative" in
	root/etc/uci-defaults/00-luci-sbproxy-migrate|\
	root/etc/uci-defaults/luci-sbproxy|\
	root/etc/init.d/sbproxy|\
	tests/static-embedded-tailscale.sh|\
	tests/test-legacy-migration.sh)
		;;
	*)
		echo "Unexpected legacy product reference in $relative" >&2
		exit 1
		;;
	esac
done

if find "$PACKAGE_ROOT" -iname "*$legacy_word*" -print | grep -q .; then
	echo 'Legacy product name remains in an SBProxy file or directory name' >&2
	exit 1
fi

echo 'SBProxy naming test passed: legacy references are restricted to migration compatibility code'
