# 0053. 家里用 home\* preset 不可用 — 对端对称 NAT + 国际出口被封，DERP 中继封顶 ~18KB/s；不在本地做优化，家里改用公网 preset

> **Status**: ✅ Accepted
> **日期**: 2026-10-27
> **关联**: `lib/init-llm.sh`、`lib/ensure-bridge.sh`、`option-llmswitch/openai_bridge.py`、`ccprivate/conf/llmprivate.json`、ADR [0014](0014-tailscale-jump-server.md)、[0047](0047-tailscale-subnet-vs-office-intranet.md)、[0048](0048-wsl-large-upload-stall.md)、[0051](0051-tailscale-accept-routes-blackholes-office-intranet.md)
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

2026-10-27，在家里（市内移动宽带，出口是运营商 CGNAT）切到 `homeds41flash`
（`base_url` = tailnet 节点 `<tailnet-node-ip>:18080` + `host_header` 透传到 `<office-llm-gateway>`，
经 bridge 走 `curl.exe`）后，Claude 侧持续报 **529**。

分层现象：

| payload / 并发 | 结果 |
|---|---|
| 小请求（~5KB），单路 | 200 OK，3-6s |
| 100KB，单路 | 200，但 8-17s |
| 100KB，4 路并发 | 一半失败（`curl (52) Empty reply` / `(56) schannel: server closed abruptly`） |
| 300KB | 常失败或 40s+ |

### 定位到的根因（不是本地问题）

| 观测点 | 结果 |
|---|---|
| `tailscale ping <tailnet-node>` | 恒 `via DERP(<far-derp-region>)` + `direct connection not established` |
| magicsock 指标 | `cached_peer_contact_direct=0`、`disco_recv_ping=0`（对端从未打到本机） |
| 本机 netcheck | `UDP: true`、`MappingVariesByDestIP: false`、UPnP/NAT-PMP/PCP 有映射；最近 DERP 78ms |
| **对端** netcheck | `MappingVariesByDestIP: true` → **对称 NAT，直连在原理上不可能** |
| **对端国际测速** | 欧洲 / 东京 / 新加坡 / Cloudflare CDN → **全部 0 B/s**（被封或不可用） |
| 对端国内测速 | 清华源 144 KB/s |
| 对端网卡 | **USB WiFi 网卡**，非有线 |
| 双向真实吞吐（自建测速端点，默认区域） | up 17.5 KB/s / down 18.7 KB/s（换区表现见下） |
| 对端公网端口 | 22 / 443 / 18080 从公网全不可达（NAT 无转发）→ 绕不开 tailscale |

即：**所有 DERP 都在境外，而对端到境外的路被掐死，只剩 DERP 被放行且被限到 ~18KB/s。**
本机的链路（移动 CGNAT → DERP）是好的；瓶颈在对端的国际出口与其 WiFi 上行。

### 已实测证伪的两个"看起来该有用"的修法

1. **把中继换到别的区域** — 无效（有增益但方向相反、量级不够）。逐区实测：

   | 对端 home DERP | 上行（请求体，关键方向） | 下行（响应流） |
   |---|---|---|
   | 原区域 `<far-derp-region>`（默认） | 17.5 KB/s | 18.7 KB/s |
   | 法兰克福 | 13.1 KB/s | 37.6 KB/s |
   | 东京 | 对端判定不可达，`force-prefer-derp` 2 分钟内未被采纳，仍回原区域 | — |

   即换区只在两个方向之间**重新分配**带宽，全部落在 13-38 KB/s 区间；而 Claude 请求的关键方向是
   **上行**（50-150KB 的请求体），法兰克福反而更差。原因：A→B 走的是 **B 的 home DERP**，
   而且无论哪个 DERP 都仍要过对端那条几乎不通的国际出口。
   另注：`systemctl restart tailscaled` 不会改变 home DERP；`debug force-prefer-derp` 需要该区域
   在对端可达才生效，且有数分钟延迟——所以"五分钟内看一眼没变"不足以判定它无效。
2. **放宽超时/加 retry** — 无效。`--connect-timeout` 由 15s 提到 45s 后并发失败率不变，
   说明失败不是"没等够"，而是中继在传输中被断（52/56）或吞吐不足。**与 ADR 0048 同一类陷阱的对偶**：
   0048 是"把慢当断"，这次是"把断当慢"——都必须先用正交证据定性。

## Decision Drivers

- **D1 不在本地投入**：本机链路已证实完好，任何 timeout / win_curl / 换区调优都是在错误层面做手术
- **D2 能在 1 分钟内自证**：给出可复现的判据，下次同类症状不必重跑一天排查
- **D3 不改变现有可用路径**：单位场景（局域网直连 `office*`）必须不受影响
- **D4 不新增运维负担**：不为一个偶发场景引入自建中转/额外机器的长期维护成本

## Considered Options

1. **换 DERP 区域（东京/法兰克福）** — ❌ 实测无效（见上），且 home DERP 由对端决定，本机改不动
2. **放宽超时 / 加 retry / 改传输栈** — ❌ 实测无效，天花板是对端吞吐而非超时
3. **自建境内中转（自建 DERP 或 frp）** — ✅ 理论有效（两端都走境内路径），❌ 需要一台境内公网机器 + 长期维护；暂不投入，保留为条件满足时的首选
4. **对端换有线 / 换到有正常国际出口的网络** — ✅ 最直接，但需要人到现场操作
5. **家里改用公网 preset，`home*` 只在单位用** — ✅ 零成本、零维护、立即可用（选定）

## Decision

1. **家里不启用 `home*` preset**，改用公网预设（`deepseek41flash` / `minimax31`）。`home*` 的适用场景限定为"对端链路可用"时（单位/有线/有正常国际出口）。
2. **不为本案做任何本地传输层改动**：不调 `--connect-timeout`、不加 `force_win_curl`、不切 DERP 区域、不在 bridge 里加并发限制。天花板在对端，本地改动只增加复杂度与误判面。
3. **`home*` 若要真正可用，前置条件必须满足其一**：
   - 对端换有线接入，或换到国际出口正常的网络；
   - 境内部署中转（自建 DERP / frp），让两端都走境内路径；
   - 把反代搬到"网络更好且能直连单位网关"的机器上。
4. **保留本次判据**（下表），下次同类症状先跑一遍再谈优化。

### 一分钟判据

```bash
tailscale ping <tailnet-node>          # 恒 via DERP + no direct → 中继路径
tailscale netcheck                     # 本机 UDP/NAT/DERP 延迟
# 对端（若可登录）
tailscale netcheck                     # MappingVariesByDestIP: true → 直连无解
curl -o /dev/null --max-time 15 -w '%{speed_download}\n' <境外大文件>   # 0 B/s → 国际出口被封
curl -o /dev/null --max-time 15 -w '%{speed_download}\n' <境内大文件>   # 有速度 → 只是境外不通
```

判据组合：**本机 netcheck 正常 + 对端对称 NAT + 对端境外 0B/s + 双向吞吐 ~18KB/s**
→ 结论直接落到本 ADR，不要再查 bridge / DNS / 网关 / 超时。

## Consequences

- ✅ 立即可用：家里用公网预设，零额外维护
- ✅ 制止了"在本地继续优化"的错误方向，省掉同类排查
- ✅ 给出了 `home*` 从"不可用"转为"可用"的三个明确前置条件
- ❌ `home*` 在家暂不可用；单位模型在家拿不到
- ⚠️ 若对端换网络/加境内中转，本 ADR 的 Decision 3 需重新评估并可能被取代
- ⚠️ 对端 USB WiFi + 国际出口被封是**环境事实**，不是 ccconfig 的配置缺陷；不要据此改默认值

## Related Decisions

- [0048](0048-wsl-large-upload-stall.md) — 同类归因陷阱的对偶：那里把"慢"当"断"，这里容易把"断"当"慢"；共同的纪律是"失败须先确认真失败，且对照维度正交"
- [0047](0047-tailscale-subnet-vs-office-intranet.md) / [0051](0051-tailscale-accept-routes-blackholes-office-intranet.md) — tailscale 抢路由型故障（本地可修），与本 ADR（对端链路型故障，本地不可修）互为反例
- [0014](0014-tailscale-jump-server.md) — 跳板机部署；本 ADR 补上它的**可用性前提**：跳板机自身必须有可用出口
- [0016](0016-tailscale-subnet-router.md) — subnet router 与 `--use-win-curl` 触发条件，本案中 win_curl 正常但无用

## Notes

- 对端细节（IP、SSH 入口、具体区域、每次排查手法与 `pkill` 自杀坑）记在私有仓 memory `tailscale-ops`，本文件按公开仓规范只留泛化占位符。
- 本案**不影响** `office*` preset：在单位是局域网直连 `<office-llm-gateway>`，不经 tailscale，与本案无关。
