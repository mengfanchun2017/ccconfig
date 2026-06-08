# findings — 研究 / 发现 / 临时笔记

> **L2.5 追踪层**。研究笔记、调研结论、临时发现、外部资源引用。
> **不进入 ADR 的不入这里**；进入 ADR 的链接到这里。
> 时序倒序（最新在最上）。
> **生命周期**: 完成后可归档到 `findings-archive.md` 或转成 ADR。

---

## 2026-06-08 — KR + Task 合并（fractal OKR）

**主题**: 个人 OKR 实践中 KR 与 Task 的区分度低，合并为单一交付实体

**3 个独立来源验证用户论据**：

1. **MoonCamp** [glossary/outcome-based-goals](https://mooncamp.com/glossary/outcome-based-goals) — "Skill-building/training 必走 activity-based"，显式承认学习类 KR 是 output
2. **Todoist** [OKR 方法](https://www.todoist.com/productivity-methods/okrs-objective-key-results) — "1000 words/day" 等高频小步 KR **当 task** 更合理
3. **Linear Docs** [Cycles](https://linear.app/docs/use-cycles) — 无独立 Goals 实体，Project=OKR, Issue=Task，单表设计

**相关理论**：
- [Atomic Habits (James Clear)](https://jamesclear.com/atomic-habits) — "You fall to the level of your systems, not your goals"
- GTD — Project (outcome) + Next Action (物理动作) 同 workflow
- Notion Goals / Asana Goals — 同表 + parent_id 自引用 + type 字段

**OPC 是什么**：**非公开框架**。Tavily/minimax 三源搜索无结果。最接近的官方命名是 WorkBoard "Outcome Mindset" 和 Todoist "process goals vs outcome goals"。建议改用「**fractal OKR**」或「**单一交付实体**」。

**最终方案**（Model B，OKR_KR 同表 + 类别字段）：
- 类别 = outcome (原 26 条 KR) / process (新增预位) / action (10 条 Phase 0 任务)
- OKR_KR 加 4 字段：类别 / Status (Hill) / 关联ADR / Estimated (min)
- 10 条 Tasks 数据迁移到 OKR_KR
- Worklog 加 关联Action 字段（→ OKR_KR，过滤 类别=action）
- Tasks 表清空（飞书 Base 不能删表，保留 placeholder）
- 详见 [ADR-0002](adr/0002-merge-kr-and-task.md)

**借鉴来源**：
- [Shape Up Ch.13 Hill Chart](https://basecamp.com/shapeup/3.4-chapter-13) — 进度模型
- [MADR 4.0](https://adr.github.io/madr/) — ADR 模板

---

## 2026-06-08 — f-ship skill 三大决策（hybrid 模式最终版）

**主题**: f-ship skill 的 3 个核心架构决策

**3 个决策**（用户拍板）:

1. **L2 tasks 表放飞书 Base**（不在仓库内）
   - 理由：联动 OKR、复用 f-logme 现有 5 表、自动 dashboard view
2. **findings / adr 保持 2 文件**（不合并）
   - 理由：findings 临时自由、ADR 永久 MADR 4 字段，生命周期不同
3. **f-ship skill v0.1 在 Phase 0 末尾抽取**（不在 Phase 2）
   - 理由：趁架构记忆热乎，本仓库是天然 seed 案例

**最终 4 层 source of truth**（无冗余）:

| 层 | 文件 / 表 | 位置 | 备注 |
|---|---|---|---|
| L1 愿景 | `ROADMAP.md` | repo (git) | 公开、git-tracked |
| L0 决策 | `docs/adr/NNNN-*.md` | repo (git) | MADR 4 字段，公开 |
| L2 任务 | **Tasks 表** | 飞书 Base（f-logme 扩展）| 联动 OKR，含 Hill Chart 字段 |
| L4 日志 | Worklog 表 | 飞书 Base（现有）| hook 自动 |
| L3 视图 | Dashboard view | 飞书 Base | L2 过滤 + L4 join，**实时** |
| L2.5 研究 | `docs/findings.md` | repo (git) | 自由研究笔记 |
| L3 镜像 | `docs/progress.md` | repo (git) | 5 行手写快查 + 飞书 view 链接 |

**关键洞察**: L3（progress）**不是 source of truth，是 view**。可以完全从 L2 + L4 派生。仓库里的 `progress.md` 是手写快查，飞书里 Dashboard 是权威实时视图。

**飞书 Tasks 表 schema**:

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| ID | AutoNumber | ✓ | #1, #2, ... |
| Title | Text | ✓ | 任务名（一句话）|
| Phase | Select | ✓ | Phase 0/1/2/3 |
| Priority | Select | ✓ | P0/P1/P2 |
| Status (Hill) | Select | ✓ | 🔴 unknown / 🟡 known / 🟢 done |
| Estimated (min) | Number |  |  |
| Actual Start | Date |  |  |
| Actual Done | Date |  |  |
| Linked KR | Link → OKR_KR | ✓ | 关联到 O.ccconfig-正式化/KR1 |
| Notes | Text |  |  |
| Linked ADR | Text |  | 如 "ADR-0001" |

**L3 实时视图（飞书 Base Dashboard）**:
- 过滤：`Status != done`
- 排序：Phase ASC, Priority DESC, ID ASC
- 显示：Title / Status (Hill) / Linked KR / 最近 5 条 Worklog

**f-ship skill 雏形 v0.1**（任务 #10，Phase 0 末尾执行）:

```
link/skills/f-ship/
├── SKILL.md
├── rules.d/
├── references/
│   ├── 4-layer-model.md
│   ├── hybrid-default.md
│   └── feishu-setup.md
├── templates/
│   ├── ROADMAP.md.tmpl
│   ├── progress.md.tmpl
│   ├── findings.md.tmpl
│   └── ADR.md.tmpl
└── init.sh
```

**依赖**: f-logme (OKR 联动) + f-doc (飞书文档) + lark-cli (Base 操作) — 都已存在。

**反模式（避开）**:
- ❌ L2/L3 全部放仓库（不联动 OKR，浪费 f-logme）
- ❌ L2/L3 全部放飞书（不 git-tracked，失去代码仓库可见性）
- ❌ f-ship skill 现在就抽（设计还在迭代，skill 会频繁重写）
- ❌ task_plan / progress 合并（方向相反、未来/过去时态不同）

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
