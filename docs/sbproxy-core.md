# SBProxy 独立核心构建与发布

核心源码、编译配置和 Tailscale 补丁统一在 `welenwho/packages` 维护。
不使用也不修改 `singbox-v2ray-api` 的产物。

## 发布与版本

每日维护队列调用 `Update-Sing-Box.yml`，检查上游最新稳定版以及本仓库
补丁、包定义、构建脚本的指纹。有变化才编译，未变化不会每日重复构建。
也可手动运行该工作流。仅发布完整 SBProxy 核心，不增加 standard/minimal 配置。

- Release：`sbproxy-core-v1.14.0-r2`（示例）。
- 架构：ARM64（ARMv8.0）和 AMD64（x86-64-v1）。
- `sing-box-1.14.0-r2-linux-arm64.tar.gz`：供固件打包的预编译核心。
- `sing-box-1.14.0-r2-arm64.apk`：供当前 ImmortalWrt APK 系统在线安装。
- `core-manifest.json`、`SHA256SUMS`：架构、核心版本、源码提交、补丁、编译信息和校验值。
- `sbproxy-core-build-source.tar.gz`：该版本的构建脚本与补丁快照；上游源码固定为清单中的 Git tag，Tailscale 依赖由该 tag 的 go.mod 确定。

同一上游版本的补丁/构建变更递增 `rN`。已发布的 Release 不覆盖，不纳入滚动
APK 的版本清理，也不抢占仓库 Latest。两种架构都成功、核心功能及静态链接检查
通过后才发布。补丁无法应用时任务失败，不跳过补丁，也不推进固件版本。

## 固件编译

发布成功后，工作流提交 `Makefile` 与 `core-prebuilt.mk` 中的精确版本、架构 SHA-256。
普通完整包构建下载该固定压缩包，不构建 Go 工具链或 sing-box；当前 SDK 自行打包
APK/IPK 并保留其服务文件、依赖、包数据库。OpenWRT-CI 已引入本仓库的 `sing-box`
包定义，更新 feed 后即可生效，不需要跨 SDK 直接导入 APK。

首次发布完成前、不支持的架构、tiny/custom 构建继续源码编译。
可通过 `CONFIG_SING_BOX_BUILD_FROM_SOURCE=y` 强制源码编译。
独立核心 CI 使用 `SBPROXY_CORE_SOURCE_BUILD=1`，生成静态链接、基线 CPU 核心，
APK 内二进制与压缩包内二进制来自同一次构建。
下载失败或哈希错误直接报错，不回退 latest，也不悄悄改为源码构建。

## 在线升级与回滚

LuCI 核心管理读取版本化 Release 的历史列表，允许升级、重装或选择旧版回滚。
仅接受本仓库匹配架构的资产，使用 GitHub SHA-256 校验、APK 名称/版本/架构校验、
完整编译标签与 Tailscale 路由 API 检查，并校验当前客户端/服务端配置。
1.14 之前的核心不展示；版本达到最低要求也不意味着兼容当前配置，实际检查失败会阻止切换。

手动回滚不依赖已保存的本地回滚包。每次切换先从仓库下载当前版本的应急恢复包，
避免新核心启动失败后还要联网恢复。首次从旧固件迁移时，应急包可从原有
`apk-packages-arm64/amd64` 发布获取；如果两处均已无当前版本，则拒绝不安全切换。
离线时不能下载历史版本，但切换过程中已准备的应急包仍可用于自动恢复。

在线安装目前针对支持的 ARM64/AMD64 APK 系统；其他系统可复用预编译压缩包进行
固件打包，不承诺不同 OpenWrt 分支的 APK 依赖一定兼容。

## 验证

```
python3 sing-box/tests/test-core-release.py
sh sing-box/tests/static-tailscale-route-api.sh
sh luci-app-sbproxy/tests/static-core-management.sh
```

实际双架构源码编译及 QEMU 核心检查在 GitHub Actions 中执行。

在线切换前记录本次应运行的客户端/服务端实例及监听端口。切换后检查对应核心进程
（含 ujail 子进程）与它持有的 TCP/UDP socket，连续 5 次 PID/启动时间稳定才通过。
日志清理、接口同步等辅助进程不能代替核心健康状态；失败仍进入自动恢复流程。
