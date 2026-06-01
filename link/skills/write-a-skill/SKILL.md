---
name: write-a-skill
description: 创建结构正确、支持 progressive disclosure 并带 bundled resources 的新 agent skills。Use when user wants to create, write, or build a new skill.
---

# Writing Skills

## Process

1. **Gather requirements** — 询问用户：
   - skill 覆盖什么 task/domain？
   - 应处理哪些具体 use cases？
   - 需要 executable scripts，还是只需要 instructions？
   - 是否有 reference materials 要包含？

2. **Draft the skill** — 创建：
   - 带 concise instructions 的 SKILL.md
   - 如果内容超过 500 行，创建 additional reference files
   - 如果需要 deterministic operations，创建 utility scripts

3. **Review with user** — 展示 draft 并询问：
   - 是否覆盖你的 use cases？
   - 是否缺失或不清楚？
   - 是否有 section 应更详细或更简短？

## Skill Structure

```
skill-name/
├── SKILL.md           # Main instructions (required)
├── config.yaml        # User-configurable settings
├── init.sh            # Install: symlink rules.d/ → ~/.claude/rules/
├── rules.d/           # Global constraints (always loaded into every session)
│   └── skill-name.md  #   Extracted subset of SKILL.md formatting rules
├── references/        # Detailed workflows (loaded on demand)
│   └── workflow-*.md
└── scripts/           # Utility scripts (if needed)
    └── helper.py
```

Canonical template: `skills/skill-template/` — copy and fill in `{{PLACEHOLDERS}}`.

### rules.d/ — 全局约束注入

Skill 的格式硬约束需要全局可见（不调 skill 也生效），但真相源在 SKILL.md。解决方案：

- `rules.d/<name>.md` — 从 SKILL.md 提取的 **硬约束子集**（~25行），始终加载
- `init.sh` — 将 `rules.d/*.md` 符号链接到 `~/.claude/rules/`
- SKILL.md 保留完整参考，rules.d/ 只放精简版 + 指针

规则：**rules.d/ 和 SKILL.md 不能有重复内容**。rules.d/ 是 SKILL.md 的子集提取 + 指针，不是独立副本。

### config.yaml — 用户可配置项

```yaml
settings:
  setting_name:
    value: <default>
    description: "<说明>"
    type: string | number | boolean | enum
    options: [a, b]  # 仅 enum 需要
```

Skill 读取 config.yaml 获取用户偏好。用户直接编辑文件或通过 `init.sh --config`。

### init.sh — 安装脚本

两个职责：
1. 符号链接 `rules.d/*` → `~/.claude/rules/`
2. 可选交互配置（`--config` flag）

幂等，可重复运行。仅在 ccconfig 体系外需要链接 skill 自身。

## SKILL.md Template

```md
---
name: skill-name
description: Brief description of capability. Use when [specific triggers].
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebSearch
---

# Skill Name

## Quick start

[Minimal working example]

## 前置条件

[依赖的 skill、工具、配置]

## Workflows

[Step-by-step processes with checklists for complex tasks]

## 格式规范

[Hard formatting rules — also extracted to rules.d/]

## 关键陷阱

[Common pitfalls]

## 线上文档索引

[Documents created/edited by this skill]
```

## Description Requirements

description 是 agent 决定是否加载 skill 时**唯一看到的内容**。它会和其他 installed skills 一起出现在 system prompt 中。agent 会读取这些 descriptions，并根据用户请求选择相关 skill。

**Goal**：给 agent 足够信息，让它知道：

1. 这个 skill 提供什么 capability
2. 何时/为什么触发它（specific keywords、contexts、file types）

**Format**：

- 最多 1024 chars
- 使用 third person
- 第一句说明它做什么
- 第二句："Use when [specific triggers]"

**Good example**：

```
Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when user mentions PDFs, forms, or document extraction.
```

**Bad example**：

```
Helps with documents.
```

坏例子无法让 agent 区分它和其他 document skills。

## When to Add Scripts

以下情况添加 utility scripts：

- Operation 是 deterministic（validation、formatting）
- 同一段 code 会被反复生成
- Errors 需要明确 handling

相比 generated code，scripts 节省 tokens 并提升 reliability。

## When to Split Files

以下情况拆分为独立文件：

- SKILL.md 超过 100 行
- 内容有不同 domains（finance vs sales schemas）
- Advanced features 很少需要

## Review Checklist

draft 完成后验证：

- [ ] Description 包含 triggers（"Use when..."）
- [ ] SKILL.md 低于 200 行（复杂 skill 可用 references/ 拆分）
- [ ] 格式硬约束已提取到 `rules.d/<name>.md`（~25行，不重复 SKILL.md 内容）
- [ ] `config.yaml` 列出用户可改的配置项
- [ ] `init.sh` 幂等，可重复运行
- [ ] 没有 time-sensitive info
- [ ] Terminology 一致
- [ ] 包含 concrete examples
- [ ] References 只深入一层
