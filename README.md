# Claude Config

Claude Code 配置文件仓库，用于跨设备同步配置。

## 目录结构

```
claude-config/
├── init01git.sh           # Git + GitHub CLI 环境初始化
├── init02claude.sh        # Claude Code 安装 + API 配置
├── init03env.sh           # 环境准备 + auto-sync 启动
├── init-auto-sync.sh      # 文件变化自动同步到 GitHub
├── init-enable-autostart.sh # auto-sync 自启动配置
├── hook-status.sh         # 状态检查（SessionStart hook 自动运行）
├── claudeinit.sh         # MCP 服务器安装与配置（进入 Claude 后运行）
├── conf-init.json         # 初始化配置（Git/API），init01-03 使用
├── conf-claude.json       # MCP 服务器配置
├── link/                  # 符号链接文件目录
│   ├── CLAUDE.md         # 权限白名单
│   ├── settings.json      # Claude Code 设置
│   └── -home-francis-git/ # 项目记忆
│       └── MEMORY.md
└── .gitignore
```

## 配置文件架构

### 符号链接（本地 ↔ GitHub 同步）

| 本地路径 | 指向 | GitHub 路径 | 作用 |
|---------|------|-------------|------|
| `~/.claude/settings.json` | → `claude-config/link/settings.json` | `link/settings.json` | Claude Code 设置同步 |
| `~/CLAUDE.md` | → `claude-config/link/CLAUDE.md` | `link/CLAUDE.md` | 权限白名单同步 |
| `~/.claude/projects/-home-francis-git/memory/MEMORY.md` | → `claude-config/link/-home-francis-git/MEMORY.md` | `link/-home-francis-git/MEMORY.md` | 记忆同步 |

### 主配置文件（Claude Code 运行时读取）

| 文件 | 位置 | 内容 | 同步方式 |
|------|------|------|---------|
| `~/.claude.json` | 用户主目录 | mcpServers、hooks、环境变量、session 记录、metrics 等 | 通过 claudeinit.sh 同步关键配置到 link/settings.json |

### 配置同步策略

```
┌─────────────────────────────────────────────────────────────┐
│                    Claude Code 运行时                      │
│                      ~/.claude.json                         │
│  (mcpServers, hooks, env, metrics, session 等)          │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ claudeinit.sh 同步
                      ▼
┌─────────────────────────────────────────────────────────────┐
│               claude-config/link/settings.json               │
│           (mcpServers, hooks, permissions 等)              │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ 符号链接
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   GitHub 远程仓库                           │
│        <your-github-username>/claude-config                       │
└─────────────────────────────────────────────────────────────┘
```

### 为什么 ~/.claude.json 不是符号链接？

| 原因 | 说明 |
|------|------|
| Claude Code 自动写入 | 运行时状态、session 记录、metrics 等 |
| 包含用户数据 | userID、session 历史等私密信息 |
| 不应全部同步 | 需要选择性同步关键配置（mcpServers、hooks） |

## 新环境初始化流程

### 阶段一：Ubuntu 环境初始化（直接执行脚本）

```bash
# 1. 复制 claude-config 到 ~/git/
# 2. 确保 conf-init.json 配置正确
# 3. 依次运行：
bash claude-config/init01git.sh   # Git + gh + 克隆仓库
bash claude-config/init02claude.sh  # Claude Code 安装
bash claude-config/init03env.sh   # 环境准备 + 符号链接 + auto-sync 启动
```

### 阶段二：Claude 初始化（进入 Claude Code 后执行）

```bash
# 启动 Claude Code，它会自动运行 hook-status.sh
# 然后让 Claude 参考 claudeinit.sh 进行初始化检查

# 或者手动运行：
bash claude-config/claudeinit.sh  # MCP 配置 + 链接检查
```

## 配置文件说明

### conf-init.json
```json
{
  "git": {
    "repo": "<your-github-username>/claude-config",
    "target_dir": "/home/francis/git/claude-config",
    "email": "your@email.com",
    "username": "your-github-username"
  },
  "api": {
    "vendor": "minimax",
    "base_url": "https://api.minimaxi.com/anthropic",
    "model": "MiniMax-M2.7",
    "key": "your-api-key"
  }
}
```

### conf-claude.json
包含所有 MCP 服务器的配置（命令、环境变量、描述等）。

## MCP 服务器配置

### 当前 MCP 服务器

| MCP | 命令 | 功能 |
|-----|------|------|
| playwright | `npx @playwright/mcp` | 浏览器自动化 |
| tavily | `npx tavily-mcp` | 网络搜索 |
| minimax | `uvx minimax-coding-plan-mcp` | MiniMax 编程模型 |
| minimax-mcp | `uvx minimax-mcp` | MiniMax 多模态 |
| octocode | `npx -y octocode-mcp@latest` | GitHub 代码搜索 |
| supabase | `npx -y @supabase/mcp-server-supabase` | 数据库操作 |

### 管理 MCP

```bash
# 同步 MCP 配置到 GitHub
bash claude-config/claudeinit.sh

# 查看 MCP 状态
claude mcp list
```

## 同步机制

### 自动同步（推荐）

init03env.sh 会启动 auto-sync 服务，监控文件变化自动同步：
- 文件变化 → 自动 commit → 自动 push 到 GitHub
- 无需手动操作

### 手动同步

如果 auto-sync 未运行：
```bash
cd claude-config
git add -A
git commit -m "描述"
git push origin main
```

### auto-sync 管理

```bash
bash claude-config/init-auto-sync.sh start   # 启动
bash claude-config/init-auto-sync.sh stop    # 停止
bash claude-config/init-auto-sync.sh status   # 状态
```

## 常见问题

### Q: 为什么 SessionStart hook 不生效？
A: 确保 hooks 配置在 `~/.claude.json` 的顶层，而不是在 `link/settings.json` 中。运行 `bash claude-config/claudeinit.sh` 修复。

### Q: 如何添加新的 MCP 服务器？
A: 在 `conf-claude.json` 中添加配置，然后运行 `bash claude-config/claudeinit.sh`。

### Q: 如何更新配置到最新？
A:
```bash
cd claude-config
git pull origin main
```
