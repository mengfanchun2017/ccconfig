# 0004. OfficeCLI Skill 架构：base + load_skill 运行时加载

> **Status**: ✅ Accepted
> **日期**: 2026-07-07
> **关联**: [tech-decisions.md](../tech-decisions.md)
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

OfficeCLI 生态有多个 skill 层次，需要决定如何管理：

- `officecli` base skill（417 行，npx 可安装）— 覆盖 .docx/.xlsx/.pptx 全部命令
- `officecli-pptx`（568 行，本地手动复制）— PPTX 专属设计系统
- `officecli-docx` / `officecli-xlsx` — GitHub 不存在（404），无法 npx 安装

之前手动复制了 officecli-pptx 到 `~/.claude/skills/`，但不清楚：
1. 它的来源是什么（GitHub？CLI 二进制？）
2. docx/xlsx 对应 skill 是否存在
3. 应该用 base 还是 3 个独立 skill

## Decision Drivers

- **D1 准确性**：AI 生成 Office 文档的质量（设计系统 vs 纯命令参考）
- **D2 可维护性**：skill 更新是否自动跟随 CLI 升级
- **D3 简洁性**：减少冗余文件和手动管理
- **D4 可靠性**：AI 是否总能获取到设计系统（不依赖运行时行为）

## Considered Options

### Option A: 只留 base skill，运行时 load_skill（**采纳**）

```
officecli base SKILL.md (npx 管理)
  └─ 告诉 AI: 创作前先 officecli load_skill pptx/word/excel
     └─ AI 执行命令 → 获取完整设计系统（568+558+481 行）
```

- **Pros**:
  - 一份文件，零冗余（CLI 二进制内置子技能）
  - CLI 升级 → 子技能自动升级（版本始终一致）
  - npx 管理，`npx skills update -g -y` 一键更新
  - 这是 officecli 作者的设计意图（base 第 30 行原文："need their own skill loaded first"）
- **Cons**:
  - AI 必须主动调用 `load_skill`（依赖 AI 遵循 base skill 指令）
  - 首次创作多一次命令往返

### Option B: 手动提取 3 个独立 SKILL.md

```
officecli base (npx) + officecli-pptx + officecli-docx + officecli-xlsx (本地)
```

- **Pros**:
  - 设计系统在 session 启动时即加载到 context
  - 不依赖 AI 运行时调用 load_skill
- **Cons**:
  - 冗余：CLI 二进制已有一份，本地再存一份
  - 版本漂移：SKILL.md 手动提取，CLI 升级后需手动重提取
  - officecli-docx/xlsx 不存在于 GitHub/npx，只能手动从 `load_skill` 提取
  - 4 个文件 × 400-568 行 = ~2000 行 context 占用（vs 417 行 base）

### Option C: 只留 base，不 load_skill

- **Pros**: 最简单
- **Cons**: AI 只有命令语法，没有设计系统。生成质量差（base 不含字号层级、色板、字体配对、QA 门禁等）

## Decision

**采纳 Option A**：只保留 npx 管理的 `officecli` base skill，删除手动复制的 `officecli-pptx`。依赖 `officecli load_skill <name>` 运行时获取格式专属设计系统。

具体执行：
1. 删除 `~/.claude/skills/officecli-pptx/`
2. `third-party-skills.txt` 改为 `iofficeai/officecli  officecli`
3. f-pptx/f-docx/f-xlsx 是个人设计系统 + 模板，不重复 officecli 的命令参考

## Consequences

### Positive

- ✅ 零冗余：设计系统在 CLI 二进制内，不额外存文件
- ✅ 版本一致：CLI 升级 = 设计系统升级，永不漂移
- ✅ 维护简单：`npx skills update -g -y` 一键更新
- ✅ Context 节省：417 行 vs 4×500=2000 行
- ✅ 作者设计意图：base skill 的 Specialized Skills 表格 + load_skill 就是为此设计的

### Negative

- ❌ AI 可能忘记调用 load_skill → base skill 的指令足够明确（第 30 行 + 第 373-407 行 Specialized Skills 表）
- ❌ 首次创作多一次 load_skill 往返（~1s，可接受）

### Risks

- **R1** AI 跳过 load_skill 直接用 base 命令 → 生成质量差 → 缓解：base 第 30 行 "Before doc work, check Specialized Skills" 是强指令
- **R2** load_skill 内容随 CLI 版本变化 → 行为可能漂移 → 缓解：版本一致正是我们想要的

## Implementation

- 删 `~/.claude/skills/officecli-pptx/`
- `third-party-skills.txt`: `iofficeai/officecli  officecli`
- f-pptx/f-docx/f-xlsx 继续作为个人设计系统独立演进

## Notes

- 调研时（2026-07-07）发现 `officecli load_skill pptx/word/excel` 返回完整 SKILL.md（含 frontmatter），正是之前手动复制的 officecli-pptx 的来源
- 子技能还有更专用的：pitch-deck、financial-model、data-dashboard、academic-paper、morph-ppt、morph-ppt-3d
- 这些同样通过 load_skill 按需加载，无需本地 SKILL.md

## Related Decisions

- (none yet)

## Related Memory

- [[officecli-skill-architecture]] (本次调研结论)
