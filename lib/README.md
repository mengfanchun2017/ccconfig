# lib/ — 子脚本 + 共享库

> init.sh / maintain.sh 调用的所有子脚本和公共函数。

## 子脚本

| 文件 | 用途 | 调用者 |
|------|------|--------|
| `init-ubuntu.sh` | Ubuntu/WSL 全环境初始化 | init.sh all |
| `init-llm.sh` | LLM 后端切换 | init.sh / init-ubuntu.sh |
| `init-mcp.sh` | MCP 服务器管理 | init.sh all |
| `init-skill.sh` | Skills 同步管理 | init.sh all |
| `init-autostart.sh` | auto-sync systemd 服务 | init-ubuntu.sh |
| `monitor.sh` | 多仓库文件监听 + 自动 git 同步 | maintain.sh / systemd |
| `status.sh` | 状态检查（11 项） | maintain.sh status |
| `sync.sh` | 多仓库智能同步 | maintain.sh sync |
| `update.sh` | 月度组件升级 | maintain.sh update |
| `setup-links.sh` | 公开部分符号链接 | ccprivate/setup.sh |
| `deps-check.sh` | 依赖完整性检查 | status.sh |

## 共享库

| 文件 | 用途 |
|------|------|
| `path-helper.sh` | Node.js 路径发现（4 级回退）、版本文件读写、PATH 清理 |
| `git-conflict.sh` | Git 冲突解决公共库 |
| `colors.sh` | 终端颜色定义 |

## 路径约定

子脚本通过 `CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"` 定位仓库根目录：

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/path-helper.sh"          # sibling in lib/
CONFIG="$CCCONFIG_ROOT/conftemp/llm.json"    # conftemp/ at repo root
```

## 使用

```bash
# 用户入口（repo root）
bash maintain.sh status      # → lib/status.sh
bash init.sh all             # → lib/init-ubuntu.sh → lib/init-mcp.sh → lib/init-skill.sh
```
