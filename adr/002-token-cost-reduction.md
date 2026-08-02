# ADR-002: Token 成本优化

**日期**: 2026-08-02
**状态**: 已实施
**关联**: `templates/.claudeignore.example`、`commands/should-compact.md`、ccprivate `link/settings.json` + `setup.sh`

## 背景

token 账单异常增长。调研三个 2026 年流行工具（caveman / rtk / headroom），同时审视 ccconfig 自带的 baseline 优化项（cache / ignore / compact），决定动哪些。

## 决策

| # | 措施 | 落地 | 优先级 |
|---|------|------|--------|
| 1 | 确认 `ENABLE_PROMPT_CACHING_1H=1` 已开 | 已在 env | 必做，已开 |
| 2 | `.claudeignore` 全局模板 | ccconfig `templates/.claudeignore.example` + ccprivate `link/.claudeignore` + setup.sh symlink | 必做 |
| 3 | `/should-compact` 命令 | ccconfig `commands/should-compact.md` + setup.sh symlink | 推荐 |
| 4 | `CLAUDE_EFFORT=high`（保留默认） | settings.json env | 保留 |
| 5 | **不装** caveman / rtk / headroom | — | 显式拒绝 |

## 不装 rtk / headroom / caveman-plugin 的理由

### caveman-plugin (`JuliusBrussee/caveman`)
- 作者没删 — 94k★ 活跃。但只省 output，plugin 每轮 +1-1.5k input token。
- HONEST-NUMBERS 自承：对已 terse prompt 用户净账单**可负**。
- MUO 测试：70% output 省 vs +233% input 花，约打平。
- 替代更强：同一个 prompt 用 `--effort low` 直接 11× 省。
- **用户当前用的是 ccconfig 输出风格规则（极简输出），已达成其效果 80%，无需再装 plugin**。

### rtk (`rtk-ai/rtk`)
- 强：单 Rust binary、可审计、零遥测、tee 失败救场。
- 弱：**只 hook Bash 工具**（Read/Grep/Glob 旁路）。
- 致命：**JetBrains Skill Trial 2026-07 受控实验**（n=80 配对任务，p=0.004）：
  - 账单 **+7.6%**
  - 轮次 +13.8%，cache read +14.3%
  - 新 input（rtk 唯一能压的桶）**p=0.23 干净无效**
- 根因：账单大头是 cache_read（1/10 价），rtk 不动；`rtk gain` 用全 raw 当反事实，bias 严重。
- 附加 bug：Issue #1820 **subagent shell 不继承 hook**（multi-agent 时完全失效）。
- Codepointer 614M token 实测：session 净省 0.5%。

### headroom (`headroomlabs-ai/headroom`)
- 覆盖 input 主路径，最大理论潜力。
- 但 SigNoz / Mat Banik 24 provider 独立 bench：**token 中位 +2.9%（更贵），latency +148%**。
- Mac app 安装行为被 HN 批评不透明；proxy 看到 API key。
- 120ms 中位 + 300ms P90 latency 反噬体验。
- Codepointer replay：净省 2.8%。

### 共同结论

Caveman 写 plugin 卖 output；rtk/headroom 卖 input。Anthropic API 实际账单结构：
- **cache_create + cache_read 占大头**（Codepointer: 71%）
- 新 input 仅占 29%
- 这部分 rtk/headroom 才有空间压

但 prompt caching 1h TTL 已 1/10 摊薄该空间，再压收益几乎为 0，反而引入 latency（headroom）/turn 数量上升（rtk / cache read 增加）。

## 真正的成本杠杆（按实测 ROI 排序）

| # | 措施 | 实测收益 | 实施 |
|---|------|---------|------|
| 1 | `ENABLE_PROMPT_CACHING_1H=1` | cache read 1/10 价（账单最大块） | 已开（ccprivate memory prompt-caching-1h.md） |
| 2 | `.claudeignore` 排除 deps/锁/binary/IDE | 单交互 -60%+（中文社区多源） | 刚实施 |
| 3 | 大任务主动 `/compact` | 25k → 3k 类无损 | 内置；`/should-compact` 给阈值判断 |
| 4 | 模型路由（轻 task Haiku/小模型） | 5-10× 单价差 | ccconfig `init-llm` 已支持 |

## 实施文件

- ccconfig 新增
  - `templates/.claudeignore.example`（公开模板）
  - `commands/should-compact.md`（slash command）
- ccprivate 新增 / 改
  - `link/settings.json` env 加 `CLAUDE_EFFORT`
  - `link/.claudeignore`（用户级 + 自定义追加位）
  - `setup.sh` 加两行 `setup_link`

## 验证

- `/should-compact` 跑样例（2026-08-02 session fde264e9）：
  - 累计 cache_read 5.1M token（1/10 价），cache_creation 0
  - 平均 in/turn 449，cache hit 100%
  - 当前 ctx 估算 < 1k（健康，无 compact 必要）
  - 账单折算 ~510k 等价 token — 验证 caching 链路有效

## 不装 rtk/headroom 的复核机制

如未来某天账单再次异常，先查：
1. Anthropic invoice 月度分项 cache_create / cache_read / new_input / output 比例
2. 是否切回短 cache TTL（5min 默认）无意恢复
3. 是否有大文件 Read 没被 `.claudeignore` 截到（先扩 ignore 规则）
4. 才考虑装 rtk 跑 paired bill 对比一周

不复装 headroom（latency 反噬已独立证实）。

## 回退

- 删 `~/.claude/.claudeignore` symlink 即关闭 ignore
- 删 `~/.claude/commands/should-compact.md` 即关闭命令
- 删 `settings.json` 的 `CLAUDE_EFFORT` 行回退默认
