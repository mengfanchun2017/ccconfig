# ccconfig 术语表（Glossary）

> 版本: v1.0 | 日期: 2026-07-07
> 对应软考考点: 系统分析师 — 文档管理（信息文档管理）；系统架构师 — 按标准编写设计文档

## 核心概念

### 三仓库模型 (Three-Repository Model)

| 术语 | 英文 | 定义 |
|------|------|------|
| **ccconfig** | Claude Code Config | 公开的 Claude Code 配置基础设施仓库。包含 init/update/status/monitor 等管理脚本、rules/agents/commands 等配置模板、conf/*.example 配置模板。是用户 fork/clone 的入口仓库。不含任何密钥。 |
| **claude-skills** | Claude Skills Marketplace | 公开的 Skill 插件市场仓库。包含 12 个自建 f-* skill 的 SKILL.md + 辅助脚本。符合 Anthropic marketplace 规范，可独立使用（不依赖 ccconfig）。 |
| **ccprivate** | Claude Code Private Config | 用户自建的私有配置仓库。存放 API key、Token、个人 CLAUDE.md、settings.json、项目 memory 等敏感数据。通过 symlink 穿透给 ccconfig 读取。每个用户自己创建，不 fork。 |

### 配置系统

| 术语 | 英文 | 定义 |
|------|------|------|
| **symlink 穿透** | Symlink Passthrough | ccconfig 通过符号链接读取 ccprivate 中的真实配置值。cconfig/conf/llm.json 是 symlink → ccprivate/conf/llm.json。脚本通过 ccconfig 路径读文件，实际拿到 ccprivate 真实值。 |
| **config.yaml** | Skill Config (YAML) | Skill 的私有配置文件（YAML 格式）。位于 `~/.claude/skills/<skill>/config.yaml`，实际是 symlink → `ccprivate/config/<skill>.yaml`。skill 内 Python 脚本通过 `open('config.yaml')` 自动跟踪 symlink 读到真实 token。 |
| **config.yaml.example** | Config Template (YAML) | Skill 配置的公开模板。含注释说明每个字段用途，不含真实值。用户复制为 config.yaml 后填入真实值，或通过 ccprivate overlay 覆盖。 |
| **conf/*.json.example** | Config Template (JSON) | 系统级配置的公开模板（JSON 格式）。含占位符，供用户参考。真实值在 ccprivate/conf/*.json 中。 |
| **.example 模式** | Example Pattern | ccconfig 的配置模板隔离策略：公开仓库只提交 `.example` 模板（含占位符），真实配置文件通过 `.gitignore` 排除。 |
| **YAML 配置覆盖** | YAML Config Overlay | ccprivate 通过 `apply-config.sh` 将 `config/*.yaml` 以 symlink 方式注入 `~/.claude/skills/<skill>/config.yaml`，覆盖 skill 自带的 config.yaml.example。修改 ccprivate 立即生效。 |

### Skill 系统

| 术语 | 英文 | 定义 |
|------|------|------|
| **Skill** | Claude Code Skill | Claude Code 的可复用能力模块。每个 skill 是一个目录，含 SKILL.md（指令）+ 可选脚本/模板/配置。安装在 `~/.claude/skills/` 下。 |
| **自建 Skill** | Self-Built Skill | 用户自己开发并维护在 claude-skills/plugins/ 中的 f-* 系列 skill。通过 init-skill.sh symlink 安装。共 12 个。 |
| **第三方 Skill** | Third-Party Skill | 来自外部 GitHub 仓库的 skill（如 mattpocock-skills）。通过 `npx skills add` 安装，自动 symlink 到 `~/.claude/skills/`。由 `conf/third-party-skills.txt` 管理清单。 |
| **f-*** | F-Series Skills | ccconfig 自建 skill 的命名前缀。f = francis（作者名首字母）。包括: f-doc, f-ppt, f-pdf, f-search, f-research, f-research-deep, f-research-report, f-report-std, f-logme, f-launch, f-moocrec, f-vessel。 |
| **marketplace.json** | Plugin Marketplace Manifest | Anthropic 规范的 skill 市场清单文件。位于 `.claude-plugin/marketplace.json`。定义每个 plugin 的名称、描述、源路径、版本、关键词。 |
| **SKILL.md** | Skill Definition File | Skill 的核心定义文件。YAML frontmatter（name, description, allowed-tools）+ Markdown body（工作流指令）。Claude Code 通过此文件理解 skill 的能力和调用方式。 |
| **Skill 三层架构** | Three-Layer Skill Architecture | ccconfig skill 的分层设计：Layer 1 原语（f-search, f-pdf, f-report-std）被委托调用；Layer 2 编排（f-doc, f-ppt, f-research, f-logme）组合 Layer 1；Layer 3 复合工作流（f-research-deep, f-research-report, f-launch, f-moocrec, f-vessel）编排 Layer 2。 |

### 基础设施

| 术语 | 英文 | 定义 |
|------|------|------|
| **init.sh** | Unified Entry Point | ccconfig 的统一入口脚本。提供交互式两级菜单和 `all` 一键初始化模式。调度 init-ubuntu.sh → init-mcp.sh → init-skill.sh。 |
| **init-ccprivate.sh** | ccprivate Creation Wizard | ccprivate 仓库的交互式创建向导。收集 GitHub 账号、邮箱、LLM API Key，自动生成 conf/*.json + link/ + setup.sh，创建 GitHub 私有仓库并推送。 |
| **init-skill.sh** | Skill Sync Manager | Skills 同步脚本。3 阶段 pipeline：Phase 1 symlink 自建 skill → Phase 2 marketplace 检 → Phase 2.5 ccprivate 配置覆盖 → Phase 3 npx skills 装第三方。 |
| **update.sh** | Monthly Upgrade Script | 月度组件升级脚本。覆盖 Node.js, npm 全局包, Python pip, GitHub CLI, Claude Code, uv, MCP 缓存, OfficeCLI, systemd 服务。升级前创建版本快照。 |
| **status.sh** | Health Check Script | 11 项状态检查脚本。每次 Claude Code session 启动时通过 SessionStart hook 自动运行。检查 symlink/依赖/sync/推送/记忆/项目/飞书/Playwright/MCP/远程/可选组件。 |
| **monitor.sh** | Auto-Sync Daemon | 多仓库文件监控守护进程。基于 inotify 监听 ~/git/ 下所有仓库，60s debounce 后自动 git commit + push。由 systemd user service 守护。 |
| **setup-links.sh** | Public Symlink Builder | ccconfig 公开部分的符号链接建立脚本。将 link/rules, link/agents, link/commands 链接到 ~/.claude/。被 ccprivate/setup.sh 调用。 |
| **sync.sh** | Multi-Repo Sync Tool | 多仓库智能同步脚本。支持 pull/push/check 模式，自动检测 ~/git/ 下仓库。暗号 `pullff` 触发强拉。 |

### 配置与运行时

| 术语 | 英文 | 定义 |
|------|------|------|
| **Rule** | Conditional Rule | Claude Code 的条件规则文件（Markdown）。按路径条件加载到 Claude Code session。位于 ~/.claude/rules/。ccconfig 提供 10 个 rule：code, git, python, search, feishu, godot, memory, context-budget, feishu-cli-cheatsheet, feedback_cwd_drift。 |
| **Agent** | Custom Agent | Claude Code 的自定义 agent 定义。位于 ~/.claude/agents/。ccconfig 提供 2 个 agent：assistant（意图路由）、knowledge-expander（知识扩展）。 |
| **Command** | Slash Command | Claude Code 的自定义斜杠命令。位于 ~/.claude/commands/。 |
| **Option** | Optional Component | ccconfig 的可选组件。位于 option-*/ 目录，每个含 init.sh（安装）和支持 --status 标志。当前：option-bridge（飞书 Bridge）、option-officecli（OfficeCLI）、option-llmswitch（LLM 网关代理）。 |
| **SessionStart Hook** | Session Start Hook | Claude Code 启动时自动执行的钩子。ccconfig 配置为运行 status.sh。 |
| **SessionEnd Hook** | Session End Hook | Claude Code 会话结束时自动执行的钩子。ccconfig 配置为运行 session-end-aggregator.sh，自动写 worklog 到飞书 Base。 |
| **Auto-Sync** | Automatic Git Synchronization | monitor.sh 提供的自动 git 同步能力。监听文件变化 → debounce → commit → push。systemd 守护。 |
| **版本快照** | Version Snapshot | update.sh 升级前自动保存的组件版本记录。位于 .snapshots/versions.json.pre.*。保留 90 天，用于回滚参考。 |

### 环境变量

| 术语 | 英文 | 定义 |
|------|------|------|
| **CCCONFIG_HOME** | ccconfig Home Directory | ccconfig 仓库的本地路径。默认 `$HOME/git/ccconfig`。所有脚本通过此变量定位 ccconfig。 |
| **CCPRIVATE_HOME** | ccprivate Home Directory | ccprivate 仓库的本地路径。默认 `$HOME/git/ccprivate`。 |
| **CLAUDE_SKILLS_SRC** | Skills Source Directory | 自建 skill 插件的源目录。默认 `$HOME/git/claude-skills/plugins`。init-skill.sh 从此目录 symlink skill。 |

### 飞书集成

| 术语 | 英文 | 定义 |
|------|------|------|
| **lark-cli** | Lark CLI | 飞书开放平台命令行工具（`@larksuite/cli`）。npm 全局安装。ccconfig 通过 f-doc skill 编排所有飞书操作（文档/Base/表格/白板）。 |
| **lark-doc / lark-wiki / lark-whiteboard / lark-base** | Lark Sub-Skills | larksuite/cli monorepo 中的子 skill（26 个）。ccconfig 不使用这些子 skill，而是通过 f-doc 直接调 lark-cli 命令。 |
| **cc-connect** | CC Connect Bridge | 飞书消息桥接服务。可选组件 option-bridge 的一部分。提供 Claude Code ↔ 飞书消息的双向通信。 |
| **飞书 Base** | Feishu Base (Bitable) | 飞书多维表格。ccconfig 用其存储 OKR/Worklog/Reflect 数据（f-logme skill）。 |
| **飞书 Wiki** | Feishu Wiki | 飞书知识库。ccconfig 用其作为文档输出目标（f-doc skill）。 |

### 开发流程

| 术语 | 英文 | 定义 |
|------|------|------|
| **BOOTSTRAP** | Bootstrap Guide | 新机器 0→1 拉起指南。7 个阶段：WSL 前置 → OS 基础 → gh CLI → SSH Key → 克隆三仓库 + init ccprivate → init.sh all → 验证。 |
| **Pullff** | Pull Fast-Forward | 暗号。触发 sync.sh --pull 强拉远程 + 重建符号链接。 |
| **ADR** | Architecture Decision Record | 架构决策记录。MADR 4.0 格式。位于 docs/adr/。记录不可逆的技术决策及其上下文、后果。 |
| **ROADMAP** | Product Roadmap | 产品路线图。Shape Up 风格（pitch + cycle）。按 Phase 0-3 组织，每阶段有明确主题和时间窗口。 |
| **CHANGELOG** | Change Log | 用户视角的变更日志。按语义版本（MAJOR.MINOR.PATCH）组织，记录 Added/Changed/Fixed/Removed/Security。 |
| **Release 分支** | Release Branch | 稳定发布分支。main = 高频开发，release = 仅大版本时 merge main。用户 clone release 拿稳定版。 |
