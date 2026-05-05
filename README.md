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
├── init-update.sh            # ★ 月度升级（9组件一键更新）
│
├── lib/                      # 共享库
│   └── path-helper.sh        # 动态路径解析（find_node_bin）
│
├── sync-monitor.sh           # 文件监控 + 自动 Git 同步
├── sync-pullff.sh            # 强制拉取远程覆盖本地
├── check-status.sh           # 状态检查（SessionStart hook 调用）
├── fix-wsl-interop.sh        # WSL interop 修复
│
├── conf/                     # 配置文件
│   ├── versions.json         # 版本单一真相源（Node/gh/cc-connect）
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

## 月度升级

```bash
bash ccconfig/init-update.sh          # 交互式菜单（单项升级）
bash ccconfig/init-update.sh all      # ★ 一键升级全部组件
bash ccconfig/init-update.sh node     # 仅升级 Node.js
```

升级组件（严格顺序）：

| 步骤 | 组件 | 检查方式 |
|------|------|---------|
| 1 | **cconfig** 自身 | `git pull`，自身变更则 re-exec |
| 2 | **Node.js** | nodejs.org 最新 LTS |
| 3 | **lark-cli** | `npm update -g @larksuite/cli` |
| 4 | **cc-connect** | GitHub Release API |
| 5 | **GitHub CLI** | GitHub Release API |
| 6 | **Claude Code** | `claude install` |
| 7 | **uv** | `curl \| sh` |
| 8 | **MCP 缓存** | 清 npx 缓存 + 预拉取包 |
| 9 | **Skills 索引** | `npx skills update` |
| 10 | **systemd 服务** | 用新 Node 路径重建 |

附加功能：升级前自动 `git pull` ccconfig、前后快照对比、锁文件防并发、旧 Node 目录清理、快照保留 3 个月。

### 版本管理

- `conf/versions.json` — 所有组件版本单一真相源，升级后自动更新
- `lib/path-helper.sh` — `find_node_bin()` 4级回退发现 Node 路径，所有脚本通过它获取 Node 路径，不再硬编码

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
bash ccconfig/init-llm.sh deepseek     # 切换到 DeepSeek (pro 双路)
bash ccconfig/init-llm.sh minimax      # 切换到 MiniMax
```

**缓存策略**: 系统任务(haiku)与主模型使用同一模型，共享 prefix cache。
系统任务调用零散、间隔常超 5 分钟缓存 TTL，分模型导致 <50% 命中率、频繁冷启动，
统一模型可达到 >90% 缓存命中。虽然单价更高但系统任务输出极短，省下的输入成本远超输出差价。

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
