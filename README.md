# ccconfig — Claude Code 配置中枢

> 统一管理 Claude Code 的配置文件、脚本、权限、MCP 服务器，通过 GitHub 跨设备同步。

## 目录结构

```
ccconfig/
├── init.sh                   # ★ 总入口（交互式两级菜单）
├── init-ubuntu.sh            # Ubuntu/WSL 全环境初始化
├── init-llm.sh               # LLM 后端切换
├── init-mcp.sh               # MCP 服务器管理
├── init-skill.sh             # Skills 同步管理
├── init-autostart.sh         # auto-sync 自启动
├── init-update.sh            # 一键升级所有组件
│
├── sync-monitor.sh           # 文件监控 + 自动 Git 同步
├── sync-pullff.sh            # 强制拉取远程覆盖本地
├── check-status.sh           # 状态检查（SessionStart hook 调用）
├── fix-wsl-interop.sh        # WSL interop 修复
│
├── conf/                     # 配置文件
│   ├── claude.json           # MCP + API Key
│   ├── feishu.json           # 飞书 + cc-connect
│   ├── llm.json              # LLM 多后端配置
│   └── ubuntu.json           # Git 用户信息
│
├── feishu/                   # 飞书集成
│   ├── feishureadme.md
│   ├── init-feishu.sh        # lark-cli 安装配置
│   ├── init-cconnect.sh      # cc-connect Bridge
│   └── cc-connect.service    # systemd 服务模板
│
├── remote/                   # 远程连接
│   ├── remotereadme.md       # 总览 + 方案对比 + 初始化步骤
│   ├── remote-ub-sshd.sh     # Ubuntu: SSH Server
│   ├── remote-ps-portforward.ps1  # PowerShell: 端口转发
│   ├── soft-tmux.conf        # 方案A: tmux
│   ├── soft-tmux-profile.ps1 # 方案A: Win Terminal 一键连接
│   └── soft-easytier.ps1     # 方案B: EasyTier P2P
│
├── link/                     # 符号链接源 → ~/.claude/
│   ├── settings.json         # 权限 + MCP + hooks
│   ├── config.json           # env + 状态
│   ├── CLAUDE.md             # AI 行为指南
│   ├── agents/               # Claude Code agents
│   ├── skills/               # 全部 skills
│   └── projects/             # MEMORY.md 记忆
│
└── mcp-status/               # 自研 MCP 服务器（环境状态）
```

## 权限双层机制

| 层级 | 文件 | 作用 |
|------|------|------|
| AI 行为指南 | `link/CLAUDE.md` | 告诉 Claude AI 哪些命令可用 |
| 权限系统 | `link/settings.json` → `permissions.allow` | 控制是否弹窗询问 |

两者**必须同步**。运行 `bash ccconfig/check-status.sh` 检查状态（Claude 内说 `hookstatus`）。

## 快速开始

```bash
# 交互式菜单
bash ~/git/ccconfig/init.sh

# 一键全部初始化
bash ~/git/ccconfig/init.sh all

# 查看状态
bash ~/git/ccconfig/init.sh status
```

## 日常命令

```bash
bash ccconfig/check-status.sh         # 状态检查 (Claude内: hookstatus)
bash ccconfig/sync-pullff.sh          # 强制同步远程覆盖本地
bash ccconfig/sync-pullff.sh projectu # 同步其他仓库
bash ccconfig/init-llm.sh             # 切换 LLM
bash ccconfig/init-update.sh          # 升级组件
```

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
./sync-monitor.sh tail      # 实时跟踪
```

## 子模块 README

- [飞书集成](feishu/feishureadme.md)
- [远程连接](remote/remotereadme.md)
