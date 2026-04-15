# Project Memory

This file persists across Claude Code conversations. Keep it concise (&lt;200 lines).

## Quick Links
- Project root: /home/francis/git
- CLAUDE.md: /home/francis/git/CLAUDE.md

---

## ccconfig 仓库结构

```
ccconfig/                    # GitHub: <your-github-username>/ccconfig
├── ubuntuinit.sh               # Ubuntu 合一初始化脚本
├── claudeinit.sh               # MCP 服务器安装与配置
├── init-auto-sync.sh           # auto-sync 自动同步
├── init-enable-autostart.sh    # 自启动配置
├── hook-status.sh              # 状态检查（MCP 和 SessionStart 调用）
├── mcp-status/
│   └── status-mcp.js          # 提供 status 工具
├── conf-ubuntu.json             # ubuntuinit.sh 配置
├── conf-claude.json            # claudeinit.sh 配置（MCP + Key/Token）
└── link/                       # 符号链接文件目录
```

**新环境初始化流程**：
```bash
# 阶段一：终端执行
bash ccconfig/ubuntuinit.sh

# 阶段二：进入 Claude 后执行
bash ccconfig/claudeinit.sh  # MCP 安装 + 链接检查
```

---

## Claude Code 配置文件体系

| 文件 | 作用 | 同步 |
|------|------|------|
| `~/.claude/settings.json` | 权限、环境变量、hooks | ✅ → ccconfig/link |
| `~/.claude/.config.json` | MCP 配置、用户状态 | ✅ → ccconfig/link |
| `~/CLAUDE.md` | 全局 AI 指令 | ✅ → ccconfig/link |
| `~/.claude.json` | Claude 自动维护状态 | ❌ 不同步 |

---

## User Preferences

- Memory mode: Manual recording at checkpoints
- Preferred language: Chinese (中文)
- **Session Sync**: 每次收尾时同步记忆到 ccconfig 仓库
- **MCP 操作**: 运行 `bash ccconfig/claudeinit.sh` 管理
- **Key/Token 存储**: conf-claude.json 中
- **提交后通知**: 必须用 ✅ 标记 commit hash + message
- **进入 Claude 行为**: 说"hookstatus"→ 运行 `bash ccconfig/hook-status.sh`
- **Queue 指令**: 以 `queue xxx` 开头→先完成当前工作
- **搜索策略**: 中文=minimax web_search, 英文=tavily search

---

## 飞书集成配置（完整版）

### 飞书文件夹 Token

| 名称 | Token | 用途 |
|------|-------|------|
| cc编程大虾 | IFngftQdzlUhW7db6AOcZvYxnrg | 默认文档目录 |
| ClaudeCode | VB6nflC8JlFYhcdXNric6vORndg | Claude 相关文档 |
| 知识库（向前一步）| 7465636191379996675 | Wiki 知识库 ID |

### lark-cli 完整安装配置

```bash
# 1. 安装
npm install -g @larksuite/cli

# 2. PATH 修复（npm 全局路径问题）
ln -sf ~/.local/node-v20.11.0-linux-x64/bin/lark-cli ~/.local/bin/lark-cli

# 3. 初始化（使用飞书应用凭证）
echo "<your-feishu-app-secret>" | lark-cli config init \
  --app-id <your-feishu-app-id> --app-secret-stdin --brand feishu

# 4. 用户 OAuth 授权（以用户身份操作）
lark-cli auth login --recommend

# 5. 验证配置
lark-cli config list
```

### ccbot 完整安装配置（飞书双向对话）

```bash
# 1. 安装
npm install -g @ccbot/cli

# 2. PATH 修复
ln -sf ~/.local/node-v20.11.0-linux-x64/bin/ccbot ~/.local/bin/ccbot
ln -sf ~/.local/node-v20.11.0-linux-x64/bin/pm2 ~/.local/bin/pm2

# 3. 消息接收授权（需要 im:message:receive_v1 权限）
lark-cli auth login --scope "im:message:receive_v1"

# 4. 启动 ccbot（WebSocket 长连接）
ccbot login --app-id <your-feishu-app-id>

# 5. 管理命令
pm2 list                    # 查看状态
pm2 logs ccbot             # 查看日志
pm2 restart ccbot          # 重启
```

### 飞书 Open Platform 配置要求

- **App ID**: <your-feishu-app-id>
- **能力**: WebSocket 长连接（接收消息）
- **事件订阅**: im.message.receive_v1
- **权限**: im:message:receive_v1, space:document:retrieve

### 文档创建命令

```bash
# 创建富文档（markdown 会被飞书渲染）
lark-cli docs +create --as user \
  --folder-token IFngftQdzlUhW7db6AOcZvYxnrg \
  --title "标题" --markdown "$(cat file)"

# 创建多维表格
lark-cli base +base-create --as user \
  --folder-token IFngftQdzlUhW7db6AOcZvYxnrg --name "名称"

# 创建电子表格
lark-cli sheets +create --as user \
  --folder-token IFngftQdzlUhW7db6AOcZvYxnrg --title "标题"
```

### 飞书文档创建规则

- **身份**: 都用 `--as user` 以用户身份创建
- **feishu-mcp**: 适合发送消息，不适合创建文档（不渲染 markdown）
- **lark-cli**: 创建文档时 markdown 会被飞书原生渲染
- **OAuth 管理**: https://account.feishu.cn/ → 账号与安全 → 应用授权管理

---

## 目录规则

- **Git 仓库根目录**: `/home/francis/git`
- 项目结构按仓库名组织

---

## 待办任务

### 初始化触发指令
**触发关键词**: "新环境初始化"

执行：
1. `bash ccconfig/claudeinit.sh` 配置 MCP
2. `bash ccconfig/hook-status.sh` 检查状态
3. 确认：文件链接 ✅、sync 进程 ✅、MCP ✅、记忆最新 ✅

---

## Session Logs

### 2026-04-15 [Francis_MiPro] - ccbot 自启动 + .bashrc PATH 污染修复

**问题 1**: `.bashrc` 第 126 行有 `export PATH="$(npm bin -g):$PATH"`，但 npm 10.x 已移除 `bin` 命令
- 导致 PATH 污染 + `set -e` 下脚本提前退出
- 修复：删除该行，保留 `export PATH="$HOME/.local/bin:$PATH"`

**问题 2**: ccbot 在 WSL 重启后不自动复活
- 修复方案（三重保障）：
  1. `~/.bashrc` 添加 `pm2 resurrect 2>/dev/null || true`（每次开终端自动恢复）
  2. `init-auto-sync.sh` 的 `start_watch()` 调用 `resurrect_pm2()`（auto-sync 启动时恢复）
  3. `init-enable-autostart.sh` 调用 `pm2 save`（启用自启动时保存进程列表）

**ccbot 重启命令**（备用）：
```bash
pm2 start /home/francis/.local/node-v20.11.0-linux-x64/lib/node_modules/@ccbot/cli/dist/server.js --name ccbot-git -- "/home/francis/git/ccbot.json"
```

**注意**：VPN 需保持稳定，否则 git push 会失败

### 2026-04-14 [Francis_MiPro] - 飞书集成完整配置

- lark-cli 用户 OAuth 完成、ccbot WebSocket 长连接配置完成
- feishu-mcp: 发消息/读文档 | lark-cli: 创建文档（--as user）| ccbot: 接收飞书消息

### 2026-04-13 [Francis_MiPro] - 配置文件体系修正

- settings.json ↔ .config.json 职责明确，三个核心文件同步到 ccconfig/link

### 2026-04-10 [Francis_MiPro] - claudeinit.sh 同步逻辑修复

- is_registered() 改为同时检查 ~/.claude.json 和 conf-claude.json

### 2026-04-05 [Francis_MiPro] - 飞书集成初始配置

- App ID: <your-feishu-app-id>，lark-cli Skills 安装完成

---

## Key Learnings

- npm 全局包 → ~/.local/node-v20.11.0-linux-x64/bin/，需创建 ~/.local/bin/ 符号链接
- WebSocket 长连接 = 飞书推送消息给 Claude 的唯一方式
- 飞书文档创建用 lark-cli + --as user，feishu-mcp 不渲染 markdown
- PM2 进程在 WSL 重启后不会自动复活 → 需 `pm2 resurrect` 自动恢复
- `npm bin -g` 在 npm 10.x 已移除，勿在 .bashrc 中使用
- WSL 开新终端时 PATH 继承父进程，开新 session 才能验证 PATH 修复
