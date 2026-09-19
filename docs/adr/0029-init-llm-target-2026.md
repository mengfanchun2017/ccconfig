# 0029. init-llm 目标文档化与架构清理

> **Status**: ✅ Accepted
> **日期**: 2026-09-17
> **关联**: `lib/init-llm.sh`、`lib/init-llm-bill.sh`、`lib/ensure-bridge.sh`、`option-llmswitch/`、`docs/init-llm.md`
> **模板**: MADR 4.0 极简版
> **备注**: 同步落地 [docs/init-llm.md](../init-llm.md)（目标文档 294 行）
> **后续**: [ADR-0031](./0031-init-llm-consolidation-2026.md) 完成本 ADR 未落地的简化项（探测函数合并、删交互式 CRUD），并修复其 §稳定性增强 中两项带来的回退

## Context and Problem Statement

### 起因

2026-09-17 用户反馈：家里 altllmtail 反复出现 `waiting api response 之后读秒 curl 000`，但 `init-llm.sh test` 返 HTTP 200，"探测 OK 但实际跑挂"。同时给出三约束：

1. 在家只用 1 种模型（默认 altllmtail，挂时切 minimax/deepseek 直连）
2. Gateway 模式无用 → 删
3. Token 价格输入无用 → 只读用量

### 现状（init-llm 启动前）

| 模块 | 行数 | 现状 |
|------|------|------|
| `option-llmswitch/init.sh` | 798 | Gateway 启动管理 + 配置 UI（用户不用）|
| `option-llmswitch/proxy.py` | 439 | FastAPI 网关代理 |
| `option-llmswitch/watchdog.sh` | 108 | Gateway watchdog |
| `option-llmswitch/openai_bridge.py` | 628 | Anthropic↔OpenAI 桥（必须保留）|
| `option-llmswitch/conf/llmswitch.json.example` | 17 | Gateway 模板 |
| `option-llmswitch/README.md` | 141 | Gateway 文档 |
| `lib/init-llm.sh` gateway 段 | ~120 | switch_to_gateway / stop_gateway / get_gateway_status |
| `lib/init-llm-bill.sh` 价格段 | ~140 | bill_set / bill_del / show_table |
| **合计待清理** | **~2270 行** | |

### 核心稳定性问题（来自 3 轮调研，详见 [docs/init-llm.md §五](../init-llm.md#五核心稳定性要求)）

| 问题 | 根因 | 现状 |
|------|------|------|
| **探测 OK 但实际挂** | watchdog 探活用 5KB body，真实 Claude 请求 600KB+，SNI cert 重传 / MTU fragmentation / TCP slow start 5+ 次重传才成功 | 短探完全发现不了 |
| **流式 SSE 中断** | upstream 不发 token 时（agent 等 tool call 30-60s）撞 tailscale 75s idle / ALB 60s idle / CF 100s idle 必断 | SSE 路径只 catch TransportError 一刀切 |
| **2.5min watchdog 空窗** | `fail_threshold=5` × 30s 周期 | 期间 Claude 任何请求都 529 |
| **WSL2 MTU 1280 杀大包** | [tailscale#4833](https://github.com/tailscale/tailscale/issues/4833) | WSL 侧所有 HTTPS 请求都可能撞 |
| **tailscale 在 Windows 侧** | 2026-09-17 用户确认 tailscaled 跑在 Windows 主机 | WSL 经 mirrored 网络栈访问，假设文档已落地 |

## Decision Drivers

- **D1 稳定性优先**：用户的首要痛点（家里 altllmtail 反复挂），3 个稳定性增强必须落地
- **D2 简化架构**：gateway 模式是早期"在家多模型自动路由"的过设计，现在 1 种模型不需要
- **D3 单一真相源**：init-llm 能力 + 取舍 + 演进路径 → 写目标文档 docs/init-llm.md，避免每次新需求翻遍 11+ 份 ADR/memory
- **D4 不破坏现有用户**：ccprivate 端点配置 schema 不变，bridge 新订阅 + watchdog 自愈都不动

## Considered Options

### Option A — 维持现状（小修小补）

只修稳定性 bug，保留 gateway 整层。

**Pros**: 改动最小。**Cons**: 维护负担不降；用户在不用的功能上反复踩坑。

### Option B — 目标文档化 + 架构清理（采纳）

落地 `docs/init-llm.md` 目标文档，删 gateway 整层 + 简化 bill + 合并 preset + 3 个稳定性增强。

**Pros**: 删除 ~2270 行无用代码；稳定性增强根治"探测 OK 实际挂"；未来维护只读 1 份文档。
**Cons**: 一次性改动量大；需要逐项 commit 可回滚。

### Option C — 全部推到外部（OpenRouter / LiteLLM）

换商业网关。

**Pros**: 跨 provider failover。**Cons**: 单 provider 场景过设计；OpenRouter p50 慢 2.3× + 5.5% 费；LiteLLM 自带 5 种生产故障模式。

## Decision

**采纳 Option B**，分 4 个独立 commit 落地：

### Commit 1：本 ADR + 目标文档

- `docs/adr/0029-init-llm-target-2026.md`（本文件）
- `docs/init-llm.md`（已在 commit a0e1f99 落地）

### Commit 2：3 个稳定性增强

- **增强 1 — watchdog 双向探活**（根治"探测 OK 但实际挂"）
  - `lib/ensure-bridge.sh` watchdog wrapper 30s 周期小 body 探（100B）+ 5min 周期大 body 探（128KB）
  - 大 body 探不命中 fail_threshold（仅 log + counter），避免误杀
- **增强 2 — SSE heartbeat 注入**（根治"流式中断 vs 非流式 OK"）
  - `option-llmswitch/openai_bridge.py:513` SSE 路径起 `heartbeat_loop`，每 15s yield `: ping\n\n`
  - 只在 idle（`time.time() - last_chunk_time > 5`）注入，Anthropic SDK 忽略 SSE 注释
- **增强 3 — watchdog 指数退避**（根治 2.5min 空窗）
  - `lib/ensure-bridge.sh` 周期 30s → 10s，连续 3 次失败才重启（30s 空窗 vs 150s）
  - 指数退避：10s / 20s / 40s
  - `openai_bridge.py` TransportError 后**重建 transport 对象**，不复用（绕 [httpx#2983](https://github.com/encode/httpx/issues/2983)）
- **额外 — WSL2 MTU 1280 warn**
  - `lib/ensure-bridge.sh` 启动前检测 `ip link show eth0 | grep mtu 1280` → warn

### Commit 3：删 option-llmswitch gateway 整层

- 删 `option-llmswitch/init.sh`（798 行 Gateway 启动管理）
- 删 `option-llmswitch/proxy.py`（439 行 FastAPI 网关代理）
- 删 `option-llmswitch/watchdog.sh`（108 行 Gateway watchdog）
- 删 `option-llmswitch/conf/llmswitch.json.example`（17 行）
- 删 `option-llmswitch/README.md`（141 行）
- 删 `option-llmswitch/__pycache__/`（缓存）
- 删 `lib/init-llm.sh` gateway 相关段（~120 行）：
  - `BUILTIN_PRESETS` 去 `gateway`
  - `LLMSWITCH_CONF/INIT/WATCHDOG` 变量（第 34-36 行）
  - `is_proxy_running / get_gateway_status / read_gateway_routes`（行 124-165）
  - `stop_gateway`（行 309-316）
  - `switch_to_gateway`（行 424-457）
  - `gateway` case 分支（行 347）
  - 菜单 `2D` 子命令（行 968-971）和顶部菜单（行 951）
  - `main` 顶部 gateway import 处理
- 删 `lib/init-llm.sh` 菜单 2D 引用

### Commit 4：init-llm-bill 简化为用量读取

- 删 `lib/init-llm-bill.sh` 价格段（~140 行）：`bill_set / bill_del / show_table`
- 主菜单 `2E Bill 模型单价` → `2E 用量统计`
- 读 `ccprivate/usage/YYYY-MM-DD.csv`，按 model + day 聚合
- 保留模型发现四源（llm.json presets + 已配 pricing 字典 + usage CSV + jsonl 实扫）但只显示模型列表，不输入价格

### Commit 5：合并 altllm preset 4 → 2

- `altllm + altllmtail` → `office-deck-flash + home-deck-flash`（含 `--use-win-curl` + `host_header`）
- `altllmdsp + altllmdsp_tail` → `home-deck-pro`（pro 不常用只留家里）
- 更新 `BUILTIN_PRESETS`
- ccprivate 旧 preset key 保留（向后兼容，用户可手动迁）

## Consequences

### Positive

- ✅ 删除 ~2270 行无用代码（gateway 整层 1503 + bill 140 + init-llm gateway 段 120 + preset 合并 ~507）
- ✅ 稳定性增强根治"探测 OK 但实际挂"（2.5min 空窗 → < 30s）
- ✅ SSE 流式中断概率从 tailscale 75s idle 必断 → 心跳决定（理论无限）
- ✅ 目标文档 docs/init-llm.md 替代 11 份 ADR/memory 翻找
- ✅ bill 模块简化为只读用量（去 4 字段价格输入的繁琐）
- ✅ preset 合并降低切换心智负担

### Negative / Risks

- ⚠️ **删 gateway 后无法回退**：proxy.py 等管理代码删了就没了。缓解：保留 git 历史 + option-llmswitch README 不删（指向 docs/init-llm.md 解释为什么删）
- ⚠️ **bill 价格段删除**：之前用过 ccprestore 价格信息的脚本会找不到字段。缓解：pricing 字段保留在 llm.json（不再写入但能读）
- ⚠️ **preset 改名**：altllm → office-deck-flash 会让用户切换习惯改变。缓解：llm.json 老 key 保留 → 一次性迁移，新 key 文档化
- ⚠️ **稳定性增强未充分测试**：watchdog 指数退避 + transport 重建可能引入新 bug。缓解：先小流量试跑 + 保留 5x fail_threshold 作为环境变量 `BRIDGE_WD_FAIL_THRESH` 默认值可调
- ⚠️ **batch 改动量大**：5 个 commit 每个独立可回滚；但任一 commit 单独 cherry-pick 可能破坏关联（如 commit 3 删 gateway 段但 commit 5 改 BUILTIN_PRESETS，单独挑会断）

## Implementation

按本 ADR §Decision 4 个 commit 顺序落地，每个 commit 独立 `bash -n` 验证 + 必要时人工验证。

### 验证清单（每个 commit）

1. `bash -n lib/init-llm.sh lib/ensure-bridge.sh option-llmswitch/openai_bridge.py` — 防 P0 行合并 bug
2. `init-llm.sh list / status / test <builtin>` — 现有 builtin 行为不回归
3. `init-llm.sh switch <name>` — 切换后 `settings.json` env 块正确（人工 spot-check 1 个 preset）
4. 稳定性增强 commit：`init-llm.sh heal` 拉起 bridge + watchdog 30s 内自愈

### 落地 checklist

- [ ] Commit 1：ADR-0029 + 目标文档（✅ 已 a0e1f99，引用编号修正）
- [ ] Commit 2：3 个稳定性增强 + WSL2 MTU warn
- [ ] Commit 3：删 option-llmswitch gateway 整层
- [ ] Commit 4：init-llm-bill 简化为用量读取
- [ ] Commit 5：合并 altllm preset 4 → 2

## Related Decisions

- [ADR-0013](../adr/0013-bridge-selfheal-sessionstart.md) — bridge 自愈 SessionStart hook（仍有效）
- [ADR-0015](../adr/0015-llm-0731-deprecation.md) — 废弃 altllm0731 停止自改 bridge 适配（仍有效）
- [ADR-0016](../adr/0016-tailscale-subnet-router.md) — Tailscale Subnet Router（仍有效）
- [ADR-0019](../adr/0019-bridge-win-curl-wsl-vpn.md) — bridge WSL/VPN 三层修复（仍有效）
- [ADR-0020](../adr/0020-llm-current-local-per-machine.md) — settings.json LLM 本地化（仍有效）

## Related Memory

本 ADR 的配套笔记（切 LLM 需重启 session、4 preset 拆分沿革、`use_bridge` 三态、
tailscale 跑在 Windows 侧而非 WSL）存在使用者的私有 memory 中，不随公开仓库分发。

## Related Docs

- [docs/init-llm.md](../init-llm.md) — 目标文档（必读）