# Project Memory

This file persists across Claude Code conversations.

## Quick Links
- Project root: /home/francis/git
- CLAUDE.md: /home/francis/git/CLAUDE.md
- ccconfig: /home/francis/git/ccconfig

---

## 飞书文档创建（重要）

**正确方式**：必须用 `lark-cli`，不能用 feishu-mcp（创建的文档访问不了）

```bash
lark-cli docs +create \
  --title "文档标题" \
  --as user \
  --folder-token VB6nflC8JlFYhcdXNric6vORndg \
  --markdown "# 标题\n\n内容"
```

- ClaudeCode 文件夹 token: `VB6nflC8JlFYhcdXNric6vORndg`
- 链接格式: `https://www.feishu.cn/docx/<doc_id>`

**feishu-mcp 和 ccbot 的关系**：
- `ccbot`（bridgeinit.sh）= 接收飞书消息（飞书→Claude，WebSocket 长连接）
- `feishu-mcp` = 发送飞书消息（Claude→飞书）
- **双向消息互通**：两个都要装
- 飞书文档操作（创建/读取）= lark-cli --as user，不走 feishu-mcp

---

## User Preferences

- Preferred language: Chinese (中文)
- **Session Sync**: 每次收尾时同步记忆到 ccconfig 仓库
- **MCP 操作**: `bash ccconfig/claudeinit.sh`
- **Skills 操作**: `bash ccconfig/skillinit.sh`（install/sync/lock/list）
- **Skills 全局**: `~/.claude/skills/` → `ccconfig/.agents/skills/`，所有项目共享
- **飞书操作**: feishuinit.sh（所有环境）| bridgeinit.sh（仅 Bridge 环境）
- **Key/Token 存储**: conf-claude.json（已同步到 ccconfig/link）
- **进入 Claude 行为**: 说"hookstatus"→ 运行 `bash ccconfig/hook-status.sh`
- **搜索策略**: 中文=minimax web_search, 英文=tavily search
- **Agent**: `~/.claude/agents/assistant.md`（指令分流：@dev/@research/@summary）
  - 新环境初始化时会自动创建符号链接 `~/.claude/agents/`

---

## Key Learnings（重要，需熟记）

- npm 全局包路径: `~/.local/node-v20.11.0-linux-x64/bin/`，需创建 `~/.local/bin/` 符号链接
- `npm bin -g` 在 npm 10.x 已移除，勿在 .bashrc 中使用
- WebSocket 长连接 = 飞书推送消息给 Claude 的唯一方式
- 飞书文档创建用 `lark-cli + --as user`，feishu-mcp 不渲染 markdown
- PM2 进程在 WSL 重启后不会自动复活 → 需 `pm2 resurrect` 自动恢复
- WSL 开新终端时 PATH 继承父进程，开新 session 才能验证 PATH 修复
- Claude Code v2.1+ 推荐原生安装（`curl -fsSL https://claude.ai/install.sh | bash`）
- Claude Code 从 npm 切换到原生: `claude install --force`
- **API 变量统一**: 统一使用 `ANTHROPIC_AUTH_TOKEN`，不再用 `ANTHROPIC_API_KEY`
- **Claude 项目身份**: 由启动 Claude 时的绝对路径决定（找最近的 .git 目录往上）
- **工作习惯**: 在 `~/git/` 下启动 Claude（总目录），不频繁切换到子仓库
- **monitor-sync.sh**: init-auto-sync.sh 已删除，统一用 monitor-sync.sh（含 start/stop/status/log/monitor/tail 命令）
- **pull --ff**: auto-sync 先 commit → pull --ff → push，解决多机同时 push 的冲突问题

---

## 飞书集成配置（详细配置见 ccconfig/conf-feishu.json）

- 飞书 App ID: `<your-feishu-app-id>`
- **文档操作**:
  - **创建/读取文档**: 必须用 `lark-cli docs +create --as user` 或 `lark-cli docs +fetch --as user`
  - feishu-mcp 的 `feishu_get_doc` 无法读取 wiki（返回403），因为是 bot 身份而非用户身份
  - lark-cli --as user 用用户身份，可以读取私有 wiki 文档
- **文件夹 Token**: ClaudeCode 文件夹 `VB6nflC8JlFYhcdXNric6vORndg`
- **分工**:
  - `feishu-mcp` → 发飞书消息（只能用 SendMessage，不能读写文档）
  - `lark-cli --as user` → 创建/读取飞书文档、日历、任务
  - `ccbot` → 接收飞书消息 WebSocket 长连接（仅 Bridge 环境）
- **OAuth 管理**: https://account.feishu.cn/ → 账号与安全 → 应用授权管理
- **ccbot PATH 问题**: pm2 在 `~/.local/node-v20.11.0-linux-x64/bin/pm2`，需加入 PATH
  - `bridgeinit.sh` 已修复此问题（设置完整 PATH）
  - crontab 自动启动时也需完整 PATH

---

## 多项目架构（~/git/ 总目录）

```
~/.claude/                        ← 全局配置（不被 Git 追踪）
├── skills/ → ccconfig/.agents/skills/    ← 符号链接，全局 skills
├── agents/ → ccconfig/link/.claude/agents/  ← 符号链接，指令分流 agent
└── projects/
    ├── -home-francis-git/
    │   └── memory/MEMORY.md → ccconfig/link/-home-francis-git/MEMORY.md
    └── -home-francis-git-projectu/
        └── memory/MEMORY.md → ccconfig/link/-home-francis-git-projectu/MEMORY.md

~/git/                            ← 项目目录（总目录）
├── ccconfig/                      ← 配置仓库，monitor-sync 在跑
│     └── link/                    ← 同步到 GitHub: <your-github-username>/ccconfig
│           ├── -home-francis-git/MEMORY.md
│           └── -home-francis-git-projectu/MEMORY.md
└── projectu/                      ← Godot 项目
      └── .claude/                 ← 符号链接指向 ~/.claude/
```

**工作方式**: 
- 在 `~/git/` 下启动 Claude（总目录），不切换子仓库目录
- skills 全局可用：`~/.claude/skills/` → `ccconfig/.agents/skills/`
- 不同项目有不同的 memory，保存在 ccconfig/link/ 下
- monitor-sync 在 ccconfig 目录运行，自动同步所有配置

---

## ccconfig 仓库结构

```
ccconfig/
├── ubuntuinit.sh              # Ubuntu 合一初始化
├── feishuinit.sh              # 飞书 lark-cli 配置（所有环境）
├── bridgeinit.sh              # ccbot Bridge 专用（仅 Bridge 环境）
├── claudeinit.sh              # MCP 安装配置
├── skillinit.sh               # Skills 安装配置（与 claudeinit.sh 配套）
├── monitor-sync.sh            # 文件监控 sync（start/stop/status/log/monitor）
├── init-enable-autostart.sh   # 自启动（systemd + pm2 save）
├── hook-status.sh             # 状态检查
├── conf-ubuntu.json           # ubuntuinit 配置
├── conf-claude.json          # MCP + Key/Token 配置（同步源）
├── conf-feishu.json          # 飞书配置（App ID/Secret/Bridge workDir）
└── link/                      # 符号链接 → ~/.claude/（所有配置同步到 GitHub）
```

**注意**: `init-auto-sync.sh` 已删除，旧名统一改为 `monitor-sync.sh`

**link/ 目录结构**:
```
link/
├── .config.json                        ← MCP 配置 + 用户状态（被 Git 追踪）
├── settings.json                       ← Claude Code 全局设置（被 Git 追踪）
├── CLAUDE.md                          ← 全局 AI 指令（被 Git 追踪）
├── .claude/                           ← Claude Code 全局目录（被 Git 追踪）
│     └── agents/
│           └── assistant.md           ← 指令分流 agent（@dev/@research/@summary）
└── -home-francis-git/                 ← 项目记忆目录（被 Git 追踪）
      └── MEMORY.md                    ← Claude 记忆文件（被 Git 追踪）
```

**新环境初始化**:
```bash
# 1. 终端：基础环境（完成后 Claude Code 就可用了）
bash ccconfig/ubuntuinit.sh
bash ccconfig/feishuinit.sh

# 2. 终端：MCP 安装（claudeinit.sh 需要 Claude Code 已安装）
bash ccconfig/claudeinit.sh

# 3. 仅 Bridge 环境额外运行
bash ccconfig/bridgeinit.sh
```

**monitor-sync.sh 用法**:
```bash
bash ccconfig/monitor-sync.sh start     # 后台启动监控
bash ccconfig/monitor-sync.sh stop      # 停止监控
bash ccconfig/monitor-sync.sh status     # 查看状态
bash ccconfig/monitor-sync.sh log       # 查看最近日志
bash ccconfig/monitor-sync.sh monitor   # 前台实时查看文件变化（调试用）
```

**sync 流程**: 变化 → 等 120s 防抖 → commit → pull --ff → push
- pull --ff 解决两台机器同时 push 的冲突（不能 ff 时报错"请手动处理"）

---

## Session Logs（精简）

### 2026-04-17
- hook-status.sh 修复: PID 文件名从 `.auto-sync.pid` 改为 `.monitor-sync.pid`（匹配实际）
- 清理 ccconfig: 删除残留 `.auto-sync.log` 和已废弃的 `init-auto-sync.sh`
- 更新 ubuntuinit.sh / init-enable-autostart.sh 中对 init-auto-sync.sh 的引用 → monitor-sync.sh
- 重写 README.md：统一用 monitor-sync.sh，删除过时引用，增加 monitor/monitor 区别说明
- MEMORY.md 同步更新

### 2026-04-15（续）
- monitor-sync.sh 新增 `monitor` 前台模式，可实时查看文件变化
- pull --ff 解决多机 sync 冲突：先 pull 再 push，不能 ff 则报警"请手动处理"
- auto-sync 后台仍用 setsid 完全脱离 PTY，不再污染 Claude Code 终端
- GitHub push 失败后 index.lock 级联失败问题已修复
- 用户习惯确认：在 `~/git/` 下启动 Claude（总目录），不频繁切换子仓库

### 2026-04-15
- 飞书初始化拆分: feishuinit.sh（lark-cli，所有环境） + bridgeinit.sh（ccbot Bridge，仅一台机器）
- API 变量统一: 全部改用 `ANTHROPIC_AUTH_TOKEN`，移除残留的 `ANTHROPIC_API_KEY`
- `ubuntuinit.sh` 添加 `unset ANTHROPIC_API_KEY` 防新环境系统级冲突
- auto-sync 防抖修复: 改为 120 秒，修正连续变化合并逻辑
- ccbot 自启动三重保障: .bashrc/pm2 resurrect + monitor-sync/pm2 resurrect + init-enable-autostart/pm2 save
- .bashrc 删除 `npm bin -g`（npm 10.x 已移除）
- claudeinit.sh 顶部设置干净 PATH 避免 WSL 继承污染
- ubuntuinit.sh Claude 安装优先原生脚本，检测 npm 版本并切换
- auto-sync 防抖改为 60 秒
- GitHub 连接不稳定时多试几次

### 2026-04-14
- 飞书集成完成: lark-cli OAuth + ccbot WebSocket + feishu-mcp

### 2026-04-13
- 配置文件体系修正: settings.json ↔ .config.json 职责明确
- 暗号（hookstatus/deepresearch/ccusage）已迁移到 CLAUDE.md 全局
