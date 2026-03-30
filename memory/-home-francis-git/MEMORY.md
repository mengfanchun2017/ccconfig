# Project Memory

This file persists across Claude Code conversations. Keep it concise (&lt;200 lines).

## Quick Links
- Project root: C:\git
- CLAUDE.md: C:\git\CLAUDE.md

---

## claude-config 仓库结构（2026-03-30 重构）

```
claude-config/                    # GitHub: <your-github-username>/claude-config
├── init01git.sh                # Git + GitHub CLI 环境初始化
├── init02claude.sh             # Claude Code 安装 + API 配置
├── init03env.sh                # 环境准备（Node.js/uv/Playwright/字体/符号链接）
├── claudemcp.sh                # MCP 服务器安装与配置
├── status.sh                   # 状态检查（SessionStart hook 自动运行）
├── config/                     # 配置文件
│   ├── CLAUDE.md              # 权限白名单
│   ├── settings.json           # Claude Code 设置（符号链接到 ~/.claude/settings.json）
│   ├── initconf.json          # 初始化配置（Git/API）
│   └── mcpconf.json           # MCP 服务器配置
└── memory/                     # 项目记忆
    └── -home-francis-git/
        └── MEMORY.md
```

**新环境初始化流程**：
```bash
# 1. 复制 claude-config 到 ~/git/claude-config
# 2. 确保 initconf.json 配置正确
# 3. 依次运行：
bash claude-config/init01git.sh   # Git + gh + 克隆仓库
bash claude-config/init02claude.sh  # Claude Code 安装
bash claude-config/init03env.sh   # 环境准备 + 符号链接
bash claude-config/claudemcp.sh  # MCP 配置
```

**注意**：
- 已删除 init.sh、scripts/ 目录、README.md、LICENSE
- 已删除 auto-sync 相关功能（auto-sync.sh、enable-autostart.sh、sync-settings.js）
- 所有脚本现在直接在 claude-config/ 根目录下

---

## User Preferences (用户偏好)

- Memory mode: Manual recording at checkpoints / end of session
- Preferred language: Chinese (中文)
- **Session Sync Requirement (会话同步要求)**
  - 每次工作收尾时必须同步记忆
  - 更新 MEMORY.md 后要同步到 claude-config 仓库
- **MCP 操作规则**:
  - 运行 `bash claude-config/claudemcp.sh` 管理 MCP
  - Key/Token 存储在 `config/mcpconf.json` 中
- **提交后通知要求**:
  - 每次提交后，必须用 ✅ 标记 commit hash + message

---

## 设备列表

| 主机名 | 操作系统 | 备注 |
|--------|---------|------|
| Francis_MiPro | Windows 11 家庭中文版 | 主工作电脑 |
| (待添加) | | |

---

## Project Context (项目上下文)

- Current working directory: C:\git
- **当前设备**: Francis_MiPro
- **设备识别方式**: 使用 `hostname` 命令获取主机名

---

## Key Learnings (关键知识点)

### 2026-03-30 [Francis_MiPro] - claude-config 重构
- **重大变更**:
  - 删除 init.sh，脚本移动到根目录
  - 删除 auto-sync 相关文件
  - 删除 README.md、LICENSE
  - 简化目录结构

- **MCP 配置规范**:
  - ~/.claude.json 是权威存储
  - mcpconf.json 是初始化数据源
  - minimax MCP 需要 MINIMAX_API_KEY 和 MINIMAX_API_HOST 两个环境变量

- **当前 MCP 状态**:
  - playwright: ✅
  - tavily: ✅
  - minimax: ✅
  - minimax-mcp: ✅
  - octocode: ✅
  - supabase: ✅

### 2026-03-15 [Francis_MiPro] - Windows 11 - Claude Code 升级方法
- **升级步骤**:
  1. 关闭所有 Claude Code 窗口和进程 (taskkill /F /IM claude.exe)
  2. 在 PowerShell 中运行: `winget upgrade Anthropic.ClaudeCode`

---

## Session Logs (会话记录)

### 2026-03-30 [Francis_MiPro] - claude-config 目录结构重构
**完成变更**：
1. 删除 init.sh、scripts/ 目录
2. 脚本移动到根目录: init01git.sh, init02claude.sh, init03env.sh, claudemcp.sh
3. 删除 auto-sync 相关文件
4. 删除 README.md、LICENSE
5. init03env.sh 移除 auto-sync 功能
6. 修复 minimax MCP 配置（添加 MINIMAX_API_HOST）
7. 更新 status.sh 移除 auto-sync 引用

**新目录结构**：
```
claude-config/
├── init01git.sh
├── init02claude.sh
├── init03env.sh
├── claudemcp.sh
├── status.sh
├── config/
└── memory/
```

**Git 状态**: db18c19 已推送
