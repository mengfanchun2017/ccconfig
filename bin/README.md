# bin/ — 辅助脚本

独立执行的小工具，不参与 init.sh 主流程。

| 脚本 | 用途 |
|------|------|
| `init-ccprivate-repo.sh` | ccprivate 仓库交互式创建向导 |
| `memory-check.sh` | MEMORY.md 过期/孤立条目检测 |

与 `lib/` 的区别：
- `bin/` — 面向用户/交互式操作的脚本（init-ccprivate-repo.sh, memory-check.sh）
- `lib/` — 脚本库 + 子功能模块（init/update/sync/monitor/publish）
