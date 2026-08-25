#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH="$PACKAGE_ROOT/patches/010-api-expose-tailscale-peer-subnet-routes.patch"
TAILSCALE_PATCH="$PACKAGE_ROOT/tailscale-patches/010-restore-linux-policy-routing.patch"
MAKEFILE="$PACKAGE_ROOT/Makefile"

test -s "$PATCH"
grep -Fq 'PrimaryRoutes' "$PATCH"
grep -Fq 'primaryRoutes = 18' "$PATCH"
grep -Fq 'commandAPITailscaleRouteList' "$PATCH"
grep -Fq 'List Tailscale peer subnet routes' "$PATCH"

test -s "$TAILSCALE_PATCH"
grep -Fq 'r.ipRuleAvailable = (cmd.run("ip", "rule") == nil)' "$TAILSCALE_PATCH"
grep -Fq 'checkOpenWRTUsingMWAN3()' "$TAILSCALE_PATCH"
grep -Fq 'TAILSCALE_MODULE_VERSION:=v1.102.1-sing-box-1.14-mod.3' "$MAKEFILE"
grep -Fq 'GO_PKG_INSTALL_EXTRA:=third_party/tailscale' "$MAKEFILE"
grep -Fq 'go mod download $(GO_MOD_ARGS) $(TAILSCALE_MODULE)' "$MAKEFILE"
grep -Fq '$(call PatchDir,$(PKG_BUILD_DIR)/third_party/tailscale,./tailscale-patches,)' "$MAKEFILE"
grep -Fq -- '-replace github.com/sagernet/tailscale=./third_party/tailscale' "$MAKEFILE"

echo 'sing-box Tailscale test passed: route API and patched local dependency build wiring are present'
