# Claude Code 配置同步仓库

用于在多台设备间同步 Claude Code 的配置。

---

## 📋 目录

1. [快速开始（日常使用）](#快速开始日常使用)
2. [全新电脑部署](#全新电脑部署)
3. [核心使用规范](#核心使用规范)
4. [配置文件说明](#配置文件说明)
5. [Git 代理配置](#git-代理配置)
6. [安全提示](#安全提示)

---

## 🚀 快速开始（日常使用）

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

---

## 🎯 Claude Code 对话关键词

在与 Claude Code 对话时，可以直接使用以下关键词：

| 关键词 | 功能 | 说明 |
|--------|------|------|
| `gitinit` | 开始工作 - 拉取配置 | 从 GitHub 拉取最新配置并同步到本地 |
| `gitarc` | 结束工作 - 推送配置 | 收集本地配置并推送到 GitHub |

**同步内容包括：**
- `.claude.json` - 全局 MCP 配置
- `settings.json` - 全局设置、插件、权限
- `CLAUDE.md` - 权限白名单
- `memory/MEMORY.md` - 项目记忆
- 其他所有仓库内容

---

## 💻 全新电脑部署

### 完整流程

请参考 [INIT.md](./INIT.md) 进行全新环境部署。

快速预览：
```
1. 环境准备 → PowerShell 7 + Git + Node.js + WinGet
2. 安装 Claude → 原生版本（WinGet / PowerShell）
3. 克隆配置 → git clone claude-config
4. 同步配置 → start-work.bat
5. 安装 MCP → 使用 claude mcp 命令
6. 验证部署 → 检查 Claude + MCP + Skill
```

---

## 📐 核心使用规范

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
> - MCP 配置已包含在 `.claude.json` 中，同步后即可使用

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

- **MCP 服务器**：全部配置在全局 `~/.claude.json`
- **插件/技能**：全部配置在全局 `~/.claude/settings.json`
- **权限白名单**：放在项目根目录 `C:/git/CLAUDE.md`
- **不使用**：项目级 `.mcp.json`、项目级 `settings.json`/`settings.local.json`

---

## 📁 配置文件说明

| 文件 | 说明 |
|------|------|
| `.claude.json` | 全局配置（MCP 服务器、插件等） |
| `settings.json` | 全局设置（权限、使用统计等） |
| `CLAUDE.md` | 权限白名单配置 |
| `INIT.md` | 全新环境部署指南 |
| `memory/MEMORY.md` | 项目记忆文件 |

---

## 🔧 settings.json 智能同步

`settings.json` 包含两部分内容，智能同步脚本会分别处理：

### 同步的配置部分（跨设备共享）

| 配置项 | 说明 |
|--------|------|
| `env` | 环境变量配置 |
| `permissions` | 权限配置 |
| `model` | 默认模型配置 |
| `extraKnownMarketplaces` | 额外的插件市场 |
| `enabledPlugins` | 启用的插件/技能 |
| `mcpServers` | MCP 服务器配置 |

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

## 🌐 Git 代理配置（必需）

所有三台电脑都需要配置 Git 走代理：

```bash
git config --global http.proxy http://127.0.0.1:7897
git config --global https.proxy http://127.0.0.1:7897
```

- **代理工具**: Clash Verge
- **代理端口**: 7897
- **注意**: VPN 需要常开

---

## 🔒 安全提示

⚠️ `.claude.json` 中包含 API Key，请确保：
- 使用私有 Git 仓库
- 不要推送到公开仓库
- 或者将 secrets 移到环境变量

---

## 📚 相关文档

- [INIT.md](./INIT.md) - 全新环境部署完整指南
- Claude Code 官方文档：https://code.claude.com/docs
- MCP 规范：https://modelcontextprotocol.io

