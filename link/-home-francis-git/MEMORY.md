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

## 多项目架构（~/git/ 总目录）

```
~/.claude/                          ← 全局配置（不被 Git 追踪）
├── skills/ → ccconfig/.agents/skills/           ← 符号链接，全局 skills
├── agents/ → ccconfig/link/.claude/agents/     ← 符号链接，指令分流 agent
└── projects/-home-francis-git/memory/MEMORY.md → ccconfig/link/-home-francis-git/MEMORY.md

~/git/ccconfig/                     ← 配置仓库，monitor-sync 在跑
├── llminit.sh                      ← LLM 切换脚本（conf-llm.json）
├── ubuntuinit.sh                   ← Ubuntu 合一初始化
├── feishuinit.sh                   ← 飞书 lark-cli 配置
├── bridgeinit.sh                   ← ccbot Bridge 专用（仅 Bridge 环境）
├── claudeinit.sh                  ← MCP 安装
├── skillinit.sh                   ← Skills 安装
├── monitor-sync.sh                ← 文件监控 sync
├── conf-llm.json                  ← LLM 配置（多后端）
├── conf-claude.json               ← MCP + Key/Token
├── conf-feishu.json               ← 飞书配置
└── link/ → GitHub (<your-github-username>/ccconfig)
```

**初始化流程**:
1. `bash ccconfig/ubuntuinit.sh`（含 LLM 配置）
2. `bash ccconfig/feishuinit.sh`
3. `bash ccconfig/claudeinit.sh`（需 Claude Code 已安装）
4. 仅 Bridge 环境: `bash ccconfig/bridgeinit.sh`

---

## Session Logs

### 2026-04-26
- 新增 `llminit.sh` + `conf-llm.json`：LLM 配置从 ubuntuinit.sh 拆分，支持多后端切换
- 增加 DeepSeek 配置: base_url=https://api.deepseek.com/anthropic, model=deepseek-v4-pro
- ubuntuinit.sh 的 LLM 配置改为调用 llminit.sh
- monitor-sync 日志中 `??:??:??` 时间戳问题：inotifywait 输出行被截断导致 date 读取失败（未影响实际 sync）

### 2026-04-17
- monitor-sync.sh 替换 init-auto-sync.sh（统一管理 start/stop/status/log/monitor）
- pull --ff 解决多机 sync 冲突