# 0014. Tailscale 跳板机部署方案

> **Status**: ✅ Accepted
> **日期**: 2026-08-21
> **模板**: MADR 4.0 极简版
> **目的**: 规范跨网络访问内部服务器时的 Tailscale 部署方案

## Context and Problem Statement

内部服务器（Ubuntu Server）无公网 IP，需要从外网安全访问。多个居家设备需要同时通过该服务器进行 SSH/服务转发。

要求：无需图形界面、无需浏览器交互、支持批量/重复部署、密钥自动管理。

## Decision Drivers

- 服务器无人值守，不能依赖定期人工重认证
- 国内网络环境，官方安装源被墙
- 设备不应绑定个人账号生命周期

## Considered Options

### A — Tag 模式 + Auth Key（选定）

通过 Tailscale 的 Tag 机制将服务器标记为基础设施节点，使用 Auth Key 绕过浏览器登录。

**步骤**：

1. ACL 配置：在 Tailscale Access Controls 的 `tagOwners` 中定义 tag
2. 生成 Auth Key：在 Keys 页面 Generate auth key，设置 Tags 为该 tag，勾选 Reusable，不勾 Ephemeral
3. 安装 Tailscale：使用国内镜像源
   ```bash
   curl -fsSL https://ts-mirror.xedge.cc/install.sh | sh
   ```
4. 认证：
   ```bash
   sudo tailscale up --auth-key=tskey-auth-xxxxx
   ```
5. 开机自启：`sudo systemctl enable tailscaled`（安装后默认已配）

**优点**：
- 节点 key 永不过期（Tag 模式默认禁用 key expiry），服务器无需定期重认证
- 不绑定个人账号，账号变动不影响设备
- 无人值守，无需浏览器交互
- Auth Key 支持 Reusable，同类型服务器可复用

**缺点**：
- Tag 节点不能主动 SSH 到用户节点（不影响跳板机场景）
- Tag 模式下 ACL 需额外配置 tagOwners

### B — 用户模式交互登录

直接在服务器 `tailscale up` 打开浏览器 URL 交互认证。

**优点**：配置简单。**缺点**：节点 key 默认 180 天过期；服务器无图形界面需 auth key 辅助；个人账号变动导致设备丢失。

### C — WireGuard 自建

手动生成密钥对、配置 Peer、维护路由表。

**优点**：完全自主可控。**缺点**：NAT 穿透需自建 STUN/TURN；多设备组网需自建中心节点；无 ACL 管理界面；密钥轮换全手动。

## Decision

选 A。

- 跳板机是基础设施，不应依赖个人账号生命周期
- 无人值守场景必须避免 180 天过期陷阱
- Auth Key + Tag 组合一次性完成认证，适合批量部署
- Tailscale 在国内有可用镜像源（xEdge、中科大），安装不依赖科学上网

## Consequences

### Positive

- ✅ 即装即用，后续维护成本接近零
- ✅ 同一 auth key 可复用于同类型服务器
- ✅ 国内网络可装

### Negative / Risks

- ❌ Auth Key 一次性展示，需妥善保存或重新生成
- ❌ 认证 URL 也可能被墙，必须用 Auth Key 方式跳过
- ⚠️ 需要理解 Tag 和 ACL 概念才能正确配置

## Notes

- 官方安装脚本被墙时可用 `https://ts-mirror.xedge.cc/install.sh` 或中科大镜像源
- Auth Key 过期（最长 90 天）不影响已认证设备，只限制加新设备
- `sudo systemctl is-enabled tailscaled` 输出 `enabled` 确认开机自启
- 默认 `*:*` ACL 规则满足跳板机需求，不需细粒度 ACL

## Related

- [Auth keys](https://tailscale.com/docs/features/access-control/auth-keys)
- [Tags](https://tailscale.com/docs/features/tags)
- [Key expiry](https://tailscale.com/docs/features/access-control/key-expiry)
- [xEdge 镜像](https://ts-mirror.xedge.cc/)
- [中科大镜像](https://mirrors.ustc.edu.cn/help/tailscale.html)
