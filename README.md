# ccconfig — Claude Code 配置中枢

> 统一管理 Claude Code 配置。Git 跨设备同步。一键恢复到新终端。

## 概述

ccconfig 管理 Claude Code 配置的完整生命周期：

- **环境**：Ubuntu/WSL 一键初始化
- **配置**：LLM 后端、MCP 服务器、API key 单一真相源
- **同步**：文件监听 + 自动 git commit/push，覆盖 `~/git/` 下所有仓库
- **Skills**：8 自建（symlink）+ 2 外部 monorepo 聚合（marketplace auto install）
- **Rules**：按路径条件加载（编码、git、python、搜索、飞书、godot）
- **Agents**：意图路由 agent（assistant、feishucreate、learnchinese）
- **可选**：飞书 Bridge、OfficeCLI、PPT 生成、Vessel 浏览器、远程 SSH

## 架构

```
~/.claude/  (符号链接)  ←──  ccconfig/link/  (源，git 跟踪)
    ├── settings.json        ├── settings.json
    ├── .config.json         ├── .config.json
    ├── rules/               ├── rules/         (8 个规则)
    ├── skills/              ├── skills/        (8 自建 + README)
    ├── agents/              ├── agents/        (4 个 agent)
    └── projects/memory/     └── projects/memory/  (跨 session memory)

~/CLAUDE.md  ←──  ccconfig/link/CLAUDE.md
```

```
ccconfig/
├── init.sh                   # 入口（交互式二级菜单）
├── init-ubuntu.sh            # Ubuntu/WSL 全环境初始化
├── init-llm.sh               # LLM 后端切换
├── init-mcp.sh               # MCP 服务器管理
├── init-skill.sh             # Skills 同步管理
├── init-autostart.sh         # auto-sync systemd 服务
├── update.sh                 # 月度组件升级（9 个组件）
│
├── status.sh                 # 状态检查（12 项）
├── monitor.sh                # 多仓库文件监听 + 自动 git 同步
├── sync.sh                   # 多仓库智能同步（云端↔本地）
├── setup-links.sh            # 重建 ~/.claude/ 符号链接
├── deps-check.sh             # 依赖完整性检查（CLI + JSON）
│
├── conf/                     # 配置（单一真相源）
│   ├── claude.json           # MCP 服务器、API key
│   ├── feishu.json           # 飞书统一配置（lark-cli + cc-connect）
│   ├── llm.json              # LLM 多后端配置
│   ├── ubuntu.json           # Git 用户信息
│   ├── versions.json         # 组件版本 + pin
│   └── python-requirements.txt  # Python 包清单
│
├── lib/                      # 共享库
│   └── path-helper.sh        # 动态路径解析（4 级回退）
│
├── link/                     # → ~/.claude/ 符号链接源
│   ├── CLAUDE.md             # AI 行为指南
│   ├── settings.json         # 权限 + MCP + hooks
│   ├── .config.json          # 环境 + 状态
│   ├── rules/                # 条件规则（按路径加载）
│   ├── agents/               # 意图路由 agent
│   ├── skills/               # 8 自建（f-* + f-logme 私有 + skill-template）
│   └── projects/             # 每个项目的 MEMORY.md
│
├── share/                    # 公开分享模块
│   └── setup.sh              # 引导式 onboarding 向导
│
├── option-bridge/            # 可选：飞书消息 Bridge
│   ├── init.sh               # lark-cli + cc-connect 安装器
│   ├── lark-switch.sh        # 多账号切换
│   ├── bot-status.sh         # bot 状态查看
│   └── mcp-bridge/           # 可选 MCP 消息桥
│
├── option-officecli/         # 可选：OfficeCLI（AI 原生 Office 工具）
│   └── init.sh               # 安装器 + 状态 + 升级
│
├── option-ppt-master/        # 可选：PPT 生成（python-pptx）
│   └── init.sh               # 克隆仓库 + 装依赖
│
├── option-vessel/            # 可选：Vessel AI 浏览器
│   └── init.sh               # 安装器 + MCP 注册
│
├── remote/                   # 远程访问（Tailscale + SSH + tmux）
│   ├── server/               # SSH Server + tmux 配置
│   └── client/               # Windows Tailscale 配置
│
├── windows/                  # Windows/WSL 互操作
│
├── LICENSE                   # MIT
├── BOOTSTRAP.md              # 新机器 0→1 拉起指南（gh auth + clone + init.sh all）
├── CHANGELOG.md              # 变更历史
├── CONTRIBUTING.md           # 贡献指南
└── .editorconfig             # 编辑器设置
```

## 快速开始

> **新机器？** 从零开始（包括装 gh、登录、克隆）→ 看 [BOOTSTRAP.md](BOOTSTRAP.md)。
> **已初始化过的机器** → 直接：

```bash
# 拉最新
cd ~/git/ccconfig && git pull

# 交互式菜单
bash init.sh

# 或一键全初始化（Ubuntu + LLM + MCP + Skills + Python 包）
bash init.sh all

# 状态检查
bash status.sh
```

## 核心命令

| 命令 | 用途 |
|---------|---------|
| `bash init.sh` | 交互式菜单（环境、远程、MCP、skill、工具） |
| `bash init.sh all` | 一键全初始化 |
| `bash status.sh` | 完整状态检查（12 项） |
| `bash deps-check.sh` | 依赖完整性检查 |
| `bash update.sh all` | 月度组件升级 |
| `bash monitor.sh start` | 启动 auto-sync 守护进程 |
| `bash monitor.sh status` | 同步守护进程状态 |
| `bash monitor.sh log` | 最近同步日志 |
| `bash setup-links.sh` | 重建 ~/.claude/ 符号链接 |
| `bash sync.sh --pull` | 强拉远程（暗号 `pullff`） |

## 状态检查覆盖

`status.sh` 每次 Claude Code session 启动时做 12 项检查：

1. 配置文件链接（settings.json、.config.json、CLAUDE.md、MEMORY.md、rules、commands）
2. 核心依赖（git、bash、curl）
3. auto-sync 守护进程 + systemd 服务
4. GitHub 最后推送日期
5. MEMORY.md 最后更新
6. ppt-master 环境（仓库、python-pptx、cairosvg）
7. 飞书（lark-cli：安装、配置、auth、bridge、bot）
8. Vessel AI 浏览器（安装、进程、token、MCP）
9. OfficeCLI（安装、MCP 注册）
10. MCP 服务器（并行健康检查，24h 缓存）
11. 远程访问（SSH、端口、WSL 网络模式、Tailscale）
12. Option 组件自动发现（含 4 个 option-*）

## 依赖检查

`deps-check.sh` 验证所有工具和包依赖：

```bash
bash deps-check.sh              # 完整检查
bash deps-check.sh --required   # 仅必要依赖
bash deps-check.sh --json       # JSON 输出（脚本调用）
```

检查项：git、bash、curl、node、python3、pip3、npm、gh、claude、inotify-tools、systemd、tmux、ssh、uv、lark-cli、cc-connect、officecli、python-pptx、cairosvg、lxml、pillow，外加网络连通性（GitHub、npm、PyPI）。

## Auto-Sync

`monitor.sh` 监听 `~/git/` 下所有 git 仓库，自动 commit 和 push：

```bash
./monitor.sh start     # 启动守护进程（120s debounce，60s 最小推送间隔）
./monitor.sh stop      # 停止
./monitor.sh status    # 查看状态 + 跟踪的仓库 + 待推送改动
./monitor.sh log 50    # 最近 50 行日志
./monitor.sh tail      # 实时跟踪推送结果
./monitor.sh monitor   # 实时跟踪文件变化
```

流程：`inotifywait` 监听 `~/git/` → 检测变化 → 120s debounce → `git add -A` → `git commit` → `git pull --ff-only` → `git push` → 重建符号链接 → 同步 skills。

## 可选组件

所有可选组件遵循 `option-<name>/` 约定：

```bash
# 飞书 Bridge（lark-cli + cc-connect）
bash option-bridge/init.sh

# OfficeCLI（AI 原生 .pptx/.docx/.xlsx）
bash option-officecli/init.sh

# PPT 生成（python-pptx + cairosvg + ppt-master）
bash option-ppt-master/init.sh

# Vessel AI 浏览器
bash option-vessel/init.sh
```

每个 option 组件至少支持 `init.sh --status` 健康检查。

## LLM 后端

```bash
bash init-llm.sh              # 交互式选择
bash init-llm.sh list         # 列出可用后端
bash init-llm.sh deepseek     # 切到 DeepSeek
bash init-llm.sh minimax      # 切到 MiniMax
bash init-llm.sh claude       # 切到 Claude（Anthropic）
```

## 远程访问

通过 Tailscale + SSH 从笔记本连到桌面 Claude Code tmux session：

```bash
# 桌面 WSL（一次性配置）
bash remote/server/tmux-sshd.sh

# 桌面 Windows（管理员 PowerShell）
powershell -ExecutionPolicy Bypass -File "remote/client/ts-setup.ps1"

# 笔记本
ssh francis@<Tailscale IP> -p 2222  # 自动 attach 到 tmux 'claude' session
```

## 开发

```bash
# 语法检查所有脚本
for f in *.sh lib/*.sh option-*/*.sh share/*.sh; do bash -n "$f" && echo "$f OK"; done

# 跑依赖检查
bash deps-check.sh

# 状态
bash status.sh

# 验证 JSON 配置
python3 -c "import json; [json.load(open(f'conf/{f}.json')) for f in ['claude','llm','ubuntu','versions','feishu']]"
```

### 添加 Option 组件

1. 创建 `option-<name>/`，含 `init.sh` 和 `README.md`
2. `init.sh` 支持 `--status` 标志
3. 依赖加到 `deps-check.sh` 的 `OPTIONAL_DEPS` 数组
4. 自动出现在 `status.sh` option 组件区

### 添加 Skill

1. 在 `link/skills/<name>/` 创建 skill
2. 跑 `bash init-skill.sh sync`

## 不跟踪的文件

- `conf/claude.json` — API key
- `conf/feishu.json` — App secret
- `conf/llm.json` — LLM API key
- `conf/ubuntu.json` — Git 用户信息
- `link/settings.json` — 个人权限
- `.monitor-sync.*` — 运行时状态
- `.snapshots/` — 升级快照
- `tmp/` — 一次性任务产物
- `cccshare/` — 公开导出（生成）

> `link/.config.json` 虽然包含 env 凭证（API key），但**实际在 git 跟踪中**（私有仓库）。生成由 `init-mcp.sh sync` 合并 `conf/*.json` + `~/.claude.json` 写入。

## 许可证

MIT —— 见 [LICENSE](LICENSE)
