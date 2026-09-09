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
tool_dir="$(mktemp -d "$RUNNER_TEMP/sbproxy-rule-tool.XXXXXX")"
curl -fsSL --retry 3 "$url" -o "$tool_dir/tool.tar.gz"
printf '%s  %s\n' "${digest#sha256:}" "$tool_dir/tool.tar.gz" | sha256sum -c -
tar -xzf "$tool_dir/tool.tar.gz" -C "$tool_dir" "$name"
test -x "$tool_dir/$name/sing-box"
LD_LIBRARY_PATH="$tool_dir/$name" "$tool_dir/$name/sing-box" version
echo "SING_BOX=$tool_dir/$name/sing-box" >> "$GITHUB_ENV"
echo "LD_LIBRARY_PATH=$tool_dir/$name" >> "$GITHUB_ENV"
