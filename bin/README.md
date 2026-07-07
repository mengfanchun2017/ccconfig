# bin/ — 辅助脚本

独立执行的小工具，不参与 init.sh 主流程。

| 脚本 | 用途 |
|------|------|
| `init-ccprivate.sh` | ccprivate 仓库交互式创建向导 |
| `memory-check.sh` | MEMORY.md 过期/孤立条目检测 |

与 `scripts/` 的区别：
- `bin/` — 面向用户手动调用的工具
- `scripts/` — 面向自动化/internal 流程的脚本（publish.sh, update-third-party-skills.sh, merge_worklog.py）
