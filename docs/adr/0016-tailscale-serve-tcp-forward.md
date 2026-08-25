# 0016. Tailscale Serve TCP 转发 — 内网 LLM API 远程访问

> **Status**: ✅ Accepted
> **日期**: 2026-08-25
> **模板**: MADR 4.0 极简版
> **目的**: 通过 Tailscale Serve TCP 转发，从外网安全访问内网 LLM API

## Context and Problem Statement

内网 LLM API（例如 `aiplus.example.com:18080`）仅在单位内网可达。居家办公时需要通过跳板机安全地访问该 API，且要求：

- 端到端加密，不暴露公网端口
- 跳板机无需安装额外代理软件
- 不修改系统内核参数或网络路由

## Decision Drivers

- 跳板机已在同一 Tailnet 内，无需新增基础设施
- 配置需简单、可脚本化、开机后自动恢复
- 不引入第三方代理（如 socat、rinetd、haproxy 等）

## Considered Options

### A — Tailscale Serve TCP 转发（选定）

利用 Tailscale Serve 的 TCP forwarder 功能，在跳板机上把内网 LLM API 转发到 Tailscale 地址上。

**命令**（跳板机 S 上执行）：

```bash
sudo tailscale serve --bg --tcp 18080 tcp://aiplus.example.com:18080
```

- `--bg`：后台常驻
- `--tcp 18080`：S 在 Tailscale 网络上监听 18080 端口
- `tcp://aiplus.example.com:18080`：内网 LLM API 的真实地址（需带 `tcp://` scheme，非 localhost 目标强制要求）

**验证**（居家机器 A 上）：

```bash
curl -k https://100.x.x.x:18080/v1/models
```

注：内网 LLM API 实际走 HTTPS，curl 必须用 `https://`。证书自签时加 `-k`。

**持久化**：

- `tailscale serve` 配置存入 `/var/lib/tailscale/serve.json`
- tailscaled 重启后自动恢复，无需额外开机脚本
- `sudo systemctl is-enabled tailscaled` 确认开机自启即可

**关闭**：

```bash
sudo tailscale serve --tcp 18080 off
```

**优点**：
- ✅ Tailscale 内建功能，零额外组件
- ✅ 端到端 WireGuard 加密，仅 tailnet 内设备可达
- ✅ 配置重启持久化
- ✅ 支持转发到 DNS 域名（不只是 IP）

**缺点**：
- ❌ 目标地址非 localhost 时必须写 `tcp://` 前缀，否则报 "must include scheme"
- ❌ `sudo` 需要（tailscale serve 写系统配置）

### B — SSH Local Forward（已有方案）

altllm_tail 已采用此方案（ssh_tunnel 配置）。

**优点**：SSH 自带，无需额外配置。
**缺点**：需维护 SSH 隧道进程 + 自愈逻辑；端口必须不同（本地 8890 → 远程 18080）；断开后需重连。

### C — socat / rinetd

在跳板机手动装 socat 并配 systemd 服务。

**优点**：通用 TCP 转发。
**缺点**：需额外安装和维护；无自带加密，需依赖 WireGuard 或 SSH 隧道。

## Decision

选 A。

- SSH 隧道（方案 B）已用于 altllm_tail，但需要额外维护隧道进程
- tailscale serve 是 Tailscale 内建能力，零维护
- 同一个 LLC 访问场景，方案 A 做基础设施层转发，方案 B 可降级为备选/回退

## Consequences

### Positive

- ✅ 无需额外守护进程，tailscaled 管生命周期
- ✅ WireGuard 加密，安全性等同 VPN
- ✅ 居家机器直接访问跳板机 Tailscale IP，配置简单

### Negative / Risks

- ❌ 依赖 Tailscale 网络连通性
- ❌ 转发规则只适用于 TCP，UDP 不支持
- ⚠️ 跳板机到内网 LLM API 的网络路径仍需畅通（防火墙规则不变）

## Notes

- 非 localhost 目标必须加 `tcp://` scheme，否则 tailscale 报 "must include scheme"
- 跳板机上 18080 端口需未被其他进程占用；若已占用，换用其他端口（`--tcp <port>`）
- 内网 LLM API 走 HTTPS 时，curl 用 `https://` 而非 `http://`，否则返回 400
- `tailscale serve status` 查看所有转发规则

## Related

- [tailscale serve 文档](https://tailscale.com/docs/reference/tailscale-cli/serve)
- [ADR 0014: Tailscale 跳板机部署方案](0014-tailscale-jump-server.md)
