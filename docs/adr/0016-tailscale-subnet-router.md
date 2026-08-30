# 0016. Tailscale Subnet Router — 内网 LLM API 远程访问

> **Status**: ✅ Accepted
> **日期**: 2026-08-29
> **模板**: MADR 4.0 极简版
> **目的**: 通过 Tailscale Subnet Router，从外网安全直接访问内网 LLM API

## Context and Problem Statement

内网 LLM API 仅在单位内网可达。居家办公时需要从外网安全访问该 API，且要求：

- 端到端加密，不暴露公网端口
- 跳板机零维护，重启自动恢复
- 支持 HTTP/1.1 keep-alive 和流式 SSE 响应
- 客户端无需额外进程守护

## Decision Drivers

- 跳板机已在同一 Tailnet 内，无需新增基础设施
- 之前尝试的 tailscale serve --tcp 对流式 SSE 响应不稳定（httpx.ReadError）
- 服务地址是内网固定 IP，适合子网路由
- 不想在跳板机装 nginx/caddy 等额外软件

## Considered Options

### A — Tailscale Subnet Router（选定）

利用 Tailscale 的 Subnet Router 功能，在跳板机上广告内网 LLM API 所在子网的路由。

**原理**：Tailscale 在跳板机 S 上设置路由广告，把 `10.x.x.0/24` 网段注册到 Tailscale 路由表。
居家机器 A 访问 `10.x.x.x:18080` 时，Tailscale 自动通过 S 中转到目标。
流量走 WireGuard 加密、IP 路由层，不做应用层转发，因此 HTTP/1.1 keep-alive 和流式 SSE 完全正常。

### 步骤

#### 跳板机 S 上

如果 S 是全新机器，先装 tailscale 并登录：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

已有 tailscale 则跳过安装，直接配置：

```bash
# 1. 关闭旧的 tailscale serve（如果还在）
sudo tailscale serve --tcp <port> off

# 2. 启用 IP 转发
net.ipv4.ip_forward = 1 | sudo tee /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# 3. 广告内网 LLM API 所在子网路由（掩码 /24 或 /32 按需）
sudo tailscale set --advertise-routes=10.x.x.0/24
```

**清理旧 socat systemd 服务**（如果之前写过）：

```bash
sudo systemctl stop tailscale-aiplus.service 2>/dev/null || true
sudo systemctl disable tailscale-aiplus.service 2>/dev/null || true
sudo rm /etc/systemd/system/tailscale-aiplus.service 2>/dev/null || true
sudo systemctl daemon-reload
```

#### Tailscale Web 控制台

1. 登录 https://login.tailscale.com/admin/machines
2. 找到跳板机 S 设备
3. 点击 "..." → "Edit route settings..."
4. 批准 `10.x.x.0/24` 路由（Approve）
5. 保存

#### 居家机器 A 上

```bash
# 1. 启用接受路由（WSL/Linux 用 sudo，Windows 则在 tailscale 设置中勾选 "Accept routes"）
sudo tailscale set --accept-routes

# 2. 验证子网可达
ping -c 3 10.x.x.x
curl -k --max-time 15 https://10.x.x.x:18080/v1/models
```

响应 401（未提供令牌）即表示网络通了。

> **WSL 注意**：如果 A 是 Windows + WSL，WSL 的虚拟网卡不直接继承 Windows 路由表。
> bridge 会自动检测 RFC1918 私有段并启用 `--use-win-curl`（通过 Windows 侧 curl.exe 转发），
> 解决 WSL 看不到 Windows tailscale 子网路由的问题。无需手动干预。

#### A 上 init-llm.sh 配置

在 `llm.json` 中添加或修改预设，base_url 直接指向内网 llmapi 地址：

```json
"altllm_tailscale": {
    "name": "altLLM-tailscale",
    "base_url": "https://10.x.x.x:18080/v1",
    "model": "deepseek-v4-flash",
    "key": "<your-key>",
    "small_model": "deepseek-v4-flash"
}
```

切换：

```bash
bash lib/init-llm.sh switch altllm_tailscale
```

### 开机自动恢复

- Subnet router 配置存于 tailscaled，**重启自动恢复**
- `sudo systemctl is-enabled tailscaled` 确认开机自启即可
- 不再需要 systemd 自定义服务或启动脚本

### 优点

- ✅ WireGuard 加密，安全级别等同 VPN
- ✅ HTTP/1.1 + 流式 SSE 完整支持（IP 路由层，无应用层转发损耗）
- ✅ 跳板机零维护，tailscaled 管生命周期
- ✅ 居家机器直接用内网 IP 访问，配置简单
- ✅ 延迟低（实测 ~0.4s，tailscale serve TCP 方案 ~2.4s）
- ✅ 子网内所有服务可用，不仅是单端口

### 缺点

- ❌ 需 Tailscale Web 控制台批准路由（一次性操作）
- ❌ 需在客户端启用 `--accept-routes`
- ❌ 子网路由暴露整个网段，需 ACL 控制访问范围

### B — Tailscale Serve TCP 转发（已失败）

之前采用的方案。raw TCP 转发对 SSE 流式响应不稳定，长连接中途断开（httpx.ReadError）。

### C — SSH Local Forward（已废弃）

需维护 SSH 隧道进程 + 自愈逻辑，已从 `llm.json` 和 `init-llm.sh` 中移除。

### D — Nginx/Caddy 反代

在跳板机装反代软件。增加维护负担且无必要（subnet router 即可满足需求）。

## Decision

选 A。

- tailscale serve TCP 方案（B）在实际使用中暴露了流式 SSE 不可靠的问题
- subnet router 是 Tailscale 原生能力，无需任何额外依赖
- 链路简单：A → WireGuard → S → 内网 llmapi，没有应用层中间跳转
- 延迟和稳定性均优于 TCP 转发方案

## Consequences

### Positive

- ✅ 全链路 WireGuard 加密
- ✅ 流式响应稳定
- ✅ 跳板机不需要 systemd 自定义服务
- ✅ tailscaled 重启即恢复

### Negative / Risks

- ❌ 客户端 A 必须保持 Tailscale 运行（Windows GUI 手动启动）
- ❌ 子网路由会把 S 所在内网网段暴露到 Tailnet，ACL 需控制谁可以访问
- ⚠️ 控制台批准路由需要一次性的 Web 操作
- ⚠️ 如果内网 llmapi 换了 IP，需要重新配置

## Security Considerations

- Subnet router 只暴露指定网段（`10.x.x.0/24`），不暴露全内网
- 访问受 Tailscale ACL 控制，默认只有同 tailnet 设备可达
- 建议配 `autoApprovers` 策略自动批准路由：`"autoApprovers": { "route": "10.x.x.0/24": ["tag:jumpbox"] }`
- 不在跳板机上开任何公网端口（已关闭 tailscale serve 和 socat 服务）
- A 上的 Tailscale token 有失效时间，建议用 fine-grained PAT 认证

## 新机器首次设置流程（端到端）

以下是从零开始搭建的完整流程：

1. **跳板机 S**：装 tailscale → 登录 → 开 ip_forward → 广告路由 → 确认开机自启

```bash
# S 上一次性操作
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
net.ipv4.ip_forward = 1 | sudo tee /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
sudo tailscale set --advertise-routes=10.x.x.0/24
sudo systemctl enable tailscaled
```

2. **Tailscale 控制台**：登录后找到 S → Edit route settings → Approve `10.x.x.0/24`

3. **居家机器 A**：打开 tailscale → 设置 Accept routes → 验证连通

```bash
# A 上（WSL 环境）
sudo tailscale set --accept-routes
ping -c 3 10.x.x.x  # 通表示路由生效
curl -k --max-time 15 https://10.x.x.x:18080/v1/models  # 返回 401 即网络通
```

4. **ccconfig LLM 配置**：通过 `init-llm.sh custom` 交互输入

```bash
bash lib/init-llm.sh
# 选择 3A（新增自定义）
# Base URL: https://10.x.x.x:18080/v1
# Model: deepseek-v4-flash  （按实际模型名）
# API Key: <your-key>
# 保存为预设：altllm_tailscale
# 自动切到新 preset
```

或在 `conf/llm.json` 中手动添加 preset 后用 `switch` 切换。

## Notes

- `tailscale status` 不显示自己的路由广告。路由生效通过客户端能否 ping 通内网 IP 来验证
- WSL 需要 `sudo tailscale set --accept-routes`，Windows 宿主则在 Tailscale 设置中勾选 "Accept routes"
- `tailscale set --advertise-routes=...` 会持久化到 tailscaled 配置，重启自动恢复
- 删除路由广告：`sudo tailscale set --advertise-routes=`（清空后需控制台取消批准）
- 查看已广告的路由：`tailscale debug` 或控制台 Machines 页面

## Related

- [Subnet routers | Tailscale Docs](https://tailscale.com/docs/features/subnet-routers)
- [ADR 0014: Tailscale 跳板机部署方案](0014-tailscale-jump-server.md)
- [Tailscale ACL 文档](https://tailscale.com/docs/features/access-control)
