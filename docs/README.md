# docs/ — 项目追踪与决策

> ccconfig 正式化项目的所有追踪、规划、决策文档统一在此。
> 4 层追踪系统 + 1 层决策层，配合 f-logme 飞书 Base 自动日志。
> 模板来源: [planning-with-files](https://github.com/OthmanAdi/planning-with-files) (3 文件拆) + [MADR 4.0](https://adr.github.io/madr/) (4 字段 ADR) + [Shape Up](https://basecamp.com/shapeup) (Hill Chart 3 态进度)

## 目录结构

```
docs/
├── README.md                ← 本文件（索引）
├── task_plan.md             ← L2 当前 phase 详细计划（含 Hill Chart）
├── findings.md              ← L2.5 研究 / 发现 / 临时笔记
├── progress.md              ← L3 跨 session 进度（冷启动入口）
├── adr/                     ← L0 决策记录
│   ├── README.md            ← ADR 索引 + 模板
│   └── NNNN-*.md
└── plans/                   ← Phase 归档（已完成 phase 详细计划）
    └── README.md
```

## 4 层追踪 + 1 层决策

| 层 | 粒度 | 文件 | 模板来源 | 何时更新 | 谁维护 |
|---|---|---|---|---|---|
| L1 Roadmap | 季度 / 多月 | `ROADMAP.md`（根）| Shape Up pitch | 阶段切换 | 人 |
| L2 Phase 计划 | 1-2 周 | `docs/task_plan.md` | planning-with-files | 阶段开始/结束 | 人 + TaskCreate |
| L2.5 研究 | 滚动 | `docs/findings.md` | planning-with-files | 调研后即写 | 人 |
| L3 当前任务 | 当 session | `docs/progress.md` | planning-with-files | **每次 session 末**（必改）| 人 |
| L0 决策 | 不定期 | `docs/adr/NNNN-*.md` | MADR 4.0 | 决策时 | 人 |
| L4 Worklog | 天 | 飞书 f-logme Base | f-logme 5 层 | **自动**（SessionEnd hook）| hook |

**关键设计**：

- `progress.md` 是**唯一冷启动入口**（每次新 session 必读）
- `task_plan.md` 用 **Hill Chart 3 态进度**（unknown / known / done）替代 0-100%
- `findings.md` 记录**不进入 ADR**的临时发现（避免 ADR 膨胀）
- `adr/` 强制 **MADR 4 字段**（status / context / decision / consequences），其他可选

## 工作流（每次 session 5 步）

```
开始
  ↓
1. 读 progress.md（30 秒定位）
  ↓
2. TaskCreate 建本期任务（自动追踪）
  ↓
3. 写代码 + commit（每个文件 1 commit，msg 写 WHY）
  ↓
4. 改 progress.md（标完成 / 写阻塞 / 写下次入口）
  ↓
5. commit progress.md
  ↓
session 结束 → hook 自动写 worklog 到飞书
```

## 命名约定

- **Phase 文件**：`task_plan.md`（active 永远在根），归档到 `plans/phase-N-<topic>-archive.md`
- **ADR 文件**：`NNNN-<kebab-case-topic>.md`，NNNN 4 位递增
- **Findings entry**：`## YYYY-MM-DD — <topic>` 标题，**时序倒序**

## 配套系统

- **f-logme**（飞书 Base）— OKR/Worklog/Reflect/SUM 5 层。SessionEnd hook 已集成
- **GitHub** — 公开仓库，main 分支保护（Phase 1+ 加）
- **CHANGELOG.md**（根）— 用户视角变更日志，阶段结束更新

## 不在本目录的内容

- Skill 内部文档 → `link/skills/<skill>/SKILL.md`
- 单个脚本说明 → 脚本顶部注释
- README 速查 → 根 `README.md` + `CONTRIBUTING.md`
- 操作指南 → `BOOTSTRAP.md`（新机器用）

## Seed 未来 f-ship skill

本目录结构 + ROADMAP 是 `f-ship` skill 的种子。未来把本目录内容抽成模板 + 工作流脚本 + Skill spec，让任何项目都能复用。
