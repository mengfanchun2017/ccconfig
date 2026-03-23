# Claude Code 配置同步仓库模板

本仓库提供了一套完整的 Claude Code 配置管理方案，通过 Git 实现多设备间的配置同步。

> **注意**：这是模板仓库。实际使用时，请将其 Fork 或克隆后，按需修改配置模板中的占位符。

---

## 目录

1. [项目概述](#项目概述)
2. [架构说明](#架构说明)
3. [文件结构说明](#文件结构说明)
4. [快速开始（日常使用）](#快速开始日常使用)
5. [全新电脑部署](#全新电脑部署)
6. [初始化脚本说明](#初始化脚本说明)
7. [配置文件模板](#配置文件模板)
8. [部署检查清单](#部署检查清单)
9. [安全提示](#安全提示)

---

## 项目概述

### 核心理念

本仓库解决了以下问题：

- **多设备同步**：在多台电脑间同步 Claude Code 的配置、权限、插件等
- **一键部署**：新电脑可以快速克隆并运行脚本完成全部配置
- **版本控制**：所有配置变更都有记录，方便回溯和管理

### 同步内容

| 类型 | 说明 |
|------|------|
| settings.json | Claude Code 全局设置（权限、插件配置等） |
| CLAUDE.md | 权限白名单配置 |
| mcplist.json | MCP 服务器列表（不含密钥） |
| apillm.json | LLM API 端点配置模板 |
| memory/ | 项目记忆目录（按项目名子目录） |
| scripts/ | 同步和管理脚本 |

### 不同步的内容（本地保留）

| 文件 | 说明 |
|------|------|
| `.claude.json` | 本地配置（含 API Key、MCP 认证信息等敏感数据） |

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

| 文件 | 仓库位置 | 本地位置 (Linux/macOS) | 本地位置 (Windows) |
|------|----------|----------------------|-------------------|
| settings.json | `config/settings.json` | `~/.claude/settings.json` | `%USERPROFILE%\.claude\settings.json` |
| CLAUDE.md | `config/CLAUDE.md` | `~/CLAUDE.md` | `%USERPROFILE%\CLAUDE.md` |
| MEMORY.md | `memory/{项目标识}/MEMORY.md` | `~/.claude/projects/{项目标识}/memory/MEMORY.md` | `%USERPROFILE%\.claude\projects\{项目标识}\memory\MEMORY.md` |

### 脚本架构

```
scripts/
├── bash/                    # Linux/WSL/macOS 独立实现
│   ├── start.sh             # 创建符号链接 + git pull
│   ├── end.sh               # git add/commit/push
│   ├── mcpcheck.sh          # MCP 环境检查
│   ├── initgit.sh           # Git + GitHub CLI 安装
│   ├── initclaude.sh        # Claude API 配置
│   ├── initmcp.sh           # Node.js + uv 安装
│   └── initplaywright.sh    # Playwright 安装
│
├── pwsh/                    # Windows PowerShell 独立实现（与 bash 对称）
│   ├── start.ps1            # 创建符号链接 + git pull
│   ├── end.ps1              # git add/commit/push
│   ├── mcpcheck.ps1         # MCP 环境检查
│   ├── initgit.ps1          # Git + GitHub CLI 安装
│   ├── initclaude.ps1       # Claude API 配置
│   └── initmcp.ps1          # Node.js + uv 安装
│
└── shared/                  # 跨平台共享脚本
    └── sync-settings.js     # settings.json 智能合并
```

**设计原则**：
- Bash 和 PowerShell 是不同语言，**不共享代码**
- 各平台脚本独立完整实现，功能一一对称

### Memory 同步说明

Claude Code 会为每个项目维护记忆文件 `MEMORY.md`。本仓库的 `memory/` 目录按项目组织：

```
memory/
└── your-project-name/       # 项目标识（目录名 → 路径转换）
    └── MEMORY.md            # 该项目的记忆文件
```

**项目标识转换规则**：
- 路径 `/home/user/project` → 标识 `home-user-project`
- 路径 `C:\Users\project` → 标识 `C--Users-project`

---

## 文件结构说明

### 仓库文件清单

| 文件/目录 | 说明 | 同步 |
|-----------|------|------|
| `README.md` | 说明文档 | ✅ |
| `USENOTE.md` | 模板使用说明 | ✅ |
| `LICENSE` | MIT 开源许可证 | ✅ |
| `config/CLAUDE.md` | 权限白名单配置模板 | ✅ 符号链接 |
| `config/settings.json` | Claude Code 全局设置模板 | ✅ 符号链接 |
| `config/apillm.json` | LLM API 配置模板（不含敏感信息） | ✅ |
| `config/mcplist.json` | MCP 服务器列表模板 | ✅ |
| `memory/` | 项目记忆目录（模板结构） | ✅ 符号链接 |
| `scripts/bash/` | Bash 脚本（Linux/WSL/macOS） | ✅ |
| `scripts/pwsh/` | PowerShell 脚本（Windows） | ✅ |
| `scripts/shared/` | 跨平台共享脚本 | ✅ |

### 不同步的文件（本地保留）

| 文件 | 说明 |
|------|------|
| `.claude.json` | 本地配置（含 API Key、MCP 认证信息等） |

---

## 快速开始（日常使用）

### 在当前设备开始工作前

**Windows:**
```powershell
cd C:\git\claude-config
.\scripts\pwsh\start.ps1
```

**WSL Ubuntu / Linux / Mac:**
```bash
cd ~/git/claude-config
./scripts/bash/start.sh
```

这个脚本会自动：
1. 从 GitHub 拉取最新配置
2. 通过符号链接同步 settings.json 到本地
3. 通过符号链接同步 CLAUDE.md 到本地主目录
4. 通过符号链接同步 MEMORY.md（自动检测项目）

### 在当前设备结束工作后

**Windows:**
```powershell
cd C:\git\claude-config
.\scripts\pwsh\end.ps1
```

**WSL Ubuntu / Linux / Mac:**
```bash
cd ~/git/claude-config
./scripts/bash/end.sh
```

这个脚本会自动：
1. 显示 git 状态
2. 提交更改（可自定义提交信息）
3. 推送到 GitHub

### 快捷命令（关键词）

在 Claude Code 对话中使用这些关键词快速触发脚本：

| 关键词 | 功能 | 说明 |
|--------|------|------|
| `gitinit` | 开始工作 | 等同于运行 `start.sh`，拉取配置并建立符号链接 |
| `gitarc` | 结束工作 | 等同于运行 `end.sh`，提交并推送更改到 GitHub |

---

## 全新电脑部署

### 选择你的平台

- [Windows 11](#windows-11-部署)
- [WSL Ubuntu](#wsl-ubuntu-部署)
- [Linux / Mac](#linux--mac-部署)

---

### Windows 11 部署

#### 部署流程

```
┌─────────────────┐
│  1. 环境准备     │ → PowerShell 7 + Git + Node.js + WinGet
└────────┬────────┘
         ▼
┌─────────────────┐
│  2. 安装 Claude  │ → 原生版本（WinGet 或 PowerShell）
└────────┬────────┘
         ▼
┌─────────────────┐
│  3. 克隆配置仓库 │ → git clone 你的仓库
└────────┬────────┘
         ▼
┌─────────────────┐
│  4. 同步配置     │ → 运行 scripts/pwsh/start.ps1
└────────┬────────┘
         ▼
┌─────────────────┐
│  5. 安装 MCP    │ → 使用 npm 全局安装
└────────┬────────┘
         ▼
┌─────────────────┐
│  6. 验证部署     │ → 检查 Claude + MCP + Skill
└─────────────────┘
```

#### 第一步：环境准备

##### 1.1 检查并安装 WinGet

```powershell
winget --version
```

如果没有，从 Microsoft Store 安装「App Installer」。

##### 1.2 安装 PowerShell 7（推荐）

```powershell
winget install Microsoft.PowerShell
```

##### 1.3 安装 Git

```powershell
winget install Git.Git
```

**配置 Git（必需）：**
```powershell
git config --global user.name "你的名字"
git config --global user.email "你的邮箱"
```

##### 1.4 安装 Node.js LTS

```powershell
winget install OpenJS.NodeJS.LTS
```

##### 1.5 配置 Git 代理（如果需要）

```powershell
git config --global http.proxy http://127.0.0.1:7897
git config --global https.proxy http://127.0.0.1:7897
```

---

#### 第二步：安装 Claude Code

##### 方式一：WinGet（推荐）

```powershell
winget install Anthropic.ClaudeCode
```

##### 方式二：PowerShell 脚本

```powershell
irm https://claude.ai/install.ps1 | iex
```

##### 验证安装

```powershell
claude --version
```

---

#### 第三步：克隆配置仓库

```powershell
# 创建项目目录
cd C:\
mkdir git
cd git

# 克隆你的配置仓库
git clone https://github.com/YOUR_USERNAME/claude-config.git
```

---

#### 第四步：同步配置

```powershell
cd C:\git\claude-config
.\scripts\pwsh\start.ps1
```

---

#### 第五步：配置本地 API

首次使用需要配置 LLM API（在本地 `.claude.json` 中）：

```powershell
# 编辑本地配置文件
code $env:USERPROFILE\.claude.json
```

配置示例：
```json
{
  "installMethod": "native",
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "your-api-key-here",
    "ANTHROPIC_BASE_URL": "https://api.your-provider.com/anthropic",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-20250514"
  },
  "mcp": {}
}
```

---

#### 第六步：验证部署

```powershell
claude --version
claude doctor
```

---

### WSL Ubuntu 部署

#### 部署流程

```
┌─────────────────┐
│  1. 环境准备     │ → Ubuntu 24.04 + Git + Node.js
└────────┬────────┘
         ▼
┌─────────────────┐
│  2. 安装 Claude  │ → curl 安装脚本
└────────┬────────┘
         ▼
┌─────────────────┐
│  3. 克隆配置仓库 │ → git clone 你的仓库
└────────┬────────┘
         ▼
┌─────────────────┐
│  4. 同步配置     │ → 运行 start.sh
└────────┬────────┘
         ▼
┌─────────────────┐
│  5. 安装 MCP    │ → 使用 npm 全局安装
└────────┬────────┘
         ▼
┌─────────────────┐
│  6. 验证部署     │ → 检查 Claude + MCP
└─────────────────┘
```

#### 第一步：环境准备

##### 1.1 安装 Ubuntu

```powershell
wsl --install -d Ubuntu-24.04
```

##### 1.2 安装 Git 和 Node.js

```bash
sudo apt update
sudo apt install -y git nodejs npm
```

##### 1.3 配置 Git 代理（如果需要）

```bash
git config --global http.proxy http://127.0.0.1:7897
git config --global https.proxy http://127.0.0.1:7897
```

---

#### 第二步：安装 Claude Code

```bash
curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/install.sh | sh
```

---

#### 第三步：克隆配置仓库

```bash
mkdir -p ~/git
cd ~/git
git clone https://github.com/YOUR_USERNAME/claude-config.git
cd claude-config
```

---

#### 第四步：同步配置

```bash
./scripts/bash/start.sh
```

---

#### 第五步：配置本地 API

```bash
# 编辑本地配置文件
code ~/.claude.json
```

---

### Linux / Mac 部署

```bash
# 1. 安装依赖
# Ubuntu/Debian:
sudo apt install -y git nodejs npm

# macOS (Homebrew):
brew install git node

# 2. 克隆仓库
mkdir -p ~/git
cd ~/git
git clone https://github.com/YOUR_USERNAME/claude-config.git
cd claude-config

# 3. 安装 Claude Code
curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/install.sh | sh

# 4. 同步配置
./scripts/bash/start.sh

# 5. 配置本地 API
code ~/.claude.json
```

---

## 初始化脚本说明

> **注意**：初始化脚本用于全新部署。首次部署时，需要先将脚本复制到本地再执行。

### 使用流程

```
1. 从仓库获取初始化脚本
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
| Ubuntu / Linux / WSL | `scripts/bash/initgit.sh` | `scripts/bash/initclaude.sh` |
| Windows | `scripts/pwsh/initgit.ps1` | `scripts/pwsh/initclaude.ps1` |

### initgit.sh / initgit.ps1 功能

1. 检查/安装 git
2. 自动下载安装 GitHub CLI (gh)
3. 引导 `gh auth login` 登录 GitHub
4. 询问仓库地址并克隆

### initclaude.sh / initclaude.ps1 功能

1. 选择 LLM 订阅厂商
2. 读取 `config/apillm.json` 配置模板
3. 逐条询问用户配置（API 地址、API Key、模型名称）
4. 写入本地 `~/.claude/settings.json` 配置

---

## 配置文件模板

> **重要**：以下模板中的值均为示例，使用时请替换为你的实际配置。

### config/settings.json

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep",
      "Agent",
      "Skill",
      "TaskOutput",
      "TaskStop",
      "TaskCreate",
      "TaskUpdate",
      "TaskGet",
      "TaskList",
      "AskUserQuestion",
      "NotebookEdit",
      "Bash(*)"

      // 添加其他权限...
    ],
    "deny": [
      "WebSearch",
      "WebFetch"
    ]
  },
  "extraKnownMarketplaces": {
    "your-skill-repo": {
      "source": {
        "source": "github",
        "repo": "your-org/your-skill-repo"
      }
    }
  },
  "enabledPlugins": {
    "your-plugin": true,
    "simplify": true
  }
}
```

### config/CLAUDE.md

```markdown
# Claude Code 权限配置模板

## 允许的 Bash 命令

### 文件浏览（只读，安全）
- `ls` - 列出目录内容
- `pwd` - 显示当前路径
- `cd` - 切换目录

### 文件操作
- `mkdir` - 创建目录
- `cp` - 复制文件
- `mv` - 移动/重命名文件
- `rm` - 删除文件
- `touch` - 创建空文件

### Git 操作
- `git status` - 查看状态
- `git log` - 查看提交历史
- `git add` - 添加文件
- `git commit` - 提交
- `git push` - 推送到远程
- `git pull` - 拉取远程更新

### Node.js / npm
- `node` - Node.js 运行时
- `npm` - npm 包管理器
- `npx` - 执行本地或远程包

### Python
- `python` - Python 解释器
- `pip` - pip 包管理器

// 添加其他需要的命令...

## 禁止的命令（危险操作）
- `rm -rf` - 强制递归删除
- `git reset --hard` - 硬重置
- `sudo` - 管理员权限

## 允许的工具
- Read - 读取文件
- Write - 写入文件
- Edit - 编辑文件
- Grep - 搜索文件
- Glob - 文件匹配

## 暗号命令
- `gitinit` - 开始工作
- `gitarc` - 结束工作
```

### config/apillm.json

```json
{
    "description": "LLM API 配置模板",
    "base_url": "https://api.your-provider.com/anthropic",
    "model_name": "claude-sonnet-4-20250514"
}
```

### config/mcplist.json

```json
{
  "description": "MCP 服务器列表模板",
  "mcp": [
    {
      "name": "tavily",
      "description": "网络搜索",
      "type": "stdio",
      "install": "npx tavily-mcp",
      "install_local": "npm install -g tavily-mcp",
      "needsKey": true,
      "keyEnv": "TAVILY_API_KEY",
      "keyUrl": "https://tavily.com"
    },
    {
      "name": "playwright",
      "description": "浏览器自动化",
      "type": "stdio",
      "install": "npx @playwright/mcp",
      "install_local": "npm install -g @playwright/mcp"
    },
    {
      "name": "your-mcp",
      "description": "你的 MCP 服务器",
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "your-mcp-package"],
      "install": "npx -y your-mcp-package",
      "needsKey": false,
      "doc_url": "https://github.com/your-org/your-mcp"
    }
  ]
}
```

### memory 目录结构

```
memory/
└── your-project-identifier/     # 项目标识符（对应 ~/.claude/projects/ 下的目录名）
    └── MEMORY.md               # 项目记忆文件（内容为空，由 Claude Code 自动填充）
```

**创建方法**：
1. 确定项目的标识符（如 `/home/user/project` → `home-user-project`）
2. 在 `memory/` 下创建对应子目录
3. 在子目录中创建空的 `MEMORY.md` 文件

---

## 部署检查清单

### 通用检查项

- [ ] Git 已安装并配置（user.name, user.email）
- [ ] Node.js LTS 已安装
- [ ] Claude Code 原生版本已安装
- [ ] 配置仓库已克隆到本地
- [ ] 本地 `.claude.json` 已配置（包含 API 密钥）
- [ ] start.sh / start.ps1 已运行，配置已同步

### Windows 检查项

- [ ] WinGet 已安装
- [ ] PowerShell 7 已安装（推荐）

### Linux/macOS 检查项

- [ ] 系统依赖已安装

### 验证检查项

- [ ] Claude Code 能正常启动
- [ ] `claude --version` 显示正确版本
- [ ] `/mcp` 能看到配置的 MCP 服务器（如有）
- [ ] `/plugins` 能看到配置的插件（如有）

---

## 安全提示

### 敏感信息保护

以下配置包含敏感信息，**保留在本地不同步**：

| 文件 | 包含内容 |
|------|----------|
| `.claude.json` | LLM API 密钥、MCP 服务器认证信息、Personal Access Token 等 |

### 仓库安全建议

1. **使用私有仓库**：将配置仓库设为私有
2. **不提交密钥**：不要将包含实际密钥的配置文件提交到仓库
3. **使用模板**：模板文件只包含占位符和示例值
4. **本地配置**：每个设备的 API 密钥保留在本地 `.claude.json`

### 配置 .gitignore

建议在仓库根目录添加以下内容到 `.gitignore`：

```
# 本地配置（包含敏感信息）
.claude.json
*.local.json

# 临时文件
*.tmp
*.log
```

---

## 相关链接

- Claude Code 官方文档：https://code.claude.com/docs
- MCP 规范：https://modelcontextprotocol.io
- GitHub CLI 文档：https://cli.github.com/manual
