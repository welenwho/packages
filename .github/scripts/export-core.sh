#!/usr/bin/env bash
# Export the exact SDK-packaged binary, not an independently rebuilt binary.
set -euo pipefail
sdk="$1"
apk_output="$2"
output="$3"
arch="$4"
version="$5"
revision="$6"
[[ "$arch" == arm64 || "$arch" == amd64 ]]
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$revision" =~ ^[1-9][0-9]*$ ]]
apk="$sdk/staging_dir/host/bin/apk"
package="$apk_output/sing-box-$version-r$revision.apk"
name="sing-box-$version-r$revision-linux-$arch"
mkdir -p "$output/$name/release/config"
extract="$(mktemp -d)"
trap 'rm -rf -- "$extract"' EXIT
"$apk" --allow-untrusted extract --destination "$extract" "$package"
binary="$extract/usr/bin/sing-box"
# A portable archive must not need a target libc or dynamic interpreter.
readelf -l "$binary" > "$extract/elf.txt"
! grep -q INTERP "$extract/elf.txt"
readelf -d "$binary" > "$extract/dynamic.txt"
! grep -q NEEDED "$extract/dynamic.txt"
runner=()
if [[ "$arch" == arm64 ]]; then runner=(qemu-aarch64-static); fi
"${runner[@]}" "$binary" version > "$extract/version.txt"
grep -Fxq "sing-box version $version" "$extract/version.txt"
for tag in with_acme with_clash_api with_dhcp with_gvisor with_quic with_tailscale with_utls with_wireguard; do
    tr ',' ' ' < "$extract/version.txt" | grep -qw "$tag"
done
"${runner[@]}" "$binary" api tailscale route list --help > "$extract/route.txt"
grep -Fq 'List Tailscale peer subnet routes' "$extract/route.txt"
"${runner[@]}" "$binary" check -c "$extract/etc/sing-box/config.json"
cp "$binary" "$output/$name/sing-box"
cp "$extract/etc/sing-box/config.json" "$output/$name/release/config/config.json"
mapfile -t licenses < <(find "$sdk/build_dir" -type f -path "*/sing-box-$version/LICENSE")
[[ "${#licenses[@]}" == 1 ]]
cp "${licenses[0]}" "$output/$name/LICENSE"
cp "$extract/version.txt" "$output/$name/BUILD_INFO"
binary_sha="$(sha256sum "$binary" | cut -d' ' -f1)"
jq -n --arg version "$version-r$revision" --arg arch "$arch" --arg sha "$binary_sha" \
    --arg source "$CORE_SOURCE_SHA" '{profile:"sbproxy",version:$version,arch:$arch,binary_sha256:$sha,source_sha:$source}' \
    > "$output/$name/SBP_BUILD_INFO"
tar -C "$output" -czf "$output/$name.tar.gz" "$name"
cp "$package" "$output/sing-box-$version-r$revision-$arch.apk"
apk_arch="$("$apk" adbdump "$package" | awk '/^  arch: / { print $2; exit }')"
python3 .github/scripts/core-release.py export "$output" "$arch" "$version-r$revision" \
    "$apk_arch" "$binary_sha" "$extract/version.txt" \
    "$(sed -n 's/^PKG_HASH:=//p' sing-box/Makefile)" \
    "$(sed -n 's/^TAILSCALE_MODULE_VERSION:=//p' sing-box/Makefile)"
