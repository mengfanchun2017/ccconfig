# 0047. 开发机不做 tailscale subnet router（与单位内网访问互斥）

> **Status**: ✅ Accepted
> **日期**: 2026-10-16
> **关联**: `lib/ensure-bridge.sh`、`option-llmswitch/openai_bridge.py`、`docs/adr/0019-bridge-win-curl-wsl-vpn.md`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

2026-10-16 在单位内网使用 `office*` 系列 preset 连内部 LLM 网关，表现为**极慢并最终报错**；同一台机器在家用 `home*` 系列（走 tailscale 网段）完全正常。

第一直觉指向 bridge 层（[0019](0019-bridge-win-curl-wsl-vpn.md) 的 win-curl 直连/转发双模式），但实测证伪：

| 观测点 | 结果 |
|---|---|
| WSL 内 `curl` 直连 `<单位网关内网IP>:<port>` | TCP 无回包，`conn=0`，8s 超时 |
| Windows `curl.exe` 同一目标 | 同样无回包 |
| DNS 解析 `<公司内网域名>` | 正常返回单位内网 IP |
| 公网（如 baidu） | 200，146ms |

关键特征：**DNS 能解析但 TCP 握手无回包 —— 是静默丢包（黑洞），不是连接拒绝**。这排除了服务下线、端口封禁、证书问题，指向本机路由被劫持。

进一步查 Windows 路由表，发现本机 tailscale 开启了 **subnet 模式（advertise-routes）**，把 `10.0.0.0/8` 等内网段装成指向 `Tailscale Tunnel` 的路由，且 metric 优于物理网卡默认路由。访问单位网关的流量因此被接进 tailscale 隧道，而隧道对端并无对应节点 → 静默丢弃。

用户在 Windows 上关掉 subnet 模式后，同一条 `Test-NetConnection` 立即由 `False` 变 `True`，故障消失。

## Decision Drivers

- **D1 快速归因**：同类症状下必须能区分「本机路由问题」与「bridge/服务端问题」，不能每次重新考古
- **D2 环境约束显式化**：subnet router 是常用需求，但与「本机直连单位内网」存在硬冲突，需写清取舍
- **D3 不改代码**：本次故障不在 ccconfig 代码缺陷，改代码属于过度反应

## Considered Options

1. **给 office\* preset 加 win-curl 降级路径**（bridge 直连超时后自动改走 Windows 侧 curl）— 能覆盖所有 WSL 不可达场景，包括 tailscale 抢路由。但本次两侧（WSL + Windows）都不可达，降级也救不了；且为非本因的故障增加常驻复杂度
2. **扩展 win_curl 判定支持域名**（判定前 `getent hosts` 解析，命中私网段即走 Windows 通路）— office\* 用域名确实匹配不上当前只认字面 IP 的正则，属真实存在的结构性缺口。但当前直连已可用且更快，不构成本次故障的修复项
3. **不动代码，把约束与判据写进 ADR** — 故障根因在本机网络配置，代码行为符合预期

## Decision

**选方案 3**：不在需要直连单位内网的开发机上启用 tailscale subnet 模式；若必须保留 subnet router，把它放到另一台机器。

同时确立诊断顺序：**内网地址两侧同时 `Test-NetConnection` 为 False 且 DNS 能解析 → 先查本机路由（`Find-NetRoute` 看 `InterfaceAlias` 是否为 `Tailscale Tunnel`），不要先查 bridge。**

office\* preset 的配置方式（`base_url` 用内网域名、不触发 win-curl、WSL 内 httpx 直连）经实测正确且更快，**保持不变**：

| preset | 路径 | 首字节 | 总耗时 |
|---|---|---|---|
| `officeds41flash` | WSL 直连单位网关 | 2.30s | 2.30s |
| `homeds41flash` | WSL → tailscale 网段 + Host 头 | 5.72s | 5.72s |

单位内网用 office\* 系列优于 home\* 系列。

## Consequences

- ✅ **无代码改动**：不引入为非本因故障服务的复杂度，preset 行为与 ADR 0019 的双模式设计保持一致
- ✅ **判据可复用**：黑洞 vs 拒绝的区分 + `Find-NetRoute` 定位法写进 ADR，下次同样症状可直接跳到结论
- ✅ **两个 preset 的取舍有据**：单位用 office\*（2.3s），需要 tailscale 时才用 home\*
- ❌ **subnet router 需求需另找机器承载**：本机不能再同时承担 subnet router 角色
- ⚠️ **风险**：日后重开 subnet 模式会再次触发同样故障 —— 由本文档 + memory 记录缓解
- ⚠️ **风险**：若未来 Windows 侧确实可通而 WSL 侧不可达，届时应重新评估 Considered Options 1/2（当前两者都未实施）

## Implementation

### 诊断命令（PowerShell）

```powershell
# 1. TCP 是否通（False + DNS 能解析 = 黑洞，先查路由）
Test-NetConnection -ComputerName <单位网关内网IP> -Port <port> -InformationLevel Quiet

# 2. 该目标流量最终选了哪块网卡（InterfaceAlias 为 Tailscale Tunnel 即中招）
Find-NetRoute -RemoteIPAddress <单位网关内网IP> | Format-Table IPAddress,InterfaceAlias,NextHop,RouteMetric

# 3. 确认本机在承担 subnet router
& "$env:ProgramFiles\Tailscale\tailscale.exe" debug prefs
```

### 处置

- 首选：开发机上关闭 subnet 模式，subnet router 迁至其他机器
- 必须保留时（客户端侧）：`& "$env:ProgramFiles\Tailscale\tailscale.exe" set --accept-routes=false` —— 保留 tailscale 连接功能，仅不接受被通告的子网路由

### 读表提醒

`route print <ip>` 带过滤参数，只显示匹配项。「活动路由: 无」表示没有比默认路由更具体的路由（正常），**不代表路由表为空** —— 判断劫持要用 `Find-NetRoute`。

## Related Decisions

- [0019](0019-bridge-win-curl-wsl-vpn.md) — bridge win-curl 双模式（本文档在其之上定位本因，未修改其设计）
- [0040](0040-remote-file-transfer-channels.md) — 远程文件传输通道（同为 tailscale + 多网络环境运维）
- [0046](0046-remote-multi-window-tmux.md) — 多窗口远程会话（同为 WSL/Windows 网络栈协同问题域）

## Notes

2026-10-16 核实发现：ADR 0019 正文描述的「PowerShell DNS 预解析」与「WSL 网络可达性 5s 探测」在当前 `lib/ensure-bridge.sh` / `option-llmswitch/openai_bridge.py` 中**已不存在**（全仓 grep 无命中）。win-curl 启用条件现为 `lib/ensure-bridge.sh` 中对 upstream 字面 IP 的段匹配正则 —— 域名形式的上游（如 office\* 的内网域名）因此拿不到 Windows 侧通路。0019 正文尚未回填这一漂移，后续若整理 0019 需一并更正。
