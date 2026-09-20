# 自适应路由安全边界

- 直连探测使用独立 outbound 标签，不再与默认直连失败混用。正在探测的同一目标暂不采信其失败日志。
- 不成功的三轮探测进入一小时冷却；后续失败事件不重置冷却。已恢复健康的默认路径也冷却一小时。
- 最少观测次数同样适用于失败连接；两次探测样本必须两次成功，三次样本至少两次成功，才允许提升。
- 默认启用“保护国内目标”。仅当自适应目标为代理时生效；worker 不学习 GeoIP CN 地址，启动时移除当前策略已有的国内 IP 学习记录；自动分流匹配还排除 GeoIP/GeoSite CN。
- 国内保护只约束自适应规则，显式自定义规则优先，反向学习到直连不受此开关影响。
- 原始 IP 的学习规则只匹配实际探测的 TCP 443，不影响同 IP 的 UDP/QUIC 或其他端口。
- Dashboard/API 独立限制为 LAN 设备、本机，以及显式允许的 Tailscale 接口，即便 WAN input 为 ACCEPT 也不放行。不会为 Dashboard 改动整个 WAN 区域策略。建议随机密钥；LuCI 启用时要求至少 16 字符。

验证：`sh luci-app-sbproxy/tests/static-adaptive-safety.sh`。在 OpenWrt 上将脚本、模块、测试及 UCI 副本放入临时目录后，使用 `ucode -L <模块目录> tests/adaptive-safety.uc <worker路径>` 测试函数，不进入 worker 主循环。生成的配置另用 `sing-box check` 校验。

TUN MTU 与以太网 MTU 不必一致：用户态代理会重新建立外部连接。不能仅凭 9000/1500 就认定发生了分片故障；调整应依据 PMTU、丢包或分片失败证据。
