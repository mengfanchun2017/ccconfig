# src/ 目录说明

## 背景

原本此目录包含 `lib-common.sh`，用于在 bash 和 PowerShell 脚本之间共享公共函数。

## 为什么删除

**Bash 和 PowerShell 是完全不同的语言，无法共享代码。**

原来的 `lib-common.sh` 包含：
- OS 检测函数（`detect_os`）- bash 中调用，但 Windows 检测无意义
- Windows/WSL 路径转换 - 仅 PowerShell 需要
- 多平台路径处理 - 反而让代码更复杂

## 现在的架构

```
scripts/
├── bash/          # 独立实现，无公共库依赖
│   ├── start.sh
│   ├── end.sh
│   └── ...
├── pwsh/          # 独立实现，与 bash 对称
│   ├── start.ps1
│   ├── end.ps1
│   └── ...
└── shared/        # 仅放置真正可共享的脚本（如 Node.js）
```

## 原则

| 内容 | 处理方式 | 原因 |
|------|----------|------|
| 同步逻辑 | `sync-settings.js` | 真正的跨平台代码 |
| 路径操作 | 各平台独立实现 | Linux/Windows 路径格式不同 |
| Git 操作 | 各平台相同 | 直接调用 `git` 命令 |
| MCP 检查 | 各平台独立实现 | 逻辑相同但实现差异大 |

## 各平台脚本职责

### Linux/WSL (bash)

- `start.sh` - 创建符号链接，git pull
- `end.sh` - git add/commit/push
- `mcpcheck.sh` - MCP 环境检查
- `initgit.sh` - Git + GitHub CLI 安装
- `initclaude.sh` - Claude API 配置
- `initmcp.sh` - Node.js + uv 安装

### Windows (PowerShell)

- `start.ps1` - 创建符号链接，git pull
- `end.ps1` - git add/commit/push
- `mcpcheck.ps1` - MCP 环境检查
- `initgit.ps1` - Git + GitHub CLI 安装
- `initclaude.ps1` - Claude API 配置
- `initmcp.ps1` - Node.js + uv 安装

每个脚本都是完整独立实现，不依赖任何公共库。
