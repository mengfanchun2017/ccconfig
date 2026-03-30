# Project Memory

This file persists across Claude Code conversations. Keep it concise (&lt;200 lines).

## Quick Links
- Project root: C:\git
- CLAUDE.md: C:\git\CLAUDE.md

---

## claude-config 仓库结构（2026-03-30）

```
claude-config/                    # GitHub: <your-github-username>/claude-config
├── init01git.sh                # Git + GitHub CLI 环境初始化
├── init02claude.sh             # Claude Code 安装 + API 配置
├── init03env.sh                # 环境准备 + auto-sync 启动
├── claudemcp.sh                # MCP 服务器安装与配置
├── auto-sync.sh                # 文件变化自动同步到 GitHub
├── enable-autostart.sh          # auto-sync 自启动配置
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
# 2. 确保 config/initconf.json 配置正确
# 3. 依次运行：
bash claude-config/init01git.sh   # Git + gh + 克隆仓库
bash claude-config/init02claude.sh  # Claude Code 安装
bash claude-config/init03env.sh   # 环境准备 + 符号链接 + auto-sync 启动
bash claude-config/claudemcp.sh  # MCP 配置
```

---

## 配置文件架构

### 符号链接（本地 ↔ GitHub 同步）

| 本地路径 | 指向 | GitHub 路径 | 作用 |
|---------|------|-------------|------|
| `~/.claude/settings.json` | → `claude-config/config/settings.json` | `config/settings.json` | Claude Code 设置同步 |
| `~/CLAUDE.md` | → `claude-config/config/CLAUDE.md` | `config/CLAUDE.md` | 权限白名单同步 |
| `~/.claude/projects/-home-francis-git/memory/MEMORY.md` | → `claude-config/memory/-home-francis-git/MEMORY.md` | `memory/-home-francis-git/MEMORY.md` | 记忆同步 |

### 主配置文件（Claude Code 运行时读取）

| 文件 | 位置 | 内容 | 同步方式 |
|------|------|------|---------|
| `~/.claude.json` | 用户主目录 | mcpServers、hooks、环境变量、session 记录、metrics 等 | 通过 claudemcp.sh 同步到 settings.json |

### 同步策略

```
Claude Code 运行时 ~/.claude.json
       ↓ claudemcp.sh 同步
claude-config/config/settings.json (符号链接)
       ↓
GitHub 远程仓库
```

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

## Key Learnings (关键知识点)

### 2026-03-30 [Francis_MiPro] - claude-config 架构稳定

**最终目录结构**：
```
claude-config/
├── init01git.sh
├── init02claude.sh
├── init03env.sh        # 会启动 auto-sync
├── claudemcp.sh        # 同步 mcpServers/hooks 到 settings.json
├── auto-sync.sh        # 自动同步服务
├── enable-autostart.sh # systemd 自启动
├── status.sh
├── config/
└── memory/
```

**auto-sync 工作机制**：
- inotifywait 监控文件变化
- 防抖 3 秒后自动 commit + push
- `.auto-sync.pid` 和 `.auto-sync.log` 在 .gitignore 中

**配置文件优先级**：
- hooks/mcpServers 必须写在 `~/.claude.json` 顶层
- `~/.claude/settings.json` 只是符号链接，方便 Git 同步

---

## Session Logs (会话记录)

### 2026-03-30 [Francis_MiPro] - claude-config 架构最终稳定

**完成内容**：
1. 恢复 auto-sync.sh、enable-autostart.sh
2. 删除 end.sh（auto-sync 已自动同步）
3. auto-sync 服务运行中（PID: 44222）
4. GitHub 同步正常

**Git 状态**: c0260dd 已推送
