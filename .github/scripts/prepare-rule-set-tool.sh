#!/usr/bin/env bash
# Validation-only compiler. This binary is never packaged for the router;
# deployed SBProxy cores continue to come from our patched core releases.
set -euo pipefail
version="$(sed -n 's/^PKG_UPSTREAM_VERSION:=//p' sing-box/Makefile)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
name="sing-box-$version-linux-amd64"
metadata="$(gh api "repos/SagerNet/sing-box/releases/tags/v$version")"
asset="$(jq -ce --arg name "$name.tar.gz" '.assets[] | select(.name == $name)' <<< "$metadata")"
url="$(jq -r .browser_download_url <<< "$asset")"
digest="$(jq -r .digest <<< "$asset")"
[[ "$url" == "https://github.com/SagerNet/sing-box/releases/download/v$version/$name.tar.gz" ]]
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]
if [[ "${1:-prepare}" == resolve ]]; then
	printf 'version=%s\nsha256=%s\n' "$version" "${digest#sha256:}" >> "$GITHUB_OUTPUT"
	exit 0
fi
cache_dir="${RULE_TOOL_CACHE:-$RUNNER_TEMP/sbproxy-rule-cache}"
mkdir -p "$cache_dir"
archive="$cache_dir/$name.tar.gz"
if [[ ! -f "$archive" ]] || [[ "$(sha256sum "$archive" | cut -d' ' -f1)" != "${digest#sha256:}" ]]; then
	curl -fsSL --retry 3 "$url" -o "$archive.part"
	printf '%s  %s\n' "${digest#sha256:}" "$archive.part" | sha256sum -c -
	mv "$archive.part" "$archive"
fi
tool_dir="$(mktemp -d "$RUNNER_TEMP/sbproxy-rule-tool.XXXXXX")"
printf '%s  %s\n' "${digest#sha256:}" "$archive" | sha256sum -c -
tar -xzf "$archive" -C "$tool_dir" "$name"
test -x "$tool_dir/$name/sing-box"
LD_LIBRARY_PATH="$tool_dir/$name" "$tool_dir/$name/sing-box" version
echo "SING_BOX=$tool_dir/$name/sing-box" >> "$GITHUB_ENV"
echo "LD_LIBRARY_PATH=$tool_dir/$name" >> "$GITHUB_ENV"
