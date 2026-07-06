# 新机器 Bootstrap 指南

> **从零起步，把一台新机器拉到 monitor 跑起来。**
> 不假设机器上有 claude、git、gh 任何东西。
> 全程 5-10 分钟，全手动。
> 走完一遍后，所有 ccconfig 配置会自动同步、monitor 自动 commit+push。

**适用**：
- 新装的 WSL2 / Ubuntu 24.04+ / Debian 12+
- 重装系统后恢复
- 公司新发的工作机

**不适用**：
- macOS（部分命令不同，看文末备注）
- 真机/裸金属（无 sudo 的情况，看文末备注）


## 阶段 0 — Windows 前置：WSL2 + Ubuntu 24.04

> 如果机器已经是 Linux，跳过本节直接到阶段 1。
>
> 本节目标：让不熟悉 WSL 的人也能完成环境搭建。每一步都带验证命令——看到 ✅ 才能继续。


### 1. 升级 PowerShell 7（推荐，最优先做）

Windows 自带 PowerShell 5.1 功能老旧。PowerShell 7 有更好的 JSON/HTTP 处理、`&&`/`||` 管道、跨平台兼容。cconfig 的 Windows 工具脚本也推荐在 PS7 下运行。

**安装**：以**管理员**身份打开 PowerShell，执行：

```powershell
# 用 winget 一键安装（Windows 11 自带 winget）
winget install --id Microsoft.PowerShell --source winget

# 如果 winget 报错 MSI 缓存丢失（Error 1612/1714/1603），用 ccconfig 自带脚本：
# 先下载脚本：Invoke-WebRequest -Uri "https://raw.githubusercontent.com/<your-github-username>/ccconfig/main/windows-tools/psupdate/psupdate.ps1" -OutFile "$env:TEMP\psupdate.ps1"
# 再安装：powershell -ExecutionPolicy Bypass -File "$env:TEMP\psupdate.ps1"
```

**验证**：

```powershell
pwsh --version
# 应该看到: PowerShell 7.x.x
```

**进入 PS7**：装完后，开始菜单会出现 **PowerShell 7**。后续所有 PowerShell 操作在 PS7 中执行。也可以在任何终端输入 `pwsh` 启动 PS7。

> PowerShell 7 和系统自带 5.1 共存，不会冲突。`pwsh.exe` = 新版，`powershell.exe` = 旧版。


### 2. 安装 WSL2 + Ubuntu 24.04 LTS

在 **PowerShell 7（管理员）** 中执行：

```powershell
wsl --install -d Ubuntu-24.04
```

这会自动启用 WSL 功能、安装内核、安装 Ubuntu 24.04 LTS。发行版在 WSL 中的名称为 `Ubuntu-24.04`（`wsl --list` 可查）。

**重启 Windows** 后，Ubuntu 会自动启动，提示创建 Linux 用户名和密码（牢记，这就是你的 sudo 密码）。

> `--install` 不带 `-d` 装默认版本。`-d Ubuntu-24.04` 锁定 24.04 LTS，apt 源成熟稳定。
>
> **国内用户**：下载慢用 `wsl --install -d Ubuntu-24.04 --web-download`。


### 3. 验证安装

```powershell
wsl --list --verbose
# 应该看到: Ubuntu-24.04  Running  2
```

> `Ubuntu-24.04` 是 WSL 发行版名称（`-d` 指定的），所有后续命令用它定位。新装 WSL 默认就是 V2，无需额外设置。

### 4. 进入 Ubuntu

```powershell
wsl -d Ubuntu-24.04
```

进去后验证系统版本：

```bash
lsb_release -a
# 应该看到: Ubuntu 24.04.x LTS
```

也可从开始菜单启动 **Ubuntu 24.04**。

> **推荐 Windows Terminal**：[Microsoft Store 免费安装](https://aka.ms/terminal)——多标签、GPU 加速渲染、UTF-8 完善。WSL 发行版自动出现在下拉菜单。


### 5. WSL 网络配置（推荐）

WSL 2 默认 NAT 网络，配成镜像模式后 Windows 和 WSL 共享 localhost，远程 SSH 等场景更顺畅。

在 **PowerShell（普通用户）** 中创建 `%USERPROFILE%\.wslconfig`：

```powershell
# 方法一：手动创建文件
notepad $env:USERPROFILE\.wslconfig
```

写入以下内容：

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=true
memory=8GB
```

> `memory=8GB` 限制 WSL 最大内存，按自己机器内存调整（16GB → 8GB，32GB → 16GB）。

**方法二**：克隆 ccconfig 后用自带脚本（阶段 4 之后）：

```powershell
powershell -ExecutionPolicy Bypass -File ".\windows-tools\wslconf\wslconfig.ps1"
```

**配置生效**：改 `.wslconfig` 后必须重启 WSL：

```powershell
wsl --shutdown
```

然后重新 `wsl -d Ubuntu-24.04` 进入 Ubuntu。


### 可选：WSL 备份 / 导出 / 导入

熟悉 WSL 基本操作后，建议定期备份 Ubuntu 环境，防止配置丢失。

**导出（备份）**：

```powershell
# 导出到 D 盘（压缩成 tar.gz）
wsl --export Ubuntu-24.04 D:\backup\ubuntu-24.04-backup.tar

# 检查备份文件大小
ls D:\backup\ubuntu-24.04-backup.tar
```

**导入（恢复/迁移）**：

```powershell
# 先注销原有发行版（谨慎！会删除原环境）
wsl --unregister Ubuntu-24.04

# 从备份文件导入（第一个参数是名称，可自定义，如 u24claudec）
wsl --import Ubuntu-24.04 D:\wsl\ubuntu D:\backup\ubuntu-24.04-backup.tar

# 设置默认用户（导入后 root 是默认用户）
Ubuntu-24.04 config --default-user <你的用户名>
```

**快速重置**（不需要备份，直接删掉重装）：

```powershell
wsl --unregister Ubuntu-24.04
wsl --install -d Ubuntu-24.04
```

> **日常使用**：备份文件放非系统盘（D:/E:），Windows 重装不会丢失。每月备份一次即可。


### 可选：WSL 版本升级

```powershell
# 检查当前 WSL 版本
wsl --version

# 升级到最新 WSL
wsl --update

# 升级后建议重启
wsl --shutdown
```


> **完成本节后**：WSL + Ubuntu 24.04 已就绪，PS7 已安装，网络已配置。进入 Ubuntu 继续阶段 1。


## 阶段 1 — OS 基础（首次装的机器）

```bash
# 1. 更新包索引
sudo apt update

# 2. 装 git / curl / wget / sudo（通常已有，但保险起见）
sudo apt install -y git curl wget sudo

# 3. 验证
git --version   # git version 2.34+ 即可
curl --version  # curl 7.81+ 即可
```

**WSL 专属**：如果是从 Windows Store 装的 Ubuntu，默认就有 sudo。如果 `sudo` 报
"unable to resolve host"，先 `sudo nano /etc/hosts` 把 hostname 加到 127.0.1.1。


## 阶段 2 — 装 gh CLI

**Ubuntu 24.04+ / Debian 12+（apt 源有）**：

```bash
# GitHub 官方 apt 源（一次性）
sudo apt install -y gh
```

**Ubuntu 20.04 / 其他（apt 源没有，直接下 binary）**：

```bash
# 看 https://github.com/cli/cli/releases/latest 的版本号，替换下面 v2.x.x
GH_VERSION="2.62.0"
curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz
tar -xzf /tmp/gh.tar.gz -C /tmp
sudo mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/gh
rm -rf /tmp/gh.tar.gz /tmp/gh_${GH_VERSION}_linux_amd64

# 验证
gh --version  # gh version 2.62.0
```

**装完会做这几件事**：
- `gh` 命令可用
- `gh auth login` 准备就绪
- `gh auth setup-git` 可配置 git credential helper


## 阶段 3 — 登录 GitHub

```bash
# 浏览器走 OAuth 协议
gh auth login --web --hostname github.com
```

**操作流程**：
1. 命令行会问 "What account do you want to log into?" → 选 **GitHub.com**
2. 问 "What is your preferred protocol?" → 选 **HTTPS**
3. 问 "How would you like to authenticate?" → 选 **Login with a web browser**
4. 终端打印一行 `! First copy your one-time code: ****-****`
5. 按回车打开浏览器（或手动访问 https://github.com/login/device）
6. 粘贴 code → 授权你的 GitHub 账号
7. 回到终端，命令完成

**验证**：

```bash
gh auth status
# 应该看到: ✓ Logged in to github.com as <你的账号>
```

**保存到哪里**：
- `~/.config/gh/hosts.yml` — 包含 `oauth_token: gho_xxx`（**不要外传**）
- 这就是 GitHub 发给"这台机器"的 device-scoped token
- 跨机器**不能直接复制**这文件（OAuth 带 device fingerprint），要在每台机器独立登录


## 阶段 4 — 克隆 ccconfig + 初始化 ccprivate

> **用户**：clone release 分支，一条命令建 ccprivate。
> **开发者**：先 Fork 再 clone 自己的 fork（main 跟踪最新代码）。

### 4a. 克隆 ccconfig

**用 gh 克隆，不要用 git**（gh 知道用你的 token）：

```bash
mkdir -p ~/git && cd ~/git

# 稳定版用 release 分支
gh repo clone <your-github-username>/ccconfig -- --branch release

# 开发者跟踪最新代码用 main：
# gh repo clone <your-github-username>/ccconfig
```

### 4b. 初始化 ccprivate（一条命令）

ccprivate 是私有配置仓库，存放 API key + Token + 个人配置。**一条命令完成**：

```bash
bash ~/git/ccconfig/bin/init-ccprivate.sh
```

脚本交互式收集信息（GitHub 账号、邮箱、LLM API Key），自动：
- 创建 `~/git/ccprivate/` 完整目录结构
- 生成 `conf/llm.json` + `conf/claude.json` + `conf/ubuntu.json`
- 生成 `link/CLAUDE.md` + `link/settings.json` + `setup.sh`
- 创建 GitHub 私有仓库并推送
- 建立所有 symlink（私有 + 公开）

> **已有 ccprivate？** 其他机器恢复时用 `bash ~/git/ccconfig/bin/init-ccprivate.sh --clone` 直接克隆。
>
> **手动控制**：需要自定义更多配置 → [docs/ccprivate-guide.md](docs/ccprivate-guide.md)。

### 4c. Windows 用户：WSL 网络配置（如果前置步骤 5 没做）

> Linux/macOS 用户跳过。

如果已在 Windows 前置步骤 5 手动创建了 `.wslconfig`，跳过本节。否则用 ccconfig 自带脚本：

```powershell
powershell -ExecutionPolicy Bypass -File ".\windows-tools\wslconf\wslconfig.ps1"
powershell -ExecutionPolicy Bypass -File ".\windows-tools\wslconf\wslconf.ps1"
wsl --shutdown
```

> 配完 WSL 会 shutdown，重新 `wsl -d Ubuntu-24.04` 进入 Ubuntu 后继续阶段 5。


## 阶段 5 — 系统初始化

```bash
cd ~/git/ccconfig
bash init.sh all
```

**这一步会自动做**（按顺序）：

| 步骤 | 脚本 | 做了什么 |
|------|------|----------|
| 1/3 | `init-ubuntu.sh` | git 配置 / gh 复用 / 装 Node / 装 uv / 装 Claude Code / 配置 LLM（从 conf/llm.json 读取当前后端）/ 配 SessionStart hook / 配 git credential helper / 配 auto-sync monitor |
| 2/3 | `init-mcp.sh` | 装并同步 MCP 服务器 |
| 3/3 | `init-skill.sh sync` | 链接自建 skill + npx skills 装第三方（conf 清单幂等，~2s）|

> **symlink 已在 3b 完成**，阶段 5 不需要再跑 `ccprivate/setup.sh`。

**全程无输入**：gh 已登录，LLM 默认值在 3b 已写入 conf/llm.json，MCP 和 skills 自动装。

**会触发 sudo**（安装系统包时），提前准备好 sudo 密码。


## 阶段 6 — 克隆所有项目

ccconfig 已就绪，接下来把其他项目也拉下来。用 `gh repo list` 自动发现：

```bash
gh repo list <your-github-username> --limit 50 --json name --jq '.[].name' | while read repo; do
    [ "$repo" = "ccconfig" ] && continue           # 已克隆
    [ -d "$HOME/git/$repo" ] && continue            # 已存在
    echo "克隆 $repo ..."
    gh repo clone "<your-github-username>/$repo" "$HOME/git/$repo"
done
```

**这一步自动跳过已存在的项目**，可以安全重跑。


## 阶段 7 — 验证

```bash
# 12 项状态检查
bash status.sh
```

**应该看到（精简版）**：
```
[1] 配置文件链接      ✅ settings.json, .config.json, CLAUDE.md, rules ...
[2] 核心依赖         ✅ git / bash / curl / node / python3 / pip3 / npm
[3] auto-sync        ✓ Monitor loop running
[4] 最后推送          (刚才 init 的某个时间)
[5] MEMORY 更新       ✅
[7] 飞书              (未配置，可选)
[7c] OfficeCLI        (未安装，可选)
```

**如果 auto-sync 没起来**：

```bash
# 手动启
bash init-autostart.sh

# 或临时跑前台（看日志）
./monitor.sh start
```

**端到端测试**（确认 monitor 推得动）：

```bash
# 在 ccconfig 目录随便改个文件
echo "# smoke test $(date)" >> /tmp/cc-smoke.md
cp /tmp/cc-smoke.md ~/git/ccconfig/tmp/smoke.md

# 等 2-3 分钟（monitor debounce 120s + push）
tail -f ~/git/ccconfig/logs/monitor.log
# 应该看到: OK committed → OK pushed → GitHub
```

去 `https://github.com/<your-github-username>/ccconfig/commits/main` 也能看到刚才的 commit。


## 日常使用约定

### Claude 启动位置

| 任务 | 命令 |
|------|------|
| 配置/环境维护 | `cd ~/git/ccconfig && claude` |
| 项目开发 | `cd ~/git/<project> && claude` |

> **不要从 `~/git/` 启动 Claude**：`~/git/` 不是 git repo，没有项目 CLAUDE.md，上下文不完整。
> ccconfig 是配置管理的「控制中心」— 改 rules、conf、CLAUDE.md、skills 都在这里。

### CLAUDE.md 分层（写什么去哪层）

| 层级 | 文件 | 写什么 |
|------|------|--------|
| 用户级 | `~/CLAUDE.md` | 编码规范、行为偏好、权限说明、自然语言触发、允许命令 |
| 项目级 | `<project>/CLAUDE.md` | 项目架构、暗号、常用命令、版本管理、项目特有约束 |

> ccconfig 不记录项目级 memory。架构决策在用户级 memory。

## 完成 — 接下来干嘛

机器已经全功能：

| 操作 | 命令 |
|------|------|
| 改文件自动推 | 默认行为，monitor 在跑 |
| 看状态 | `bash status.sh` |
| 装可选组件 | `bash init.sh` → 7) 可选组件 |
| 强制拉远程 | `bash sync.sh --pull`（暗号 `pullff`） |
| 切 LLM 后端 | `bash init.sh` → 1) → 2) |
| 月度升级 | `bash update.sh all` |
| 启动 Claude | `cd ~/git/ccconfig && claude`（配置）或 `cd ~/git/<project> && claude`（开发） |


## 旧终端快速恢复（已初始化过的机器）

> 适用场景：机器已经按上面走完一遍、ccconfig + ccprivate 都在 `~/git/`、gh 已登录、
> 但长时间没用 / 终端重启 / 切换到新会话后想恢复使用。

**不需要重跑 init.sh all**（会重装系统包）。只需要 4 步：

```bash
# 1. 拉最新
cd ~/git/cconfig && git pull
cd ~/git/ccprivate && git pull

# 2. 重建所有符号链接（私有 + 公开一步到位）
bash ~/git/ccprivate/setup.sh

# 3. 状态检查
cd ~/git/ccconfig && bash status.sh

# 4. 启动 monitor（如果没在跑）
bash init-autostart.sh
# 或前台跑：./monitor.sh start
# 查看状态：./monitor.sh status
```

> **monitor push 行为**：监听 `~/git/` 下所有 git 仓库，触发条件是 inotify 检测到文件变化 → 120s debounce → **只 sync 真正改动的仓库**（不是全量扫）。所以同一个 repo 改两个文件不会重复 push，不同 repo 之间互不打扰。
> 跑 `./monitor.sh status` 看每个仓库的 `pending file(s)` 数；如果哪个仓库一直显示 "clean" 但你想强制推，临时改成 `conf/versions.json` 之类即可触发。

**`pullff` 暗号 = 上面 1+2 一步到位**：

```bash
cd ~/git/cconfig && git pull && cd ~/git/ccprivate && git pull && bash ~/git/ccprivate/setup.sh
```

### 常见"看着有问题"但实际正常

| 现象 | 原因 | 处理 |
|------|------|------|
| `/skills` 菜单看不到新加的 skill | Claude Code 启动时缓存 skill 列表，**不重扫** | **新开一个 session**（`claude` 新窗口或 `claude -c`） |
| `bash init-skill.sh sync` 显示"本地已有，跳过" | `~/.claude/skills/<name>` 是真目录不是 symlink | `rm -rf ~/.claude/skills/<name>` 再跑 sync |
| `./monitor.sh status` 显示 stopped | systemd user service 没起来 | `systemctl --user status ccconfig-monitor.service` 看原因；`bash init-autostart.sh` 重装 |
| LLM 切了但 Claude 还是用旧的 | `conf/llm.json` 改了但 settings.json 没更新 | `bash init-llm.sh <backend>` 重写 settings.json |
| 飞书操作报 token 过期 | 跨账号 / 长效 token 过期 | 重新跑 `bash option-bridge/init.sh` |

### 状态检查发现问题的应对

`bash status.sh` 12 项检查，**任何一项 ✗ 都先看该项的命令**：

| 失败项 | 修命令 |
|--------|--------|
| 配置文件链接 | `bash ~/git/ccprivate/setup.sh` |
| 核心依赖 | `apt install` 对应包 |
| auto-sync | `bash init-autostart.sh` |
| 最后推送 >24h | `systemctl --user start ccconfig-monitor` 或 `./monitor.sh start` |
| ppt-master 环境 | `bash option-ppt-master/init.sh` |
| 飞书 / OfficeCLI | 对应 `option-*/init.sh` 重装 |


## 常见坑

| 现象 | 原因 | 解决 |
|------|------|------|
| `gh: command not found` | 阶段 2 binary 没装到 PATH | `which gh`，没结果就 `source ~/.bashrc` 或手动加 `/usr/local/bin` |
| `gh auth login` 浏览器没自动开 | WSL 没装 `wslview` | 手动复制终端的 one-time code，访问 https://github.com/login/device |
| `gh repo clone` 报 404 | 没登录成功 / 账号不是仓库协作者 | `gh auth status` 确认账号；如果不是协作者，联系 owner 加 |
| `init.sh all` 卡在 sudo | 密码没缓存 | 输密码，或配 sudo 免密（`echo "<your-username> ALL=(ALL) NOPASSWD:ALL" \| sudo tee /etc/sudoers.d/<your-username>`） |
| monitor 不推 | SSH key 没注册到 GitHub | `gh auth setup-git`（init.sh 已自动做）；如还有问题 `git remote set-url origin https://<your-username>@github.com/<your-username>/ccconfig.git` |
| WSL 报 `Could not resolve hostname` | `/etc/hosts` 没本机 hostname | `echo "127.0.1.1 $(hostname)" \| sudo tee -a /etc/hosts` |
| WSL 内存占用过高 | WSL 2 默认占 50% 主机内存 | 在 `%USERPROFILE%\.wslconfig` 加 `memory=8GB`（见 windows-tools/wslconf/） |
| WSL 里 `code .` 打不开 VSCode | 没装 WSL 扩展 | 在 VSCode 装 "WSL" 扩展；或直接用 `code` 命令（Windows PATH 注入） |
| `claude` 命令不存在 | npm 全局安装后 PATH 没刷新 | `hash -r` 或新开终端；还不行就 `export PATH="$HOME/.local/bin:$PATH"` |
| npm 全局安装权限错误 | npm 全局目录需要 sudo | ccconfig 的 `init-ubuntu.sh` 已将 Node 装到 `~/.local/`，无此问题；如手动装过 Node，跑 `npm config set prefix ~/.local` |
| `wsl --install` 报 0x8007019e | BIOS 没开虚拟化 | 进 BIOS 启用 Intel VT-x / AMD SVM |
| `wsl --install` 报 0x80370102 | WSL 2 内核没装 | `wsl --update` 升级 WSL 内核 |
| init-ubuntu.sh 中途失败 | 某个子步骤挂了 | init-ubuntu.sh 内部子步骤有容错，看报错哪一步；重新跑 `bash init-ubuntu.sh`（多数步骤幂等） |
| 符号链接在 Windows 文件系统不工作 | WSL 和 Windows 文件系统隔离 | 所有文件放 WSL 原生文件系统（`~/git/`），不要放 `/mnt/c/` |

## Windows 工具

ccconfig 的 `windows-tools/` 目录提供 Windows/WSL 互操作脚本，在 PowerShell 中运行：

| 工具 | 用途 | 命令 |
|------|------|------|
| `wslconf/` | WSL 配置（网络镜像 + 关 PATH 注入） | `powershell -File .\windows-tools\wslconf\wslconfig.ps1` |
| `psupdate/` | PowerShell 7 升级（绕过 winget bug） | 管理员 PowerShell 执行 `psupdate.ps1` |
| `music-convert/` | 网易云 NCM 解密 | `powershell -File .\windows-tools\music-convert\convert.ps1` |

> WSL 里调 Win 端脚本的标准模式：`powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w <path-to-ps1>)"`


## macOS 备注

- 阶段 1：`brew install git curl`
- 阶段 2：`brew install gh`
- 阶段 3-6：都一样

## 无 sudo 备注

- 阶段 1-2 改成用户级安装：gh binary 装到 `~/bin/`
- 阶段 5 `init.sh all` 会失败（要装系统包），需要 sudo
- 替代：只跑 `bash init-skill.sh sync`（不需 sudo），手动配置 `~/.claude/` 符号链接
