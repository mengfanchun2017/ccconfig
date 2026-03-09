# Claude Code 配置同步仓库

用于在多台设备间同步 Claude Code 的配置。

## 包含的配置文件

| 文件 | 说明 |
|------|------|
| `.claude.json` | 全局配置（MCP 服务器等） |
| `settings.json` | 全局设置（插件、权限等） |
| `CLAUDE.md` | 权限白名单配置 |
| `memory/MEMORY.md` | 项目记忆文件 |

## 配置原则

- **MCP 服务器**：全部配置在全局 `~/.claude.json`
- **插件/技能**：全部配置在全局 `~/.claude/settings.json`
- **权限白名单**：放在项目根目录 `C:/git/CLAUDE.md`
- **不使用**：项目级 `.mcp.json`、项目级 `settings.json`/`settings.local.json`

## 新电脑完整设置步骤

### 前置条件

1. 确保已安装 Claude Code
2. 确保有 GitHub 访问权限
3. 确保仓库路径为 `C:/git/claude-config`

### 步骤 1: 克隆 claude-config 仓库

```bash
cd C:/git
git clone git@github.com:<your-github-username>/claude-config.git
```

如果网络问题无法 clone，可以手动下载文件并创建目录结构。

### 步骤 2: 备份当前配置（如果有）

**Windows (PowerShell):**
```powershell
# 备份用户级配置
Move-Item $env:USERPROFILE\.claude.json $env:USERPROFILE\.claude.json.backup
Move-Item $env:USERPROFILE\.claude\settings.json $env:USERPROFILE\.claude\settings.json.backup

# 备份项目级配置（如果存在）
if (Test-Path C:\git\.claude\settings.json) {
    Move-Item C:\git\.claude\settings.json C:\git\.claude\settings.json.backup
}
if (Test-Path C:\git\.claude\settings.local.json) {
    Move-Item C:\git\.claude\settings.local.json C:\git\.claude\settings.local.json.backup
}
```

**Git Bash:**
```bash
# 备份用户级配置
cp ~/.claude.json ~/.claude.json.backup
cp ~/.claude/settings.json ~/.claude/settings.json.backup

# 备份项目级配置（如果存在）
[ -f C:/git/.claude/settings.json ] && cp C:/git/.claude/settings.json C:/git/.claude/settings.json.backup
[ -f C:/git/.claude/settings.local.json ] && cp C:/git/.claude/settings.local.json C:/git/.claude/settings.local.json.backup
```

### 步骤 3: 复制全局配置文件

**Windows (PowerShell):**
```powershell
# 复制 .claude.json 到用户目录
Copy-Item C:\git\claude-config\.claude.json $env:USERPROFILE\.claude.json -Force

# 复制 settings.json 到用户 .claude 目录
Copy-Item C:\git\claude-config\settings.json $env:USERPROFILE\.claude\settings.json -Force
```

**Git Bash:**
```bash
# 复制 .claude.json 到用户目录
cp /c/git/claude-config/.claude.json ~/.claude.json

# 复制 settings.json 到用户 .claude 目录
cp /c/git/claude-config/settings.json ~/.claude/settings.json
```

### 步骤 4: 配置项目权限白名单

**Windows (PowerShell):**
```powershell
# 复制 CLAUDE.md 到 C:/git 根目录
Copy-Item C:\git\claude-config\CLAUDE.md C:\git\CLAUDE.md -Force

# 删除项目级配置文件（确保使用全局配置）
if (Test-Path C:\git\.claude\settings.json) {
    Remove-Item C:\git\.claude\settings.json -Force
}
if (Test-Path C:\git\.claude\settings.local.json) {
    Remove-Item C:\git\.claude\settings.local.json -Force
}
```

**Git Bash:**
```bash
# 复制 CLAUDE.md 到 C:/git 根目录
cp /c/git/claude-config/CLAUDE.md /c/git/CLAUDE.md

# 删除项目级配置文件（确保使用全局配置）
rm -f /c/git/.claude/settings.json
rm -f /c/git/.claude/settings.local.json
```

### 步骤 5: 设置 Memory 同步链接（推荐）

**重要**：使用符号链接可以让 Claude Code 直接读写 git 仓库中的 memory 文件，实现自动同步。

**Git Bash (推荐):**
```bash
# 备份现有的 memory（如果存在）
cd ~/.claude/projects/C--git
[ -d memory ] && mv memory memory.backup

# 创建符号链接指向 git 仓库中的 memory
ln -s /c/git/claude-config/memory memory

# 验证链接
ls -la memory
```

**Windows (PowerShell，需要管理员权限):**
```powershell
# 备份现有的 memory（如果存在）
cd $env:USERPROFILE\.claude\projects\C--git
if (Test-Path memory) {
    Rename-Item memory memory.backup
}

# 创建符号链接指向 git 仓库中的 memory
New-Item -ItemType SymbolicLink -Path memory -Target C:\git\claude-config\memory

# 验证链接
Get-Item memory
```

**如果符号链接无法使用，使用复制方式：**
```bash
# 复制 MEMORY.md
cp /c/git/claude-config/memory/MEMORY.md ~/.claude/projects/C--git/memory/MEMORY.md
```

### 步骤 6: 重启 Claude Code

完全退出 Claude Code 并重新启动，使配置生效。

### 验证配置

重启后，确认以下内容：

1. **MCP 服务器**：应该有 tavily、playwright、markitdown、github、supabase
2. **插件/技能**：应该有 tavily@tavily-ai-skills、simplify、claude-api
3. **权限模式**：应该使用全局 settings.json 中的配置
4. **Auto Memory**：对话中应该自动加载 MEMORY.md

---

## Memory 同步工作流

使用符号链接后，Memory 文件会自动同步。以下是多台电脑协同工作的流程：

### 在新电脑上开始工作前

1. **从 git 拉取最新版本**
```bash
cd C:\git\claude-config
git pull
```

2. **与自己的版本融合**
   - Claude Code 会自动加载 git 中的 MEMORY.md
   - 如果有冲突，手动编辑合并内容

### 日常工作中

- **直接编辑**：在对话中直接更新 MEMORY.md（通过 /memory 命令或手动编辑）
- **自动同步**：由于使用符号链接，修改会直接保存到 git 仓库目录

### 收尾时（准备切换电脑前）

1. **将更新的 memory 提交到 git**
```bash
cd C:\git\claude-config
git add memory/MEMORY.md
git commit -m "Update memory: [简要说明更新内容]"
git push
```

### 在另一台电脑上继续工作

1. **拉取最新的 memory**
```bash
cd C:\git\claude-config
git pull
```

2. **开始工作** - Claude Code 会自动加载最新的 MEMORY.md

---

## 日常配置更新流程

### 推送配置更新（在修改配置的电脑上）

**注意**：Memory 文件通过符号链接自动同步，无需额外复制。

```bash
cd C:\git\claude-config

# 1. 复制最新的配置到仓库
cp ~/.claude.json /c/git/claude-config/.claude.json
cp ~/.claude/settings.json /c/git/claude-config/settings.json
cp /c/git/CLAUDE.md /c/git/claude-config/CLAUDE.md

# 2. 提交并推送
git add .
git commit -m "Update config"
git push
```

### 拉取配置更新（在其他电脑上）

```bash
cd C:\git\claude-config
git pull

# 复制到对应位置（Memory 通过符号链接自动同步）
cp /c/git/claude-config/.claude.json ~/.claude.json
cp /c/git/claude-config/settings.json ~/.claude/settings.json
cp /c/git/claude-config/CLAUDE.md /c/git/CLAUDE.md
```

---

## 安全提示

⚠️ `.claude.json` 中包含 API Key，请确保：
- 使用私有 Git 仓库
- 不要推送到公开仓库
- 或者将 secrets 移到环境变量

## 回退

如果出问题，恢复备份：

**Windows (PowerShell):**
```powershell
Move-Item $env:USERPROFILE\.claude.json.backup $env:USERPROFILE\.claude.json -Force
Move-Item $env:USERPROFILE\.claude\settings.json.backup $env:USERPROFILE\.claude\settings.json -Force
```

**Git Bash:**
```bash
mv ~/.claude.json.backup ~/.claude.json
mv ~/.claude/settings.json.backup ~/.claude/settings.json
```
