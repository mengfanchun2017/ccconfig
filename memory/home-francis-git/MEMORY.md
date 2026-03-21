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

### Multi-Device Memory (多终端记忆)
- **设备识别**: 使用 `hostname` 命令获取当前主机名
- **记忆结构**: 会话记录时标记设备，如 `### 2026-03-19 [Francis_MiPro]`
- **同步时机**: 每次 `gitarc` 时自动更新本终端的会话记录
- **会话记录格式**: `### 2026-03-19 [设备主机名]`
- **Memory 目录命名规则**:
  - Linux/WSL: `/home/francis/git` → `home-francis-git`（仓库中）
  - Windows: `C:\git` → `C--git`（仓库中）
  - 脚本使用 `get_memory_dir()` 自动转换，不要手动创建目录

---

## 设备列表

| 主机名 | 操作系统 | 备注 |
|--------|---------|------|
| Francis_MiPro | Windows 11 家庭中文版 | 主工作电脑 |
| (待添加) | | |

> 注意：新增设备后在此表添加记录

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
- **当前设备**: Francis_MiPro
- **设备识别方式**: 使用 `hostname` 命令获取主机名

---

## 设备识别与WSL操作

### 如何识别当前设备
- 运行 `hostname` 命令获取 Windows 主机名
- 对照设备列表确定当前是哪台电脑

### WSL 命令执行注意
- **Git Bash 下直接用 `wsl -e` 会失败**，因为 Git Bash 会错误转换路径
- **正确方式**: 使用 `powershell.exe -Command "wsl -e ..."`
- 示例: `powershell.exe -Command "wsl -e /home/franc/.npm-global/bin/openclaw --version"`
- **如果需要加载 .bashrc 中的环境变量**（如 PATH），使用交互式 shell: `powershell.exe -Command "wsl -d Ubuntu-24.04 -e bash -ic 'openclaw --version'"`

---

## Key Learnings (关键知识点)

### 2026-03-07 [Francis_MiPro] - Windows 11
- **Claude Code Memory System**:
  - Auto Memory: Built-in feature, uses `~/.claude/projects/{project}/memory/` directory
  - MEMORY.md: Auto-loaded into every conversation, needs manual updating
  - Memory MCP: Just a recommendation in docs, not an actual plugin
  - claude-md-management: Official plugin for managing CLAUDE.md files

### 2026-03-07 [Francis_MiPro] - Windows 11 - MCP 服务器配置
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

### 2026-03-15 [Francis_MiPro] - Windows 11 - Claude Code 升级方法
- **升级步骤**:
  1. 关闭所有 Claude Code 窗口和进程 (taskkill /F /IM claude.exe)
  2. 在 PowerShell 中运行: `winget upgrade Anthropic.ClaudeCode`
  3. 重启 Claude Code
- **注意**: Claude Code 在中国无法正常使用 API，需要代理或使用其他方式
- **配置文件位置**: `C:\Users\franc\.claude\` - 升级不会丢失配置
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

### 2026-03-09 [Francis_MiPro] - Windows 11 - Supabase MCP 配置方式
- **Supabase MCP 三种认证方式**:
  1. **OAuth 动态注册** (当前在用): 浏览器授权，无需配置 key，适合本地开发
  2. **Personal Access Token (PAT)**: 在 Supabase 账户生成，配置在 headers 中，适合多设备同步
  3. **手动 OAuth App**: 在组织设置中创建，适合需要固定 client_id/secret 的场景
- **多设备开发建议**: 使用 PAT 方式更方便，配置文件可直接通过 claude-config 仓库同步

### 2026-03-10 [Francis_MiPro] - Windows 11 - Git 代理与多设备同步配置
- **Git 代理配置**:
  - 使用 Clash Verge，代理端口: **7897**
  - 配置命令: `git config --global http.proxy http://127.0.0.1:7897`
  - 配置命令: `git config --global https.proxy http://127.0.0.1:7897`
  - 三台电脑都使用相同的配置
- **自动化脚本**:
  - **重要**: 脚本从**主工作目录**运行，不是从 claude-config 仓库内运行
  - 运行方式: `cd /home/francis/git && bash claude-config/scripts/bash/start.sh`
  - 脚本会自动检测当前目录作为项目目录
- **日常工作流**:
  1. 到公司/家: `bash claude-config/scripts/bash/start.sh` 或 `gitinit`
  2. 正常工作（在 Claude Code 中）
  3. 结束工作: `bash claude-config/scripts/bash/end.sh` 或 `gitarc`
- **Git 远程仓库**: https://github.com/<your-github-username>/claude-config
- **对话关键词**:
  - `gitinit`: 开始工作 - 从 GitHub 拉取最新配置并同步到本地
  - `gitarc`: 结束工作 - 收集本地配置并推送到 GitHub

---

## OpenClaw 设备列表

| 主机名 | 地址 | Token | 状态 | Dashboard |
|--------|------|-------|------|------------|
| Francis_MiPro | ws://127.0.0.1:18789 | franc123 | ✅ 运行中 | http://127.0.0.1:18789/#token=franc123 |

---

### 2026-03-15 [Francis_MiPro] - Windows 11 - OpenClaw 安装
- **安装方式**: WSL Ubuntu 中 npm 全局安装
- **安装路径**: /home/franc/.npm-global/bin/openclaw
- **Gateway 端口**: 18789
- **Token**: franc123
- **Web UI**: http://127.0.0.1:18789/#token=franc123
- **PATH 配置**: 在 WSL 的 ~/.bashrc 中添加 `export PATH="$PATH:/home/franc/.npm-global/bin"`
- **启动命令**: `powershell.exe -Command "wsl -d Ubuntu-24.04 -e bash -ic 'openclaw gateway'"`
- **状态命令**: `wsl openclaw status`

---

## Session Logs (会话记录)

### 2026-03-20 [Francis_MiPro] - Windows 11 - claude-config 重构

**重大架构变更：bash/pwsh 脚本分离 + 符号链接双向同步**

**问题**：
- 原来的 `src/lib-common.sh` 被 bash 脚本引用但包含 Windows 检测代码（无意义）
- `start.sh` 和 `end.sh` 依赖 lib-common，但这些函数对 bash 无用
- bash 和 pwsh 脚本功能对称但共享了不该共享的代码

**解决方案**：
1. **删除 lib-common.sh** - bash 和 PowerShell 无法共享代码，各自独立实现
2. **符号链接替代复制** - 所有配置文件通过符号链接同步，双向实时
3. **新目录结构**：
   ```
   scripts/
   ├── bash/           # Linux/WSL 独立实现
   ├── pwsh/           # Windows PowerShell 独立实现（与 bash 对称）
   └── shared/         # 仅放真正的跨平台脚本（如 sync-settings.js）
   ```

**同步机制**：
- `settings.json`: 仓库 `config/settings.json` ↔ 本地 `~/.claude/settings.json`
- `CLAUDE.md`: 仓库 `config/CLAUDE.md` ↔ 本地 `~/CLAUDE.md`
- `MEMORY.md`: 仓库 `memory/home-francis-git/MEMORY.md` ↔ 本地 `~/.claude/projects/home-francis-git/memory/MEMORY.md`

**符号链接 = 两个路径指向同一文件，修改任一另一处同步变化**

**测试结果**：
- ✅ start.sh 正常工作
- ✅ 符号链接正确创建
- ✅ README.md 已更新架构说明
- ✅ start.ps1/end.ps1 已更新符号链接检查
- ✅ initgit.sh 添加 Git 身份检查

**关键词已添加到 README**：
- `gitinit` - 开始工作
- `gitarc` - 结束工作

**Windows 待测**：
- start.ps1 / end.ps1 的符号链接检查

### 2026-03-21 [Francis_MiPro] - Windows 11 - initgit.sh 添加符号链接检查
- `initgit.sh` 完成后添加符号链接状态检查
- 检查 settings.json, CLAUDE.md, MEMORY.md 是否已链接
- 输出清晰的下一步操作指引
- 符号链接检查逻辑：✅正常 / ❌断开 / ⚠️文件 / ⭕未配置

### 2026-03-20 [Francis_MiPro] - Windows 11
- 测试 memory 同步功能
- 配置了 GitMCP（GitHub 仓库读取）
- 更新 mcpcheck 脚本（新增单独安装/添加选项）
- 删除了 mcpupdate（功能已被 mcpcheck 包含）
- 安装飞书 MCP (lark-mcp) - 待解决: 应用需要添加到知识库成员

### 2026-03-20 [修复] - Memory 同步路径问题
- **问题**: `start.sh` 和 `end.sh` 中的 memory 路径计算错误
  - 错误: `CLAUDE_PROJECT_PATH="$HOME/$CURRENT_PROJECT"` (得到 `~/.claude/projects/git/memory`)
  - 正确: `CLAUDE_PROJECT_PATH="$(pwd)"` 然后传给 `get_memory_dir()` (得到 `~/.claude/projects/home-francis-git/memory`)
- **修复内容**:
  1. 重命名 `memory/git/` → `memory/home-francis-git/`
  2. 修复 `start.sh`: 使用完整路径 `$(pwd)` 和 `get_memory_dir()` 正确计算 memory 目录
  3. 修复 `end.sh`: 同上
- **memory 目录命名规范** (由 `get_memory_dir()` 决定):
  - Linux/WSL: `/home/francis/git` → `home-francis-git`
  - Windows: `C:\git` → `C--git`
  - 所以跨设备同步时注意目录名不同

### 2026-03-19 [Francis_MiPro] - Windows 11
- 删除了 claude-config/memory 目录（重复记忆）
- 更新记忆结构：添加设备列表，记录主机名和操作系统
- 会话记录格式改为：`### 日期 [主机名] - 操作系统`

### 2026-03-07 [Francis_MiPro] - Windows 11
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

### 2026-03-09 [Francis_MiPro] - Windows 11
- **检查 Supabase MCP 配置**:
  - 当前使用 OAuth 动态注册方式，项目 ref: <your-supabase-project-id>
  - 测试连接成功，可访问 test_data 和 test_logs 表
  - 研究了 Supabase MCP 三种认证方式的对比
- **用户需求确认**: 讨论多台电脑开发时的配置方式，推荐使用 PAT 方式
- **记忆同步要求**: 用户明确要求每次工作收尾时必须同步记忆并更新到 claude-config 仓库

### 2026-03-10 [Francis_MiPro] - Windows 11
- **完善多设备同步方案**:
  - 创建自动化脚本: `start-work.bat` 和 `end-work.bat`
  - 更新 README.md，添加快速使用指南
  - 配置 Git 走 Clash 代理 (端口 7897)
  - 所有三台电脑都使用相同配置: Clash Verge + 端口 7897
  - 成功推送配置到 GitHub
- **白名单更新**:
  - 添加 `git push`、`git push --set-upstream`、`git config --global` 到 CLAUDE.md

### 2026-03-11 [Francis_MiPro] - Windows 11
- **修复 tavily MCP 工具权限问题**:
  - 问题根源: 项目级配置 `C:\git\.claude\settings.local.json` 覆盖了全局配置，只允许 3 个特定的 tavily 工具
  - 解决方案: 删除项目级配置文件，在全局配置中添加 `"mcp__tavily__*"` 通配符
  - 测试结果: `mcp__tavily__tavily_search`、`mcp__tavily__tavily_extract`、`mcp__tavily__tavily_research` 都可以直接调用，不需要批准
- **关键知识点**: 项目级配置优先级高于全局配置，之前删除项目级配置后又被重新创建了

### 2026-03-12 [Francis_MiPro] - Windows 11 - Get笔记
- **配置文件**: ~/.openclaw/openclaw.json (apiKey, clientId)
- **测试成功**: 创建了 t1, t2, t3 三个测试笔记，都带 claude 标签

### 2026-03-12 [Francis_MiPro] - Windows 11 - Secrets 管理工具分析
| 服务 | 免费计划 | 国内访问 | 推荐场景 |
|------|---------|----------|----------|
| Doppler | ✅ Community 免费（无限用户） | ✅ 可访问 | 企业级 |
| Infisical | ✅ Free (5身份) + 开源自托管 | ⚠️ 被墙 | 团队/开源 |
| Bitwarden | ✅ 免费版（无限密码） | ✅ 可访问 | 个人/多设备 |
| 1Password | ❌ 无免费 | ⚠️ 被墙 | 不推荐 |
- **结论**: 当前配置文件方案已够用，暂不需要迁移
- **敏感信息存放规则**:
  - Key 放配置文件，MEMORY.md 只记录路径索引
  - 配置文件同步到 claude-config 私有仓库（安全）
  - 当前: ~/.openclaw/openclaw.json → 同步到 claude-config

### 2026-03-12 [Francis_MiPro] - Windows 11
- **安装 Get笔记 Claude Skill**:
  - Skill 来源: https://clawhub.ai/iswalle/getnote
  - 安装位置: ~/.claude/skills/getnote/
  - 功能: 记录笔记、查找笔记、知识库管理、链接/图片笔记等
  - API 测试成功: 读取笔记列表 ✅, 创建笔记 ✅
  - 环境变量: GETNOTE_API_KEY, GETNOTE_CLIENT_ID (已通过 setx 永久设置)
  - 白名单更新: 添加 `setx` 命令到 CLAUDE.md
  - 同步到 claude-config 仓库并推送成功

### 2026-03-11 [Francis_MiPro] - Windows 11 - Native 安装与配置位置
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

### 2026-03-12 [Francis_MiPro] - Windows 11 - 删除 GitHub MCP
- **原因**: 分析后发现 GitHub MCP 是 GitHub Copilot CLI 专用的，对 Claude Code 没用
- **删除内容**: 从全局 mcpServers 中删除 github 条目
- **影响**: 之后 git 操作只能通过 git 命令，不再能用 MCP 工具操作 GitHub
- **单位电脑需操作**: 同样从 ~/.claude.json 中删除 github 条目

---

