# Project Memory

This file persists across Claude Code conversations. Keep it concise (&lt;200 lines).

## Quick Links
- Project root: C:\git
- CLAUDE.md: C:\git\CLAUDE.md

---

## Recording Flow (记录流程)

### When to Record (什么时候记录)
- At the end of each session (会话结束时)
- When important decisions are made (做出重要决定时)
- When learning something new about the codebase (了解到代码库新信息时)
- When user preferences are clarified (明确用户偏好时)

### How to Record (如何记录)
Use the following sections in this file:

| Section | Purpose |
|---------|---------|
| User Preferences | 工作方式、工具偏好等 |
| Project Context | 项目架构、关键决策 |
| Key Learnings | 技术知识点、坑点 |
| Session Logs | 按时间记录的会话摘要 |

---

## User Preferences (用户偏好)

- Memory mode: Manual recording at checkpoints / end of session
- Preferred language: Chinese (中文)
- **Session Sync Requirement (会话同步要求)
  - 每次工作收尾时必须同步记忆
  - 更新 MEMORY.md 后要同步到 claude-config 仓库
- Tools:
- **Bash Command Approval Rule**:
  - 把运行过、需要我批准的命令，除非是高危的，都加到 CLAUDE.md 配置文件里
  - 避免下次再批准太麻烦
  - 每次更新记忆时记录哪些命令已加入白名单

## Auto Memory (自动记忆)

- **Question**: 记忆可以自动触发么，比如每4小时，或者每天第一次启动的时候把昨天的写上？
- **Answer**: Claude Code 的 Auto Memory 目前需要手动更新 MEMORY.md 文件
  - 没有内置的定时自动记录功能
  - 可以手动在会话结束时或关键节点调用 /memory 更新

---

## Project Context (项目上下文)

- Current working directory: C:\git

---

## Key Learnings (关键知识点)

### 2026-03-07
- **Claude Code Memory System**:
  - Auto Memory: Built-in feature, uses `~/.claude/projects/{project}/memory/` directory
  - MEMORY.md: Auto-loaded into every conversation, needs manual updating
  - Memory MCP: Just a recommendation in docs, not an actual plugin
  - claude-md-management: Official plugin for managing CLAUDE.md files

### 2026-03-07 - MCP 服务器配置
- **Playwright MCP**:
  - 正确包名: `@playwright/mcp` (npm 上存在)
  - 全局安装: `npm install -g @playwright/mcp`
  - 命令: `playwright-mcp`

- **MarkItDown MCP**:
  - 正确包名: `markitdown-mcp-npx` (不是 `markitdown-mcp`)
  - 全局安装: `npm install -g markitdown-mcp-npx`
  - 命令: `markitdown-mcp-npx`

- **Claude Code MCP 配置方式**:
  - 项目级配置: `{project}/.mcp.json`
  - 用户级配置: `~/.claude.json`
  - 使用 `claude mcp` 命令管理
  - `claude mcp reset-project-choices` 重置项目选择

- **用户偏好决策 (2026-03-07)**:
  - 所有 MCP 服务器都配置在全局 `~/.claude.json`
  - 所有插件/技能也配置在全局 `~/.claude.json`
  - 不使用项目级 `.mcp.json` 和项目级 `settings.json`/`settings.local.json`
  - 后续新增 MCP、插件默认都加到全局配置
  - 除非特别要求，否则所有配置都放在全局

### 2026-03-07 - GitHub Token 权限说明
- **Fine-grained tokens vs Classic tokens**:
  - Fine-grained: 权限精确、可过期、更安全（推荐）
  - Classic: 配置简单、权限较粗
- **必需权限**:
  - `Contents` (Read and write): 代码读写、拉取推送
  - `Administration` (Read and write): 创建/管理仓库
- **可选权限**:
  - `Pages`: 部署 GitHub Pages 网站
  - `Actions`: CI/CD 自动构建
  - `Deployments`: 部署记录追踪
  - `Workflows`: 修改 GitHub Actions 工作流
  - `Webhooks`: 事件通知回调
  - `Variables`: 仓库环境变量（非敏感）
  - `Pull requests`: 代码审核
  - `Issues`: 任务管理

### 2026-03-09 - Supabase MCP 配置方式
- **Supabase MCP 三种认证方式**:
  1. **OAuth 动态注册** (当前在用): 浏览器授权，无需配置 key，适合本地开发
  2. **Personal Access Token (PAT)**: 在 Supabase 账户生成，配置在 headers 中，适合多设备同步
  3. **手动 OAuth App**: 在组织设置中创建，适合需要固定 client_id/secret 的场景
- **多设备开发建议**: 使用 PAT 方式更方便，配置文件可直接通过 claude-config 仓库同步

### 2026-03-10 - Git 代理与多设备同步配置
- **Git 代理配置**:
  - 使用 Clash Verge，代理端口: **7897**
  - 配置命令: `git config --global http.proxy http://127.0.0.1:7897`
  - 配置命令: `git config --global https.proxy http://127.0.0.1:7897`
  - 三台电脑都使用相同的配置
- **自动化脚本**:
  - `scripts/start-work.bat`: 开始工作前运行，拉取最新配置并同步到本地
  - `scripts/end-work.bat`: 结束工作后运行，收集本地配置并提交推送
- **日常工作流**:
  1. 到公司/家: 双击 `start-work.bat`
  2. 正常工作
  3. 结束工作: 双击 `end-work.bat`
- **Git 远程仓库**: https://github.com/<your-github-username>/claude-config
- **对话关键词**:
  - `gitinit`: 开始工作 - 从 GitHub 拉取最新配置并同步到本地
  - `gitarc`: 结束工作 - 收集本地配置并推送到 GitHub

---

## Session Logs (会话记录)

### 2026-03-07
- Set up Auto Memory system
- Created MEMORY.md with recording flow
- Confirmed Auto Memory is enabled by default
- Set preferred language to Chinese (中文)
- **Fixed MCP servers configuration**:
  - Identified issue: markitdown-mcp package doesn't exist on npm
  - Found correct packages: @playwright/mcp and markitdown-mcp-npx
  - Installed both packages globally
  - Configured .mcp.json in project root
  - Reset project choices for approval on next restart
- **MCP 配置迁移到全局 (2026-03-07)**:
  - 将 playwright 和 markitdown 从项目级 .mcp.json 迁移到用户级 ~/.claude.json
  - 删除了 C:\git\.mcp.json
  - 确认所有 MCP 服务器现在都在全局配置中
- **更新 CLAUDE.md 白名单 (2026-03-07)**:
  - 新增: wsl, powershell, powershell.exe, pwsh, reg query, winget
  - 新增: claude-code, claude mcp
  - 新增: bun add
  - 补充文本处理命令: wc, sort, uniq, diff, cmp, md5sum, sha256sum
- **插件/技能配置迁移到全局 (2026-03-07)**:
  - 将 enabledPlugins 从项目级移到全局 ~/.claude/settings.json
  - 将项目级权限配置也移到全局
  - 删除了 C:\git\.claude/settings.json 和 settings.local.json
  - 确认所有插件/技能现在都在全局配置中
- **配置同步仓库创建 (2026-03-07)**:
  - 创建 claude-config Git 仓库: C:\git\claude-config
  - 配置 GitHub MCP (使用 Personal Access Token)
  - 创建 GitHub 私有仓库: https://github.com/<your-github-username>/claude-config
  - 首次推送成功！包含 .claude.json、settings.json、CLAUDE.md
- **收尾任务 - 补充白名单 (2026-03-07)**:
  - 对比 settings.json 中所有批准过的命令
  - 补充缺失命令到 CLAUDE.md: claude plugin、claude agents、tavily-mcp
  - 清理项目级残留配置文件
  - 更新 claude-config 仓库并推送

### 2026-03-09
- **检查 Supabase MCP 配置**:
  - 当前使用 OAuth 动态注册方式，项目 ref: <your-supabase-project-id>
  - 测试连接成功，可访问 test_data 和 test_logs 表
  - 研究了 Supabase MCP 三种认证方式的对比
- **用户需求确认**: 讨论多台电脑开发时的配置方式，推荐使用 PAT 方式
- **记忆同步要求**: 用户明确要求每次工作收尾时必须同步记忆并更新到 claude-config 仓库

### 2026-03-10
- **完善多设备同步方案**:
  - 创建自动化脚本: `start-work.bat` 和 `end-work.bat`
  - 更新 README.md，添加快速使用指南
  - 配置 Git 走 Clash 代理 (端口 7897)
  - 所有三台电脑都使用相同配置: Clash Verge + 端口 7897
  - 成功推送配置到 GitHub
- **白名单更新**:
  - 添加 `git push`、`git push --set-upstream`、`git config --global` 到 CLAUDE.md

### 2026-03-11
- **修复 tavily MCP 工具权限问题**:
  - 问题根源: 项目级配置 `C:\git\.claude\settings.local.json` 覆盖了全局配置，只允许 3 个特定的 tavily 工具
  - 解决方案: 删除项目级配置文件，在全局配置中添加 `"mcp__tavily__*"` 通配符
  - 测试结果: `mcp__tavily__tavily_search`、`mcp__tavily__tavily_extract`、`mcp__tavily__tavily_research` 都可以直接调用，不需要批准
- **关键知识点**: 项目级配置优先级高于全局配置，之前删除项目级配置后又被重新创建了

### 2026-03-11 - Native 安装与配置位置
- **Native 安装方式**:
  - 使用 WinGet 安装: `winget install Claude.Code`
  - 安装路径: `C:\Users\franc\AppData\Local\Microsoft\WinGet\Links\claude.exe`
  - 版本: 2.1.70
  - 配置文件位置: `C:\Users\franc\.claude.json` (主配置)
- **清理旧配置文件**:
  - 删除了 `C:\Users\franc\.claude\.claude.json` (旧版残留配置)
  - 现在只有一个主配置文件: `~/.claude.json`
- **项目级 MCP 禁用**:
  - 可以在项目配置的 `disabledMcpServers` 中禁用特定 MCP
  - 当前 C:/git 项目禁用了 tavily (用于测试)
  - 注意: 禁用后 MCP 工具调用需要每次批准

### 2026-03-12 - 删除 GitHub MCP
- **原因**: 分析后发现 GitHub MCP 是 GitHub Copilot CLI 专用的，对 Claude Code 没用
- **删除内容**: 从全局 mcpServers 中删除 github 条目
- **影响**: 之后 git 操作只能通过 git 命令，不再能用 MCP 工具操作 GitHub
- **单位电脑需操作**: 同样从 ~/.claude.json 中删除 github 条目

---

