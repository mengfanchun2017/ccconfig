# 0003. 废弃 Tasks 表 + KR_Progress 表

> **Status**: ✅ Accepted
> **日期**: 2026-06-09
> **关联**: [ADR-0002](0002-merge-kr-and-task.md)（KR+Task 合并）, [[okr-base-v2-2026-05-31]]（飞书 Base 现状）
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

飞书 OKR Base v2 在 2026-06-08 经历 2 步大改：

1. **ADR-0002（2026-06-08）**：合并 Tasks 表入 OKR_KR，加 `类别` 字段（outcome/process/action）作 fractal OKR
2. **10 条 Tasks 数据已迁 OKR_KR**（编号 27-36，类别=action），Tasks 表清空（0 记录）

但飞书 Base **不支持删表**，Tasks 表（`<tasks-table-id>`）和 KR_Progress 表（`<kr-progress-table-id>`）作为 placeholder 留在 Base 内，造成：
- Base 视图 6 个表（OKR_O / OKR_KR / Worklog / Reflect / KR_Progress / Tasks），实际用 4 个
- 新用户打开 Base 看到空表困惑「这是干嘛的」
- Tasks 字段 ID 仍占用但无数据，未来可能误用

**用户决策**（2026-06-09）：
- Tasks 表：自行在飞书 UI 删除
- KR_Progress 表：同废弃处理

## Decision Drivers

- **D1 简化**：Base 越少表越好，新用户上手快
- **D2 单一权威**：OKR_KR 已是 L2 主权威（合并后），Tasks 是冗余
- **D3 历史可追溯**：废弃 ≠ 数据丢失，Tasks 10 条数据在 OKR_KR 完整保留
- **D4 KR_Progress 评估**：原意是 KR 进度历史快照（time series），但实际：
  - 写入触发（worklog +5% / reflect +10%）**未自动化**
  - 0 记录说明从未启用
  - 新进度模型（Hill Chart 3-state）已覆盖「当前进度」概念
  - 「历史轨迹」需求**未验证**（暂不投入）

## Considered Options

### Option A：保留 2 表作 placeholder

- **Pros**：万一未来需要可恢复；零动作
- **Cons**：Base 视图冗余，新用户困惑；字段 ID 占位

### Option B：Tasks 删 + KR_Progress 保留（**部分采纳**）

- **Pros**：Tasks 100% 冗余可删；KR_Progress 留作未来启用
- **Cons**：两表处理不一致，决策理由需解释

### Option C：Tasks 删 + KR_Progress 也删（**部分采纳**）

- **Pros**：彻底简化，Base 5 表（O/KR/Worklog/Reflect/空闲位）；新用户清爽
- **Cons**：KR_Progress 未来如需启用需重建（成本低，但需重新建字段）

### Option D：2 表都保留但加「已废弃」重命名

- **Pros**：可见但不误用
- **Cons**：飞书 UI 名字变长；本质同 Option A

## Decision

**采纳 Option C**：

1. **Tasks 表 (`<tasks-table-id>`)**：用户在飞书 UI 自行删除（2026-06-09）
2. **KR_Progress 表 (`<kr-progress-table-id>`)**：在 ccconfig 文档中标记废弃（用户自行决定是否 UI 删除）
3. **OKR_KR.进度 字段**：保留但标记为「**legacy**，新 action 不必填」，23 旧 KR 的 进度 值不破坏
4. **新进度模型统一用 `Status (Hill)` 3 态**（unknown / known / done）

## Consequences

### Positive

- ✅ Base 视图清爽（Tasks 表删除后剩 5 表）
- ✅ OKR_KR 是唯一交付实体（fractal OKR 一致性强化）
- ✅ 新用户不被空表困惑
- ✅ 10 条 Tasks 数据在 OKR_KR 完整保留（不丢）
- ✅ 23 旧 KR.进度 值不破坏（向后兼容）

### Negative

- ❌ KR_Progress 未来启用需重建（建表 + 4 字段，约 30 分钟）
- ❌ OKR_KR.进度 字段残留（legacy，新数据不填，但不删）

### Risks

- **R1**：飞书 UI 删 Tasks 时**误删 OKR_KR**（用户操作风险）→ 缓解：用户在删前先用 +table-list 确认 table_id 是 `<tasks-table-id>`
- **R2**：未来想启用 KR_Progress，需查 ADR-0003 才知道原 schema（已写在 cheatsheet）→ 缓解：本 ADR 已记录表 ID 和原 schema 来源

## Implementation

**用户操作**（2026-06-09）：
1. 飞书 UI 打开 OKR Base v2
2. 找到 Tasks 表（最后 1 个，0 记录）
3. 确认 table_id = `<tasks-table-id>`（用 `lark-cli base +table-list` 验）
4. 右键 → 删除表（飞书 UI 操作）
5. 同样可选处理 KR_Progress (`<kr-progress-table-id>`)

**Claude 操作**（本 ADR 落地）：
- 写本 ADR
- 更新 [[okr-base-v2-2026-05-31]] 标记 Tasks 和 KR_Progress 为 deprecated
- 更新 [[ccconfig-4-layer-framework-2026-06-08]] L2 描述
- 更新 `../.github/findings.md` 加本决策 entry
- 更新 `ROADMAP.md` 飞书 Base 状态描述

## Notes

- 飞书 Base 删表是**不可逆**操作（飞书官方限制）。如需回滚只能从 git history 查 ADR 重建设
- OKR_KR.进度 字段虽不强制填，但 23 旧 KRs 的值是 5-31 期间累积的有效数据，**保留**
- 未来如需历史轨迹，参考 KR_Progress 原 schema（在原 `link/skills/flogme/SKILL.md` 5 层架构定义中）

## Related Decisions

- [ADR-0002: 合并 KR+Task 为单一交付实体](0002-merge-kr-and-task.md) — 此次废弃的前提
- [ADR-0001: 真实配置文件不入 git 仓](0001-secret-strategy.md) — 同期安全相关

## Related Memory

- [[okr-base-v2-2026-05-31]] — OKR Base 5 表最终状态（Tasks/KR_Progress 标记 deprecated）
- [[ccconfig-4-layer-framework-2026-06-08]] — L2 主权威 OKR_KR
