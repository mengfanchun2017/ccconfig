# 0053. 某些网络位置下 home\* preset 只能走 DERP 中继（~18KB/s）— 判据、preset 并发闸与选型

> **Status**: ✅ Accepted
> **日期**: 2026-10-27
> **关联**: `lib/ensure-bridge.sh`、`lib/bridge-restart.sh`、`option-llmswitch/openai_bridge.py`、`ccprivate/conf/llmprivate.json`、ADR [0014](0014-tailscale-jump-server.md)、[0048](0048-wsl-large-upload-stall.md)、[0051](0051-tailscale-accept-routes-blackholes-office-intranet.md)
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

2026-10-27，在**市内某地址**（运营商 CGNAT 网络）切到 `homeds41flash`
（`base_url` = tailnet 节点 `<tailnet-node-ip>:18080`，经 `tailscale serve` TCP 转发 + `host_header`
透传到 `<office-llm-gateway>`，bridge 走 `curl.exe`）后，Claude 侧持续报 **529**。

**同一 preset 在另一地址是正常的、能直连** —— 所以这不是 preset 配置缺陷，也**不是"家里一律不行"**，
而是**该网络位置**不满足 P2P 条件，被迫落回 DERP 中继。

### 该位置为什么直连不上

| 观测点 | 结果 |
|---|---|
| 本机路由 | `<lan-gateway>` → `<upstream-router-lan>` → **`<carrier-cgnat-hop>`（运营商 CGNAT）** → 公网 |
| 本机路由器 WAN 地址 | **私网** `<router-wan-private>`（说明上游还有一层 NAT） |
| 本机 netcheck | `UDP: true`、UPnP/NAT-PMP/PCP 有映射，但映射只在第一层路由器上生效 |
| 对端 netcheck | `MappingVariesByDestIP: true` → 对称 NAT |
| 对端国际出口 | 境外测速（欧洲/东京/新加坡/CDN）**全部 0 B/s**；境内 144 KB/s |
| `tailscale ping <tailnet-node>` | 恒 `via DERP(<far-region>)` + `direct connection not established` |
| magicsock 指标 | `cached_peer_contact_direct=0`、`disco_recv_ping=0`（对端打不进来） |

结论：本机三层 NAT（两层本地 + 一层运营商 CGNAT）、对端对称 NAT，**两侧都不可被入站访问** → P2P 无解。
而所有 DERP 都在境外，对端到境外的路又被封 → 中继吞吐被压到 **上行 17.5 / 下行 18.7 KB/s**。
换到有公网映射的地址，其中一侧可达，直连即可建立（对端实测正常工作）。

### 失败形态：不是"body 太大"，是"在途字节太多"

| 负载 | 结果 |
|---|---|
| 单路 20/50/80/120 KB | 3/3 全成功（4.7s / 6.7s / 9s / 20s） |
| 2 路 × 50 KB | 稳定成功 |
| 2 路 × 100 KB | 一半轮次双双失败 |
| 4 路 × 100 KB | 约 50% 失败（`curl (52) Empty reply` / `(56) schannel: server closed abruptly`） |

即中继在**同时在途字节 ≳100KB** 时整体断流；单路再大也只是慢。并发压力来自 Claude 侧并行请求
（主请求 + 分类器 / 小模型调用 / 子代理），默认同时打到同一个上游。

## Decision Drivers

- **D1 不改变既有可用路径**：公网 preset、`office*`（局域网直连）必须零影响
- **D2 判据可自证**：下次同类症状一分钟内能定性，不再重跑"查 bridge / DNS / 超时"的老路
- **D3 不在错误层面优化**：本机链路已证实完好，调 timeout / 换 DERP 区 / 改传输栈都无收益
- **D4 让慢链路"可用"而非"更快"**：吞吐天花板改不动，能做的是别让它在并发下整条断掉

## Considered Options

1. **换 DERP 区域** — ❌ 实测只重新分配带宽：原区域上行 17.5/下行 18.7；法兰克福上行 13.1/下行 37.6；
   东京在对端判定不可达、未被采纳。上限仍是几十 KB/s，且关键的上行反而更差
2. **放宽 connect-timeout / 加 retry** — ❌ 15s→45s 失败率不变；`curl -d @-` 读 stdin 不可重放，retry 无处可加
3. **减小 body（关 MCP / 砍 context）** — ⚠️ 有效但治标、且用户要付功能代价
4. **bridge 侧并发闸（preset 可配 `max_concurrency`）** — ✅ 直接对准"在途字节"这个真实约束，代价是排队
5. **该位置继续用公网 preset** — ✅ 零成本，作为首选

## Decision

1. **新增 preset 字段 `max_concurrency`**（0/缺省 = 不限）：
   - `lib/ensure-bridge.sh` 新增 `bridge_max_concurrency()`，`_bridge_spawn` 经
     `OPENAI_BRIDGE_MAX_CONCURRENCY` 传给 bridge；`lib/bridge-restart.sh`（watchdog 重启）同源读取；
   - bridge 用 `asyncio.Semaphore` 排队，闸门**持有到上游第一个回包为止**（瓶颈是请求体上行，
     token 回流只有几 KB/s，不必占用闸门）；
   - `/health` 暴露 `max_concurrency`，`ensure_bridge` 比对运行值，不一致即重启（与 `use_win_curl` 同款）。
2. **`home*` 系列预设设 `max_concurrency: 1`**（该链路实测单路稳定）；公网 preset 不设（无限并发）。
3. **该网络位置优先用公网 preset**（`deepseek41flash` / `minimax31`）；`home*` 仅当必须在场时启用，接受串行排队。
4. **不做** timeout / DERP 区域 / 传输栈层面的调优（见 Considered Options 1、2）。

### 效果（实测，改前/改后同一负载）

| 4 路 × 100KB 并发 | 改前 | 改后（`max_concurrency: 1`） |
|---|---|---|
| 成功率 | ~50% | **4/4，且 4 条流都收到 `message_stop`** |
| 耗时分布 | 部分失败 / 部分 17s+ | 11.6s / 21.0s / 28.3s / 39.1s（明显串行排队） |

### 一分钟判据

```bash
tailscale ping <tailnet-node>   # 恒 via DERP + no direct
tailscale netcheck              # 本机 UDP/NAT；对端须另跑，看 MappingVariesByDestIP
tracert -d -h 8 <public-ip>     # 出现 10.x / 100.64.x 跳 → 运营商 CGNAT（P2P 无解）
# 对端（可登录时）
curl -o /dev/null --max-time 15 -w '%{speed_download}\n' <境外大文件>   # 0 B/s → 国际出口被封
```

命中「三层 NAT + 对端对称 NAT + 对端境外 0B/s」→ 直接按本 ADR 处理，别再查 bridge / DNS / 网关。

## Consequences

- ✅ 慢链路从"并发必挂"变成"排队但可用"（4/4 成功）
- ✅ 公网 / `office*` 路径零影响：字段缺省即旧行为
- ✅ 判定单点化：并发闸与 win_curl 判定同源，首启 / watchdog 重启 / 自愈三处一致
- ❌ 吞吐天花板不变（~18KB/s），单轮仍要数秒到数十秒
- ⚠️ 闸门是**排队不是加速**；`max_concurrency` 设成 >1 只是把"排队"换回"并发失败"，需按链路实测取值
- ⚠️ 字段只能经 preset 配置；换值会让 bridge 重启一次（进行中的请求会断）

## Implementation

- `option-llmswitch/openai_bridge.py` — `_gate()` / `_gated()`、`--max-concurrency`、`/health` 暴露
- `lib/ensure-bridge.sh` — `bridge_max_concurrency()`、`_bridge_spawn` 第 8 参、health 比对
- `lib/bridge-restart.sh` — watchdog 重启路径同源传参
- `ccprivate/conf/llmprivate.json` — `home*` 三个预设加 `max_concurrency: 1`

## Related Decisions

- [0048](0048-wsl-large-upload-stall.md) — 归因陷阱的对偶：0048 把"慢"当"断"，本案失败却是真断；
  共同纪律是"失败须先确认真失败 + 对照维度正交"（本案对照＝对端境外 0B/s vs 境内 144KB/s）
- [0047](0047-tailscale-subnet-vs-office-intranet.md) / [0051](0051-tailscale-accept-routes-blackholes-office-intranet.md)
  — 本地可修的路由型故障；本 ADR 是对端/运营商链路型故障，本地不可修，只能降级使用
- [0014](0014-tailscale-jump-server.md) — 跳板机部署；本 ADR 补上其**可用性前提**
- [0050](0050-bridge-structural-refactor.md) — bridge 判定单点化；本次的 `max_concurrency` 沿用同一原则

## Notes

- 对端细节（IP、SSH 入口、逐区实测、`pkill -f` 自杀坑）记在私有仓 memory `tailscale-ops`，本文件按公开仓规范只留占位符。
- 本案不影响 `office*`：在单位是局域网直连 `<office-llm-gateway>`，不经 tailscale。
- 若将来该位置换了接入方式（公网映射 / 有线 + 非 CGNAT），直连会自然恢复，届时可重新评估 Decision 1–3。
