# scripts/ — 内部流程脚本

面向自动化/开发流程，非用户直接调用。

| 脚本 | 用途 |
|------|------|
| `publish.sh` | 将 ccconfig/link/skills/ 发布到 claude-skills/plugins/ |
| `update-third-party-skills.sh` | 委托 `init-skill.sh update` 更新第三方 skill |
| `merge_worklog.py` | Worklog 合并去重（飞书 Base → LLM → 写回） |

与 `bin/` 的区别：
- `bin/` — 面向用户手动调用的工具
- `scripts/` — 面向自动化/internal 流程的脚本
