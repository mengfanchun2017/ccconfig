# Project Memory

This file persists across Claude Code conversations. Keep it concise (&lt;200 lines).

## Quick Links
- Project root: C:\git
- CLAUDE.md: C:\git\CLAUDE.md

---

## ccconfig 仓库结构（2026-04-02）

```
ccconfig/                    # GitHub: <your-github-username>/ccconfig
├── init01git.sh                # Git + GitHub CLI 环境初始化
├── init02claude.sh             # Claude Code 安装 + API 配置
├── init03env.sh                # 环境准备 + auto-sync 启动
├── init-auto-sync.sh           # 文件变化自动同步到 GitHub
├── init-enable-autostart.sh    # auto-sync 自启动配置
├── hook-status.sh              # 状态检查（SessionStart hook 自动运行）
├── claudeinit.sh               # MCP 服务器安装与配置（进入 Claude 后运行）
├── conf-init.json              # 初始化配置（Git/API），init01-03 使用
├── conf-claude.json            # MCP 服务器配置
└── link/                       # 符号链接文件目录
    ├── CLAUDE.md              # 权限白名单
    ├── settings.json           # Claude Code 设置
    └── -home-francis-git/     # 项目记忆
        └── MEMORY.md
```

**新环境初始化流程**：
```bash
# 阶段一：Ubuntu 环境初始化
# 1. 复制 ccconfig 到 ~/git/
# 2. 确保 conf-init.json 配置正确
# 3. 依次运行：
bash ccconfig/init01git.sh   # Git + gh + 克隆仓库
bash ccconfig/init02claude.sh  # Claude Code 安装
bash ccconfig/init03env.sh   # 环境准备 + 符号链接 + auto-sync 启动

# 阶段二：Claude 初始化（进入 Claude 后）
# Claude 会参考 claudeinit.sh 进行初始化检查
bash ccconfig/claudeinit.sh  # MCP 配置 + 链接检查
```

---

## 配置文件架构

### 符号链接（本地 ↔ GitHub 同步）

| 本地路径 | 指向 | GitHub 路径 | 作用 |
|---------|------|-------------|------|
| `~/.claude/settings.json` | → `ccconfig/link/settings.json` | `link/settings.json` | Claude Code 设置同步 |
| `~/CLAUDE.md` | → `ccconfig/link/CLAUDE.md` | `link/CLAUDE.md` | 权限白名单同步 |
| `~/.claude/projects/-home-francis-git/memory/MEMORY.md` | → `ccconfig/link/-home-francis-git/MEMORY.md` | `link/-home-francis-git/MEMORY.md` | 记忆同步 |

### 主配置文件（Claude Code 运行时读取）

| 文件 | 位置 | 内容 | 同步方式 |
|------|------|------|---------|
| `~/.claude.json` | 用户主目录 | mcpServers、hooks、环境变量、session 记录、metrics 等 | 通过 claudeinit.sh 同步到 link/settings.json |

### 同步策略

```
Claude Code 运行时 ~/.claude.json
       ↓ claudeinit.sh 同步
ccconfig/link/settings.json (符号链接)
       ↓
GitHub 远程仓库
```

---

## User Preferences (用户偏好)

- Memory mode: Manual recording at checkpoints / end of session
- Preferred language: Chinese (中文)
- **Session Sync Requirement (会话同步要求)**
  - 每次工作收尾时必须同步记忆
  - 更新 MEMORY.md 后要同步到 ccconfig 仓库
- **MCP 操作规则**:
  - 运行 `bash ccconfig/claudeinit.sh` 管理 MCP
  - Key/Token 存储在 `conf-claude.json` 中
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

### 2026-04-02 [Francis_MiPro] - ccconfig 重构完成

**目录结构变更**：
- `auto-sync.sh` → `init-auto-sync.sh`
- `enable-autostart.sh` → `init-enable-autostart.sh`
- `status.sh` → `hook-status.sh`
- `claudemcp.sh` → `claudeinit.sh`
- `confinit.json` → `conf-init.json`
- `mcpconf.json` → `conf-claude.json`
- `memory/` → `link/`
- `config/` 目录已删除

**重构要点**：
- init01-03 在 Ubuntu 直接执行，配置读取 conf-init.json
- claudeinit 在进入 Claude 后执行，完成 MCP 和链接检查
- 链接文件统一放在 link/ 目录

---

---

## 待办任务

### 初始化触发指令
**触发关键词**: "新环境初始化"

当用户在新 Ubuntu 环境说完这句话后，执行以下操作：
1. 运行 `bash ccconfig/claudeinit.sh` 配置所有 MCP
2. 运行 `bash ccconfig/hook-status.sh` 检查状态
3. 确认结果：文件链接 ✅、sync 自动同步进程 ✅、MCP 配置 ✅、记忆最新 ✅

---

## Session Logs (会话记录)

### 2026-04-02 [Francis_MiPro] - ccconfig 重构

**完成内容**：
1. 重命名所有脚本文件（添加 init-/hook- 前缀）
2. 移动配置文件到根目录
3. memory 目录改名为 link
4. 更新所有文档和引用
5. 中文字体安装优化（免密失败才让我输入密码）

### 2026-04-04 [Francis_MiPro] - 添加初始化触发指令

**完成内容**：
1. 记录"初始化claudeinit检查status"触发指令到待办任务
2. 等待用户在新的 Ubuntu 环境配置完成后说出该指令
3. 届时将执行：claudeinit.sh → hook-status.sh → 确认四项状态
