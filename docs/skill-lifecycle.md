# Skill 生命周期管理

> 安装 → 更新 → 卸载 → 发布 → 漂移检测，一站式参考。

## 架构

```
ccconfig (infra)                       skill (content)
─────────────────                      ──────────────────────
init-skill.sh ──symlink──────────────> plugins/*/SKILL.md
update.sh ──调用──> init-skill.sh      .claude-plugin/marketplace.json
setup-links.sh ──调用──> init-skill.sh
                                       ~/.claude/skills/  ←── 运行时目标
ccprivate (private) ──config overlay──> ~/.claude/skills/*/config.yaml
```

**三层仓库模型：**

| 仓库 | 角色 | 可见性 |
|------|------|--------|
| `~/git/ccconfig` | 安装/更新/初始化脚本、规则、代理 | 公开 |
| `~/git/skill` | 16 个自建 f-* skill 实体（SKILL.md）、marketplace 注册表 | 公开 |
| `~/git/ccprivate` | API key、token、个人配置覆盖 | 私有 |

## Skill 分类

| 类型 | 来源 | 安装方式 | 管理 |
|------|------|---------|------|
| **自建 f-*** | `skill/plugins/` | symlink 到 `~/.claude/skills/` | git 仓库（skill） |
| **第三方 (npx)** | 上游 GitHub 仓库 | `npx skills add` → `~/.agents/skills/` → auto symlink | `conf/third-party-skills.txt` 清单 |
| **私有配置** | `ccprivate/skill-config/` | symlink `config.yaml` 覆盖 skill 默认配置 | ccprivate 仓库 |

## 命令速查

| 操作 | 命令 | 说明 |
|------|------|------|
| 完整安装 | `bash init-skill.sh sync` | CLI 依赖 + symlink 自建 + 配置覆盖 + 装第三方 |
| 更新 | `bash init-skill.sh update` | 更新 CLI 工具 + npx skills |
| 卸载 | `bash init-skill.sh remove <name>` | 从清单和磁盘删第三方 skill |
| 清理断链 | `bash init-skill.sh cleanup` | 删 ~/.claude/skills/ 中断链 |
| 查看列表 | `bash init-skill.sh list` | 已安装 skills + 来源标注 |
| 状态总览 | `bash init-skill.sh status` | 自建数量 + 链接状态 + marketplace |
| 漂移检测 | `bash init-skill.sh diff` | third-party-skills.txt vs 实际安装 |
| 发布自建 skill | `bash lib/publish.sh <name> [--push]` | link/skills/ → skill/plugins/ |
| 月度升级（含 skills） | `bash update.sh all` | 包含 skills sync |
| 单独 skill 升级 | `bash update.sh skills` | 只跑 init-skill.sh sync |

## 安装流程（`init-skill.sh sync`）

5 阶段流水线：

```
阶段 0: CLI 工具依赖
  └─ 扫描自建 skill deps.txt → 去重 → npm/go 安装缺失包

阶段 1: symlink 自建 skill
  └─ skill/plugins/* → ~/.claude/skills/*
  └─ 保护 user-managed symlink（npx 装的跳过）

阶段 2: marketplace 检
  └─ claude plugin marketplace add（幂等，自建 skill 可见性）

阶段 2.5: ccprivate 配置覆盖
  └─ ccprivate/bin/apply-config.sh → config.yaml symlink

阶段 3: 第三方 skill (npx)
  └─ 读 conf/third-party-skills.txt → npx skills add（幂等）
```

### 触发时机

| 触发 | 何时运行 |
|------|---------|
| `init.sh all` | 新环境初始化（第 3/3 步） |
| `init-ubuntu.sh` | WSL/Ubuntu 完整初始化 |
| `setup-links.sh` | 符号链接重建 |
| `sync.sh`（cconfig post-sync） | 每次 ccconfig git pull 后 |
| `update.sh all` | 月度升级 |
| 手动 `bash init-skill.sh sync` | 任何时候 |

## 更新流程

**自建 skill**：`git pull` skill 仓库即可 — symlink 指向源目录，无需重链接。

**第三方 skill**：
```bash
bash init-skill.sh update          # 更新所有第三方 skill
npx skills update -g -y            # 等效直接命令
```

**CLI 工具**：`init-skill.sh update` 会遍历所有 `deps.txt` 执行 `npm update -g` / `go install`。

## 卸载流程（`init-skill.sh remove <name>`）

```
1. 检查是否为自建 skill → 是则拒绝（由 skill 仓库管理）
2. 删除 ~/.claude/skills/<name>
3. 从 conf/third-party-skills.txt 移除对应行
4. 提示 ~/.agents/skills/<name> 需手动清理
```

**自建 skill 的移除**：删除 `skill/plugins/<name>/` 目录，提交 PR，然后 `git pull` + `init-skill.sh sync`。

## 发布自建 skill

编辑 → 发布 → 安装流水线：

```
1. 在 ccconfig/link/skills/<name>/ 编辑 SKILL.md（开发沙箱）
2. bash lib/publish.sh <name>        # 复制到 skill/plugins/
3. bash lib/publish.sh <name> --push # 同上 + git push
4. cd ~/git/skill && git pull    # 拉最新
5. bash init-skill.sh sync               # symlink 到 ~/.claude/skills/
```

**注意**：`link/skills/` 是开发编辑区，`skill/plugins/` 是发布源。`init-skill.sh sync` 只从 `skill/plugins/` 安装。

## deps.txt 格式

skill 目录下的 `deps.txt` 声明 CLI 工具依赖，`init-skill.sh sync` 阶段 0 自动安装。

```
# 格式：<package> <manager>
# manager: npm | go
# 注释行和空行被忽略

pymupdf npm
@anthropic-ai/claude-code npm
github.com/example/tool go
```

- 去重 key = `package|manager`，同包被多个 skill 依赖只装一次
- npm 包还自动 symlink binary 到 `~/.local/bin/`

## 第三方 skill 清单（`conf/third-party-skills.txt`）

```
# 格式：<source>  <skill-name>（两个空格分隔）
# 注释行（#开头）和空行被忽略

mattpocock/skills  diagnosing-bugs
mattpocock/skills  grill-me
mattpocock/skills  improve-codebase-architecture
mattpocock/skills  writing-great-skills
iofficeai/officecli  officecli
```

- `init-skill.sh diff` 对比此清单与实际 `~/.claude/skills/` 内容
- 添加第三方 skill：在此文件加一行 → `init-skill.sh sync`
- 移除第三方 skill：`init-skill.sh remove <name>`（自动更新此文件）

## 漂移检测（`init-skill.sh diff`）

三类检测：

| 类别 | 含义 | 处理 |
|------|------|------|
| 清单有但未装 | third-party-skills.txt 有，~/.claude/skills/ 无 | `init-skill.sh sync` |
| 已装但不在清单 | ~/.claude/skills/ 有，但不在清单也不在自建 | 手动加清单或删文件 |
| 自建 skill | skill/plugins/ 中的，不在清单管理范围 | 正常，无操作 |

## 状态检查（`maintain.sh status` 第 12 项）

SessionStart 自动运行，检查：
- 自建 skill 源目录是否存在
- ~/.claude/skills/ 断链数量
- 第三方清单条目数

断链 > 0 时提示 `bash init-skill.sh cleanup`。

## 故障排查

| 症状 | 可能原因 | 解决 |
|------|---------|------|
| `init-skill.sh sync` 报 "Skills 源目录不存在" | skill 未 clone | `git clone` 到 `~/git/skill` |
| npx skills add 失败 | GitHub HTTPS 未配 | `init-skill.sh sync` 自动设 `git config --global url."https://github.com/".insteadOf` |
| 自建 skill 修改不生效 | symlink 断链或指向旧目录 | `init-skill.sh cleanup` + `init-skill.sh sync` |
| marketplace add 失败 | GITHUB_USER 未设 | `export GITHUB_USER=<your-username>` 或 `gh auth login` |
| 第三方 skill 更新后 dialog 仍显示旧内容 | Claude Code 缓存 | 重启 Claude Code |
| `maintain.sh status` 报告断链 | skill 源目录被移动/删除 | `init-skill.sh cleanup` |

## Rules 三层模型

Skill 的行为约束分三层，各司其职：

```
Layer 1: 全局 Rule（始终加载）          ~/.claude/rules/ ← ccprivate/rules/
  └─ 每个 session 都注入，适合编码规范、飞书操作等跨领域约束
  └─ 成本：6.6 KB always-on budget（15KB 上限的 44%）

Layer 2: 路径 Rule（条件加载）          ~/.claude/rules/ + paths: frontmatter
  └─ 仅当操作文件匹配 glob 时才注入，适合语言/框架特定规则
  └─ python.md → **/*.py | git.md → **/.git/** | godot.md → **/*.gd
  └─ 不破坏 prompt cache（注入到 conversation history，非 system prompt）

Layer 3: Skill 正文（调用时加载）       plugins/*/SKILL.md
  └─ 仅当 skill 被 invoke 时加载，含完整工作流 + 约束
  └─ 已删除 rules.d/ 模式（之前是 Layer 1.5，冗余 + 断链风险）
```

**三仓库分工**：

| 仓库 | 提供 | 受众 |
|------|------|------|
| **ccconfig** | Layer 1+2 rules（全局 + 路径）+ setup-links.sh 安装 | fork/clone ccconfig 的用户 |
| **skill** | Layer 3 SKILL.md（skill 正文，调用时加载） | `/plugin marketplace add` 或 clone 的用户 |
| **ccprivate** | 无 rules 注入（仅 CLAUDE.md + settings.json 个人配置） | 用户自建 |

**设计原则**：
- 全局 rule 只放"不管做什么都可能用到的约束"（code style, feishu auth, search routing）
- 语言/框架 rule 用 `paths:` 条件加载，不烧无关 session 的 context
- Skill 约束在 SKILL.md 正文里写，skill 被调用时自然加载
- 不再使用 rules.d/ symlink 机制（复杂度高 + 断链风险 + 对外部用户不友好）
