# 0048. 大 body 上传"断流"是误判 — 实为网关后端 ~3.3KB/s 处理延迟

> **Status**: ⚠️ 原结论（WSL2 大 body 断流）**已被证伪**；本文件保留为归因方法论教材
> **日期**: 2026-10-16（2026-10-16 当天修正）
> **关联**: `lib/ensure-bridge.sh`、`option-llmswitch/openai_bridge.py`、`docs/adr/0049-auto-mode-discards-allow-rules.md`
> **模板**: MADR 4.0 极简版
> **取代**: 原文的"限制在 WSL2 网络栈"结论与 `force_win_curl` 决策

## Context and Problem Statement

2026-10-16 排查单位内网 office\* preset「很慢还会报错」，第一层根因 tailscale subnet 抢路由见 [0047](0047-tailscale-subnet-vs-office-intranet.md)。

### 第一次归因（错误）：WSL2 大 body 断流

观察到 body 超过 200~250KB 时请求"挂死"，而 Windows 侧 `curl.exe` 同一 body 成功。据此判定限制在 WSL2 网络栈，并据此加了 `force_win_curl` opt-in。

**理由是错的。** 两处缺陷：

1. **超时不对等**：WSL 组用 `--max-time 90~100s`，curl.exe 组用 `--max-time 120s`。而该请求实际耗时 ~90~100s —— **对照组之间唯一的差异是我给的超时值**。
2. **把"慢"当"断"**：命中超时被读成"连接被切断"，实际只是没等够。

### 第二次归因（正确）：唯一的瓶颈是网关后端吞吐

放宽超时后重测，各传输栈结果**完全相同**：

| 路径 | body | 结果 |
|---|---|---|
| WSL `curl` 直连 | 300KB | 200，88.9 / 93.2 / 99.5s |
| bridge httpx 模式 | 300KB | 200，94.9s |
| bridge win_curl 模式 | 300KB | 200，86.9s |
| Windows `curl.exe` | 300KB | 200，95.7s |

四条路径都是 ~90s，差异在噪声范围内。再结合此前 gzip 实验（body 压到 443 字节仍耗时 92.6s），结论明确：

**耗时来自网关后端处理 prompt，约 3.3 KB/s（≈0.25s/KB），与传输栈、body 大小、压缩全都无关。**

### 对 home\* 的复核

home\* 的 `base_url` 是字面 tailscale IP，命中私网段正则自动启用 win_curl。实测从 WSL 直连该 IP 小请求 **0.93s 正常返回**（401，仅缺 key）—— 本机 `.wslconfig` 已开 `networkingMode=mirrored`，WSL 共享 Windows 网络栈与路由，win_curl 对其同样不是必需。

## Decision

1. **撤销 `force_win_curl` 在 office\* preset 上的启用**（`ccprivate/conf/llmprivate.json`）：实测无收益，属无谓复杂度。
2. **保留 win_curl 能力本身**：非镜像网络的 WSL（默认 NAT 模式）确实看不到 Windows 侧 VPN/tailscale 路由，该通路仍是有效兜底。改为纯 opt-in 判定。
3. **统一判定来源**：抽出 `bridge_win_curl()`（`lib/ensure-bridge.sh`），首启与 watchdog 重启共用（见下）。
4. **不据此 ADR 做任何性能优化**：瓶颈在后端，本地无可优化空间。

### 同批修掉的真实缺陷

复查中发现原实现有一处会**静默改变行为**的问题：`ensure_bridge`（首启）与 `bridge-restart.sh`（watchdog 重启）各写一份 win_curl 判定，后者漏了 `force_win_curl` 且只有字面 IP 正则 —— 域名上游**首启走 win_curl、一重启就退回 httpx**，传输栈静默漂移，无任何告警。现已抽 `bridge_win_curl()` 单点判定，两处同源。

## Consequences

- ✅ **去掉无用的复杂度**：不再有基于错误前提的 `force_win_curl` 配置
- ✅ **判定单点化**：消除了首启/重启的传输栈漂移
- ✅ **排除了错误方向**：明确"本地网络优化"对本案无效，避免继续在传输层投入
- ❌ **慢的问题依然存在**：300KB 请求仍需 ~90s，本地无解，只能靠减小 context 或网关侧调优
- ⚠️ **原 ADR 结论已作废**：本文件的"WSL2 断流"标题与结论不再成立，保留仅为记录教训

## 归因方法论（本文件的主要价值）

同一天内两次归因错误，且**第二次是第一次的变体**，值得记录：

| 次序 | 错误 | 共同错误内核 |
|---|---|---|
| 第一次 | 用「WSL curl 失败 + bridge 失败」证明网关限制 | 对照组共享被测变量（都在 WSL） |
| 第二次 | 用「WSL 挂死 + curl.exe 成功」证明 WSL 断流 | 对照组共享……**不，是超时值不同** |

两次都对「失败」的确切含义缺少定义：

- **对照组必须在被测维度上正交**，且**其他所有维度必须对齐**——包括超时、重试次数、并发度。
- **报告"失败"前必须确认失败是真失败**：是连接被拒、被 RST、还是自己先超时走了？本案例全是后者。
- **跨组比较耗时类指标时，超时值应显著大于预期耗时**，否则测的是超时值而非系统行为。
- 出现「A 快 B 慢」时，先确认 A、B 的测量条件一致，再找系统差异。

## Related Decisions

- [0047](0047-tailscale-subnet-vs-office-intranet.md) — tailscale subnet 抢路由（同一次故障的第一层，结论仍成立）
- [0049](0049-auto-mode-discards-allow-rules.md) — auto 模式丢弃 allow 规则（同环境另一层问题）
- [0019](0019-bridge-win-curl-wsl-vpn.md) — bridge win-curl 双模式（win_curl 机制来源，本 ADR 未推翻其设计）
- [0053](0053-home-preset-unusable-on-cgnat-derp-cap.md) — 同类归因陷阱的对偶：本案把"慢"当"断"，0053 把"断"当"慢"；纪律一致（失败须先确认真失败 + 对照维度正交）

## Notes

- 本 ADR 最初以「WSL2 大 body 上传断流」为题并据此实施 `force_win_curl`，同日证伪后改写。**保留原文决策记录是刻意的**：错误归因的过程比结论更有复用价值。
- 若未来需要在本地降低大 context 的等待时间，唯一有效手段是减小请求体（即减小 context 或关闭 MCP/skills），压缩无效。
