# Project Memory

This file persists across Claude Code conversations.

## Quick Links
- Project root: /home/francis/git
- CLAUDE.md: /home/francis/git/CLAUDE.md
- ccconfig: /home/francis/git/ccconfig

---

## User Preferences

- Preferred language: Chinese (中文)
- **Session Sync**: 每次收尾时同步记忆到 ccconfig 仓库
- **MCP 操作**: `bash ccconfig/claudeinit.sh`
- **Key/Token 存储**: conf-claude.json（已同步到 ccconfig/link）
- **进入 Claude 行为**: 说"hookstatus"→ 运行 `bash ccconfig/hook-status.sh`
- **搜索策略**: 中文=minimax web_search, 英文=tavily search

---

## Key Learnings（重要，需熟记）

- npm 全局包路径: `~/.local/node-v20.11.0-linux-x64/bin/`，需创建 `~/.local/bin/` 符号链接
- `npm bin -g` 在 npm 10.x 已移除，勿在 .bashrc 中使用
- WebSocket 长连接 = 飞书推送消息给 Claude 的唯一方式
- 飞书文档创建用 `lark-cli + --as user`，feishu-mcp 不渲染 markdown
- PM2 进程在 WSL 重启后不会自动复活 → 需 `pm2 resurrect` 自动恢复
- WSL 开新终端时 PATH 继承父进程，开新 session 才能验证 PATH 修复
- Claude Code v2.1+ 推荐原生安装（`curl -fsSL https://claude.ai/install.sh | bash`）
- auto-sync 防抖时间 60 秒，避免高频变化时反复提交
- Claude Code 从 npm 切换到原生: `claude install --force`

---

## 飞书集成配置（详细配置见 ccconfig/conf-feishu.json）

- 飞书 App ID: `<your-feishu-app-id>`
- 飞书文件夹 Token: ccconfig/conf-feishu.json
- **分工**: feishu-mcp 发消息/读文档 | lark-cli 创建文档 | ccbot 接收飞书消息
- **OAuth 管理**: https://account.feishu.cn/ → 账号与安全 → 应用授权管理

---

## ccconfig 仓库结构

```
ccconfig/
├── ubuntuinit.sh     # Ubuntu 合一初始化
├── claudeinit.sh     # MCP 安装配置
├── init-auto-sync.sh  # auto-sync（防抖60秒）
├── init-enable-autostart.sh  # 自启动（pm2 save）
├── hook-status.sh     # 状态检查
├── conf-ubuntu.json  # ubuntuinit 配置
├── conf-claude.json  # MCP + Key/Token 配置（同步源）
└── link/             # 符号链接 → ~/.claude/
```

**新环境初始化**:
```bash
bash ccconfig/ubuntuinit.sh    # 终端执行
bash ccconfig/claudeinit.sh     # Claude 中执行
```

---

## Session Logs（精简）

### 2026-04-15
- ccbot 自启动三重保障: .bashrc/pm2 resurrect + init-auto-sync/pm2 resurrect + init-enable-autostart/pm2 save
- .bashrc 删除 `npm bin -g`（npm 10.x 已移除）
- claudeinit.sh 顶部设置干净 PATH 避免 WSL 继承污染
- ubuntuinit.sh Claude 安装优先原生脚本，检测 npm 版本并切换
- auto-sync 防抖改为 60 秒
- GitHub 连接不稳定时多试几次

### 2026-04-14
- 飞书集成完成: lark-cli OAuth + ccbot WebSocket + feishu-mcp

### 2026-04-13
- 配置文件体系修正: settings.json ↔ .config.json 职责明确

---

## 暗号

### hookstatus → 状态检查
```bash
bash /home/francis/git/ccconfig/hook-status.sh
```

### ccusage → Claude Code 用量统计
```bash
npx ccusage@latest monthly
```
