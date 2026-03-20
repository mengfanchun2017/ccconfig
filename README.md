# Claude Code 配置同步仓库

用于在多台设备间同步 Claude Code 的配置。

---

## 目录

1. [快速开始（日常使用）](#快速开始日常使用)
2. [全新电脑部署](#全新电脑部署)
3. [初始化脚本说明](#初始化脚本说明)
4. [文件结构说明](#文件结构说明)
5. [核心使用规范](#核心使用规范)
6. [配置文件说明](#配置文件说明)
7. [settings.json 智能同步](#settingsjson-智能同步)
8. [Git 代理配置](#git-代理配置)
9. [故障排查](#故障排查)
10. [部署检查清单](#部署检查清单)
11. [安全提示](#安全提示)

---

## 快速开始（日常使用）

### 在当前设备开始工作前

**Windows (双击):**
```
scripts\pwsh\start.ps1
```

**WSL Ubuntu / Linux / Mac:**
```bash
cd ~/git/claude-config
./scripts/bash/start.sh
```

这个脚本会自动：
1. 从 GitHub 拉取最新配置
2. 同步配置文件到本地（settings.json 使用智能合并）
3. 同步 CLAUDE.md 到本地主目录
4. 检查 Memory 目录状态

### 在当前设备结束工作后

**Windows (双击):**
```
scripts\pwsh\end.ps1
```

**WSL Ubuntu / Linux / Mac:**
```bash
cd ~/git/claude-config
./scripts/bash/end.sh
```

这个脚本会自动：
1. 从本地收集最新配置到仓库（settings.json 只提取配置部分）
2. 同步 CLAUDE.md 到仓库
3. 显示 git 状态
4. 提交更改（可自定义提交信息）
5. 推送到 GitHub

> **注意**：`.claude.json` 包含 LLM API 配置，保留在本地不同步。

### MCP 服务器同步检查

可以使用 `mcpcheck.sh` / `mcpcheck.ps1` 来检查和同步 MCP 服务器配置：

**Windows:**
```
scripts\pwsh\mcpcheck.ps1
```

**Linux / Mac:**
```bash
./scripts/bash/mcpcheck.sh
```

功能：
- 对比 mcplist.json 与当前环境
- 显示已安装/缺失/多余的 MCP
- 支持一键安装缺失的 MCP
- 支持双向同步

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
./scripts/bash/start.sh

# 结束工作
./scripts/bash/end.sh

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

- [Windows 11](#windows-11-部署)
- [WSL Ubuntu](#wsl-ubuntu-部署)
- [Linux / Mac](#linux--mac-部署)

---

### Windows 11 部署

#### 部署流程图

```
┌─────────────────┐
│  1. 环境准备     │ → PowerShell 7 + Git + Node.js + WinGet
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  2. 安装 Claude  │ → 原生版本（WinGet 或 PowerShell）
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  3. 克隆配置仓库 │ → git clone claude-config
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  4. 同步配置     │ → 运行 scripts/pwsh/start.ps1
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  5. 安装 MCP    │ → 使用 claude mcp 命令
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  6. 验证部署     │ → 检查 Claude + MCP + Skill
└─────────────────┘
```

#### 第一步：环境准备

#### 1.1 检查并安装 WinGet

Windows 11 通常自带 WinGet，验证一下：

```powershell
winget --version
```

如果没有：
1. 打开 Microsoft Store
2. 搜索「App Installer」
3. 安装或更新

#### 1.2 安装 PowerShell 7（推荐）

Windows 11 自带 PowerShell 5，但推荐安装 PowerShell 7：

```powershell
# 检查当前版本
$PSVersionTable.PSVersion

# 如果版本 < 7，安装
winget install Microsoft.PowerShell
```

验证：
```powershell
pwsh --version
```

#### 1.3 安装 Git

```powershell
winget install Git.Git
```

验证：
```powershell
git --version
```

**配置 Git（必需）：**
```powershell
git config --global user.name "你的名字"
git config --global user.email "你的邮箱"
```

#### 1.4 安装 Node.js LTS（用于 MCP 服务器）

```powershell
winget install OpenJS.NodeJS.LTS
```

验证：
```powershell
node --version
npm --version
```

#### 1.5 配置 Git 代理（如果需要）

如果使用代理（Clash Verge）：

```powershell
git config --global http.proxy http://127.0.0.1:7897
git config --global https.proxy http://127.0.0.1:7897
```

> 代理端口默认 7897，请根据实际情况调整。

---

### 第二步：安装 Claude Code（原生版本）

#### 方式一：WinGet（最推荐）

```powershell
winget install Anthropic.ClaudeCode
```

#### 方式二：PowerShell 脚本

```powershell
irm https://claude.ai/install.ps1 | iex
```

#### 验证安装

```powershell
claude --version
```

应该输出类似：`2.1.63 (Claude Code)`

---

### 第三步：克隆配置仓库

```powershell
# 创建项目目录
cd C:\
mkdir git
cd git

# 克隆配置仓库
git clone git@github.com:<your-github-username>/claude-config.git
```

> **如果 SSH 不行，使用 HTTPS：**
> ```powershell
> git clone https://github.com/<your-github-username>/claude-config.git
> ```

---

### 第四步：同步配置

#### 运行同步脚本

**Windows（双击即可）：**
```
C:\git\claude-config\scripts\pwsh\start.ps1
```

**PowerShell：**
```powershell
cd C:\git\claude-config
.\scripts\pwsh\start.ps1
```

#### 同步脚本做了什么

| 步骤 | 操作 |
|------|------|
| 1 | 从 GitHub 拉取最新配置 |
| 2 | 智能同步 settings.json → `%USERPROFILE%\.claude\settings.json` |
| 3 | 同步 CLAUDE.md → `C:\git\CLAUDE.md` |
| 4 | 智能合并 settings.json（保留本地状态） |

> **重要**：
> - `.claude.json` 包含 LLM API 配置，保留在本地不同步
> - 不要在项目目录下创建 `.claude/settings.local.json`，这会覆盖全局权限配置

#### 手动同步（如果脚本不可用）

```powershell
# 复制 settings.json
Copy-Item C:\git\claude-config\settings.json $env:USERPROFILE\.claude\settings.json -Force

# 复制 CLAUDE.md
Copy-Item C:\git\claude-config\CLAUDE.md C:\git\CLAUDE.md -Force

# 创建本地 .claude.json（从其他设备复制）
# 包含 MCP 服务器配置和环境变量
```

---

### 第五步：安装 MCP 服务器

配置同步后，部分 MCP 服务器可能需要手动安装 npm 包。

#### MCP 管理命令

```powershell
# 列出已配置的 MCP 服务器
claude mcp list

# 查看帮助
claude mcp --help
```

#### 安装常用 MCP 服务器

##### 1. Tavily MCP（网络搜索）

```powershell
npm install -g tavily-mcp
```

验证：
```bash
tavily-mcp --help
```

##### 2. Playwright MCP（浏览器自动化，推荐安装）

```bash
npm install -g @playwright/mcp
```

验证：
```bash
playwright-mcp --help
```

##### 3. MarkItDown MCP（文档解析，推荐安装）

```bash
npm install -g markitdown-mcp-npx
```

验证：
```bash
markitdown-mcp-npx --help
```

##### 4. GitHub MCP

使用 HTTP 方式，不需要安装本地 npm 包，配置在本地 `.claude.json` 中。

##### 5. Supabase MCP

使用 HTTP 方式，不需要安装本地 npm 包，配置在本地 `.claude.json` 中。

> **注意**：本地 `.claude.json` 需要手动配置 MCP 服务器。首次使用前请确保已在本地配置文件中添加以上 MCP。

---

### 第六步：验证部署

#### 6.1 验证 Claude Code

```powershell
claude --version
claude doctor
```

#### 6.2 验证 MCP 服务器

启动 Claude Code，然后在对话中输入：
```
/mcp
```

应该看到：tavily、playwright、markitdown、github、supabase

#### 6.3 验证 Skill / Plugin

在对话中输入：
```
/plugins
```

应该看到：simplify、tavily@tavily-ai-skills、claude-api

#### 6.4 测试 Tavily 搜索

在对话中说：
```
搜索一下今天的新闻
```

如果能返回搜索结果，说明部署成功！

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
./scripts/bash/start.sh
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
./scripts/bash/start.sh

# 5. 安装 MCP
npm install -g tavily-mcp @playwright/mcp markitdown-mcp-npx

# 6. 验证
claude --version
claude mcp list
```

---

## 初始化脚本说明

> **注意**：初始化脚本已包含在本仓库中。但因为仓库需要克隆后才能拉取，所以需要**先手动将脚本复制到本地**，然后再执行。

### 使用流程

```
1. 从其他渠道获取初始化脚本（initgit.sh / initgit.ps1）
   ↓
2. 手动复制到目标目录（如 ~/ 或 C:\）
   ↓
3. 执行脚本（自动安装 git + gh + 登录 + 克隆仓库）
   ↓
4. 进入克隆后的仓库目录
   ↓
5. 执行日常同步脚本 start.sh / start.ps1
```

### 脚本文件

| 平台 | Git 初始化 | Claude 配置 |
|------|-----------|-------------|
| Ubuntu / Linux / WSL | `initgit.sh` | `initclaude.sh` |
| Windows | `pwsh/initgit.ps1` | `pwsh/initclaude.ps1` |

### initgit.sh 功能

1. 检查/安装 git
2. 自动下载安装 GitHub CLI (gh)
3. 引导 `gh auth login` 登录 GitHub
4. 询问仓库地址并克隆（默认：<your-github-username>/claude-config）

### initclaude.sh 功能

1. 选择 LLM 订阅厂商（目前支持 MINIMAX）
2. 读取 `apillm.json` 配置模板
3. 逐条询问用户配置（API 地址、API Key、模型名称）
4. 跳过 Claude 登录引导
5. 写入 ~/.claude/settings.json 配置
6. 更新 ~/.bashrc 环境变量

### apillm.json 格式

```json
{
    "base_url": "https://api.minimaxi.com/anthropic",
    "model_name": "MiniMax-M2.7"
}
```

> **注意**：api_key 不保存到此文件，运行 initclaude.sh 时手动输入。

### 初始化流程

**Ubuntu / Linux / WSL:**
```bash
# 0. 添加执行权限
chmod +x initgit.sh initclaude.sh

# 1. 安装 Git + GitHub CLI + 登录 + 克隆仓库
./initgit.sh

# 2. 配置 Claude Code（选择 MINIMAX，逐条确认配置）
./initclaude.sh

# 3. 加载环境变量
source ~/.bashrc

# 4. 拉取配置仓库
cd claude-config
./scripts/bash/start.sh
```

**Windows:**
```powershell
# 1. 安装 Git + GitHub CLI + 登录 + 克隆仓库
.\scripts\pwsh\initgit.ps1

# 2. 配置 Claude Code（选择 MINIMAX，逐条确认配置）
.\scripts\pwsh\initclaude.ps1

# 3. 拉取配置仓库
cd claude-config
.\scripts\pwsh\start.ps1
```

---

## 文件结构说明

### 仓库文件清单

| 文件/目录 | 说明 | 同步 |
|-----------|------|------|
| `README.md` | 说明文档 | ✅ |
| `LICENSE` | MIT 开源许可证 | ✅ |
| `config/CLAUDE.md` | 权限白名单配置 | ✅ |
| `config/settings.json` | Claude Code 全局设置 | ✅ 智能同步 |
| `config/apillm.json` | LLM API 配置模板（不含敏感信息） | ✅ |
| `config/mcplist.json` | MCP 服务器列表 | ✅ |
| `memory/` | 项目记忆目录（按项目名子目录，如 memory/git/MEMORY.md） | ✅ |
| `scripts/bash/` | Bash 脚本（Linux/WSL/macOS） | ✅ |
| `scripts/pwsh/` | PowerShell 脚本（Windows） | ✅ |
| `src/lib-common.sh` | 公共函数库 | ✅ |

### 不同步的文件（本地保留）

| 文件 | 说明 |
|------|------|
| `.claude.json` | 本地配置（含 API Key） |
| `openclaw.json` | GetNote 等外部工具配置 |

### 本地手动维护

这些文件需要用户手动创建或从其他来源获取：

| 文件 | 说明 |
|------|------|
| `initgit.sh` / `initgit.ps1` | 首次部署时手动复制到本地再执行 |

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

## settings.json 智能同步

`settings.json` 包含两部分内容，智能同步脚本会分别处理：

### 同步的配置部分（跨设备共享）

| 配置项 | 说明 |
|--------|------|
| `permissions` | 权限配置 |
| `mcpServers` | MCP 服务器配置 |
| `enabledPlugins` | 启用的插件/技能 |
| `extraKnownMarketplaces` | 额外的插件市场 |

### 保留的本地状态（每台设备独立）

| 状态项 | 说明 |
|--------|------|
| `numStartups` | 启动次数统计 |
| `tipsHistory` | 提示显示历史 |
| `toolUsage` | 工具使用统计 |
| `skillUsage` | 技能使用统计 |
| `projects` | 项目记录 |
| `githubRepoPaths` | GitHub 仓库路径映射 |
| ... | 其他本地状态数据 |

### 手动使用智能同步脚本

如果需要手动同步 settings.json：

```bash
# 从仓库拉取配置到本地（合并配置，保留本地状态）
node scripts/sync-settings.js pull

# 从本地推送配置到仓库（只提取配置部分）
node scripts/sync-settings.js push
```

**前置条件**：需要安装 Node.js

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
