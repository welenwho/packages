# SBProxy

SBProxy is a sing-box proxy and VPN platform with client, server, routing,
subscription, adaptive-routing, and optional embedded Tailscale capabilities.

The LuCI entry is located at **VPN -> SBProxy**.

## Legacy migration

SBProxy uses isolated runtime identifiers and does not read or modify legacy files
after its one-time migration:

- UCI: `/etc/config/sbproxy` and `/etc/config/sbproxy-adaptive`
- persistent data: `/etc/sbproxy`
- runtime data: `/var/run/sbproxy`
- init scripts: `/etc/init.d/sbproxy` and `/etc/init.d/sbproxy-adaptive`
- rpcd object: `luci.sbproxy`

On first installation, when the SBProxy UCI configuration does not exist, the
migration script copies a supported legacy configuration, converts SBProxy-owned
section types and runtime paths, and uses the isolated copy. The same rule applies to
the adaptive configuration. Certificates, custom rule sets, cache data, learned
adaptive-routing state, embedded Tailscale state, and user-maintained direct/proxy
lists are copied to their isolated SBProxy locations. Package-owned scripts,
dashboard files, and geodata come from the new package.

Legacy files are never changed or removed. The copy is performed only once; later
SBProxy upgrades retain the SBProxy copy. The packages may coexist for migration and
rollback, but their services must not run at the same time because they can use the
same ports and policy-routing marks. SBProxy refuses to start while the legacy
service is running.

## Tailscale backends

This repository uses the embedded sing-box backend and no longer ships
`luci-app-tailscale`. Existing independent installations remain mutually exclusive
with the embedded backend. Disable and stop the independent Tailscale service before
enabling it in SBProxy. Compatibility checks ignore a stale `/etc/config/tailscale`
after the independent package has been removed, but still block startup when its init
script is enabled or `tailscaled` is running.

| Capability | Embedded sing-box backend | Independent tailscaled backend |
| --- | --- | --- |
| Official Tailscale and Headscale control servers | Yes | Yes |
| Interactive login, auth key/file, hostname, ephemeral node, ACL tags | Yes | Yes |
| System interface, OpenWrt network, firewall zone, forwarding | Yes | Yes |
| Accept routes and explicit peer subnet routes | Yes | Yes |
| Advertise subnets or an exit node | Yes | Yes |
| Use a remote exit node and allow local LAN access | Yes | Yes |
| Forward MagicDNS without replacing OpenWrt DNS | Yes | Yes |
| Preserve subnet source addresses | Yes | Yes |
| Peer relay, Tailscale SSH, Taildrop directory | Yes | Yes |
| LuCI status, logout, and peer ping | Yes | Yes |
| App Connector, Shields Up, stateful filtering, netfilter mode | No | Yes |
| Posture reporting and native Tailscale web client | No | Yes |
| Tailscale update checks, automatic core update, WireGuard batch tuning | No | Yes |

The missing items have no corresponding sing-box Tailscale endpoint option. Install
and maintain an external independent backend when any of them is required.

## Routing and firewall behavior

Traffic received from the Tailnet follows the normal SBProxy routing rules, so an
advertised exit node reuses the configured direct/proxy split instead of forcing all
traffic through one proxy outbound. Selecting a remote exit node affects local or
intercepted traffic only; it is not applied recursively to traffic received from the
Tailnet.

The OpenWrt Tailscale zone never enables zone-wide masquerading. By default SBProxy
SNATs only packets received on the embedded Tailscale interface and forwarded through
another system interface. Enabling **Preserve subnet source addresses** disables that
rule and requires return routes to the Tailnet address ranges on downstream networks.
Source preservation and advertising an exit node cannot be enabled together.

Taildrop in sing-box exposes a receive directory but no independent enable/disable
field. SBProxy therefore only supplies the directory when the explicit Taildrop switch
is enabled. App Connector and the other unsupported features are not emulated.
