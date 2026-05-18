# skills/ — 自定义 Skills

> Claude Code 可调用的技能定义（Markdown 格式），通过符号链接到 `~/.claude/skills/`。

## Skill 列表

| Skill | 用途 |
|-------|------|
| `lark-shared/` | 飞书基础：lark-cli 安装、认证、多账号 |
| `lark-doc/` | 飞书云文档：创建、读取、编辑、媒体 |
| `lark-base/` | 飞书多维表格：表、字段、记录、视图 |
| `worklog/` | 工作日志写入飞书 Base |
| `unified-research/` | 统一研究框架：三源搜索、自动领域判断 |
| `unified-research-deep/` | 深度研究：批量 JSON 输出 |
| `unified-research-report/` | 报告生成：JSON → Markdown |

## 同步

```bash
bash ccconfig/init-skill.sh sync
```
