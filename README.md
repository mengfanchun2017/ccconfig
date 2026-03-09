# Claude Code 配置同步仓库

用于在多台设备间同步 Claude Code 的配置。

## 包含的配置文件

| 文件 | 说明 |
|------|------|
| `.claude.json` | 全局配置（MCP 服务器等） |
| `settings.json` | 全局设置（插件、权限等） |
| `CLAUDE.md` | 权限白名单配置 |

## 安装步骤

### Windows (PowerShell，需要管理员权限)

```powershell
# 1. 备份原配置
Move-Item $env:USERPROFILE\.claude.json $env:USERPROFILE\.claude.json.backup
Move-Item $env:USERPROFILE\.claude\settings.json $env:USERPROFILE\.claude\settings.json.backup

# 2. 创建符号链接（将此路径改为你实际的仓库路径）
New-Item -ItemType SymbolicLink -Path $env:USERPROFILE\.claude.json -Target C:\git\claude-config\.claude.json
New-Item -ItemType SymbolicLink -Path $env:USERPROFILE\.claude\settings.json -Target C:\git\claude-config\settings.json

# 3. 复制 CLAUDE.md 到你的项目根目录（如需要）
# Copy-Item C:\git\claude-config\CLAUDE.md C:\git\CLAUDE.md
```

### WSL / Linux / Mac

```bash
# 1. 备份原配置
mv ~/.claude.json ~/.claude.json.backup
mv ~/.claude/settings.json ~/.claude/settings.json.backup

# 2. 创建符号链接（将此路径改为你实际的仓库路径）
ln -s /mnt/c/git/claude-config/.claude.json ~/.claude.json
ln -s /mnt/c/git/claude-config/settings.json ~/.claude/settings.json
```

## 同步流程

### 推送配置更新

```bash
cd C:\git\claude-config
git add .
git commit -m "Update config"
git push
```

### 拉取配置更新

```bash
cd C:\git\claude-config
git pull
```

## 安全提示

⚠️ `.claude.json` 中包含 API Key，请确保：
- 使用私有 Git 仓库
- 不要推送到公开仓库
- 或者将 secrets 移到环境变量

## 回退

如果出问题，恢复备份：

```powershell
# Windows
Move-Item $env:USERPROFILE\.claude.json.backup $env:USERPROFILE\.claude.json
Move-Item $env:USERPROFILE\.claude\settings.json.backup $env:USERPROFILE\.claude\settings.json
```
