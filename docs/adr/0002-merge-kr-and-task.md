# 0002. 合并 KR + Task 为单一交付实体

> **Status**: ✅ Accepted
> **日期**: 2026-06-08
> **关联**: [task_plan.md（待更新）](../../.github/task_plan.md), [Phase 0 安全 + 公开化](../../.github/task_plan.md)
> **Supersedes**: (无)
> **Superseded by**: (无)
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

ccconfig 4 层追踪系统早期设计为：O → KR → Task → Worklog，4 个层级。实际落地发现：

1. **学习类 KR 也需要 output**：用户论据 — "光记录学习没有检查点"，所以"具体可执行"不是 Task 独有特性，KR 同样可以也是 process 类
2. **KRs vs Tasks 区分度低**：在个人场景，KRs（如 "Phase 0-3 全部完成"）和 Tasks（如 "改 .gitignore"）的数量比 3:10，重叠感强
3. **企业 OKR 区分不适用**：企业 KR 是"汇报单元"（对老板），个人没这个压力
4. **6 表嫌多**：flogme 5 层架构再加 Tasks 表变 6 层，违反"简化"初衷

**外部验证**（2026-06-08 深搜）：
- [MoonCamp](https://mooncamp.com/glossary/outcome-based-goals) — skill-building 必走 activity-based
- [Todoist](https://www.todoist.com/productivity-methods/okrs-objective-key-results) — 高频小步 KR 当 task
- [Linear Docs](https://linear.app/docs/use-cycles) — Project = OKR, Issue = Task（单表实证）
- [Notion Goals / Asana Goals] — 同表 + parent_id 自引用
- [Atomic Habits](https://jamesclear.com/atomic-habits) — "You fall to the level of your systems"

## Decision Drivers

- **D1 简化**：表格越少越好
- **D2 学习友好**：学习类 KR 应有 output checkpoint
- **D3 flogme 兼容**：不破坏现有 5 层架构（O/KR/Worklog/Reflect/SUM）
- **D4 工具实证**：Linear/Notion/Asana 都收敛到同表模式
- **D5 数据迁移最小**：现有 23 条 KRs 不动

## Considered Options

### Option A：保持 O/KR/Task 三表

- **Pros**：企业 OKR 经典模式，KRs 与 Tasks 概念清晰分离
- **Cons**：
  - 个人场景区分度低
  - 飞书 Base 跨表关联复杂
  - 与 flogme 5 层架构再添一层
  - 学习类 KR 仍要 link Task，体验割裂

### Option B：合并 KR + Task 为同表，加 `类别` 字段（**采纳**）

- **Pros**：
  - 1 张表，schema 统一
  - 类别字段区分 outcome/process/action
  - 学习类 KR 用 type=outcome 配 sub-子 KR（fractal）
  - 飞书 Base 单表 + 1 个 select 字段
  - Linear/Notion 工具实证可行
- **Cons**：
  - 33 条 KRs 视图稍拥挤（缓解：飞书多视图，按类别过滤）
  - 需要重新设计进度可视化（缓解：类别分组视图）

### Option C：完全放弃 KR 概念，只用 Task

- **Pros**：最简
- **Cons**：
  - 失去 OKR 的"成功标准"概念
  - 老板/同事汇报时无 outcome 视角
  - 与 flogme 5 层架构不兼容（KR 层不能砍）

### Option D：每个 action 直接是独立 Task，无 KR 包装

- **Pros**：扁平
- **Cons**：
  - "Phase 0-3 全部完成" 这种聚合成功标准无处放
  - 失去"季度评估"信号

## Decision

**采纳 Option B**：合并 Tasks 表入 OKR_KR，加 `类别` 字段区分 outcome/process/action。

**具体执行**（2026-06-08 完成）：
1. OKR_KR 加 4 字段：`类别` (outcome/process/action) / `Status (Hill)` (unknown/known/done) / `关联ADR` (text) / `Estimated (min)` (number)
2. 10 条 Phase 0 Tasks 复制到 OKR_KR，类别=action，关联O=O.ccconfig-正式化
3. Worklog 加 `关联Action` link 字段（指向 OKR_KR）
4. 删 10 条 Tasks 记录（数据已迁 OKR_KR）
5. Tasks 表留空（飞书 Base 不能删表，但可清记录）

## Consequences

### Positive

- ✅ 1 张交付实体表（OKR_KR），schema 统一
- ✅ 学习类 KR 配 sub-子 KR 自然存在（fractal）
- ✅ 飞书 Base 操作简单（同表 1 link 字段，跨表 0）
- ✅ Worklog 关联到具体 action 更精准
- ✅ 与 Linear/Notion Goals 工具设计一致
- ✅ 飞书 Base 视图按类别过滤，季度评估 / 日常看板 两种视图共存

### Negative

- ❌ OKR_KR 记录数从 26 涨到 36（视图需配过滤）
- ❌ Worklog 关联Action 下拉显示全部 36 条 KRs（需 UI 配类别过滤）
- ❌ 旧 Tasks 表 UI 上仍可见（飞书限制无法删表）

### Risks

- **R1** 33 条 KRs 视图拥挤 → 缓解：飞书多视图（默认全部 / `类别=outcome` 季度 / `类别=action` 日常）
- **R2** Worklog 关联时选错类型 → 缓解：UI 配 link 字段下拉只显示 `类别=action`
- **R3** KR 进度被 action 进度稀释 → 缓解：action 类型用 +2% 权重（vs worklog +5%）
- **R4** 数据迁移漏字段（Phase/Priority）→ 缓解：已编码到 OKR_KR.说明 字段（"Phase 0 / P0 / ..." 前缀）

## Implementation

详见 [task_plan.md（Phase 0 任务 #14-#15 + 合并任务）](../../.github/task_plan.md)

**实际执行**（2026-06-08）：
- OKR_KR 加 4 字段
- 10 条 Tasks → OKR_KR (类别=action)
- Worklog 加 关联Action 字段
- Tasks 表清空

## Notes

- "OPC"（用户提的术语）经查**非公开框架**，建议改用「**fractal OKR**」或「**单一交付实体**」描述
- 飞书 Base 不能删表，Tasks 表 (`<tasks-table-id>`) 保留为空 placeholder
- 后续可考虑把 OKR_O 也用 parent_id 自引用（O 套 O）— 但暂不需要，等出现子 O 需求时再做

## Related Decisions

- [ADR-0001: 真实配置文件不入 git 仓](0001-secret-strategy.md) — 同期决策

## Related Memory

- [[okr-base-v2-2026-05-31]] — OKR Base 6 表 → 5 表（含空 Tasks placeholder）
- [[ccconfig-4-layer-framework-2026-06-08]] — 4 层框架（待更新 L2 描述）
