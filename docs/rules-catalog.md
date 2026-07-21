# rules/ — 条件规则

> Claude Code 按条件加载的规则文件。通过 `setup-links.sh` symlink 到 `~/.claude/rules/`。

## 加载模式

| 模式 | 触发条件 | 适用 |
|------|---------|------|
| **始终加载** | 每个 session 都注入 | 跨领域约束（编码规范、飞书规范） |
| **路径匹配** | 仅当操作文件匹配 `paths:` glob 时注入 | 语言/框架特定规则 |

路径规则不破坏 prompt cache——它们注入到 conversation history（`<system-reminder>`），不影响 system prompt 前缀。

## 规则列表

| 规则 | 加载 | 大小 | 内容 |
|------|:--:|------|------|
| `code.md` | 始终 | 0.8K | 编码规范、禁止操作 |
| `feishu.md` | 始终 | 2.7K | 飞书集成：auth 预检、账号、ffeishu 前置、URL 输出 |
| `feishu-cli-cheatsheet.md` | 始终 | 0.7K | lark-cli 速查指针 → ffeishu references/ |
| `search.md` | 始终 | 1.2K | 搜索策略、三源并行 |
| `memory.md` | 始终 | 0.5K | 自动记忆、变更摘要、试错记录 |
| `context-budget.md` | 始终 | 0.7K | rules/MEMORY 预算上限 |
| `python.md` | `**/*.py` | 2.5K | Python 版本、包管理、绘图约定 |
| `git.md` | `**/.git/**` | 0.4K | Git 提交规范、安全操作 |
| `godot.md` | `**/*.gd` | 1.2K | Godot/GDScript 规范 |

**始终加载: 6.6KB / 15KB budget（44%）\| 路径加载: 4.2KB \| 合计: 10.8KB**

> 已移除：`README.md` → docs/rules-catalog.md（给人类看的目录）。`feedback_cwd_drift.md` → memory。`ffeishu.md`（rules.d 断链）。`feishu-cli-cheatsheet.md` 命令表 → ffeishu/references/lark-cli-cheatsheet.md。
