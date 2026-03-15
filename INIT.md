# Claude Code 全新安装指南

适用于全新 Windows 11 环境的快速、专业部署流程。

---

## 部署流程图

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

---

## 目录

1. [核心概念说明](#核心概念说明)
2. [第一步：环境准备](#第一步环境准备)
3. [第二步：安装 Claude Code（原生版本）](#第二步安装-claude-code原生版本)
4. [第三步：克隆配置仓库](#第三步克隆配置仓库)
5. [第四步：同步配置](#第四步同步配置)
6. [第五步：安装 MCP 服务器](#第五步安装-mcp-服务器)
7. [第六步：验证部署](#第六步验证部署)
8. [日常使用](#日常使用)
9. [故障排查](#故障排查)

---

## 核心概念说明

| 组件 | 说明 | 依赖 |
|------|------|------|
| **Claude Code** | 主程序，原生二进制 | ❌ 无需 Node.js |
| **MCP 服务器** | 扩展工具能力（搜索、浏览器等） | ✅ 需要 Node.js |
| **Skill / Plugin** | 扩展对话能力（代码简化等） | ❌ 通常不需要 |

> **重要**：
> - Claude Code 原生版本不需要 Node.js
> - 但 Tavily、Playwright 等 MCP 服务器是用 Node.js 写的，必须安装 Node.js

---

## 第一步：环境准备

### 1.1 检查并安装 WinGet

Windows 11 通常自带 WinGet，验证一下：

```powershell
winget --version
```

如果没有：
1. 打开 Microsoft Store
2. 搜索「App Installer」
3. 安装或更新

---

### 1.2 安装 PowerShell 7（推荐）

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

---

### 1.3 安装 Git

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

---

### 1.4 安装 Node.js LTS（用于 MCP 服务器）

```powershell
winget install OpenJS.NodeJS.LTS
```

验证：
```powershell
node --version
npm --version
```

---

### 1.5 配置 Git 代理（如果需要）

如果使用代理（Clash Verge）：

```powershell
git config --global http.proxy http://127.0.0.1:7897
git config --global https.proxy http://127.0.0.1:7897
```

> 代理端口默认 7897，请根据实际情况调整。

---

## 第二步：安装 Claude Code（原生版本）

### 方式一：WinGet（最推荐）

```powershell
winget install Anthropic.ClaudeCode
```

### 方式二：PowerShell 脚本

```powershell
irm https://claude.ai/install.ps1 | iex
```

### 验证安装

```powershell
claude --version
```

应该输出类似：`2.1.63 (Claude Code)`

### 首次启动（可选）

```powershell
claude
```

按照提示完成认证（也可以等配置同步后再做）。

---

## 第三步：克隆配置仓库

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

## 第四步：同步配置

### 运行同步脚本

**Windows（双击即可）：**
```
C:\git\claude-config\scripts\start-work.bat
```

**PowerShell：**
```powershell
cd C:\git\claude-config
.\scripts\start-work.bat
```

### 同步脚本做了什么

| 步骤 | 操作 |
|------|------|
| 1 | 从 GitHub 拉取最新配置 |
| 2 | 同步 `.claude.json` → `%USERPROFILE%\.claude.json` |
| 3 | 同步 `settings.json` → `%USERPROFILE%\.claude\settings.json` |
| 4 | 同步 `CLAUDE.md` → `C:\git\CLAUDE.md` |
| 5 | 智能合并 settings.json（保留本地状态） |

> **重要**：不要在项目目录下创建 `.claude/settings.local.json`，这会覆盖全局权限配置，导致 MCP 工具报权限错误。

### 手动同步（如果脚本不可用）

```powershell
# 复制 .claude.json
Copy-Item C:\git\claude-config\.claude.json $env:USERPROFILE\.claude.json -Force

# 复制 settings.json
Copy-Item C:\git\claude-config\settings.json $env:USERPROFILE\.claude\settings.json -Force

# 复制 CLAUDE.md
Copy-Item C:\git\claude-config\CLAUDE.md C:\git\CLAUDE.md -Force
```

---

## 第五步：安装 MCP 服务器

配置同步后，部分 MCP 服务器可能需要手动安装 npm 包。

### MCP 管理命令

```powershell
# 列出已配置的 MCP 服务器
claude mcp list

# 查看帮助
claude mcp --help
```

---

### 安装常用 MCP 服务器

#### 1. Tavily MCP（网络搜索）

```powershell
npm install -g tavily-mcp
```

验证：
```powershell
tavily-mcp --help
```

#### 2. Playwright MCP（浏览器自动化）

```powershell
npm install -g @playwright/mcp
```

验证：
```powershell
playwright-mcp --help
```

#### 3. MarkItDown MCP（文档解析）

```powershell
npm install -g markitdown-mcp-npx
```

验证：
```powershell
markitdown-mcp-npx --help
```

---

### GitHub & Supabase MCP

这两个使用 HTTP 方式，不需要安装本地 npm 包，配置在 `.claude.json` 中已包含。

---

## 第六步：验证部署

### 6.1 验证 Claude Code

```powershell
claude --version
claude doctor
```

### 6.2 验证 MCP 服务器

启动 Claude Code，然后在对话中输入：
```
/mcp
```

应该看到：tavily、playwright、markitdown、github、supabase

### 6.3 验证 Skill / Plugin

在对话中输入：
```
/plugins
```

应该看到：simplify、tavily@tavily-ai-skills、claude-api

### 6.4 测试 Tavily 搜索

在对话中说：
```
搜索一下今天的新闻
```

如果能返回搜索结果，说明部署成功！

---

## 日常使用

### 开始工作前

```
双击运行：C:\git\claude-config\scripts\start-work.bat
```

### 结束工作后

```
双击运行：C:\git\claude-config\scripts\end-work.bat
```

### 对话关键词

| 关键词 | 功能 |
|--------|------|
| `gitinit` | 开始工作 - 拉取配置 + 显示当前主机名 |
| `gitarc` | 结束工作 - 推送配置 + 自动更新本地记忆 |

> **多终端记忆**: 每次 gitarc 会自动将本机的 MEMORY.md 同步到仓库，按主机名记录工作会话。

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

3. 手动添加到 PATH：
   ```powershell
   [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:USERPROFILE\.local\bin", "User")
   ```

---

### MCP 服务器不工作

1. 检查 MCP 命令是否能单独运行：
   ```powershell
   tavily-mcp --help
   ```

2. 检查 `%USERPROFILE%\.claude.json` 格式是否正确

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

## 附录

### 完整部署检查清单

- [ ] WinGet 已安装
- [ ] PowerShell 7 已安装
- [ ] Git 已安装并配置
- [ ] Node.js LTS 已安装
- [ ] Claude Code 原生版本已安装
- [ ] claude-config 仓库已克隆到 `C:\git\claude-config`
- [ ] start-work.bat 已运行，配置已同步
- [ ] Tavily MCP npm 包已安装
- [ ] Playwright MCP npm 包已安装
- [ ] MarkItDown MCP npm 包已安装
- [ ] Claude Code 能正常启动
- [ ] `/mcp` 能看到所有 MCP 服务器
- [ ] `/plugins` 能看到所有 Skill
- [ ] Tavily 搜索测试通过

---

## 相关链接

- Claude Code 官方文档：https://code.claude.com/docs
- MCP 规范：https://modelcontextprotocol.io
- claude-config 仓库：https://github.com/<your-github-username>/claude-config

