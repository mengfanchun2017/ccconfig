# findings — 研究 / 发现 / 临时笔记

> **L2.5 追踪层**。研究笔记、调研结论、临时发现、外部资源引用。
> **不进入 ADR 的不入这里**；进入 ADR 的链接到这里。
> 时序倒序（最新在最上）。
> **生命周期**: 完成后可归档到 `findings-archive.md` 或转成 ADR。

---

## 2026-06-08 — f-ship skill 调研

**主题**: 把 4 层追踪系统抽成可复用 skill 调研

**结论**:

- 已有最接近方案: **planning-with-files**（147k★, 3 文件 `task_plan/findings/progress`）
- 第二接近: **Shape Up**（Hill Chart 3 态进度）+ **MADR**（4 字段 ADR）
- 社区重方案: superpowers / BMAD 仪式过重，不借鉴

**借鉴**:

1. 3 文件拆 STATE.md（本仓库已采纳）
2. MADR 4 字段 ADR 模板（本仓库已采纳）
3. Hill Chart 3 态进度（已采纳）
4. SessionStart 自动 re-read 3 文件（**defer 到 Phase 1**）
5. 两阶段 review（spec + code）— **defer 到 Phase 1**

**避开**:

- planning-with-files 245 commits 过度工程
- BMAD YAML 4-phase 仪式
- 100% session 自动恢复

**skill 命名**: `f-ship`（"想法 → shipped 端到端循环"）
**定位**: OKR + Shape Up + MADR 三方法论的 AI 适配版，复用 ccconfig 现有 `skill-template` + `f-logme` + `lark-cli` 基础设施

**完整报告**: 见临时输出 `/tmp/claude-1000/-home-francis-git/.../abe0eedecbcbffdf9.output`（session 结束后会被清理，重要内容已固化到此 + ADR-0001）

---

## 2026-06-08 — ccconfig 架构审查

**主题**: 把 ccconfig 升级到「正式开源项目」基线

**核心问题（按优先级）**:

| P0 | 必修 |
|---|---|
| API key 提交到 git | `conf/llm.json`、`link/.config.json` 等含 `sk-cp-...`，已 commit 到 main，被 GitHub bot 实时爬取概率 ≈ 100% |
| 零 CI/CD | 无 `.github/workflows/`, 无 `Makefile`, 无 `pre-commit` |
| 零测试覆盖 | 30+ shell 脚本 ~6000 行 bash，0 行测试 |

| P1 | 重要 |
|---|---|
| Git 历史被 auto-sync 噪音淹没 | 1406 commits 中 60% 是定时器自动产物 |
| 顶级 12 个 .sh 无组织 | 应拆 `bin/init/` + `bin/ops/` |
| 文档分散 | 9 个散落 README，应建 `docs/` |
| 无 ADR | 决策只有结论无理由 |
| 配置无 schema 验证 | 5 个 JSON conf 全无 schema |
| 绝对路径硬编码 | hooks 引用 `/home/francis/git/ccconfig/...` |
| 无 release / tagging | 0 个 tag，无语义版本 |

| P2 | 加分 |
|---|---|
| Shebang 不一致（`#!/bin/bash` vs `#!/usr/bin/env bash`）|
| skill 内 init.sh 模式重复（4 个 skill 各 1 个）|
| option-* 公开面文档薄 |
| tmp/ 目录有 .py 但 gitignore（应移 scripts/）|
| 缺 CODE_OF_CONDUCT/SECURITY.md/ISSUE_TEMPLATE |
| 缺 .shellcheckrc / .shfmt / .markdownlint |
| 缺 .devcontainer |

**强项（保留发扬）**: README 架构图、CHANGELOG、BOOTSTRAP.md、CONTRIBUTING.md、.editorconfig、path-helper.sh 库、颜色变量统一、SCRIPT_DIR 模式、`.example` 模板、symlink 集中化

**采纳的方案**: `.gitignore` + `.example` + `init.sh` 引导（**模式 2**） — 见 [ADR-0001](adr/0001-secret-strategy.md)

---

## 模板（新增 entry 复制）

```markdown
## YYYY-MM-DD — <topic>

**主题**: 一句话

**问题 / 背景**: （why this matters）

**调研 / 思考**:

- 发现 1
- 发现 2

**结论 / 决策**:

- 决策 1
- 决策 2

**后续**:

- [ ] 行动项 1
- [ ] 行动项 2

**链接**: [ADR-NNNN](adr/NNNN-xxx.md), [task_plan.md](task_plan.md), [外部资源](url)
```
