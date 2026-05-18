# link/ — 符号链接源

> 此目录下的文件通过 `setup-links.sh` 链接到 `~/.claude/`（Claude Code 配置目录）。

## 目录

| 路径 | 链接目标 | 用途 |
|------|---------|------|
| `settings.json` | `~/.claude/settings.json` | 权限、MCP、hooks |
| `.config.json` | `~/.claude/.config.json` | 环境变量、项目状态 |
| `CLAUDE.md` | `~/CLAUDE.md` | AI 行为指南 |
| `rules/` | `~/.claude/rules/` | 条件规则（按路径加载） |
| `agents/` | `~/.claude/agents/` | 自定义 agents |
| `skills/` | `~/.claude/skills/` | 自定义 skills |
| `commands/` | `~/.claude/commands/` | 自定义斜杠命令 |
| `projects/` | `~/.claude/projects/` | 项目 MEMORY.md |

## 注意

此目录包含个人配置和 API Key，**不要公开提交**。
