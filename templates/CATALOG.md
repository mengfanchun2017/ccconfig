# rules/ — 条件规则

> Claude Code 按条件加载的规则文件。由 `ccprivate/setup.sh` symlink 到 `~/.claude/rules/`。

## 加载模式

| 模式 | 触发条件 | 适用 |
|------|---------|------|
| **始终加载** | 每个 session 都注入 | 跨领域约束（编码规范、飞书规范） |
| **路径匹配** | 仅当操作文件匹配 `paths:` glob 时注入 | 语言/框架特定规则 |

路径规则不破坏 prompt cache——它们注入到 conversation history（`<system-reminder>`），不影响 system prompt 前缀。

## 规则列表

| 规则 | 加载 | 大小 | 内容 |
|------|:--:|------|------|
| `ccconfig-open-source.md` | 始终 | 1.3K | ccconfig 公开仓库保密规则 |
| `code.md` | 始终 | 0.8K | 编码规范、禁止操作 |
| `context-budget.md` | 始终 | 0.6K | rules/MEMORY 预算上限 |
| `feishu.md` | 始终 | 4.5K | 飞书集成：auth 预检、账号、ffeishu 前置、URL 输出 |
| `git.md` | 始终 | 1.6K | Git 提交规范、安全操作 |
| `memory.md` | 始终 | 0.5K | 自动记忆、变更摘要、试错记录 |
| `search.md` | 始终 | 1.4K | 搜索策略、三源并行 |
| `skill.md` | 始终 | 0.3K | Skill 开发规范（描述中文、marketplace 同步） |
| `workflow.md` | 始终 | 1.5K | workflow 目录结构 + symlink 管理 |
| `python.md` | `**/*.py` | 2.5K | Python 版本、包管理、绘图约定 |
| `godot.md` | `**/*.gd` | 1.4K | Godot/GDScript 规范 |

**实测始终加载 ~13KB（9 个）\| 路径加载 ~4KB（2 个）**

> 已移除：`rules/README.md`（CATALOG.md 已承担目录索引职责）。`feedback_cwd_drift.md` → memory。`ffeishu.md`（rules.d 断链）。`feishu-cli-cheatsheet.md` 命令表 → ffeishu/references/lark-cli-cheatsheet.md。
