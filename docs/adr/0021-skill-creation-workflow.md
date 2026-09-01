# 0021. Skill 创建工作流 — fskillcreat 交互 + link-single 增量注册

> **Status**: ✅ Accepted
> **日期**: 2026-09-01
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

新建 skill 需要手动在源目录创建 SKILL.md，再跑全量 `init-skill.sh sync` 注册 symlink。全量 sync 耗时（扫 CLI deps + marketplace），且没有交互式选择公开/私有归属的流程。同时新机器跑 `ccprivate/setup.sh` 后不会自动注册私有 skill，需要额外手动 sync。

## Decision Drivers

- 创建 skill 后立即可用，不跑全量 sync
- 公开/私有归属在建目录时就确定，不事后改
- 新机器 `setup.sh` 后私有 skill 自动可见
- 多机同步：git pull ccprivate 后私有 skill 自动注册

## Considered Options

- **A. 全量 sync 每次** — 每次新建跑 `sync`（含 CLI deps 安装 + marketplace 检），慢且不必要
- **B. 父目录 symlink** — `~/.claude/skills/` 指向 `skill/plugins/` 父目录，但无法同时指向 `ccprivate/skill-local/`（单 symlink 不能两个 target），且 Claude Code 识别 skill 是按 `~/.claude/skills/` 下每个子目录独立扫，不是扫父目录
- **C. 增量 link-single + link-only 轻量扫描** — 新增单个 skill 只注册单条 symlink；全机器刷新用 link-only（跳过 CLI deps/marketplace）

**Chosen**: C

## Decision

### init-skill.sh 新增两个子命令

- `link-single <name>` — 为单个新建 skill 注册 symlink，私有源优先
- `link-only` — 只跑 `do_link_self_built`（扫两源注册缺失 symlink + 清理孤儿），跳过 CLI deps 安装和 marketplace 检

### fskillcreat 改为交互创建流程

SKILL.md 从纯设计参考手册改为交互创建入口：

1. 问归属（公开/私有），用户已说则跳过
2. 问名称（小写英文+数字，无横线）
3. 建目录骨架（SKILL.md + 可选 deps.txt + config.yaml.example）
4. 写 SKILL.md 内容（基于用户功能描述）
5. 自动调 `link-single` 注册 symlink
6. 公开 skill 自动调 `sync-marketplace.py --write`
7. 输出 Git 提交提示

设计参考部分保留为摘要，完整原则在 GLOSSARY.md。

### ccprivate/setup.sh 自动注册

末尾追加 `init-skill.sh link-only`，确保 `skill-local/` 下的私有 skill 在新机器首次 setup 后立即可用。条件守卫（`skill-local` 目录非空才调用），避免无私有 skill 时报错。

## Consequences

- **Good**: 新建 skill 后自动注册，零手动命令
- **Good**: `link-only` 轻量（<0.5s vs sync 的 5-10s），适合重复调用
- **Good**: 私有 skill 多机随 ccprivate git pull 后手动 `link-only` 刷新
- **Good**: fskillcreat 保留设计参考（GLOSSARY.md），不丢失原内容
- **Neutral**: 公开 skill 通过 marketplace 已自动可见，但新加公开 skill 后仍需本地 `link-single` 更新 `~/.claude/skills/`（供 `init-skill.sh` 内部一致性）

## Changed Files

| 仓库 | 文件 | 变更 |
|------|------|------|
| ccconfig | `lib/init-skill.sh` | 加 `link-single`、`link-only` 子命令 |
| skill | `plugins/fskillcreat/SKILL.md` | 重写为交互创建流程 |
| ccprivate | `setup.sh` | 末尾加 `init-skill.sh link-only` |

## Related

- [[skill-source-layering-20260831]] — skill 分层源目录架构
- [[ccprivate-git-push-direct]] — ccprivate 仓库可以直接推送
- `docs/adr/README.md` — ADR 索引
