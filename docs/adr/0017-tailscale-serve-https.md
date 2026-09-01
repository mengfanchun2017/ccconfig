# 0017. Tailscale Serve HTTPS — 内网 LLM API 远程访问（流式兼容）

> **Status**: ⚠️ Superseded by [0016](0016-tailscale-subnet-router.md)（subnet router 方案更优，已取代 HTTPS serve）
> **日期**: 2026-08-28
> **模板**: MADR 4.0 极简版
> **目的**: 用 tailscale serve --https 替换 --tcp，解决 raw TCP 对流式 SSE 的不兼容

## Context and Problem Statement

早期用 `tailscale serve --tcp 18081` 转发内网 LLM API，但 raw TCP 转发对 HTTP 流式响应（SSE）不友好：httpx 在长连接传输中段返回 `ReadError`，Claude 发长消息时 500 重试。

需要改用 HTTP 层代理而非 raw TCP，以正确支持 chunked transfer + keep-alive。

## Decision Drivers

- 流式响应必须稳定（Claude 消息体验核心）
- 不引入额外组件（nginx/caddy 等）
- 端到端加密，安全简单

## Considered Options

### A — nginx 反代（S 上安装 nginx + 自签证书）

**优点**：HTTP 1.1 完整支持，极稳定。**缺点**：需装 nginx、生成证书、维护 systemd 服务。

### B — bridge 禁用流式

**优点**：改代码就能解决。**缺点**：牺牲流式体验，长消息等完整返回才显示。

### C — tailscale serve --https（选定）

利用 tailscale serve 的 HTTPS 反代能力，自动获取 MagicDNS 证书。

```bash
sudo tailscale serve --https=8443 https+insecure://<internal-llm-api-ip>:<port>
```

`https+insecure://` 表示对外 HTTPS（自动证书），对内 HTTP（跳过后端证书验证）。

**优点**：
- ✅ tailscale 内建，零额外组件
- ✅ 标准 HTTP 1.1 反代，流式完美支持
- ✅ MagicDNS 自动证书，客户端免 `-k`
- ✅ tailscaled 重启自动恢复
- ✅ 端口只监听在 tailscaled 内，非 tailnet 设备不可见

**缺点**：
- ❌ 端口 443 可能被其他服务占用，需用 8443
- ❌ 依赖 MagicDNS 域名（`francistail.tailxxxx.ts.net`）可解析

## Decision

选 C。tailscale 内建能力，零维护，HTTPS 反代完美支持流式。

## Consequences

### Positive

- ✅ 流式 SSE 稳定
- ✅ 自动 TLS 证书，客户端无需 `-k`
- ✅ tailscaled 重启自动恢复，无额外运维
- ✅ ACL 控制不变（只暴露给 tailnet）

### Negative / Risks

- ❌ MagicDNS 域名在 tailnet 外不可解析
- ⚠️ 端口号变了（从 18081 改为 8443）

## 操作步骤

### S 跳板机

```bash
# 关旧 TCP
sudo tailscale serve --tcp 18081 off

# 开 HTTPS（8443 → 内网 llmapi）
sudo tailscale serve --https=8443 https+insecure://<internal-llm-api-ip>:<port>

# 验证
tailscale serve status
```

### A 客户端

修改 `altllm_tailscale` 的 base_url：

```
base_url: https://francistail.tailxxxx.ts.net:8443/v1
```

然后 `bash lib/init-llm.sh switch altllm_tailscale` 验证。

## Related

- [ADR 0014: Tailscale 跳板机部署方案](0014-tailscale-jump-server.md)
- [ADR 0016: Tailscale Subnet Router](0016-tailscale-subnet-router.md)（取代本 ADR — subnet router 在 IP 路由层转发，无需 serve，延迟更低）
