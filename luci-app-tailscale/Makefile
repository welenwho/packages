# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2024 asvow
# Modified for welenwho/packages, 2026.

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI for Tailscale
LUCI_DEPENDS:=+luci-base +tailscale +flock +ip-full
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-tailscale
PKG_VERSION:=1.3.0
PKG_RELEASE:=2

define Package/luci-app-tailscale/conffiles
/etc/config/tailscale
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
