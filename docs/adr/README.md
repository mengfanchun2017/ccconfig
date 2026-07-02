# adr/ — Architecture Decision Records

> 记录 ccconfig 正式化过程中的所有非可逆决策。
> 模板: **MADR 4.0**（[madr/](https://adr.github.io/madr/)）极简版。
> 强制字段: 4 个（status / context / decision / consequences），其他可选。
> 机器可解析: 每条 ADR 必含可被 `lark-cli docs +search` 搜的关键词。

## 索引

| 编号 | 标题 | 日期 | 状态 | 关联 Phase |
|---|---|---|---|---|
| [0001](0001-secret-strategy.md) | 真实配置文件不入 git 仓 | 2026-06-08 | ✅ Accepted | Phase 0 |
| [0002](0002-merge-kr-and-task.md) | 合并 KR + Task 为单一交付实体 | 2026-06-08 | ✅ Accepted | Phase 0 |
| [0003](0003-deprecate-tasks-and-kr-progress.md) | 废弃 Tasks + KR_Progress 表 | 2026-06-09 | ✅ Accepted | Phase 0 |

## 强制 4 字段（每条 ADR 必含）

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| **Status** | 枚举 | ✅ | `Proposed` / `Accepted` / `Rejected` / `Superseded by NNNN` |
| **Context and Problem Statement** | 段落 | ✅ | 面对什么情况、什么痛点 |
| **Decision** | 段落 | ✅ | 决定怎么做（一句话能讲清）|
| **Consequences** | 列表 | ✅ | 正面 / 负面 / 风险 / 缓解 |

## 可选字段（推荐含）

| 字段 | 用途 |
|---|---|
| Decision Drivers | 决策时考虑的关键因素 |
| Considered Options | 替代方案 + pros/cons |
| Implementation | 链接到 phase plan 的具体任务 |
| Related Decisions | 链接到其它 ADR |
| Notes | 后续观察、补充 |

## 何时写 ADR

✅ **要写**：
- 改了架构方向（拆/合模块）
- 拒绝了某个明显方案（用 A 不用 B，why）
- 引入了新工具/库/平台
- 改了用户接口（CLI 行为、配置 schema）
- 改了发布/部署流程

❌ **不写**：
- bug 修复（commit message 够）
- 单文件重构（commit message 够）
- 琐碎样式调整

## 状态机

```
Proposed ──> Accepted ──> Superseded by NNNN
    │
    └─> Rejected
```

## 命名约定

- 文件名：`NNNN-kebab-case-topic.md`
- 编号：4 位数，从 0001 起，**永不重用**
- 即使状态变 Rejected/Superseded，文件保留（不删）

## 模板

复制 `0001-secret-strategy.md` 当模板。这是 MADR canonical form 的精简版（5 字段 + 2 可选）。

## 链接

- [Phase 0 计划](../task_plan.md)
- [ROADMAP](../../ROADMAP.md)
- [progress](../progress.md)
