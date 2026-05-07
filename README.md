# ccconfig — Claude Code 配置中枢

> 统一管理 Claude Code 配置、脚本、飞书集成，通过 GitHub 跨设备同步。

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
├── check-status.sh           # 状态检查（SessionStart hook）
├── sync-monitor.sh           # 文件监控 + 自动 Git 同步（120s 防抖）
├── sync-pullff.sh            # 强制拉取远程覆盖本地
├── fix-wsl-interop.sh        # WSL interop 修复
│
├── conf/                     # 配置文件（单一来源）
│   ├── feishu.json           # 飞书统一配置（lark-cli + cc-connect）
│   ├── versions.json         # 版本单一真相源
│   ├── claude.json           # MCP + API Key
│   ├── llm.json              # LLM 多后端配置
│   └── ubuntu.json           # Git 用户信息
│
├── feishu/                   # 飞书集成（统一入口）
│   ├── init.sh               # 统一初始化（lark-cli + cc-connect）
│   ├── lark-switch.sh        # 多账号切换
│   ├── bot-status.sh         # 机器人状态
│   ├── bot-enable.sh         # 启用机器人
│   ├── bot-disable.sh        # 禁用机器人
│   └── claude-lark-refresh.* # lark-cli token 自动刷新
│
├── cconnect/                 # 向后兼容包装器 → feishu/init.sh
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

两者**必须同步**。运行 `bash ccconfig/check-status.sh` 检查状态。

## 快速开始

```bash
# 交互式菜单
bash ~/git/ccconfig/init.sh

# 一键全部初始化
bash ~/git/ccconfig/init.sh all

# 查看状态
bash ~/git/ccconfig/init.sh status
```

## 飞书集成

飞书功能统一在 `feishu/` 目录下管理，配置源为 `conf/feishu.json`。

```bash
# 完整安装（lark-cli + cc-connect）
bash ccconfig/feishu/init.sh

# 仅安装部分能力
bash ccconfig/feishu/init.sh --lark-cli     # 仅文档/日历/任务
bash ccconfig/feishu/init.sh --cc-connect   # 仅消息 Bridge

# 多账号管理
bash ccconfig/feishu/lark-switch.sh francis  # Session A
bash ccconfig/feishu/lark-switch.sh ailab    # Session B

# 机器人管理
bash ccconfig/feishu/bot-status.sh           # 查看状态
bash ccconfig/feishu/bot-enable.sh <名称>     # 启用
bash ccconfig/feishu/bot-disable.sh <名称>    # 禁用
```

### 架构

每个飞书应用包含两种能力，统一在 `conf/feishu.json` 中配置：

```
conf/feishu.json  (单一配置源)
    │
    ├── larkCli  → lark-cli (用户 OAuth) → 飞书文档/日历/任务
    └── ccConnect → cc-connect (机器人长连接) → 飞书消息 Bridge
```

### 添加新机器人

1. 飞书开放平台创建企业自建应用（机器人 + 长连接）
2. 编辑 `conf/feishu.json` → `apps[]` 新增
3. 运行 `bash ccconfig/feishu/init.sh`

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
./sync-monitor.sh start     # 后台启动（120s 防抖）
./sync-monitor.sh stop      # 停止
./sync-monitor.sh status    # 查看状态
./sync-monitor.sh log       # 最近日志
```

## 月度升级

```bash
bash ccconfig/update.sh               # 交互式菜单
bash ccconfig/update.sh all           # 一键升级全部（9组件）
```

升级组件：Node.js → npm → cc-connect → GitHub CLI → Claude Code → uv → MCP → Skills → systemd
