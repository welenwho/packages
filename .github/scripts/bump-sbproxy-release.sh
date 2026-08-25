#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
PACKAGE_ROOT="$REPO_ROOT/luci-app-sbproxy"
MAKEFILE="$PACKAGE_ROOT/Makefile"
MENU="$PACKAGE_ROOT/root/usr/share/luci/menu.d/luci-app-sbproxy.json"
CLIENT="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client.js"

make_value() {
	sed -n "s/^$1:=//p" "$MAKEFILE" | head -n1
}

replace_once() {
	local file="$1"
	local old="$2"
	local new="$3"
	local count pattern

	count="$(awk -v needle="$old" '
		{
			line = $0
			while ((position = index(line, needle)) > 0) {
				count++
				line = substr(line, position + length(needle))
			}
		}
		END { print count + 0 }
	' "$file")"
	[[ "$count" -eq 1 ]] || {
		printf 'Expected exactly one %s reference in %s, found %s.\n' \
			"$old" "$file" "$count" >&2
		return 1
	}

	pattern="${old//./\\.}"
	sed -i.bak "s|$pattern|$new|" "$file"
	rm -f -- "$file.bak"
}

version="$(make_value PKG_VERSION)"
release="$(make_value PKG_RELEASE)"
[[ -n "$version" ]] || {
	echo 'PKG_VERSION is missing from luci-app-sbproxy/Makefile.' >&2
	exit 1
}
[[ "$release" =~ ^[0-9]+$ ]] || {
	printf 'PKG_RELEASE must be numeric: %s\n' "$release" >&2
	exit 1
}

new_release=$((10#$release + 1))
cache_version="$(printf '%s\n' "$version" | sed 's/[^A-Za-z0-9_-]/-/g')"
old_cache_key="${cache_version}-r${release}"
new_cache_key="${cache_version}-r${new_release}"
old_adaptive="$PACKAGE_ROOT/htdocs/luci-static/resources/sbproxy-adaptive-${old_cache_key}.js"
new_adaptive="$PACKAGE_ROOT/htdocs/luci-static/resources/sbproxy-adaptive-${new_cache_key}.js"
old_client="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client-${old_cache_key}.js"
new_client="$PACKAGE_ROOT/htdocs/luci-static/resources/view/sbproxy/client-${new_cache_key}.js"

[[ -L "$old_adaptive" && "$(readlink "$old_adaptive")" == 'sbproxy-adaptive.js' ]] || {
	printf 'Invalid adaptive cache symlink: %s\n' "$old_adaptive" >&2
	exit 1
}
[[ -L "$old_client" && "$(readlink "$old_client")" == 'client.js' ]] || {
	printf 'Invalid client cache symlink: %s\n' "$old_client" >&2
	exit 1
}
[[ ! -e "$new_adaptive" && ! -L "$new_adaptive" ]] || {
	printf 'Target adaptive cache path already exists: %s\n' "$new_adaptive" >&2
	exit 1
}
[[ ! -e "$new_client" && ! -L "$new_client" ]] || {
	printf 'Target client cache path already exists: %s\n' "$new_client" >&2
	exit 1
}

replace_once "$MENU" "$old_cache_key" "$new_cache_key"
replace_once "$CLIENT" "$old_cache_key" "$new_cache_key"
replace_once "$MAKEFILE" "PKG_RELEASE:=$release" "PKG_RELEASE:=$new_release"
mv -- "$old_adaptive" "$new_adaptive"
mv -- "$old_client" "$new_client"

[[ "$(make_value PKG_RELEASE)" == "$new_release" ]]
[[ "$(readlink "$new_adaptive")" == 'sbproxy-adaptive.js' ]]
[[ "$(readlink "$new_client")" == 'client.js' ]]
grep -Fq "\"path\": \"sbproxy/client-${new_cache_key}\"" "$MENU"
grep -Fq "'require sbproxy-adaptive-${new_cache_key} as adaptive';" "$CLIENT"

printf 'SBProxy package release: %s-r%s -> %s-r%s (LuCI cache key: %s)\n' \
	"$version" "$release" "$version" "$new_release" "$new_cache_key"
