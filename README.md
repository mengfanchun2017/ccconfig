# ccconfig — Claude Code 配置中枢

> 统一管理 Claude Code 配置。双仓库公私分离。一键恢复到新终端。

## 概述

ccconfig 管理 Claude Code 配置的完整生命周期。**隐私数据（API key / Token / 个人配置）在 ccprivate 私有仓库**，通过 symlink 穿透访问；ccconfig 本身不含任何密钥，可安全公开。

- **环境**：Ubuntu/WSL 一键初始化
- **配置**：LLM 后端、MCP 服务器、API key 单一真相源（真实值在 ccprivate）
- **同步**：文件监听 + 自动 git commit/push，覆盖 `~/git/` 下所有仓库
- **Skills**：12 自建（symlink）+ 第三方 npx skills 自管（conf 清单）
- **Rules**：条件规则按路径加载（编码、git、python、搜索、飞书、godot）
- **Agents**：意图路由 agent
- **可选**：飞书 Bridge、OfficeCLI、PPT 生成、远程 SSH

## 架构

```
ccprivate/ (私有仓库)               ccconfig/ (公开仓库)
├── conf/*.json (真实值) ──symlink──→ conf/*.json
├── link/CLAUDE.md         ──→       ~/CLAUDE.md
├── link/settings.json     ──→       ~/.claude/settings.json
├── link/.config.json      ──→       ~/.claude/.config.json
├── link/projects/         ──symlink──→ link/projects/
└── setup.sh               调用  →   setup-links.sh

                                         ccconfig/link/ (公开部分)
                                           ├── rules/      ──→ ~/.claude/rules/
                                           ├── agents/     ──→ ~/.claude/agents/
                                           ├── commands/   ──→ ~/.claude/commands/
                                           └── skills/     ──→ ~/.claude/skills/
```

> **密钥隔离**：`conf/*.json`（llm/claude/feishu/f-logme/f-doc/f-ppt/cloudflare/supabase/ubuntu）是 ccprivate→ccconfig 的 symlink，`.gitignore` 已忽略。公开仓库只含 `.example` 模板。详见 [BOOTSTRAP.md](BOOTSTRAP.md)。

## 目录结构

```
ccconfig/
├── init.sh                   # 入口（交互式二级菜单）
├── init-ubuntu.sh            # Ubuntu/WSL 全环境初始化
├── init-llm.sh               # LLM 后端切换
├── init-mcp.sh               # MCP 服务器管理
├── init-skill.sh             # Skills 同步管理
├── init-autostart.sh         # auto-sync systemd 服务
├── update.sh                 # 月度组件升级
│
├── status.sh                 # 状态检查（13 项）
├── monitor.sh                # 多仓库文件监听 + 自动 git 同步
├── sync.sh                   # 多仓库智能同步（云端↔本地）
├── setup-links.sh            # 公开部分符号链接（被 ccprivate/setup.sh 调用）
├── deps-check.sh             # 依赖完整性检查
│
├── conf/                     # 配置模板 + symlink
│   ├── *.json.example        # 公开模板（可提交）
│   ├── *.json                # → symlink 到 ccprivate/conf/（不跟踪）
│   ├── versions.json         # 组件版本（公开）
│   └── python-requirements.txt
│
├── lib/path-helper.sh        # 动态路径解析 + CCCONFIG_HOME
│
├── link/                     # → ~/.claude/ 符号链接源（公开部分）
│   ├── rules/                # 条件规则
│   ├── agents/               # 意图路由 agent
│   ├── commands/             # 自定义斜杠命令
│   ├── skills/               # 12 自建 skill
│   └── projects/             # → symlink 到 ccprivate/link/projects/
│
├── hooks/
│   ├── pre-commit            # git hook：防私密文件意外提交
│   └── session-end-aggregator.sh  # Claude hook：自动 worklog
│
├── share/setup.sh            # 公开模式引导式配置向导
│
├── option-bridge/            # 可选：飞书消息 Bridge
├── option-officecli/         # 可选：OfficeCLI
├── option-ppt-master/        # 可选：PPT 生成
│
├── remote/                   # 远程访问（Tailscale + SSH + tmux）
├── windows-tools/            # Windows/WSL 互操作
│
├── LICENSE                   # MIT
├── BOOTSTRAP.md              # 新机器 0→1 拉起指南
├── CHANGELOG.md              # 变更历史
└── CONTRIBUTING.md           # 贡献指南
```

## 快速开始

> **新机器？** 从零开始 → 看 [BOOTSTRAP.md](BOOTSTRAP.md)（6 阶段，含 gh 登录 + 克隆 ccconfig + ccprivate）。

```bash
# 1. 克隆双仓库
gh repo clone <your-username>/cconfig ~/git/cconfig
gh repo clone <your-username>/ccprivate ~/git/ccprivate

# 2. 私有 + 公开链接一步到位
bash ~/git/ccprivate/setup.sh

# 3. 一键初始化（Ubuntu + LLM + MCP + Skills + Python）
bash ~/git/ccconfig/init.sh all

# 4. 状态检查
bash ~/git/ccconfig/status.sh
```

> **无 ccprivate？** 跑 `bash ccconfig/share/setup.sh` 进入交互式配置向导（API key 手动输入，不依赖私有仓库）。

## 核心命令

| 命令 | 用途 |
|------|------|
| `bash init.sh` | 交互式菜单 |
| `bash init.sh all` | 一键全初始化 |
| `bash status.sh` | 完整状态检查（13 项） |
| `bash deps-check.sh` | 依赖完整性检查 |
| `bash update.sh all` | 月度组件升级 |
| `bash monitor.sh start` | 启动 auto-sync |
| `bash monitor.sh status` | 同步守护进程状态 |
| `bash setup-links.sh` | 重建公开符号链接 |
| `bash sync.sh --pull` | 强拉远程 |

## 状态检查覆盖

`status.sh` 每次 Claude Code session 启动检查 13 项：

1. 配置文件链接（settings.json、.config.json、CLAUDE.md、MEMORY.md、rules）
2. 核心依赖（git、bash、curl）
3. auto-sync 守护进程
4. GitHub 最后推送
5. MEMORY 最后更新
6. ppt-master 环境
7. 飞书 lark-cli 状态
8. Playwright 浏览器测试
9. OfficeCLI 状态
10. MCP 服务器健康检查（并行，24h 缓存）
11. 远程访问（SSH、Tailscale）
12. option-* 可选组件自动发现
13. .wslconfig 同步检查

## Auto-Sync

`monitor.sh` 监听 `~/git/` 下所有 git 仓库，自动 commit + push：

```bash
./monitor.sh start     # 启动守护进程（120s debounce）
./monitor.sh stop      # 停止
./monitor.sh status    # 查看状态
./monitor.sh log 50    # 最近 50 行日志
```

## 可选组件

```bash
bash option-bridge/init.sh       # 飞书 Bridge
bash option-officecli/init.sh    # OfficeCLI
bash option-ppt-master/init.sh   # PPT 生成
```

每个组件至少支持 `init.sh --status`。

## LLM 后端

```bash
bash init-llm.sh              # 交互式选择
bash init-llm.sh list         # 列出可用后端
bash init-llm.sh deepseek     # 切到 DeepSeek
bash init-llm.sh minimax      # 切到 MiniMax
```

## 远程访问

通过 Tailscale + SSH 连接桌面 Claude Code tmux session：

```bash
# 桌面 WSL（一次性配置）
bash remote/server/tmux-sshd.sh

# 笔记本连接
ssh <your-username>@<Tailscale IP> -p 2222  # 自动 attach 到 tmux
```

## 环境变量

| 变量 | 默认值 | 用途 |
|------|--------|------|
| `CCCONFIG_HOME` | `$HOME/git/ccconfig` | ccconfig 仓库路径 |
| `CCPRIVATE_HOME` | `$HOME/git/ccprivate` | ccprivate 仓库路径 |

所有脚本优先读环境变量，默认值保持不变。自定义路径时 `export` 覆盖即可。

## 隐私模型

| 数据 | 存放 | 公开？ |
|------|------|--------|
| API key / Token | ccprivate/conf/*.json | 私有仓库 |
| 个人 CLAUDE.md / settings | ccprivate/link/ | 私有仓库 |
| 项目 memory | ccprivate/link/projects/ | 私有仓库 |
| 脚本 / skill / rule / 模板 | ccconfig/ | 公开 |
| .example 配置模板 | ccconfig/conf/*.example | 公开 |
| 版本号 / 依赖清单 | ccconfig/conf/versions.json | 公开 |

`hooks/pre-commit` 自动拦截私密文件提交。安全漏洞报告见 [SECURITY.md](SECURITY.md)。

## 开发

```bash
# 语法检查
for f in *.sh lib/*.sh option-*/*.sh; do bash -n "$f" && echo "$f OK"; done

# 验证 JSON 模板
python3 -c "import json; [json.load(open(f)) for f in __import__('glob').glob('conf/*.example')]"
```

### 添加 Option 组件

1. 创建 `option-<name>/`，含 `init.sh` 和 `README.md`
2. `init.sh` 支持 `--status` 标志
3. 自动被 `status.sh` 发现

### 添加 Skill

1. 在 `link/skills/<name>/` 创建 skill
2. 跑 `bash init-skill.sh sync`

## 许可证

MIT —— 见 [LICENSE](LICENSE)
