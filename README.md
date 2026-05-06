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
├── update.sh                 # ★ 月度升级（9组件一键更新）
│
├── lib/                      # 共享库
│   └── path-helper.sh        # 动态路径解析（find_node_bin 4级回退）
│
├── sync-monitor.sh           # 文件监控 + 自动 Git 同步（120s 防抖）
├── sync-pullff.sh            # 强制拉取远程覆盖本地
├── check-status.sh           # 状态检查（SessionStart hook 调用）
├── fix-wsl-interop.sh        # WSL interop 修复
│
├── conf/                     # 配置文件（唯一来源）
│   ├── versions.json         # 版本单一真相源（Node/gh/cc-connect）
│   ├── claude.json           # MCP + API Key
│   ├── feishu.json           # 飞书 + cc-connect
│   ├── llm.json              # LLM 多后端配置
│   └── ubuntu.json           # Git 用户信息
│
├── .snapshots/               # 升级前后版本快照（gitignored，保留3个月）
│
├── feishu/                   # 飞书集成
│   ├── feishureadme.md       # 说明 + 架构
│   ├── init-feishu.sh        # lark-cli 安装配置
│   ├── claude-lark-refresh.service  # lark-cli token 自动刷新
│   └── claude-lark-refresh.timer    # 每5天触发一次刷新
│
├── cconnect/                 # cc-connect Bridge
│   ├── init-cconnect.sh      # 多机器人飞书桥接配置
│   ├── status.sh             # 机器人状态
│   ├── bot-enable.sh         # 启用机器人
│   ├── bot-disable.sh        # 禁用机器人
│   ├── conf/bots.json        # 机器人配置（App ID/Secret/权限）
│   └── README.md
│
├── remote/                   # 远程连接
│   ├── readme.md             # 总览 + 方案对比 + 初始化步骤
│   ├── deploy.sh             # 一键部署
│   ├── server/               # 台式机端（SSH Server + tmux）
│   └── client/               # 笔记本端（Tailscale 连接）
│
├── archive/                  # 历史文件（不再使用）
│
├── link/                     # 符号链接源 → ~/.claude/
│   ├── settings.json         # 权限 + MCP + hooks
│   ├── .config.json          # env + 状态
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
bash ccconfig/update.sh               # 交互式菜单（单项升级）
bash ccconfig/update.sh all           # ★ 一键升级全部组件
bash ccconfig/update.sh node          # 仅升级 Node.js
```

升级组件（9组件，严格顺序）：

| 步骤 | 组件 | 检查/升级方式 |
|------|------|-------------|
| 1 | **Node.js** | 镜像下载（cdn.npmmirror.com），pin 锁大版本，回退官方源 |
| 2 | **npm 全局包** | `npm view` 查版本 → 匹配则跳过，不盲目更新 |
| 3 | **cc-connect** | GitHub Release API（超时 10s） |
| 4 | **GitHub CLI** | GitHub Release API（超时 10s，限流则跳过） |
| 5 | **Claude Code** | `npm view` 查版本 → 匹配则跳过，需更新时 `claude install --force` |
| 6 | **uv** | `curl \| sh` 安装器（30天缓存，不频繁检查） |
| 7 | **MCP 缓存** | 清除 npx 缓存 + 预拉取包（24h 缓存） |
| 8 | **Skills** | 由 auto-sync 自动同步，无需额外更新 |
| 9 | **systemd 服务** | 用新 Node 路径重建 cc-connect.service |

**设计原则**:
- **幂等**: 每个步骤先检查版本，已是最新则跳过
- **容错**: Node.js 镜像优先（国内 6s 下完 55MB），不可用自动回退官方源，下载后验证 gzip 合法性
- **快照**: 升级前后版本记录到 `.snapshots/`，保留 3 个月
- **缓存**: MCP 24h、uv 30天 内不重复检查，避免无意义网络请求
- **防并发**: `/tmp/ccconfig-update.lock` 锁文件

### 版本管理

- `conf/versions.json` — 所有组件版本单一真相源（`pin` 字段锁 Node 大版本）
- `lib/path-helper.sh` — `find_node_bin()` 4级回退发现 Node 路径，所有脚本不再硬编码版本号
- **注意**: ccconfig 自身的 git 同步由 `sync-monitor.sh` 负责，升级脚本不再做 git pull

## 日常命令

```bash
bash ccconfig/check-status.sh         # 状态检查 (Claude内: hookstatus)
bash ccconfig/sync-pullff.sh          # 强制同步远程覆盖本地
bash ccconfig/sync-pullff.sh projectu # 同步其他仓库
bash ccconfig/init-llm.sh             # 切换 LLM
bash ccconfig/update.sh               # 升级组件
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

**同步流程**: `watch → 120s debounce → commit → pull --ff (120s 超时) → push (60s 超时)`

**过滤规则**: `.git/`、`.snapshots/`、`*.tmp.*`、sync 自身日志文件均不入库、不触发推送。

## 子模块 README

- [飞书集成](feishu/feishureadme.md)
- [远程连接](remote/readme.md)
- [cc-connect Bridge](cconnect/README.md)
