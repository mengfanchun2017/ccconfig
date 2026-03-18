# Claude Code 配置同步仓库

用于在多台设备间同步 Claude Code 的配置。

---

## 目录

1. [快速开始（日常使用）](#快速开始日常使用)
2. [全新电脑部署](#全新电脑部署)
3. [核心使用规范](#核心使用规范)
4. [配置文件说明](#配置文件说明)
5. [settings.json 智能同步](#settingsjson-智能同步)
6. [Git 代理配置](#git-代理配置)
7. [故障排查](#故障排查)
8. [部署检查清单](#部署检查清单)
9. [安全提示](#安全提示)

---

## 快速开始（日常使用）

### 在当前设备开始工作前

**Windows (双击):**
```
scripts\start-work.bat
```

**Git Bash / Linux / Mac:**
```bash
scripts/start-work.sh
```

这个脚本会自动：
1. 从 GitHub 拉取最新配置
2. 同步配置文件到本地（settings.json 使用智能合并）
3. 检查 Memory 链接状态

### 在当前设备结束工作后

**Windows (双击):**
```
scripts\end-work.bat
```

**Git Bash / Linux / Mac:**
```bash
scripts/end-work.sh
```

这个脚本会自动：
1. 从本地收集最新配置到仓库（settings.json 只提取配置部分）
2. 显示 git 状态
3. 提交更改（可自定义提交信息）
4. 推送到 GitHub

> **注意**：`.claude.json` 包含 LLM API 配置，保留在本地不同步。

---

## 全新电脑部署

### 部署流程图

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
│  4. 同步配置     │ → 运行 start-work.bat
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

### 第一步：环境准备

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
C:\git\claude-config\scripts\start-work.bat
```

**PowerShell：**
```powershell
cd C:\git\claude-config
.\scripts\start-work.bat
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
```powershell
tavily-mcp --help
```

##### 2. Playwright MCP（浏览器自动化）

```powershell
npm install -g @playwright/mcp
```

验证：
```powershell
playwright-mcp --help
```

##### 3. MarkItDown MCP（文档解析）

```powershell
npm install -g markitdown-mcp-npx
```

验证：
```powershell
markitdown-mcp-npx --help
```

##### GitHub & Supabase MCP

这两个使用 HTTP 方式，不需要安装本地 npm 包，配置在本地 `.claude.json` 中。

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
- [ ] start-work.bat 已运行，配置已同步
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
