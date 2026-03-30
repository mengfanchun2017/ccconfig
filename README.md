# Claude Config

Claude Code 配置文件仓库，用于跨设备同步配置。

## 目录结构

```
claude-config/
├── init01git.sh      # Git + GitHub CLI 环境初始化
├── init02claude.sh   # Claude Code 安装 + API 配置
├── init03env.sh      # 环境准备 + auto-sync 启动
├── claudemcp.sh      # MCP 服务器安装与配置
├── auto-sync.sh      # 文件变化自动同步到 GitHub
├── enable-autostart.sh # auto-sync 自启动配置
├── status.sh         # 状态检查（SessionStart hook 自动运行）
├── config/           # 配置文件
│   ├── CLAUDE.md     # 权限白名单
│   ├── settings.json  # Claude Code 设置
│   ├── initconf.json # 初始化配置（Git/API）
│   └── mcpconf.json  # MCP 服务器配置
└── memory/           # 项目记忆
    └── -home-francis-git/
        └── MEMORY.md
```

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
| `~/.claude.json` | 用户主目录 | mcpServers、hooks、环境变量、session 记录、metrics 等 | 通过 claudemcp.sh 同步关键配置到 settings.json |

### 配置同步策略

```
┌─────────────────────────────────────────────────────────────┐
│                    Claude Code 运行时                      │
│                      ~/.claude.json                         │
│  (mcpServers, hooks, env, metrics, session 等)          │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ claudemcp.sh 同步
                      ▼
┌─────────────────────────────────────────────────────────────┐
│               claude-config/config/settings.json           │
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
bash claude-config/auto-sync.sh start   # 启动
bash claude-config/auto-sync.sh stop    # 停止
bash claude-config/auto-sync.sh status   # 状态
```

## 新环境初始化流程

```bash
# 1. 复制 claude-config 到 ~/git/
# 2. 确保 config/initconf.json 配置正确
# 3. 依次运行：
bash claude-config/init01git.sh   # Git + gh + 克隆仓库
bash claude-config/init02claude.sh  # Claude Code 安装
bash claude-config/init03env.sh   # 环境准备 + 符号链接
bash claude-config/claudemcp.sh  # MCP 配置
```

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
bash claude-config/claudemcp.sh

# 查看 MCP 状态
claude mcp list
```

## 配置文件说明

### initconf.json
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

### mcpconf.json
包含所有 MCP 服务器的配置（命令、环境变量、描述等）。

## 常见问题

### Q: 为什么 SessionStart hook 不生效？
A: 确保 hooks 配置在 `~/.claude.json` 的顶层，而不是在 `settings.json` 中。运行 `bash claude-config/claudemcp.sh` 修复。

### Q: 如何添加新的 MCP 服务器？
A: 在 `config/mcpconf.json` 中添加配置，然后运行 `bash claude-config/claudemcp.sh`。

### Q: 如何更新配置到最新？
A:
```bash
cd claude-config
git pull origin main
```
