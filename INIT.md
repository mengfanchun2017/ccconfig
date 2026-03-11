# Claude Code 全新安装指南

本指南用于在一台全新的 Windows 11 电脑上从零开始安装和配置 Claude Code。

---

## 目录

1. [为什么选择原生安装器](#为什么选择原生安装器)
2. [前置依赖安装](#前置依赖安装)
3. [安装 Claude Code（原生版本）](#安装-claude-code原生版本)
4. [安装 MCP 服务器](#安装-mcp-服务器)
5. [安装 Skill（插件）](#安装-skill插件)
6. [从 claude-config 同步配置](#从-claude-config-同步配置)
7. [验证安装](#验证安装)

---

## 为什么选择原生安装器

### npm/bun 安装方式已废弃

官方不再推荐使用 `npm install -g @anthropic-ai/claude-code` 或 bun 安装方式，原因如下：

| 对比项 | npm/bun 版本 | 原生安装器 |
|--------|--------------|-----------|
| **Node.js 依赖** | 需要安装 Node.js | 不需要，独立二进制文件 |
| **稳定性** | 可能受 Node.js 版本影响 | 更稳定，无依赖冲突 |
| **自动更新** | 更新机制不够稳定 | 自带更可靠的自动更新 |
| **性能** | 稍慢（通过 Node.js 启动） | 更快（直接运行） |

### 官方推荐的安装方式

| 平台 | 推荐方式 |
|------|---------|
| Windows | WinGet 或 PowerShell 脚本 |
| macOS | Homebrew 或 Shell 脚本 |
| Linux | Shell 脚本 |

---

## 前置依赖安装

### 1. 检查并更新 PowerShell（推荐安装 PowerShell 7）

Windows 11 自带 PowerShell 5，但推荐安装 PowerShell 7（跨平台版本）。

**检查当前 PowerShell 版本：**
```powershell
$PSVersionTable.PSVersion
```

**如果版本 < 7，安装 PowerShell 7：**

方式一：使用 WinGet（推荐）
```powershell
winget install Microsoft.PowerShell
```

方式二：直接下载安装
访问 https://aka.ms/powershell-release?tag=stable 下载 MSI 安装包

**验证安装：**
```powershell
pwsh --version
```

---

### 2. 安装 Git

```powershell
winget install Git.Git
```

验证安装：
```powershell
git --version
```

**配置 Git（必需）：**
```powershell
git config --global user.name "你的名字"
git config --global user.email "你的邮箱"
```

**配置 Git 代理（如果需要）：**
```powershell
git config --global http.proxy http://127.0.0.1:7897
git config --global https.proxy http://127.0.0.1:7897
```

---

### 3. 安装 Node.js（用于 MCP 服务器）

很多 MCP 服务器需要 Node.js 运行时。

```powershell
winget install OpenJS.NodeJS.LTS
```

验证安装：
```powershell
node --version
npm --version
```

---

### 4. 安装 Bun（可选，用于某些 MCP 服务器）

```powershell
powershell -c "irm bun.sh/install.ps1 | iex"
```

验证安装：
```powershell
bun --version
```

---

### 5. 安装 WinGet（如果没有）

Windows 11 通常自带 WinGet，如果没有：

1. 打开 Microsoft Store
2. 搜索 "App Installer"
3. 安装或更新

验证：
```powershell
winget --version
```

---

## 安装 Claude Code（原生版本）

### 方式一：使用 WinGet（最推荐）

```powershell
winget install Anthropic.ClaudeCode
```

### 方式二：使用 PowerShell 脚本

```powershell
irm https://claude.ai/install.ps1 | iex
```

### 验证安装

```powershell
claude --version
```

应该输出类似：`2.1.63 (Claude Code)`

### 首次启动

```powershell
claude
```

按照提示完成认证。

---

## 安装 MCP 服务器

MCP (Model Context Protocol) 服务器为 Claude Code 提供额外能力。

### MCP 服务器安装方式

**使用 `claude mcp` 命令管理：**

```powershell
# 查看可用命令
claude mcp --help

# 列出已安装的 MCP 服务器
claude mcp list
```

---

### 示例：安装 Tavily MCP（网络搜索）

Tavily 提供网络搜索能力。

#### 1. 获取 Tavily API Key

访问 https://tavily.com 注册并获取 API Key。

#### 2. 安装 Tavily MCP

```powershell
# 方式一：使用 claude mcp 安装（推荐）
claude mcp install tavily

# 方式二：手动全局安装 npm 包
npm install -g @tavily/mcp-server
```

#### 3. 配置 Tavily MCP

编辑 `~/.claude.json` 文件，添加：

```json
{
  "mcpServers": {
    "tavily": {
      "command": "tavily-mcp",
      "args": [],
      "env": {
        "TAVILY_API_KEY": "你的-tavily-api-key"
      },
      "type": "stdio"
    }
  }
}
```

#### 4. 重启 Claude Code

完全退出并重新启动 Claude Code。

---

### 其他常用 MCP 服务器

#### Playwright MCP（浏览器自动化）

```powershell
npm install -g @playwright/mcp
```

配置（~/.claude.json）：
```json
{
  "playwright": {
    "command": "playwright-mcp",
    "args": [],
    "env": {
      "PLAYWRIGHT_MCP_BROWSER": "msedge"
    },
    "type": "stdio"
  }
}
```

#### MarkItDown MCP（文档解析）

```powershell
npm install -g markitdown-mcp-npx
```

配置（~/.claude.json）：
```json
{
  "markitdown": {
    "command": "markitdown-mcp-npx",
    "args": [],
    "type": "stdio"
  }
}
```

#### GitHub MCP

GitHub MCP 使用 HTTP 方式，不需要安装本地包：

```json
{
  "github": {
    "url": "https://api.githubcopilot.com/mcp/",
    "headers": {
      "Authorization": "Bearer github_pat_你的-token"
    },
    "type": "http"
  }
}
```

#### Supabase MCP

```json
{
  "supabase": {
    "url": "https://mcp.supabase.com/mcp?project_ref=你的-project-ref",
    "type": "http"
  }
}
```

---

## 安装 Skill（插件）

Skill 是 Claude Code 的增强插件。

### Skill 管理命令

```powershell
# 查看可用命令
claude plugin --help

# 列出已安装的插件
claude plugin list

# 搜索插件
claude plugin search 关键词
```

---

### 示例：安装 Tavily Skill

#### 1. 添加插件市场（如果需要）

编辑 `~/.claude.json`：
```json
{
  "extraKnownMarketplaces": {
    "tavily-ai-skills": {
      "source": {
        "repo": "tavily-ai/skills",
        "source": "github"
      }
    }
  }
}
```

#### 2. 安装 Skill

```powershell
claude plugin install tavily@tavily-ai-skills
```

#### 3. 启用 Skill

编辑 `~/.claude.json`：
```json
{
  "enabledPlugins": {
    "tavily@tavily-ai-skills": true,
    "simplify": true,
    "claude-api": true
  }
}
```

---

## 从 claude-config 同步配置

如果你已有配置仓库，可以直接同步。

### 1. 克隆 claude-config 仓库

```powershell
cd C:\
mkdir git
cd git
git clone git@github.com:<your-github-username>/claude-config.git
```

### 2. 运行同步脚本

**Windows（双击）：**
```
scripts\start-work.bat
```

**PowerShell：**
```powershell
cd C:\git\claude-config
scripts\start-work.bat
```

这个脚本会自动：
1. 拉取最新配置
2. 同步 `.claude.json` 到用户目录
3. 同步 `settings.json` 到用户目录
4. 同步 `CLAUDE.md` 到项目目录

### 3. 手动同步（如果脚本不可用）

```powershell
# 复制 .claude.json
Copy-Item C:\git\claude-config\.claude.json $env:USERPROFILE\.claude.json -Force

# 复制 settings.json
Copy-Item C:\git\claude-config\settings.json $env:USERPROFILE\.claude\settings.json -Force

# 复制 CLAUDE.md
Copy-Item C:\git\claude-config\CLAUDE.md C:\git\CLAUDE.md -Force
```

---

## 验证安装

### 1. 验证 Claude Code

```powershell
claude --version
claude doctor
```

### 2. 验证 MCP 服务器

启动 Claude Code 后，检查 MCP 服务器是否正常加载：

```
在对话中输入：/mcp
```

应该看到已配置的 MCP 服务器列表。

### 3. 验证 Skill

```
在对话中输入：/plugins
```

应该看到已启用的 Skill 列表。

### 4. 测试 Tavily 搜索

在对话中说："搜索一下今天的新闻"

如果能返回搜索结果，说明 Tavily MCP 工作正常。

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

在与 Claude Code 对话时，可以使用：

| 关键词 | 功能 |
|--------|------|
| `gitinit` | 开始工作 - 拉取配置 |
| `gitarc` | 结束工作 - 推送配置 |

---

## 故障排查

### Claude Code 命令找不到

1. 检查是否在 PATH 中：
   ```powershell
   where.exe claude
   ```

2. 原生版本默认安装位置：
   - `%USERPROFILE%\.local\bin\claude.exe`

3. 手动添加到 PATH：
   ```powershell
   [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:USERPROFILE\.local\bin", "User")
   ```

### MCP 服务器不工作

1. 检查 MCP 命令是否能单独运行：
   ```powershell
   tavily-mcp --help
   ```

2. 检查 `~/.claude.json` 配置格式是否正确（使用 JSON 验证工具）

3. 查看 Claude Code 日志：
   ```powershell
   # 日志位置
   %USERPROFILE%\.claude\logs\
   ```

### 权限问题

确保 `CLAUDE.md` 在项目根目录（`C:\git\CLAUDE.md`），并且包含必要的权限配置。

---

## 附录：完整配置文件示例

### ~/.claude.json 示例

```json
{
  "enabledPlugins": {
    "claude-api": true,
    "simplify": true,
    "tavily@tavily-ai-skills": true
  },
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "your-token",
    "ANTHROPIC_BASE_URL": "https://api.anthropic.com"
  },
  "extraKnownMarketplaces": {
    "tavily-ai-skills": {
      "source": {
        "repo": "tavily-ai/skills",
        "source": "github"
      }
    }
  },
  "mcpServers": {
    "tavily": {
      "command": "tavily-mcp",
      "args": [],
      "env": {
        "TAVILY_API_KEY": "tvly-dev-xxx"
      },
      "type": "stdio"
    },
    "playwright": {
      "command": "playwright-mcp",
      "args": [],
      "env": {
        "PLAYWRIGHT_MCP_BROWSER": "msedge"
      },
      "type": "stdio"
    },
    "markitdown": {
      "command": "markitdown-mcp-npx",
      "args": [],
      "type": "stdio"
    },
    "github": {
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer github_pat_xxx"
      },
      "type": "http"
    }
  },
  "permissions": {
    "allow": [
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep",
      "Bash(*)"
    ],
    "deny": []
  }
}
```

---

## 相关链接

- Claude Code 官方文档：https://code.claude.com/docs
- MCP 规范：https://modelcontextprotocol.io
- Tavily：https://tavily.com
- claude-config 仓库：https://github.com/<your-github-username>/claude-config

