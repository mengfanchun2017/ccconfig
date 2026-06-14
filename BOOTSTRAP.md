# 新机器 Bootstrap 指南

> **从零起步，把一台新机器拉到 monitor 跑起来。**
> 不假设机器上有 claude、git、gh 任何东西。
> 全程 5-10 分钟，全手动。
> 走完一遍后，所有 ccconfig 配置会自动同步、monitor 自动 commit+push。

**适用**：
- 新装的 WSL2 / Ubuntu 22.04+ / Debian 12+
- 重装系统后恢复
- 公司新发的工作机

**不适用**：
- macOS（部分命令不同，看文末备注）
- 真机/裸金属（无 sudo 的情况，看文末备注）

---

## 阶段 0 — OS 基础（首次装的机器）

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

---

## 阶段 1 — 装 gh CLI

**Ubuntu 22.04+ / Debian 12+（apt 源有）**：

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

---

## 阶段 2 — 登录 GitHub

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
6. 粘贴 code → 授权 `<your-github-username>` 账号
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

---

## 阶段 3 — 克隆 ccconfig

**用 gh 克隆，不要用 git**（gh 知道用你的 token）：

```bash
# 创建工作目录
mkdir -p ~/git
cd ~/git

# 克隆
gh repo clone <your-github-username>/ccconfig

# 验证
cd ccconfig
ls
# 应该看到: init.sh init-ubuntu.sh monitor.sh README.md ...
git remote -v
# origin  https://github.com/<your-github-username>/ccconfig.git (fetch)
# origin  https://github.com/<your-github-username>/ccconfig.git (push)
```

> **坑点**：如果用 `git clone git@github.com:<your-github-username>/ccconfig.git`（SSH URL），
> 会因为没注册 SSH key 报 `Permission denied (publickey)`。
> 用 `gh repo clone` 走 HTTPS，全程无感。

---

## 阶段 4 — 一键初始化

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

**全程无输入**：因为 gh 已经登录，第 1 步的 `gh auth setup-git` 幂等跑过；
LLM 默认值是 deepseek；MCP 和 skills 都是已配置的服务器列表。

**会触发 sudo**（安装系统包时），提前准备好 sudo 免密或看着密码。

---

## 阶段 5 — 克隆所有项目

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

---

## 阶段 6 — 验证

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

去 https://github.com/<your-github-username>/ccconfig/commits/main 也能看到刚才的 commit。

---

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
| 启动 Claude | 直接输 `claude` |

---

## 旧终端快速恢复（已初始化过的机器）

> 适用场景：机器已经按上面走完一遍、ccconfig clone 在 `~/git/ccconfig`、gh 已登录、
> 但长时间没用 / 终端重启 / 切换到新会话后想恢复使用。

**不需要重跑 init.sh all**（会重装系统包）。只需要 5 步：

```bash
# 1. 拉最新
cd ~/git/ccconfig && git pull

# 2. 重建符号链接（CLAUDE.md / settings.json / rules / projects/）
bash setup-links.sh

# 3. 同步新 skill（symlink 自建 + npx skills 装第三方，幂等）
bash init-skill.sh sync

# 4. 状态检查（12 项）
bash status.sh

# 5. 启动 monitor（如果没在跑）
bash init-autostart.sh
# 或前台跑：./monitor.sh start
# 查看状态：./monitor.sh status
```

> **monitor push 行为**：监听 `~/git/` 下所有 git 仓库，触发条件是 inotify 检测到文件变化 → 120s debounce → **只 sync 真正改动的仓库**（不是全量扫）。所以同一个 repo 改两个文件不会重复 push，不同 repo 之间互不打扰。
> 跑 `./monitor.sh status` 看每个仓库的 `pending file(s)` 数；如果哪个仓库一直显示 "clean" 但你想强制推，临时改成 `conf/versions.json` 之类即可触发。

**`pullff` 暗号 = 上面 1+2 一步到位**：

```bash
bash sync.sh --pull    # = 强拉远程 + setup-links + skill sync
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
| 配置文件链接 | `bash setup-links.sh` |
| 核心依赖 | `apt install` 对应包 |
| auto-sync | `bash init-autostart.sh` |
| 最后推送 >24h | `systemctl --user start ccconfig-monitor` 或 `./monitor.sh start` |
| ppt-master 环境 | `bash option-ppt-master/init.sh` |
| 飞书 / OfficeCLI | 对应 `option-*/init.sh` 重装 |

---

## 常见坑

| 现象 | 原因 | 解决 |
|------|------|------|
| `gh: command not found` | 阶段 1 binary 没装到 PATH | `which gh`，没结果就 `source ~/.bashrc` 或手动加 `/usr/local/bin` |
| `gh auth login` 浏览器没自动开 | WSL 没装 `wslview` | 手动复制终端的 one-time code，访问 https://github.com/login/device |
| `gh repo clone` 报 404 | 没登录成功 / 账号不是 `<your-github-username>` 的协作者 | `gh auth status` 确认账号；如果不是协作者，联系 owner 加 |
| `init.sh all` 卡在 sudo | 密码没缓存 | 输密码，或配 sudo 免密（`echo "francis ALL=(ALL) NOPASSWD:ALL" \| sudo tee /etc/sudoers.d/francis`） |
| monitor 不推 | SSH key 没注册到 GitHub（这台机器以前的残留）| `gh auth setup-git`（init.sh 阶段 1 已自动做）；如还有问题 `git remote set-url origin https://<your-github-username>@github.com/<your-github-username>/ccconfig.git` |
| WSL 报 `Could not resolve hostname` | `/etc/hosts` 没本机 hostname | `echo "127.0.1.1 $(hostname)" \| sudo tee -a /etc/hosts` |

---

## macOS 备注

- 阶段 0：`brew install git curl`
- 阶段 1：`brew install gh`
- 阶段 2-6：都一样

## 无 sudo 备注

- 阶段 0-2 改成用户级安装：gh binary 装到 `~/bin/`
- 阶段 4 `init.sh all` 会失败（要装系统包），需要 sudo
- 替代：只跑 `bash init-skill.sh sync`（不需 sudo），手动配置 `~/.claude/` 符号链接
