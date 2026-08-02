# 0009. Token 成本优化：不装 caveman/rtk/headroom

> **Status**: ✅ Accepted
> **日期**: 2026-08-02
> **关联**: `templates/.claudeignore.example`、`commands/should-compact.md`、ccprivate `link/settings.json` + `setup.sh`
> **模板**: MADR 4.0 极简版
> **备注**: 原 `adr/002-token-cost-reduction.md`（3 位编号，误放仓库根 `adr/`），2026-08-02 迁回 `docs/adr/` 统一目录，编号改 4 位 0009。见 [[0010-adr-directory-location]](0010-adr-directory-location.md)。

## Context and Problem Statement

token 账单异常增长。调研三个 2026 年流行工具（caveman / rtk / headroom），同时审视 ccconfig 自带 baseline 优化项（cache / ignore / compact），决定动哪些。

## Decision Drivers

- **D1 简单性**：零新依赖、可审计、可 `rm -rf` 回退
- **D2 可信证据**：优先独立受控实验（JetBrains / SigNoz / Codepointer），不采信厂商自报
- **D3 不引入攻击面**：proxy 见 API key、shell hook 执行任意命令
- **D4 不牺牲延迟**：工具自身 latency 反噬体验
- **D5 先 baseline 后工具**：免费项（cache/ignore/compact）先到位，工具留复核机制

## Considered Options

### Option A: caveman-plugin (`JuliusBrussee/caveman`) — 拒绝

- 作者没删 — 94k★ 活跃。但只省 output，plugin 每轮 +1-1.5k input token。
- HONEST-NUMBERS 自承：对已 terse prompt 用户净账单**可负**。
- MUO 测试：70% output 省 vs +233% input 花，约打平。
- 替代更强：同一个 prompt 用 `--effort low` 直接 11× 省。
- 用户实际已在用 ccconfig 输出风格规则（极简输出），达成其效果 ~80%，无需再装 plugin。

### Option B: rtk (`rtk-ai/rtk`) — 拒绝

- 强：单 Rust binary、可审计、零遥测、tee 失败救场。
- 弱：**只 hook Bash 工具**（Read/Grep/Glob 旁路）。
- 致命：**JetBrains Skill Trial 2026-07 受控实验**（n=80 配对任务，p=0.004）：账单 **+7.6%**、轮次 +13.8%、cache read +14.3%；新 input（rtk 唯一能压的桶）**p=0.23 干净无效**。
- 根因：账单大头是 cache_read（1/10 价），rtk 不动；`rtk gain` 用全 raw 当反事实，bias 严重。
- 附加 bug：Issue #1820 **subagent shell 不继承 hook**（multi-agent 时完全失效）。
- Codepointer 614M token 实测：session 净省 0.5%。

### Option C: headroom (`headroomlabs-ai/headroom`) — 拒绝

- 覆盖 input 主路径，最大理论潜力。
- 但 SigNoz / Mat Banik 24 provider 独立 bench：**token 中位 +2.9%（更贵），latency +148%**。
- Mac app 安装行为被 HN 批评不透明；proxy 看到 API key。
- 120ms 中位 + 300ms P90 latency 反噬体验。
- Codepointer replay：净省 2.8%。

### Option D: baseline 优化（采纳）

1. `ENABLE_PROMPT_CACHING_1H=1`（已开）
2. `.claudeignore` 全局模板
3. `/should-compact` 命令
4. `CLAUDE_EFFORT=high` 保留（默认，不降）

## Decision

**采纳 Option D**，具体执行：

1. 确认 `ENABLE_PROMPT_CACHING_1H=1` 已在 env（1h TTL，cache read 1/10 价）
2. ccconfig 新增 `templates/.claudeignore.example` 公开模板；ccprivate `link/.claudeignore` 真实版 + `setup.sh` symlink → `~/.claude/.claudeignore`
3. ccconfig 新增 `commands/should-compact.md`（`/should-compact` 命令，读 session jsonl 给 compact 阈值建议）+ setup.sh symlink
4. settings.json env 保留 `CLAUDE_EFFORT=high`（`--effort` 只影响 reasoning tokens，不碰 input/cache）
5. **不装** caveman-plugin / rtk / headroom（理由见 Considered Options）

## Consequences

### Positive

- ✅ 零新依赖、零新攻击面、零额外延迟
- ✅ cache 已 1/10 摊薄账单最大块
- ✅ ignore 挡掉 deps/锁/二进制高频噪音（单交互 -60%+ 中文社区多源）
- ✅ /should-compact 提供量化 compact 决策

### Negative

- ❌ 放弃 output 压缩（caveman-plugin 场景）→ 依赖 ccconfig 输出风格规则近似
- ❌ 放弃 shell 输出压缩（rtk 场景）→ Bash 大输出仍全量进 context
- ❌ `.claudeignore` 可能误挡需要读取的路径 → 项目级覆盖可解

### Risks

- **R1** 账单再次异常 → 先查 invoice 分项（cache_create/cache_read/new_input/output 比例）再考虑装 rtk 跑 paired bill 对比一周；不复装 headroom（latency 反噬已独立证实）
- **R2** ignore 规则过宽 → 每次扩展先验证关键路径仍可读
- **R3** settings.json 后续 init-llm 重写可能丢 `CLAUDE_EFFORT` 行 → init-llm env_update dict 需同步保留

## Implementation

- ccconfig: `templates/.claudeignore.example`、`commands/should-compact.md`、`docs/adr/0009-…`（本文档）
- ccprivate: `link/.claudeignore`、`link/settings.json`（env 加 CLAUDE_EFFORT）、`setup.sh`（两行 setup_link）

## Verification

`/should-compact` 跑样例（2026-08-02 session fde264e9）：
- 累计 cache_read 5.1M token（1/10 价），cache_creation 0
- 平均 in/turn 449，cache hit 100%，当前 ctx 估算 < 1k
- 账单折算 ~510k 等价 token — 验证 caching 链路有效

## Related Decisions

- [[0010-adr-directory-location]](0010-adr-directory-location.md) — ADR 目录位置约定

## Related Memory

- `prompt-caching-1h` — 1h TTL 落地三处
- `token-usage-feature` — maintain.sh token 账单聚合
