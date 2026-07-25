# templates/ — .example 模板

> 新用户复制 `.example` 文件到 ccprivate 后自定义。运行时文件在 ccprivate，
> 由 `ccprivate/setup.sh` 管理 symlink。

## 目录

| 路径 | 说明 |
|------|------|
| `rules/*.md.example` | 编码规范模板 → 复制到 ccprivate/rules/ |
| `agents/*.md.example` | Agent 定义模板 → 复制到 ccprivate/agents/ |
| `settings.json.example` | Claude Code 配置模板（MCP、权限、hooks） |
| `skills/` | skill 开发沙箱 → 发布用 `lib/publish.sh` |

## 运行时部署一览

```
~/CLAUDE.md              ← ccprivate/link/CLAUDE.md
~/.claude/settings.json  ← ccprivate/link/settings.json
~/.claude/.config.json   ← ccprivate/link/.config.json
~/.claude/shell_init.sh  ← ccconfig/lib/shell_init.sh
~/.claude/rules/         ← ccprivate/rules/
~/.claude/agents/        ← ccprivate/agents/
~/.claude/skills/        ← ~/git/skill/plugins/f*（独立仓库）
```

## 新用户初始化

```bash
# 1. ccconfig 模板 → ccprivate
bash ccconfig/init-ccprivate-repo.sh

# 2. ccprivate → ~/.claude symlink
bash ccprivate/setup.sh
```
