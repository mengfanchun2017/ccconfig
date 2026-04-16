# Claude Config

Claude Code 配置文件仓库，用于跨设备同步配置。

## 目录结构

```
ccconfig/
├── ubuntuinit.sh            # Ubuntu 合一初始化脚本（Git + Claude + 环境）
├── feishuinit.sh            # 飞书基础配置（lark-cli，所有环境都跑）
├── bridgeinit.sh            # ccbot Bridge 专用（仅 Bridge 环境跑）
├── claudeinit.sh            # MCP 服务器安装与配置
├── hook-status.sh           # 状态检查（供 MCP 调用）
├── init-auto-sync.sh        # 文件变化自动同步到 GitHub
├── init-enable-autostart.sh  # auto-sync 自启动配置
├── mcp-status/              # 状态 MCP 服务器
│   └── status-mcp.js        # 提供 status 工具
├── conf-ubuntu.json         # ubuntuinit.sh 配置（Git/API）
├── conf-claude.json         # claudeinit.sh 配置（MCP）
├── link/                    # 符号链接文件目录
│   ├── CLAUDE.md            # 全局 AI 指令
│   ├── .config.json         # MCP 配置（用户状态）
│   ├── settings.json         # Claude Code 设置（权限/环境变量/hooks）
│   └── -home-francis-git/  # 项目记忆
│       └── MEMORY.md
└── .gitignore
```

## 配置文件架构

### Claude Code 配置文件体系

| 文件 | 作用 | 同步 |
|------|------|------|
| `~/.claude/settings.json` | 权限、环境变量、hooks、插件配置等 | ✅ 符号链接到 ccconfig |
| `~/.claude/.config.json` | MCP 配置、用户状态、项目信息等 | ✅ 符号链接到 ccconfig |
| `~/CLAUDE.md` | 全局 AI 指令 | ✅ 符号链接到 ccconfig |
| `~/.claude.json` | Claude Code 自动维护的状态（不建议手动编辑） | ❌ 不同步 |

### 符号链接（本地 ↔ GitHub 同步）

| 本地路径 | 指向 | GitHub 路径 | 作用 |
|---------|------|-------------|------|
| `~/.claude/settings.json` | → `ccconfig/link/settings.json` | `link/settings.json` | 权限/环境变量/hooks |
| `~/.claude/.config.json` | → `ccconfig/link/.config.json` | `link/.config.json` | MCP 配置/用户状态 |
| `~/CLAUDE.md` | → `ccconfig/link/CLAUDE.md` | `link/CLAUDE.md` | 全局 AI 指令 |
| `~/.claude/projects/-home-francis-git/memory/MEMORY.md` | → `ccconfig/link/-home-francis-git/MEMORY.md` | `link/-home-francis-git/MEMORY.md` | 记忆同步 |

### 配置同步策略

```
┌─────────────────────────────────────────────────────────────┐
│                   本地 ~/.claude/                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────┐  │
│  │ settings.json ──────► link/settings.json ──► GitHub   │  │
│  │ (权限/环境变量) │  │                 │  │            │  │
│  ├─────────────────┤  ├─────────────────┤  ├────────────┤  │
│  │ .config.json ──────► link/.config.json ──► GitHub   │  │
│  │ (MCP/用户状态)  │  │                 │  │            │  │
│  └─────────────────┘  └─────────────────┘  └────────────┘  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  ~/CLAUDE.md ──────► link/CLAUDE.md ──────► GitHub        │
│  (全局 AI 指令)                                        │
└─────────────────────────────────────────────────────────────┘
```

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
9. （MCP 服务器安装需要 Claude Code 已安装，见下方 claudeinit.sh）

### 飞书初始化（可选）

```bash
# 飞书基础配置（所有环境都跑）：lark-cli 文档/日历/任务
bash ccconfig/feishuinit.sh
```

feishuinit.sh 会完成：
1. lark-cli 安装（npm install -g @larksuite/cli）
2. lark-cli 配置（从 conf-feishu.json 读取凭证）
3. lark-cli 用户 OAuth 授权

```bash
# ccbot Bridge 专用（仅长期运行 Bridge 的那台机器跑）
bash ccconfig/bridgeinit.sh
```

bridgeinit.sh 会完成：
1. ccbot 安装（npm install -g @ccbot/cli）
2. ccbot 配置（从 conf-feishu.json 读取 App ID / App Secret）
3. ccbot 启动（pm2 管理）
4. 飞书开放平台长连接配置指导

**飞书组件架构：**

| 组件 | 脚本 | 用途 | 哪些环境 |
|------|------|------|---------|
| ccbot | bridgeinit.sh | Bridge 飞书→Claude（WebSocket 长连接，接收飞书消息） | 仅 Bridge 环境 |
| lark-cli | feishuinit.sh | 终端操作飞书文档/日历/任务 | 所有环境 |
| feishu MCP | claudeinit.sh | Claude→飞书（发消息、读文档） | 所有环境 |

**双向消息互通**：同时需要 ccbot + feishu-mcp
**仅 Claude 发消息/创建文档**：只装 feishu-mcp，不装 ccbot 也行

**文档操作**：统一用 lark-cli --as user
```bash
lark-cli docs +create --title "标题" --as user \
  --folder-token VB6nflC8JlFYhcdXNric6vORndg --markdown "# 内容"
```

### 查看状态

```bash
# 进入 Claude 后
"运行 status 工具"
```

status MCP 会执行 hook-status.sh 并返回状态输出。

## 配置文件说明

### conf-ubuntu.json
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

**Step 2**: App ID 和 App Secret 已在 `conf-claude.json` 中配置好

**Step 3**: 运行 `bash ccconfig/claudeinit.sh` 安装 MCP

**飞书 MCP 功能**：
- `feishu_send_message` - 发送文本/富文本/卡片消息
- `feishu_get_messages` - 获取会话消息历史
- `feishu_get_doc` - 读取文档内容
- `feishu_create_doc` - ⚠️ 创建的文档访问不了，**请用 lark-cli** 创建文档
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
