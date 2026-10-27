# 0055. 会话内延迟执行：优先用官方 CronCreate，自建 skill 只补时间解析与可见性

> **Status**: ✅ Accepted
> **日期**: 2026-10-27
> **关联**: `~/git/skill/plugins/fpostpone/`、`~/.claude/settings.json`(`statusLine`)、私有 memory `postpone-scheduling-ops`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

用户周期性用 `/transliter` 工作流做批量文档翻译，但**LLM 忙时单价更高**，
希望「现在下达、闲时执行」。原始诉求形态：

```
/postpone 18点运行 /transliter "xxx.zip" 分析后给我建议
```

需要一套「定时延迟执行」能力。三个约束互相拉扯：

- **输出必须回到发起它的那个会话**（用户明确要求）—— 后续对话要能直接引用刚跑完的结果
- 场景是**本地文件批处理**（读本地 zip）→ 排除云端执行
- 本机走第三方 LLM 端点（非 claude.ai 账号）→ 无 cloud scheduled tasks 能力

## Decision Drivers

- **D1 输出落回原会话**：不是「跑完通知我」，是「结果就在我眼前、后续能引用」
- **D2 不自己写调度器**：官方已有调度能力，重复造会与官方语义漂移
- **D3 用户可自查**：不能出现「排完了但查不到、怀疑没生效」
- **D4 避开忙时**：这是用户的原始动机，调度必须能表达「闲时窗口」
- **D5 可失败要显性**：延迟、排队、不触发等情况必须让用户看得见原因

## Considered Options

1. **自建 cron/at + 独立进程** — ❌ 无 `at`/无 crontab；即便有，输出也回不到会话（违反 D1）
2. **systemd user timer + 无头 `claude -p`** — ✅ 关终端也能跑，但 ❌ **输出回不到原会话**（违反 D1）
3. **官方 cloud scheduled tasks（`/schedule`）** — ❌ 需 claude.ai 付费账号（本机无）；❌ 不能读本地文件；❌ 输出不回会话
4. **官方 Desktop scheduled tasks** — ❌ 需桌面 App；❌ 输出不回会话
5. **官方会话内 `CronCreate` + 一层薄 skill** — ✅ 唯一满足 D1；缺口（时间解析/可见性）由 skill 补

## Decision

**以官方会话内调度工具 `CronCreate` 为核心，`fpostpone` skill 只补三件官方没做的事。**

不做调度器。`CronCreate` 的官方语义即「把 prompt 排到将来某时刻、在原会话 REPL 注入执行」——
这正是 D1 所求。skill 的职责限于：

1. **中文时间表达式 → cron**（`parse-time.py`）
2. **任务可见性**（影子表 `tasks.sh` + `statusLine`）
3. **执行留痕**（prompt 包装里带 `start`/`done` 指令）

### 官方三种调度的定位（决策依据）

| | Cloud `/schedule` | Desktop | 会话内 `/loop` + `CronCreate` |
|---|---|---|---|
| 跑在哪 | Anthropic 云 | 本机（桌面 App） | 本机（会话内） |
| 要机器开着 | 否 | 是 | 是 |
| 要会话开着 | 否 | 否 | **是** |
| 读本地文件 | 否（新 clone） | 是 | 是 |
| **输出回原会话** | 否 | 否 | **是** |
| 订阅要求 | Pro/Max/Team/Ent | 桌面 App | 任意 |

**只有会话内方案满足 D1**，故排除其余三项。代价是「会话必须活着」——这条硬约束
必须在每次排任务时显式告知用户，并允许降级到方案 2（关终端也跑，但牺牲 D1）。

### 为什么需要 skill 这层（官方缺的三件）

官方 `CronCreate` 是**给 agent 调的工具**，不是给用户敲的 slash command（正如 `/bash` 不存在）。
用户无法直接使用，且三个缺口：

1. **时间表达**：`CronCreate` 只吃 5 字段 cron。用户说「18点」「明天9点」「中午闲时」
   「2分钟以后」「14：50（全角）」，全都要转。官方无此层。
2. **任务不可见**：会话内任务**不写任何落盘文件**（`scheduled_tasks.json` 仅 durable 时写），
   用户在终端查不到 → 会怀疑任务没排上（违反 D3）。官方 `CronList` 只对 agent 可见。
3. **执行侧无提示**：注入的 prompt 到点是**一条普通消息**，且注入时本 skill 的
   SKILL.md **不加载**（只有 `/fpostpone` 被调用才进上下文）→ 无法区分「定时任务」与
   「用户刚打的」。提示与打点指令必须**写进 prompt 自身**。

### 关键实现决策

- **prompt 统一包装**：`【fpostpone 延时任务·原定 <at>】先输出一行提示…① start ② 执行 ③ done`
  —— 用自然语言而非 slash 形式。附带好处：绕开「slash 命令后夹带说明文字会被并进
  `args` 污染参数」的坑（本机实测）。
- **用排定时间 `--at` 作键，不用任务 id**：`CronCreate` 返回的 id 要等调用完才知道，
  而 prompt 在调用时就固化了 → id 写不进去。`at` 在排任务前即已知，稳定可写。
- **影子表按 session 隔离**：影子表是全局文件，若不隔离则每个会话的底栏都显示同一批任务
  （实测踩过，用户反馈）。`statusLine` 从 stdin 的 `session_id` 过滤。
- **整点自动挪 `:02`**：官方文档明确一次性任务排在 `:00`/`:30` 会**提前最多 90 秒**执行
  —— 对「避开忙时」的用例是实质威胁，故脚本自动 +2 分钟并告知用户。

## Consequences

- ✅ 输出落在原会话上下文，后续对话可直接引用（D1 满足，其余方案皆不可）
- ✅ 不自己写调度，官方语义演进（如 `--resume` 恢复）自动继承
- ✅ 任务可自查（影子表 + statusLine 底栏），排完即见、跑完留痕
- ✅ 避开忙时：`中午闲时`/`晚上闲时` 窗口直接表达用户的原始动机
- ❌ **会话必须活着且空闲**——关终端不触发；到点若 agent 忙则排队等空闲
  （实测延迟 4 秒 ~ 7 分钟不等，非丢弃）。此约束每次都要告知用户
- ❌ 影子表是会话内任务在文件系统的唯一痕迹，与真实注册表（`CronList`）可能不同步，
  需以 `CronList` 为准
- ⚠️ **不触发情形**：`--resume` 恢复时**已过期**的一次性任务不恢复；单会话上限 50 条；
  循环任务 7 天自动过期
- ⚠️ 排队延迟可能让「准点」期望落空。缓解：告知用户「到点前几秒别发新请求」；
  真需准点/关终端则降级——但那会牺牲 D1

## Implementation

- `~/git/skill/plugins/fpostpone/SKILL.md` — 主流程（拆参数 → 解析时间 → 包装 prompt → 排任务 → 登记）
- `~/git/skill/plugins/fpostpone/scripts/parse-time.py` — 中文时间 → cron（支持全角、相对、
  闲时窗口、时段词、衬词；`:00`/`:30` 自动挪位）
- `~/git/skill/plugins/fpostpone/scripts/tasks.sh` — 影子表（`pending → running → finished`，
  按 session 隔离，完成后**不自动清除**）
- `~/git/skill/plugins/fpostpone/scripts/statusline.sh` — 底栏常驻显示（待执行/执行中/已完成三态）
- `~/git/skill/plugins/fpostpone/scripts/detach-run.sh` — 降级方案：systemd user timer + 无头执行
- `~/.claude/settings.json` 的 `statusLine` — 由空操作 `true` 改为指向 `statusline.sh`
  （**改动时逐项比对 `env`/`permissions`/`hooks`/`mcpServers` 未受影响**；该文件不在 git 仓内）

端到端实测（2026-10-27，四次任务）：排定 → 注入 → `start` → 执行 → `done` 全链路自动走通，
底栏留痕形如 `✓ 16:02 计算100-200质数 已完成 16:03-16:04`。
其中一次排定 16:02、实际 16:03-16:04 执行——**证明排定时间 ≠ 实际执行时间，
故必须两端打点记录区间，不能只记完成时刻**。

## Related Decisions

- [0050](0050-bridge-structural-refactor.md) — 同为「用官方/既有能力，不自建」的取向
- [0054](0054-external-harness-bridge-anthropic-only.md) — 同属「先查清上游硬约束再选方案」；
  本 ADR 的判据是**输出落点 + 会话生命周期**，0054 是协议与 TLS 能力
- [0021](0021-skill-creation-workflow.md) — skill 注册链路；本 skill 按该流程建成

## Notes

- 官方文档：`code.claude.com/docs/en/scheduled-tasks`（会话内调度）、
  `.../routines`（cloud scheduled tasks 对照表）、`.../statusline`（statusLine 输入 JSON 含 `session_id`）
- 实测数据、跨 session 串扰修复过程、官方方案对照的取舍推理记在私有 memory
  `postpone-scheduling-ops`；本文件按公开仓规范不含真实路径/端点。
- **未来若用户提出「关电脑也要跑」**：应主动建议官方 Desktop / cloud scheduled tasks，
  而非扩展本方案 —— 那会与 D1 冲突，属另一类需求。