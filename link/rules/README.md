# rules/ — 条件规则

> Claude Code 按路径条件加载的规则文件。通过 `setup-links.sh` symlink 到 `~/.claude/rules/`。

## 加载模式

| 模式 | 触发条件 | 适用 |
|------|---------|------|
| **始终加载** | 每个 session 都注入 | 编码规范、飞书规范、记忆规范 |
| **路径匹配** | 仅当操作文件匹配 `paths:` glob 时加载 | 语言/框架特定规则 |

## 规则列表

| 规则 | 加载 | 内容 |
|------|:--:|------|
| `code.md` | 始终 | 编码规范、禁止操作 |
| `git.md` | `**/.git/**` | Git 提交规范、安全操作 |
| `python.md` | `**/*.py` | Python 版本、包管理、绘图约定 |
| `search.md` | `**/*.py` | 搜索策略、三源并行 |
| `feishu.md` | 始终 | 飞书集成规范（auth/账号/工具/文档追踪） |
| `feishu-cli-cheatsheet.md` | 始终 | lark-cli 命令速查（flag/参数/易错） |
| `godot.md` | `**/*.gd` `**/*.tscn` | Godot/GDScript 规范 |
| `memory.md` | 始终 | 自动记忆、变更摘要、试错记录 |
| `context-budget.md` | 始终 | rules/MEMORY 预算上限 |

> 已移除：`feedback_cwd_drift.md` → 转为 memory（非行为规则）。`f-feishu.md`（rules.d 断链）→ 内容在 feishu.md + feishu-cli-cheatsheet.md 中覆盖。
