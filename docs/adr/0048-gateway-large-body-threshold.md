# 0048. 单位 LLM 网关存在 ~200KB 请求体硬阈值（大 context 必挂）

> **Status**: ✅ Accepted
> **日期**: 2026-10-16
> **关联**: `option-llmswitch/openai_bridge.py`、`lib/ensure-bridge.sh`、`docs/adr/0047-tailscale-subnet-vs-office-intranet.md`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

2026-10-16 单位内网排查 office\* preset「很慢还会报错」，在排除了 tailscale 路由劫持（见 [0047](0047-tailscale-subnet-vs-office-intranet.md)）后仍有故障。逐层压测定位到**网关服务端对请求体大小的限制**，而非本地网络或 bridge 代码。

### 压测数据（单位内网，同一台机器，同一 API key）

| body 大小 | 直连网关 | 经 bridge |
|---|---|---|
| 20KB | 200，2.9s | 200，4.6s |
| 100KB | 200，14.2s | 200，17.1s |
| 150KB | 200，34.9s | — |
| 200KB | 200，50.5s | — |
| 250KB | **挂死超时** | — |
| 300KB | **挂死超时** | **挂死 90s** |

**阈值在 200~250KB 之间**，超出后连接被挂起直至 RST 或超时，bridge 侧表现为 `ReadError` / `WriteTimeout` → 上层返回 529。

### 三条关键对照（排除错误归因）

| 对照项 | 结果 | 排除了什么 |
|---|---|---|
| 公网同量级请求（300KB） | 200，2.03s | 排除「单位网络上行带宽不足」 |
| 直连网关 vs 经 bridge，大 body 表现 | **完全一致** | 排除「bridge 代码缺陷」 |
| gzip 压缩后上行（传输量 1/10） | **200 OK** | 定位限制在传输层/WAF，非后端处理能力 |

三条对照共同证明：**网关前方的 WAF / 反向代理对请求体大小设了约 200KB 的硬阈值**；后端本身能正常处理大 prompt。

### 附带发现：后端处理大 prompt 极慢

gzip 后 body 仅 443 字节仍耗时 **92.6s** 才返回，说明后端处理速度约 **3.3 KB/s**（每 50KB prompt 增加约 15s）。此延迟与传输量无关，**本地无法优化**，只能靠减小 context 或网关侧调优。

### 为什么这个问题之前没被发现

Claude Code 的实际请求体 = system prompt + tools schema + skills 摘要 + 对话历史。早期会话 context 小（几十 KB），落在阈值内表现正常；随着 skills/MCP 增多、context 增长到 200KB+ 后稳定踩中。表现为「前几天好好的，昨天突然变慢变报错」，具有伪装性。

## Decision Drivers

- **D1 区分传输限制与处理延迟**：两者现象相似（都是慢），但只有前者可本地修复，混淆会导致错误投入
- **D2 不误改 bridge**：压测证明 bridge 与直连行为一致，不应把问题误判为 bridge bug 而去改核心链路
- **D3 可落地**：需要在不改网关、不降 context 的前提下让请求送达

## Considered Options

1. **减小 context / 关闭 MCP 和 skills** — 有效但牺牲体验，且只是把阈值往后推，治标不治本
2. **请网关方调整 WAF 限制**（`client_max_body_size` / 超时）— 正解，但依赖外部响应，不在可控范围
3. **bridge 对上游请求启用 gzip 压缩** — 传输量降到原始的约 10%，直接低于 WAF 阈值；改动局限在 bridge 上游请求构造处，且网关已实测支持 `Content-Encoding: gzip`

## Decision

**选方案 3**：bridge 向网关发送请求时对 body 做 gzip 压缩并加 `Content-Encoding: gzip` 头，作为大 context 场景的传输层兜底。

同时明确**方案 2 是正解**：本地 gzip 只解决「挂死」，不解决后端 3.3 KB/s 的处理延迟。长期仍需网关侧调优，本 ADR 记录该限制供与网关方沟通时引用。

### 实测压缩率（决定该方案是否成立）

用近似真实的请求体构造（项目 CLAUDE.md + rules 全文 + 40 个 tools schema）：

| 指标 | 数值 |
|---|---|
| 原始 | 149 KB |
| gzip 后 | 14 KB |
| **压缩率** | **9.7%** |

真实 prompt 压缩率远优于普通文本 —— tools schema 与规则文档内部重复度极高。即便原始 250KB，压缩后也在 25KB 量级，远低于 WAF 阈值。**该方案对本场景成立。**

### 边界与风险

- ⚠️ **网关若不支持请求体 gzip 会返回 4xx**：必须配「失败不带 gzip 重试」的降级路径，且开关可关
- ⚠️ **不解决处理延迟**：body 越大后端越慢，压缩后仍需等待，只能减小 context 才能实质改善
- ⚠️ **阈值非硬承诺**：约 200~250KB 的观测值，随网关配置变动，需保留直连对照测试手段

## Consequences

- ✅ **大 context 可用**：250KB+ 的请求不再挂死，529 错误消失
- ✅ **改动局限**：仅影响 bridge 发往上游的请求体编码，本地链路与 Claude 行为不变
- ✅ **留下判据**：传输限制 vs 处理延迟的区分方法可直接复用于其他网关类故障
- ❌ **速度不会变快**：网关后端 3.3 KB/s 的处理延迟仍在，长 context 依旧慢
- ⚠️ **风险：压缩支持度依赖上游** — 以降级重试 + 开关兜底

## Implementation

### 复现与判据（PowerShell / WSL 均可）

```bash
# 阈值扫描：逐级加大 body，超限即挂死
for kb in 20 100 150 200 250 300; do
  # 构造 ${kb}KB 请求体后直连网关，观察 http 码与耗时
done

# 关键对照：gzip 同一 body，若通过则证明限制在传输层
gzip -c body.json > body.gz
curl -H "Content-Encoding: gzip" --data-binary @body.gz <网关URL>
```

### 排查顺序（下次同样症状）

1. 先排路由层 —— [0047](0047-tailscale-subnet-vs-office-intranet.md)（两侧 `Test-NetConnection` + `Find-NetRoute`）
2. 再排传输层 —— 本 ADR（body 大小扫描 + gzip 对照）
3. 最后排 bridge —— 仅当直连与 bridge 表现**不一致**时才动 bridge（本次一致，故排除）

## Related Decisions

- [0047](0047-tailscale-subnet-vs-office-intranet.md) — tailscale subnet 抢路由（同一次故障的第一层根因，排查顺序在其之前）
- [0019](0019-bridge-win-curl-wsl-vpn.md) — bridge win-curl 双模式（传输链路设计来源）

## Notes

本 ADR 只记录**观测事实与判据**。bridge 侧 gzip 改动实施前需先确认：开关命名（建议 `OPENAI_BRIDGE_GZIP`）、失败降级路径、以及对现有已实测支持 gzip 的上游 preset 的兼容性验证。
