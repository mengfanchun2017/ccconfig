# docs/ — 项目追踪与决策

> ccconfig 正式化项目的所有追踪、规划、决策文档统一在此。
> 4 层追踪系统：Roadmap → Phase Plan → STATE → Worklog。
> 配合 1 层决策：ADR。

## 目录结构

```
docs/
├── README.md                ← 本文件（索引）
├── STATE.md                 ← L3 跨 session 进度（最常读）
├── architecture.md          ← 整体架构图（待写：整合散落 README）
├── security.md              ← 安全模型（待写：Phase 0 后）
├── dev-guide.md             ← 开发者贡献指南（待写）
│
├── plans/                   ← L2 阶段计划（每阶段 1 个）
│   └── phase-0-security.md
│
└── adr/                     ← L0 决策记录（Architecture Decision Records）
    ├── README.md            ← ADR 索引
    ├── 0001-secret-strategy.md
    └── NNNN-xxx.md
```

## 4 层追踪系统

| 层 | 粒度 | 文件 | 何时更新 | 谁维护 |
|---|---|---|---|---|
| L1 Roadmap | 季度 / 多月 | `ROADMAP.md`（根）| 阶段切换 | 人 |
| L2 Phase 计划 | 1-2 周 | `docs/plans/phase-N-*.md` | 阶段开始/结束 | 人 + TaskCreate |
| L3 当前任务 | 当 session | `docs/STATE.md` | 每次 session 末 | 人（必改）|
| L4 Worklog | 天 | 飞书 f-logme Base | 自动（SessionEnd hook）| hook |

**ADR 是横切层**：任何阶段做了不可逆决策，落地为 `docs/adr/NNNN-*.md`。

## 工作流（每次 session 5 步）

```
开始
  ↓
1. 读 STATE.md（30 秒定位）
  ↓
2. TaskCreate 建本期任务（自动追踪）
  ↓
3. 写代码 + commit（每个文件 1 commit，msg 写 WHY）
  ↓
4. 改 STATE.md（标完成 / 写阻塞 / 写下次入口）
  ↓
5. commit STATE.md
  ↓
session 结束 → hook 自动写 worklog 到飞书
```

## 命名约定

- **Phase 文件**：`phase-<N>-<topic>.md`，N 从 0 开始
- **ADR 文件**：`NNNN-<kebab-case-topic>.md`，NNNN 4 位递增
- **STATE.md**：唯一一份，不带版本号（始终是当前）

## 配套系统

- **f-logme**（飞书 Base）— OKR/Worklog/Reflect/SUM 5 层。自动 hook 已集成
- **GitHub** — 公开仓库，main 分支保护（待加）
- **CHANGELOG.md**（根）— 用户视角变更日志，阶段结束更新

## 不在本目录的内容

- Skill 内部文档 → `link/skills/<skill>/SKILL.md`
- 单个脚本说明 → 脚本顶部注释 + `man` 风格
- README 速查 → 根 `README.md` + `CONTRIBUTING.md`
- 操作指南 → `BOOTSTRAP.md`（新机器用）
