# bin/ — 辅助脚本

独立执行的小工具，不参与 init/maintain 主流程。

| 脚本 | 用途 |
|------|------|
| `ccconfig` | 命令行入口（子命令转发到 maintain.sh / init-*.sh） |
| `refresh-gh-auth.sh` | 刷新 fine-grained PAT（引导粘贴新 token + 验证） |
| `test-bootstrap.sh` | 新机引导自检（WSL 内单跑） |
| `test-bootstrap.ps1` | 同上，Windows PowerShell 侧入口 |
| `memory-check.sh` | MEMORY.md 过期/孤立条目检测 |

与 `lib/` 的区别：
- `bin/` — 用户交互工具
- `lib/` — 脚本库 + 子功能模块
