# ccconfig 接口规范（Interface Specification）

> 版本: v1.0 | 日期: 2026-07-07
> 对应软考考点: 系统分析师 — 系统设计文档、接口定义；系统架构师 — 软件架构文档化

## 1. 概述

ccconfig 系统由三个独立仓库 + Claude Code 运行时组成。仓库间通过以下机制交互：
- **符号链接（symlink）**: 文件系统级接口
- **环境变量**: 进程级接口
- **YAML/JSON 配置文件**: 数据级接口
- **Shell 脚本调用协议**: 进程级接口

本文档精确定义每种接口的契约（contract）。

## 2. 仓库间接口

### 2.1 ccconfig ↔ ccprivate: 系统配置 JSON

**方向**: ccprivate → ccconfig（单向读取）
**机制**: symlink
**路径映射**:

```
ccprivate/conf/<name>.json  →  ccconfig/conf/<name>.json
```

**契约**:
- ccconfig 只读，不写
- ccconfig `.gitignore` 必须排除 `conf/*.json`（除 `versions.json` 和 `*.example`）
- ccprivate/setup.sh 负责建立 symlink
- 脚本通过 `$CCCONFIG_HOME/conf/<name>.json` 路径读取

**已定义接口**:

| 文件 | Schema | 消费方 |
|------|--------|--------|
| `llm.json` | `{llms: {<name>: {base_url, model, key, small_model}}, current: string}` | init-llm.sh, option-llmswitch |
| `claude.json` | `{env: {}, settings: {}, mcp_servers: [{name, command, args, env}]}` | init-mcp.sh, status.sh, update.sh |
| `feishu.json` | `{apps: [{name, appId, appSecret, larkCli, ccConnect}]}` | option-bridge, status.sh |
| `ubuntu.json` | `{git: {repo, target_dir, email, username}}` | init-ubuntu.sh |
| `cloudflare.json` | Cloudflare API tokens | option-bridge |
| `supabase.json` | Supabase project tokens | option-bridge |

### 2.2 ccconfig ↔ ccprivate: Skill 配置 YAML

**方向**: ccprivate → claude-skills（单向注入）
**机制**: symlink（通过 apply-config.sh）
**路径映射**:

```
ccprivate/config/<skill>.yaml  →  ~/.claude/skills/<skill>/config.yaml
```

**契约**:
- skill 内的 Python 脚本通过 `open('config.yaml')` 读取（相对路径）
- symlink 自动跟踪，skill 读到 ccprivate 真实值
- apply-config.sh 幂等：已链接正确的跳过
- init-skill.sh sync 自动调用 apply-config.sh

**已定义接口**:

| Skill | YAML 文件 | 必需字段 |
|-------|----------|---------|
| f-logme | f-logme.yaml | `lark_cli.config_dir`, `bases.okr_v2.token`, `bases.okr_v2.tables.*` |
| f-feishu | f-feishu.yaml | `tenant_domain`, `wiki_nodes.default`, `wiki_nodes.okr` |
| f-pptx | f-pptx.yaml | （当前无必需字段，OfficeCLI 引擎无需外部配置） |
| f-moocrec | f-moocrec.yaml | `lark_cli.config_dir`, `base.token`, `docs.*` |

### 2.3 ccconfig ↔ ccprivate: 个人配置

**方向**: ccprivate → `~/` 和 `~/.claude/`
**机制**: symlink
**路径映射**:

```
ccprivate/link/CLAUDE.md        →  ~/CLAUDE.md
ccprivate/link/settings.json    →  ~/.claude/settings.json
ccprivate/link/.config.json     →  ~/.claude/.config.json
ccprivate/link/projects/<id>/   →  ~/.claude/projects/<id>/memory/
```

**契约**:
- ccprivate/setup.sh 负责建立这些 symlink
- 项目 CLAUDE.md 额外从 `ccprivate/link/projects/<id>/CLAUDE.md` 链接到 `~/git/<project>/CLAUDE.md`

### 2.4 ccconfig ↔ claude-skills: Skill 安装

**方向**: claude-skills → `~/.claude/skills/`
**机制**: symlink（通过 init-skill.sh）
**路径映射**:

```
~/git/claude-skills/plugins/<skill>/  →  ~/.claude/skills/<skill>/
```

**契约**:
- 源目录必须含 `SKILL.md`
- init-skill.sh 保护 user-managed symlink（目标不在 `$SKILLS_SRC/` 下则跳过）
- 已正确链接的跳过，断链自动清理

## 3. 脚本间调用协议

### 3.1 init.sh → 子脚本

**调用格式**: `bash <script> [args]`
**退出码**: 0=成功, 非0=失败（init.sh 继续执行后续步骤）

| 调用 | 脚本 | 参数 |
|------|------|------|
| init.sh all | init-ubuntu.sh | （无参数） |
| init.sh all | init-mcp.sh | sync |
| init.sh all | init-skill.sh | sync |

### 3.2 ccprivate/setup.sh → ccconfig/setup-links.sh

**调用格式**: `bash $CCCONFIG_DIR/setup-links.sh`
**前置条件**: `$CCCONFIG_DIR` 已设置（默认 `$HOME/git/ccconfig`）
**后置条件**: rules/agents/commands/skills 的 symlink 已建立

### 3.3 setup-links.sh → init-skill.sh

**调用格式**: `bash $SCRIPT_DIR/init-skill.sh sync`
**前置条件**: `$SKILLS_SRC` 路径存在（默认 `$HOME/git/claude-skills/plugins`）

### 3.4 init-skill.sh → apply-config.sh

**调用格式**: `bash $CCPRIVATE_DIR/bin/apply-config.sh [skill-name]`
**前置条件**: `$CCPRIVATE_DIR` 已设置
**契约**:
- 不带参数 = 覆盖所有 `ccprivate/config/*.yaml`
- 带参数 = 覆盖单个 skill
- 输出格式: `  <skill>: <状态>` + `完成: N 覆盖, M 跳过`

## 4. 环境变量契约

### 4.1 路径变量

| 变量 | 默认值 | 消费方 | 可覆盖 |
|------|--------|--------|--------|
| `CCCONFIG_HOME` | `$HOME/git/ccconfig` | 所有脚本 | ✅ `export` |
| `CCPRIVATE_HOME` | `$HOME/git/ccprivate` | setup.sh, init-skill.sh, status.sh | ✅ `export` |
| `CLAUDE_SKILLS_SRC` | `$HOME/git/claude-skills/plugins` | init-skill.sh | ✅ `export` |

**定义位置**: `lib/path-helper.sh`（被所有脚本 source）

### 4.2 运行时变量

| 变量 | 设置方 | 消费方 |
|------|--------|--------|
| `LARKSUITE_CLI_CONFIG_DIR` | option-bridge/lark-switch.sh | lark-cli |
| `ANTHROPIC_BASE_URL` | init-llm.sh | Claude Code |
| `ANTHROPIC_MODEL` | init-llm.sh | Claude Code |
| `ANTHROPIC_AUTH_TOKEN` | init-llm.sh | Claude Code |

## 5. 配置文件 Schema

### 5.1 marketplace.json

```json
{
  "$schema": "https://json.schemastore.org/claude-code-marketplace.json",
  "name": "<owner>-skills",
  "owner": { "name": "...", "email": "..." },
  "metadata": { "description": "...", "version": "X.Y.Z", "homepage": "..." },
  "plugins": [
    {
      "name": "<plugin-name>",
      "description": "<one-line>",
      "source": "./plugins/<name>" | {"source": "github", "repo": "<owner>/<repo>"},
      "version": "X.Y.Z",
      "keywords": ["f"]
    }
  ]
}
```

### 5.2 third-party-skills.txt

```
# <source>  <skill-name>
vinvcn/mattpocock-skills-zh-CN  caveman
vinvcn/mattpocock-skills-zh-CN  diagnose
```

**格式**: 空格/制表符分隔。`#` 开头为注释。

### 5.3 versions.json

```json
{
  "components": {
    "node": {"pin": "22", "version": "22.11.0"},
    "gh": {"version": "2.62.0"},
    "claude": {"version": "2.1.199"},
    "cc_connect": {"version": "..."},
    "uv": {"version": "..."}
  },
  "last_checked": "2026-07-07T00:00:00+08:00"
}
```

### 5.4 Skill config.yaml 最小结构

```yaml
# 必需: lark-cli 配置（如 skill 使用飞书）
lark_cli:
  config_dir: "~/.lark-cli-<account>"

# 必需: 飞书租户（如 skill 使用飞书）
tenant_domain: "<tenant>.feishu.cn"

# 可选: 飞书空间
space_id: "..."

# 可选: Wiki 节点
wiki_nodes:
  default: "<token>"
  okr: "<token>"

# 可选: Base 配置
bases:
  <base-name>:
    token: "<base-token>"
    tables:
      <table-name>: "<table-id>"
```

## 6. 接口版本管理

| 接口 | 版本 | 变更策略 |
|------|------|---------|
| conf/*.json schema | v1 | 新增字段向后兼容，不删字段 |
| config.yaml schema | v1 | 新增字段向后兼容 |
| marketplace.json schema | Anthropic spec | 跟随 Anthropic 规范更新 |
| 环境变量 | v1 | 新增变量可，改名需 CHANGELOG |
| 脚本调用协议 | v1 | 新增参数向后兼容，退出码语义不变 |
