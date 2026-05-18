# ccconfig — Claude Code 配置中枢

> 统一管理 Claude Code 配置、脚本，通过 GitHub 跨设备同步。

## 目录结构

```
ccconfig/
├── init.sh                   # 总入口（交互式两级菜单）
├── init-ubuntu.sh            # Ubuntu/WSL 全环境初始化
├── init-llm.sh               # LLM 后端切换（deepseek/minimax）
├── init-mcp.sh               # MCP 服务器管理
├── init-skill.sh             # Skills 同步管理
├── init-autostart.sh         # auto-sync 自启动
├── update.sh                 # 月度升级（9组件一键更新）
│
├── status.sh           # 状态检查（SessionStart hook）
├── monitor.sh           # 文件监控 + 自动 Git 同步（120s 防抖）
├── gitforce.sh               # 强制单向同步（云↔本地，高危）
│
├── conf/                     # 配置文件（单一来源）
│   ├── feishu.json           # 飞书统一配置（lark-cli + cc-connect）
│   ├── versions.json         # 版本单一真相源
│   ├── claude.json           # MCP + API Key
│   ├── llm.json              # LLM 多后端配置
│   └── ubuntu.json           # Git 用户信息
│
├── windows/                  # Windows/WSL 互操作工具
│   ├── wslconfig.ps1         # 配置 .wslconfig（mirrored 网络）
│   └── wsl-interop.sh        # 修复 WSL interop（PATH 隔离）
│
├── option-bridge/            # 可选：飞书消息 Bridge
│   ├── init.sh               # lark-cli + cc-connect 初始化
│   ├── lark-switch.sh        # 多账号切换
│   ├── bot-status.sh         # 机器人状态
│   ├── bot-enable.sh         # 启用机器人
│   ├── bot-disable.sh        # 禁用机器人
│   ├── claude-lark-refresh.* # lark-cli token 自动刷新
│   └── mcp-bridge/           # 可选 MCP（bot 消息）
│
├── remote/                   # 远程连接（Tailscale + SSH + tmux）
│
├── lib/                      # 共享库
│   └── path-helper.sh        # 动态路径解析（4级回退）
│
├── link/                     # 符号链接源 → ~/.claude/
│   ├── settings.json         # 权限 + MCP + hooks
│   ├── .config.json          # env + 状态
│   ├── CLAUDE.md             # AI 行为指南
│   ├── agents/               # 自定义 agents
│   ├── skills/               # 全部 skills
│   └── projects/             # MEMORY.md 记忆
│
└── .snapshots/               # 升级版本快照（gitignored）
```

## 权限双层机制

| 层级 | 文件 | 作用 |
|------|------|------|
| AI 行为指南 | `link/CLAUDE.md` | 告诉 Claude AI 哪些命令可用 |
| 权限系统 | `link/settings.json` → `permissions.allow` | 控制是否弹窗询问 |

两者**必须同步**。运行 `bash ccconfig/status.sh` 检查状态。

## 快速开始

```bash
# 交互式菜单
bash ~/git/ccconfig/init.sh

# 一键全部初始化（不含可选组件）
bash ~/git/ccconfig/init.sh all

# 查看状态
bash ~/git/ccconfig/init.sh status
```

## 可选组件

### 飞书 Bridge（option-bridge/）

> 默认不包含在 `init.sh all` 中。需要时手动安装。

```bash
# 完整安装（lark-cli + cc-connect）
bash ccconfig/option-bridge/init.sh

# 仅安装部分能力
bash ccconfig/option-bridge/init.sh --lark-cli     # 仅文档/日历/任务
bash ccconfig/option-bridge/init.sh --cc-connect  # 仅消息 Bridge

# 多账号管理
bash ccconfig/option-bridge/lark-switch.sh francis  # Session A
bash ccconfig/option-bridge/lark-switch.sh ailab    # Session B

# 机器人管理
bash ccconfig/option-bridge/bot-status.sh           # 查看状态
bash ccconfig/option-bridge/bot-enable.sh <名称>     # 启用
bash ccconfig/option-bridge/bot-disable.sh <名称>    # 禁用
```

**包含组件**：
- `lark-cli` — 终端创建飞书文档/日历/任务（用户 OAuth）
- `cc-connect` — 接收飞书消息 Bridge（机器人长连接）
- `mcp-bridge` — 可选 MCP（bot 消息，配合 cc-connect 使用）

**状态检查**：`status.sh` 会标记为 `[option]`

### 添加新机器人

1. 飞书开放平台创建企业自建应用（机器人 + 长连接）
2. 编辑 `conf/feishu.json` → `apps[]` 新增
3. 运行 `bash ccconfig/option-bridge/init.sh`

### 远程连接（remote/）

> 从笔记本 SSH 连接到台式机 WSL2 中的 Claude Code tmux 会话。

**mirrored 网络模式**（推荐，`.wslconfig` 已配置）只需两步：

```bash
# 1. WSL/Ubuntu — 安装 SSH Server + tmux（一次性）
bash ~/git/ccconfig/remote/server/tmux-sshd.sh

# 2. Windows 管理员 PowerShell — 安装 Tailscale
powershell -ExecutionPolicy Bypass -File "C:\git\winremote\ts-setup.ps1"
```

完成后即可连接：`ssh francis@<Tailscale IP> -p 2222`

> 连上自动进入 tmux `claude` 会话，`Ctrl+B D` 断开（进程保持），`tmux attach -t claude` 重连。
>
> 非 mirrored 模式还需端口转发，详见 `remote/readme.md`。

## LLM 切换

```bash
bash ccconfig/init-llm.sh              # 交互式选择
bash ccconfig/init-llm.sh list         # 列出可用后端
bash ccconfig/init-llm.sh deepseek     # 切换到 DeepSeek
bash ccconfig/init-llm.sh minimax      # 切换到 MiniMax
```

## auto-sync 同步

```bash
cd ~/git/ccconfig
./monitor.sh start     # 后台启动（120s 防抖）
./monitor.sh stop      # 停止
./monitor.sh status    # 查看状态
./monitor.sh log       # 最近日志
```

## gitforce 强制同步（高危）

```bash
# 云 → 本地（丢弃本地所有改动）
bash ccconfig/gitforce.sh              # 默认 ccconfig
bash ccconfig/gitforce.sh projectu     # 指定仓库

# 本地 → 云（强制推送覆盖远程）
bash ccconfig/gitforce.sh --push ccconfig

# 查看帮助
bash ccconfig/gitforce.sh --help
```

⚠️ 高危操作，执行时需输入仓库名二次确认。默认只支持单向（云覆盖本地）。

## 月度升级

```bash
bash ccconfig/update.sh               # 交互式菜单
bash ccconfig/update.sh all           # 一键升级全部（9组件）
```

升级组件：Node.js → npm → GitHub CLI → Claude Code → uv → MCP → Skills → systemd

> 注：cc-connect 在 `update.sh all` 中也**不包含**，需单独升级：
> `bash ccconfig/option-bridge/init.sh --cc-connect`