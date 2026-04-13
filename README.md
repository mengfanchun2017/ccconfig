# Claude Config

Claude Code 配置文件仓库，用于跨设备同步配置。

## 目录结构

```
ccconfig/
├── ubuntuinit.sh            # Ubuntu 合一初始化脚本（Git + Claude + 环境）
├── claudeinit.sh            # MCP 服务器安装与配置
├── hook-status.sh           # 状态检查（供 MCP 调用）
├── init-auto-sync.sh        # 文件变化自动同步到 GitHub
├── init-enable-autostart.sh  # auto-sync 自启动配置
├── mcp-status/              # 状态 MCP 服务器
│   └── status-mcp.js        # 提供 status 工具
├── conf-ubuntu.json         # ubuntuinit.sh 配置（Git/API）
├── conf-claude.json         # claudeinit.sh 配置（MCP）
├── link/                    # 符号链接文件目录
│   ├── CLAUDE.md            # 权限白名单
│   ├── settings.json         # Claude Code 设置
│   └── -home-francis-git/  # 项目记忆
│       └── MEMORY.md
└── .gitignore
```

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
│               ccconfig/link/settings.json               │
│           (mcpServers, hooks, permissions 等)              │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ 符号链接
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   GitHub 远程仓库                           │
│        <your-github-username>/ccconfig                       │
└─────────────────────────────────────────────────────────────┘
```

### 为什么 ~/.claude.json 不是符号链接？

| 原因 | 说明 |
|------|------|
| Claude Code 自动写入 | 运行时状态、session 记录、metrics 等 |
| 包含用户数据 | userID、session 历史等私密信息 |
| 不应全部同步 | 需要选择性同步关键配置（mcpServers、hooks） |

## 新环境初始化流程

### 合一脚本（推荐）

```bash
# 一键初始化所有组件
bash ccconfig/ubuntuinit.sh
```

ubuntuinit.sh 会依次完成：
1. Git + GitHub CLI + 克隆仓库
2. Node.js + npm
3. uv (Python)
4. Claude Code (npm 安装)
5. Claude API 配置
6. 符号链接
7. auto-sync
8. SessionStart hook
9. **MCP 服务器安装（包括 status MCP）**

### 查看状态

```bash
# 进入 Claude 后
"运行 status 工具"
```

status MCP 会执行 hook-status.sh 并返回状态输出。

## 配置文件说明

### conf-init.json
```json
{
  "git": {
    "repo": "<your-github-username>/ccconfig",
    "target_dir": "/home/francis/git/ccconfig",
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
| tavily | `npx tavily-mcp` | 网络搜索 |
| minimax | `uvx minimax-coding-plan-mcp` | MiniMax 编程模型 |
| minimax-mcp | `uvx minimax-mcp` | MiniMax 多模态 |
| octocode | `npx -y octocode-mcp@latest` | GitHub 代码搜索 |
| supabase | `npx -y @supabase/mcp-server-supabase` | 数据库操作 |
| status | `node mcp-status/status-mcp.js` | 环境状态（文件链接、auto-sync、MCP） |
| feishu | `npx -y @china-mcp/feishu-mcp` | 飞书消息、文档、日历、任务 |

### 管理 MCP

```bash
# 同步 MCP 配置到 GitHub
bash ccconfig/claudeinit.sh

# 查看 MCP 状态
claude mcp list
```

### 飞书 MCP 配置

**Step 1**: 在[飞书开放平台](https://open.feishu.cn)创建企业自建应用，获取 App ID 和 App Secret

**Step 2**: 编辑 `conf-claude.json`，填入真实的 App ID 和 App Secret：
```json
{
  "name": "feishu",
  "description": "飞书 - 发送消息、创建文档、管理日程和任务",
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@china-mcp/feishu-mcp"],
  "env": {
    "FEISHU_APP_ID": "cli_xxxxxxxxxxxx",
    "FEISHU_APP_SECRET": "你的真实App Secret"
  }
}
```

**Step 3**: 运行 `bash ccconfig/claudeinit.sh` 安装 MCP

**飞书 MCP 功能**：
- `feishu_send_message` - 发送文本/富文本/卡片消息
- `feishu_get_messages` - 获取会话消息历史
- `feishu_create_doc` - 创建飞书文档
- `feishu_get_doc` - 读取文档内容
- `feishu_get_calendar` - 查询日程安排
- `feishu_create_event` - 创建会议/日程
- `feishu_create_task` - 创建任务
- `feishu_list_tasks` - 查看任务列表

## 同步机制

### 自动同步（推荐）

init03env.sh 会启动 auto-sync 服务，监控文件变化自动同步：
- 文件变化 → 自动 commit → 自动 push 到 GitHub
- 无需手动操作

### 手动同步

如果 auto-sync 未运行：
```bash
cd ccconfig
git add -A
git commit -m "描述"
git push origin main
```

### auto-sync 管理

```bash
bash ccconfig/init-auto-sync.sh start   # 启动
bash ccconfig/init-auto-sync.sh stop    # 停止
bash ccconfig/init-auto-sync.sh status   # 状态
```

## 常见问题

### Q: SessionStart hook 执行了但没看到输出？
A: Claude Code 的 SessionStart hook 设计为静默运行，输出不显示给用户。hook 内部仍会执行状态检查和 git pull。如需查看状态，请在 Claude 中说"运行 status 工具"来调用 status MCP。

### Q: 如何添加新的 MCP 服务器？
A: 在 `conf-claude.json` 中添加配置，然后运行 `bash ccconfig/claudeinit.sh`。

### Q: 如何更新配置到最新？
A:
```bash
cd ccconfig
git pull origin main
```
