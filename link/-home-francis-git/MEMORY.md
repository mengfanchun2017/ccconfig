# Project Memory

This file persists across Claude Code conversations.

## Quick Links
- Project root: /home/francis/git
- CLAUDE.md: /home/francis/git/CLAUDE.md
- ccconfig: /home/francis/git/ccconfig

---

## 飞书文档创建（重要）

**关键目录**: CC编程大虾 `CyZ6wmItQiso3AkbjZBcP3vtnAb` | worklog `J2SmwK3yJifPD8kg8ZwcAUwOnqg` (base_token: `Tq1ebqPA7aT0cSsSA8GcADZQnqd`)

- 新建文档: `cat << 'EOF' | lark-cli docs +create --wiki-node CyZ6wmItQiso3AkbjZBcP3vtnAb --as user --markdown -`
- 常见错误: ❌ `--folder-token` | ❌ `--markdown "内容"` | ✅ `--markdown -` + heredoc

**worklog 标题规则**: 工作=中文开头无空格(如 `算力机采购评分表初版完成`) | 成长=小写英文+空格+内容(如 `coze 工作流和LLM对比`)

---

## LLM 切换（重要）

**配置**: `ccconfig/conf-llm.json`（多后端支持）
**切换脚本**: `bash ccconfig/llminit.sh`

```bash
bash ccconfig/llminit.sh          # 交互式选择
bash ccconfig/llminit.sh list     # 列出所有 LLM
bash ccconfig/llminit.sh deepseek # 直接切换到 deepseek
bash ccconfig/llminit.sh minimax  # 切换回 minimax
```

**当前可用**: minimax (默认) | deepseek (deepseek-v4-pro)

---

## User Preferences

- Preferred language: Chinese (中文)
- **搜索策略**: 中文→minimax web_search | 英文→tavily | 深入调研→tavily research+extract
- **图片解析**: minimax-coding-plan-mcp 的 understand_image，Windows 路径 `/mnt/c/Users/...`
- **Agent**: `~/.claude/agents/` → 符号链接 `ccconfig/link/.claude/agents/`，指令分流 @dev/@res/@sum
- **暗号**: `welldone`→@sum 写入 worklog | `hookstatus`→运行 hook-status.sh
- **Session Sync**: 每次收尾同步记忆到 ccconfig 仓库
- **MCP 操作**: `bash ccconfig/claudeinit.sh` | **Skills**: `bash ccconfig/skillinit.sh`

---

## Key Learnings

- npm 全局路径: `~/.local/node-v20.11.0-linux-x64/bin/`，`npm bin -g` 在 npm 10.x 已移除
- Claude Code v2.1+ 推荐原生: `curl -fsSL https://claude.ai/install.sh | bash`，切换 `claude install --force`
- **API 变量**: 统一用 `ANTHROPIC_AUTH_TOKEN`
- **Claude 项目身份**: 由启动时的绝对路径决定（找最近的 .git 往上）
- monitor-sync.sh: auto-sync 监控脚本（start/stop/status/log/monitor/tail），防抖 120s
- pull --ff: sync 时先 commit → pull --ff → push，解决多机同时 push 冲突
- 飞书文档操作用 `lark-cli --as user`，feishu-mcp 无法读取 wiki（bot 身份限制）

---

## cc-connect 多用户飞书桥接

**替代 ccbot**: cc-connect (Go 二进制, v1.3.2) 原生支持多项目/多飞书 App/多用户隔离
**已删除**: bridgeinit.sh、ccbot.service（ccbot 彻底移除）

### 推荐架构（共享 ~/.claude/）
```
飞书用户A → 飞书App A → cc-connect Project "userA"
    ├── agent: claudecode
    ├── workDir: /home/francis/git → MEMORY.md 自动按目录隔离
    ├── ~/.claude/ 共享（MCP、API Key 共用）
    └── sessions: 按 chatId 独立

飞书用户B → 飞书App B → cc-connect Project "userB"
    ├── workDir: /home/francis/git/friend1 → 独立 MEMORY.md
    └── ~/.claude/ 共享（同上）
```

如需不同 Claude 账号：每个用户设独立 `claudeConfigDir`，settings.json 用符号链接共享 MCP。

### 配置
- **配置文件**: `ccconfig/conf-feishu.json` → `cconnect.users[]` 数组
- **生成 TOML**: 运行 `bash ccconfig/cconnectinit.sh` 自动从 JSON 生成 cc-connect config
- **添加用户**: 编辑 conf-feishu.json → 飞书开放平台创建新应用 → 运行 cconnectinit.sh
- **init.sh**: 5步全自动（ubuntuinit → feishuinit → claudeinit → skillinit → cconnectinit）

### 常用命令
- 统一入口: `bash ccconfig/init.sh [all|status|menu]`
- Bridge 配置: `bash ccconfig/cconnectinit.sh`
- 状态: `systemctl --user status cc-connect`
- 日志: `journalctl --user -u cc-connect -f`

---

## 多项目架构（~/git/ 总目录）

```
~/.claude/                          ← 全局配置（不被 Git 追踪）
├── skills/ → ccconfig/.agents/skills/           ← 符号链接，全局 skills
├── agents/ → ccconfig/link/.claude/agents/     ← 符号链接，指令分流 agent
└── projects/-home-francis-git/memory/MEMORY.md → ccconfig/link/-home-francis-git/MEMORY.md

~/git/ccconfig/                     ← 配置仓库，monitor-sync 在跑
├── init.sh                         ← 统一初始化入口（5步：ubuntu→feishu→claude→skill→cconnect）
├── llminit.sh                      ← LLM 切换脚本（conf-llm.json）
├── ubuntuinit.sh                   ← Ubuntu 合一初始化（含 Git/Claude/Node/LLM/auto-sync）
├── feishuinit.sh                   ← 飞书 lark-cli 配置
├── claudeinit.sh                  ← MCP 安装
├── skillinit.sh                   ← Skills 安装
├── cconnectinit.sh                 ← cc-connect Bridge（多用户飞书 WebSocket）
├── monitor-sync.sh                ← 文件监控 sync
├── conf-llm.json                  ← LLM 配置（多后端）
├── conf-claude.json               ← MCP + Key/Token
├── conf-feishu.json               ← 飞书配置（lark-cli + cc-connect 多用户）
└── link/ → GitHub (<your-github-username>/ccconfig)
```

**初始化流程**:
1. 一键: `bash ccconfig/init.sh all`（5步全自动）
2. 菜单: `bash ccconfig/init.sh`（交互式选择）
3. 分步: ubuntuinit → feishuinit → claudeinit → skillinit → cconnectinit

---

## Session Logs

### 2026-04-26
- **ccbot → cc-connect 迁移**：调研后确定用 cc-connect 替代 ccbot 实现多用户飞书桥接
- **新增 cconnectinit.sh**：自动从 conf-feishu.json 读取多用户配置，下载 cc-connect 二进制，生成 config.toml，配置 systemd 服务
- **新增 init.sh**：统一初始化入口，支持一键/交互式/分步执行
- **conf-feishu.json 重构**：拆分为 `lark`（lark-cli 配置）和 `cconnect`（多用户 Bridge 配置），每个用户独立飞书 App + CLAUDE_CONFIG_DIR
- **bridgeinit.sh**：改为兼容包装器，自动跳转 cconnectinit.sh
- **hook-status.sh**：Bridge 检查从 ccbot/pm2 改为 cc-connect/systemd
- **cc-connect.service**：systemd 服务文件（替换旧的 ccbot.service）
- **README.md、MEMORY.md**：更新架构文档和多用户说明
- 新增 `llminit.sh` + `conf-llm.json`：LLM 配置从 ubuntuinit.sh 拆分，支持多后端切换
- 增加 DeepSeek 配置: base_url=https://api.deepseek.com/anthropic, model=deepseek-v4-pro
- ubuntuinit.sh 的 LLM 配置改为调用 llminit.sh
- monitor-sync 日志中 `??:??:??` 时间戳问题：inotifywait 输出行被截断导致 date 读取失败（未影响实际 sync）

### 2026-04-17
- monitor-sync.sh 替换 init-auto-sync.sh（统一管理 start/stop/status/log/monitor）
- pull --ff 解决多机 sync 冲突