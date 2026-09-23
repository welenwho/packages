# 代理模式

从 1.0.1-r15 起，客户端“路由设置”的第一项固定为“代理模式”：关闭、大陆白名单、自定义路由、全局。切换模式不改变其位置；“路由端口”改为“代理端口”。新安装默认关闭，已有模式保持不变。

三个启用模式中，“代理模式”“代理端口”“额外端口”固定排在前三位；额外端口仅在选择“常用端口＋额外端口”时显示。关闭代理时隐藏 IPv6 支持和仪表盘配置，保留已保存的值。IPv6 偏好仍用于 Tailscale 解析，关闭代理不会改变它。仪表盘不再监听，但 Tailscale 内部管理 API 继续可用。高级设置固定在访问控制之后，作为最后一个标签页。

“关闭”不修改已选节点、默认出站或手工分流规则，只停止客户端代理接管：不生成代理 TUN、mixed 入站、节点出站、代理 DNS、分流规则或接口接管。以后重新选择原模式即可继续使用原配置。主节点的“禁用”保留以兼容旧设置，并提示优先使用代理模式关闭。

已启用的 Tailscale 和服务端不随客户端代理关闭。Tailscale 沿用相同的状态目录和身份，保留系统接口、发布子网、接受对端路由、出口节点设置、MagicDNS 及管理 API。切换模式需要重启共享 sing-box 核心，可能短暂重连，不是免重启热切换。

Tailscale 单独运行时不验证未使用的代理节点、URLTest 或分流配置；代理关闭状态也独立显示，避免将 Tailscale 核心仍在运行误认为代理仍在工作。

验证：`node luci-app-sbproxy/tests/test-proxy-mode-ui.mjs`、`node luci-app-sbproxy/tests/test-proxy-mode-init.mjs`；在隔离 OpenWrt 环境运行 `sh luci-app-sbproxy/tests/router-proxy-mode.sh` 和 `router-no-adaptive.sh`。只生成配置，不启动第二个 Tailscale 身份。
