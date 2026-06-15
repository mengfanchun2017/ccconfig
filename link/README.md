# link/ — 符号链接源

> 公开部分（rules / agents / commands / skills）链接到 `~/.claude/`。
> 私有文件（CLAUDE.md / settings.json / .config.json / projects）在 ccprivate。

## 目录

| 路径 | 链接目标 | 仓库 |
|------|---------|------|
| `rules/` | `~/.claude/rules/` | ccconfig（公开） |
| `agents/` | `~/.claude/agents/` | ccconfig（公开） |
| `skills/` | `~/.claude/skills/` | ccconfig（公开） |
| `commands/` | `~/.claude/commands/` | ccconfig（公开） |
| `shell_aliases.sh` | `~/.claude/shell_aliases.sh` | ccconfig（公开） |
| `projects/` | `~/.claude/projects/` | symlink → ccprivate |
| `settings.json.example` | —（模板）| ccconfig（公开） |

以下文件**不在** ccconfig，由 ccprivate/setup.sh 直接链接到 `~/` 和 `~/.claude/`：

- `~/CLAUDE.md` ← ccprivate/link/CLAUDE.md
- `~/.claude/settings.json` ← ccprivate/link/settings.json
- `~/.claude/.config.json` ← ccprivate/link/.config.json
