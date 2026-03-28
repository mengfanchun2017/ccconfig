# Claude Code 配置同步仓库

用于在多台设备间同步 Claude Code 的配置。

---

## 目录

1. [架构说明](#架构说明)
2. [快速开始（日常使用）](#快速开始日常使用)
3. [全新电脑部署](#全新电脑部署)
4. [初始化脚本说明](#初始化脚本说明)
5. [文件结构说明](#文件结构说明)
6. [核心使用规范](#核心使用规范)
7. [配置文件说明](#配置文件说明)
8. [settings.json 智能同步](#settingsjson-智能同步)
9. [Git 代理配置](#git-代理配置)
10. [故障排查](#故障排查)
11. [部署检查清单](#部署检查清单)
12. [安全提示](#安全提示)

---

## 架构说明

### 核心机制：符号链接双向同步

本仓库通过**符号链接（symlink）**实现本地配置与仓库的实时双向同步。

```
符号链接原理：
   仓库文件 ─────────────────────────┐
       │                             │
       ↓                             │
   符号链接 (快捷方式)                 │
       │                             │
       ↓                             ↓
   本地路径 ←────── 修改任意一个 ──────→ 另一处同步变化
```

### 同步结构

| 文件 | 仓库位置 | 本地位置 (Linux) | 本地位置 (Windows) |
|------|----------|------------------|-------------------|
| settings.json | `config/settings.json` | `~/.claude/settings.json` | `%USERPROFILE%\.claude\settings.json` |
| CLAUDE.md | `config/CLAUDE.md` | `~/CLAUDE.md` | `%USERPROFILE%\CLAUDE.md` |
| MEMORY.md | `memory/{项目名}/MEMORY.md` | `~/.claude/projects/{项目名}/memory/MEMORY.md` | `%USERPROFILE%\.claude\projects\{项目名}\memory\MEMORY.md` |

### 脚本架构

```
claude-config/
├── init01git              # Git + GitHub CLI 安装 + 仓库克隆/更新
├── init02claude           # Claude Code 安装 + API 配置
├── init03env              # Node.js + uv + Playwright + 字体 + 符号链接
│
scripts/                   # 所有脚本（Linux/WSL）
├── start.sh               # 每日启动：git pull + 符号链接检查 + auto-sync
├── end.sh                 # 每日结束：git add/commit/push
├── auto-sync.sh           # 自动同步：监控文件变化，自动 commit + push
├── enable-autostart.sh    # auto-sync 自启动配置（systemd 用户服务）
├── init01git.sh           # Git + GitHub CLI 安装 + 仓库克隆/更新
├── init02claude.sh        # Claude Code 安装 + API 配置
├── init03env.sh           # Node.js + uv + Playwright + 字体 + 符号链接 + auto-sync
├── initMCP.sh             # MCP 服务器初始化/安装/配置（统一管理）
├── initoptplaywright.sh   # 可选: Playwright 浏览器后端配置
└── sync-settings.js       # settings.json 智能合并
```

**设计原则**：
- 简化为单层目录结构，所有脚本平铺
- 入口脚本（init01git, init02claude, init03env）在仓库根目录，调用 scripts/ 下的实现

### auto-sync 自动同步机制

`auto-sync.sh` 监控仓库文件变化，自动提交并推送到 GitHub。

```
文件变化 → inotifywait 监控 → 3秒防抖 → git add/commit/push
```

**特性**：
- 使用 `inotifywait` 监控所有文件变化（排除 .git/、node_modules/、*.log、.auto-sync.*）
- 3秒防抖：避免频繁提交
- 后台运行，不阻塞终端

**自启动配置**（Linux/WSL）：
```bash
# 启用自启动（systemd 用户服务）
bash claude-config/scripts/enable-autostart.sh enable

# 禁用自启动
bash claude-config/scripts/enable-autostart.sh disable

# 查看状态
bash claude-config/scripts/enable-autostart.sh status
```

**auto-sync 与 start/end 脚本的关系**：
| 脚本 | 触发方式 | 用途 |
|------|---------|------|
| start.sh | 每次工作开始 | 拉取更新 + 同步符号链接 + 启动 auto-sync |
| end.sh | 每次工作结束 | 手动同步（auto-sync 已处理大部分情况） |
| auto-sync.sh | 后台持续运行 | 任何文件变化自动推送 |
| init03env.sh | 新环境/更新环境 | 安装依赖 + **可选配置自启动** |

### Memory 同步说明

Claude Code 会为每个项目维护记忆文件 `MEMORY.md`。本仓库的 `memory/` 目录按项目组织：

```
memory/
└── home-francis-git/           # 项目名转换：/home/francis/git → -home-francis-git
    └── MEMORY.md               # 该项目的记忆文件
```

当运行 `start.sh` 时，会自动检测当前目录：
- 如果在 `claude-config` 仓库内，自动使用**父项目**（`/home/francis/git`）的 memory
- 如果在其他项目目录，使用该项目本身的 memory

### 优点

1. **修改即时同步** - 无需手动 push/pull 配置文件
2. **仓库统一管理** - 所有变更在仓库中，方便版本控制
3. **多设备共享** - 符号链接在本地，但文件在仓库，任何设备 clone 后链接即可
4. **保持独立** - 脚本独立维护，简洁直接

---

## 快速开始（日常使用）

### 在当前设备开始工作前

**WSL Ubuntu / Linux / Mac:**
```bash
cd ~/git/claude-config
./scripts/start.sh
```

这个脚本会自动：
1. 从 GitHub 拉取最新配置
2. 通过符号链接同步 settings.json 到本地
3. 通过符号链接同步 CLAUDE.md 到本地主目录
4. 通过符号链接同步 MEMORY.md（自动检测项目）

### 在当前设备结束工作后

**WSL Ubuntu / Linux / Mac:**
```bash
cd ~/git/claude-config
./scripts/end.sh
```

这个脚本会自动：
1. 显示 git 状态（符号链接已实时同步，无需额外复制）
2. 提交更改（可自定义提交信息）
3. 推送到 GitHub

> **注意**：`.claude.json` 包含 LLM API 配置，保留在本地不同步。

### 快捷命令（关键词）

在 Claude Code 对话中使用这些关键词快速触发脚本：

| 关键词 | 功能 | 说明 |
|--------|------|------|
| `gitinit` | 开始工作 | 等同于运行 `start.sh`，拉取配置并建立符号链接 |
| `gitarc` | 结束工作 | 等同于运行 `end.sh`，提交并推送更改到 GitHub |

**使用方式**：直接在对话中输入 `gitinit` 或 `gitarc`，Claude Code 会执行相应脚本。

### MCP 服务器管理

```bash
bash claude-config/scripts/initMCP.sh
```

功能：
- 读取 mcplist.json 获取 MCP 元信息
- 读取 mcpidentity.json 获取鉴权信息
- 安装/注册 MCP 服务器
- 配置 API Key/Token
- 支持交互式选择安装

> **提示**：如果用户有 MCP 初始化、安装、更新等要求，运行此脚本。

---

## 多平台支持

### 支持的平台

| 平台 | 脚本 | 说明 |
|------|------|------|
| Windows 11 | `start.ps1` / `end.ps1` | 双击运行 |
| WSL Ubuntu | `start.sh` / `end.sh` | Bash 运行 |
| Linux / Mac | `start.sh` / `end.sh` | Bash 运行 |

### WSL Ubuntu 特别说明

WSL 环境下脚本会自动检测并适配：

- **用户主目录**：优先使用 Windows 主目录 (`/mnt/c/Users/franc`)，保持与 Windows 端配置一致
- **CLAUDE.md**：同步到 Linux 主目录 `~/CLAUDE.md`
- **配置文件**：存储在 Windows 主目录，确保多端共享

#### WSL 下手动运行

```bash
# 进入仓库目录
cd ~/git/claude-config

# 开始工作
./scripts/start.sh

# 结束工作
./scripts/end.sh

# 或添加到 PATH（可选）
# echo 'export PATH="$PATH:~/git/claude-config/scripts"' >> ~/.bashrc
# source ~/.bashrc
```

#### WSL 下 CLAUDE Code 启动

```bash
# 在 WSL 中启动 Claude Code
claude

# 或使用 PowerShell 调用
powershell.exe -Command "claude"
```

---

## 全新电脑部署

### 选择你的平台

- [WSL Ubuntu](#wsl-ubuntu-部署) ⭐ 推荐
- [Linux / Mac](#linux--mac-部署)

> **Windows 11**：PowerShell 脚本尚未实现，可使用 [WSL Ubuntu](#wsl-ubuntu-部署) 方案

---

### WSL Ubuntu 部署

适用于在 Windows Subsystem for Linux (WSL) 中运行 Ubuntu 的用户。

#### 部署流程图

```
┌─────────────────┐
│  1. 环境准备     │ → Ubuntu 24.04 + Git + Node.js
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  2. 安装 Claude  │ → 原生版本（curl 安装）
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  3. 克隆配置仓库 │ → git clone claude-config
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  4. 同步配置     │ → 运行 start.sh
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  5. 安装 MCP    │ → 使用 npm 全局安装
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  6. 验证部署     │ → 检查 Claude + MCP + Skill
└─────────────────┘
```

#### 第一步：环境准备

##### 1.1 启用 WSL 并安装 Ubuntu 24.04

```powershell
# 以管理员身份打开 PowerShell
wsl --install -d Ubuntu-24.04
```

或者手动从 Microsoft Store 安装 Ubuntu 24.04。

##### 1.2 安装 Git

```bash
sudo apt update
sudo apt install -y git
```

##### 1.3 安装 Node.js LTS

```bash
# 安装 Node.js LTS
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# 验证安装
node --version
npm --version
```

##### 1.4 配置 Git 代理（如果需要）

如果使用代理（Clash Verge）：

```bash
git config --global http.proxy http://127.0.0.1:7897
git config --global https.proxy http://127.0.0.1:7897
```

---

#### 第二步：安装 Claude Code

##### 方式一：官方安装脚本（推荐）

```bash
curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/install.sh | sh
```

##### 方式二：直接下载二进制

```bash
# 下载最新版本
curl -LO https://github.com/anthropics/claude-code/releases/latest/download/claude-linux-x64

# 移动到 PATH
chmod +x claude-linux-x64
sudo mv claude-linux-x64 /usr/local/bin/claude
```

##### 验证安装

```bash
claude --version
```

---

#### 第三步：克隆配置仓库

```bash
# 创建项目目录
mkdir -p ~/git
cd ~/git

# 克隆配置仓库
git clone https://github.com/<your-github-username>/claude-config.git

# 进入目录
cd claude-config
```

---

#### 第四步：同步配置

```bash
# 运行同步脚本
./scripts/start.sh
```

**注意**：WSL 环境下：
- `.claude.json` 存储在 Windows 主目录（`/mnt/c/Users/franc/.claude.json`），与 Windows 端共享
- `settings.json` 同步到 Windows 主目录
- `CLAUDE.md` 同步到 Linux 主目录 (`~/CLAUDE.md`)

---

#### 第五步：安装 MCP 服务器

```bash
# Tavily MCP
npm install -g tavily-mcp

# Playwright MCP
npm install -g @playwright/mcp

# MarkItDown MCP
npm install -g markitdown-mcp-npx
```

---

#### 第六步：验证部署

```bash
# 1. 验证 Claude Code
claude --version

# 2. 验证 MCP 服务器
claude mcp list

# 3. 验证插件
claude plugin list

# 4. 测试网络搜索（如果有网络问题，检查代理配置）
claude
# 在对话中说：搜索今天的新闻
```

---

### Linux / Mac 部署

适用于原生 Linux 或 Mac 系统。

#### 部署流程

```bash
# 1. 安装依赖
# Ubuntu/Debian:
sudo apt install -y git nodejs npm

# macOS (Homebrew):
brew install git node

# 2. 克隆仓库
mkdir -p ~/git
cd ~/git
git clone https://github.com/<your-github-username>/claude-config.git
cd claude-config

# 3. 安装 Claude Code
curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/install.sh | sh

# 4. 同步配置
./scripts/start.sh

# 5. 安装 MCP
npm install -g tavily-mcp @playwright/mcp markitdown-mcp-npx

# 6. 验证
claude --version
claude mcp list
```

---

## 初始化脚本说明

初始化脚本按顺序执行，每个脚本负责特定功能：

### 脚本执行顺序

```
01 - init01git              # Git + GitHub CLI + 仓库克隆/更新
02 - init02claude           # Claude Code 安装 + API 配置
03 - init03env              # Node.js + uv + Playwright + 字体 + 符号链接
MCP - initMCP.sh            # MCP 服务器初始化/安装/配置（统一管理）
```

### 脚本功能说明

| 脚本 | 功能 |
|------|------|
| `init01git` | 检查/安装 git + GitHub CLI (gh) + 引导登录 + 克隆/更新仓库 |
| `init02claude` | 安装/升级 Claude Code + 配置 API (MINIMAX) |
| `init03env` | 安装 Node.js + uv + Playwright + inotify-tools + 中文字体 + 符号链接 + **auto-sync 启动/自启动配置** |
| `initMCP.sh` | MCP 服务器初始化/安装/配置，支持 Key/Token 管理 |
| `auto-sync.sh` | 自动同步：监控文件变化，自动 commit + push（后台运行） |
| `enable-autostart.sh` | 配置 auto-sync 自启动（systemd 用户服务，仅 Linux/WSL） |

### mcpidentity.json 鉴权信息管理

所有 MCP 的 Key/Token 等敏感信息存储在 `config/mcpidentity.json`：

```json
{
  "mcp_identities": [
    {
      "name": "tavily",
      "keyEnv": "TAVILY_API_KEY",
      "keyValue": "",
      "keyUrl": "https://tavily.com"
    },
    {
      "name": "supabase",
      "keyEnv": "SUPABASE_PROJECT_ACCESS_TOKEN",
      "keyEnv2": "SUPABASE_PROJECT_ID",
      "keyValue2": "<your-supabase-project-id>"
    }
  ]
}
```

> **注意**：`mcpidentity.json` 包含敏感信息，不参与 Git 同步。

### init01git.sh 额外功能

- 如果仓库目录已存在，自动检测并提供选项：
  - 更新仓库 (git pull)
  - 跳过克隆
  - 删除旧目录重新克隆
  - 改名克隆到其他目录

### apillm.json 格式

```json
{
    "base_url": "https://api.minimaxi.com/anthropic",
    "model_name": "MiniMax-M2.7"
}
```

> **注意**：api_key 不保存到此文件，运行 init02claude.sh 时手动输入。

### 完整初始化流程（全新电脑）

**Ubuntu / Linux / WSL:**
```bash
cd ~/git/claude-config

# 01: 安装 Git + GitHub CLI + 克隆/更新仓库
bash claude-config/init01git

# 02: 安装 Claude Code + 配置 API
bash claude-config/init02claude
source ~/.bashrc

# 03: 安装 Node.js + uv + Playwright + 字体 + 符号链接
bash claude-config/init03env

# MCP: 初始化 MCP 服务器（安装 + 配置 Key）
bash claude-config/scripts/initMCP.sh

# 最后: 同步配置
bash scripts/start.sh
```

**Windows:**
```powershell
cd C:\git\claude-config

# 01: 安装 Git + GitHub CLI + 克隆/更新仓库
.\scripts\pwsh\initgit.ps1

# 02: 安装 Claude Code + 配置 API
.\scripts\pwsh\initclaude.ps1

# 03: 安装 Node.js + uv + Playwright + 字体 + 符号链接
# (注: init03env.ps1 尚未创建，可手动运行 start.ps1 完成符号链接)

# 04: 检查/安装 MCP 服务器
.\scripts\pwsh\claudeMCP.ps1

# 最后: 同步配置
.\scripts\pwsh\start.ps1
```

### 按需执行（已初始化过的电脑）

如果某些组件已安装，对应脚本会自动跳过：

```bash
# 只更新仓库和配置
bash claude-config/scripts/init01git.sh
bash scripts/start.sh

# 只检查/安装 MCP
bash claude-config/scripts/initMCP.sh

# 重新配置浏览器后端
bash claude-config/scripts/initoptplaywright.sh
```

---

## 文件结构说明

### 仓库文件清单

| 文件/目录 | 说明 | 同步 |
|-----------|------|------|
| `README.md` | 说明文档 | ✅ |
| `LICENSE` | MIT 开源许可证 | ✅ |
| `init01git` | Git 环境初始化入口 | ✅ |
| `init02claude` | Claude Code 初始化入口 | ✅ |
| `init03env` | 环境准备入口 | ✅ |
| `config/CLAUDE.md` | 权限白名单配置 | ✅ 符号链接 |
| `config/settings.json` | Claude Code 全局设置 | ✅ 符号链接 |
| `config/apillm.json` | LLM API 配置模板（不含敏感信息） | ✅ |
| `config/mcplist.json` | MCP 服务器列表 | ✅ |
| `config/mcpidentity.json` | MCP 鉴权信息（Key/Token） | ❌ 不同步 |
| `memory/` | 项目记忆目录（按项目名子目录） | ✅ 符号链接 |
| `scripts/` | Bash 脚本（Linux/WSL），包含 start/end/auto-sync/init*/claudeMCP 等 | ✅ |
| `src/README.md` | src 目录说明 | ✅ |
| `.auto-sync.log` | auto-sync 运行日志 | ❌ 不同步 |
| `.auto-sync.pid` | auto-sync 进程 PID | ❌ 不同步 |

### 不同步的文件（本地保留）

| 文件 | 说明 |
|------|------|
| `.claude.json` | 本地配置（含 API Key） |
| `openclaw.json` | GetNote 等外部工具配置 |
| `config/mcpidentity.json` | MCP 鉴权信息，包含敏感 Key/Token |

### 本地手动维护

所有初始化脚本都包含在仓库中，克隆后直接运行即可。

---

## 核心使用规范

### 1. Git 操作规范

| 操作 | 使用工具 | 说明 |
|------|---------|------|
| **git clone/commit/push** | `git` 命令 | ✅ **只使用 git 命令**，不需要 GitHub MCP/Skill |
| **查看 Issue/创建 PR** | GitHub MCP | 可选，用于对话中操作 GitHub |

> **重要**：
> - 普通 git 提交只需要 `git` 命令，不需要安装 GitHub MCP
> - GitHub MCP 仅用于让 Claude 通过对话操作 GitHub（如查看 Issue、创建 PR 等）

---

### 2. MCP 服务器管理规范

| 操作 | 命令 |
|------|------|
| 列出已配置的 MCP | `claude mcp list` |
| 安装 MCP（如支持） | `claude mcp install <name>` |
| 查看 MCP 帮助 | `claude mcp --help` |

> **注意**：
> - 部分 MCP 服务器需要先安装 npm 包：`npm install -g <package-name>`
> - MCP 配置保存在本地 `%USERPROFILE%\.claude.json`，不同步到仓库

---

### 3. Skill / Plugin 管理规范

| 操作 | 命令 |
|------|------|
| 列出已安装的插件 | `claude plugin list` |
| 安装插件 | `claude plugin install <name>` |
| 搜索插件 | `claude plugin search <keyword>` |
| 查看帮助 | `claude plugin --help` |

---

### 4. 配置原则

- **MCP 服务器**：配置在本地 `%USERPROFILE%\.claude.json`
- **LLM API 配置**：保留在本地 `%USERPROFILE%\.claude.json`，**不同步**
- **插件/技能**：配置在本地 `%USERPROFILE%\.claude\settings.json`
- **权限白名单**：放在项目根目录 `C:/git/CLAUDE.md`
- **不使用**：项目级 `.mcp.json`、项目级 `settings.json`/`settings.local.json`

---

## 配置文件说明

| 文件 | 说明 | 同步 |
|------|------|------|
| `.claude.json` | 本地配置（MCP服务器、API密钥等） | ❌ 不同步 |
| `settings.json` | 全局设置（权限、使用统计等） | ✅ 智能同步 |
| `CLAUDE.md` | 权限白名单配置 | ✅ 同步 |
| `memory/MEMORY.md` | 项目记忆文件 | ✅ 同步 |

---

## settings.json 双向同步

`settings.json` 现在通过**符号链接**与仓库实时同步。两个路径指向同一个文件，修改立即生效。

### 同步机制

```
仓库: config/settings.json ←──symlink── 本地: ~/.claude/settings.json
```

修改任一文件，另一处立即同步变化。

### 如果需要智能合并

`sync-settings.js` 仍然可用，用于需要智能合并的场景：

```bash
# 从仓库拉取配置到本地（合并配置，保留本地状态）
node scripts/shared/sync-settings.js pull

# 从本地推送配置到仓库（只提取配置部分）
node scripts/shared/sync-settings.js push
```

**前置条件**：需要安装 Node.js

### 两种同步方式对比

| 方式 | 适用场景 | 优点 |
|------|----------|------|
| 符号链接（默认） | 大部分场景 | 实时同步，无需手动 |
| 智能合并 | 多设备配置差异化 | 保留本地状态，提取共享配置 |

---

## Git 代理配置（必需）

所有三台电脑都需要配置 Git 走代理：

```bash
git config --global http.proxy http://127.0.0.1:7897
git config --global https.proxy http://127.0.0.1:7897
```

- **代理工具**: Clash Verge
- **代理端口**: 7897
- **注意**: VPN 需要常开

---

## 故障排查

### Claude Code 命令找不到

1. 检查是否在 PATH 中（注意要用 `where.exe`，不是 `where`）：
   ```powershell
   where.exe claude
   # 或
   Get-Command claude
   ```

   > **注意**：PowerShell 中 `where` 是 `Where-Object` 的别名，用于过滤对象，不是找文件的命令。正确用法是 `where.exe claude` 或 `Get-Command claude`。

2. WinGet 原生版本安装位置：
   - 实际安装：`C:\Users\franc\AppData\Local\Microsoft\WinGet\Packages\Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe\claude.exe`
   - 符号链接：`C:\Users\franc\AppData\Local\Microsoft\WinGet\Links\claude.exe`

3. 验证安装方式：
   ```powershell
   # 查看安装方式（native = WinGet 安装）
   cat $env:USERPROFILE\.claude.json | Select-String "installMethod"
   ```

4. 手动添加到 PATH：
   ```powershell
   [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:USERPROFILE\.local\bin", "User")
   ```

---

### MCP 服务器不工作

1. 检查 MCP 命令是否能单独运行：
   ```powershell
   tavily-mcp --help
   ```

2. 检查本地 `%USERPROFILE%\.claude.json` 格式是否正确

3. 查看日志：
   - 位置：`%USERPROFILE%\.claude\logs\`

---

### 权限问题

确保 `C:\git\CLAUDE.md` 存在，并且包含权限白名单配置。

---

### Native 安装后的清理

如果之前用 npm 全局安装过 Claude Code，需要清理残留：

```powershell
# 检查是否有 npm 全局安装的 Claude Code 残留
npm list -g claude-code

# 删除残留目录（如果存在）
rm -rf $env:NODE_PATH/../@anthropic-ai
# 或
rm -rf C:\Users\franc\nodejs\current\node_modules\@anthropic-ai
```

---

### 验证 Native 安装

```powershell
# 1. 检查版本
claude --version

# 2. 检查安装方式（应为 native）
Get-Content $env:USERPROFILE\.claude.json | ConvertFrom-Json | Select-Object -ExpandProperty installMethod

# 3. 检查安装路径
where.exe claude
```

输出示例：
```
2.1.70 (Claude Code)
native
C:\Users\franc\AppData\Local\Microsoft\WinGet\Links\claude.exe
```

---

### LLM API 配置问题

如果 Claude Code 报错 API 不可用：

1. 检查本地 `%USERPROFILE%\.claude.json` 中的 `env` 配置：
   ```powershell
   # 查看环境变量配置
   Get-Content $env:USERPROFILE\.claude.json | ConvertFrom-Json | Select-Object -ExpandProperty env
   ```

2. 确保以下环境变量存在：
   - `ANTHROPIC_AUTH_TOKEN` - API 密钥
   - `ANTHROPIC_BASE_URL` - API 端点
   - `ANTHROPIC_DEFAULT_SONNET_MODEL` - 默认模型

3. 重启 Claude Code

> **重要**：`.claude.json` 保留在本地不同步，请确保每台设备的 API 配置正确。

---

## 部署检查清单

- [ ] WinGet 已安装
- [ ] PowerShell 7 已安装
- [ ] Git 已安装并配置
- [ ] Node.js LTS 已安装
- [ ] Claude Code 原生版本已安装
- [ ] claude-config 仓库已克隆到 `C:\git\claude-config`
- [ ] 本地 `.claude.json` 已配置（包含 API 密钥）
- [ ] start.ps1 已运行，配置已同步
- [ ] Tavily MCP npm 包已安装
- [ ] Playwright MCP npm 包已安装
- [ ] MarkItDown MCP npm 包已安装
- [ ] Claude Code 能正常启动
- [ ] `/mcp` 能看到所有 MCP 服务器
- [ ] `/plugins` 能看到所有 Skill
- [ ] Tavily 搜索测试通过

---

## 安全提示

⚠️ 以下配置包含敏感信息，保留在本地不同步：

- `.claude.json` - 包含 LLM API 密钥、MCP 服务器认证信息
- 本地环境变量文件

如果使用公开 Git 仓库：
- 确保仓库为私有
- 不要提交包含密钥的配置文件

---

## 相关链接

- Claude Code 官方文档：https://code.claude.com/docs
- MCP 规范：https://modelcontextprotocol.io
- claude-config 仓库：https://github.com/<your-github-username>/claude-config
