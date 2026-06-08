# docs/adr/ — Architecture Decision Records

> 记录 ccconfig 正式化过程中的所有非可逆决策。
> 每条 ADR 含背景 / 方案 / 后果 / 替代。
> 模板: [MADR 3.0](https://adr.github.io/madr/) 简化版。

## 索引

| 编号 | 标题 | 日期 | 状态 | 关联 Phase |
|---|---|---|---|---|
| [0001](0001-secret-strategy.md) | 真实配置文件不入 git 仓 | 2026-06-08 | ✅ Accepted | Phase 0 |

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

## 模板

复制 `0001-secret-strategy.md` 当模板，改：

- 编号：下一个 4 位数
- 标题：kebab-case 主题
- 状态：Proposed → Accepted / Rejected / Superseded by NNNN

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

## 链接

- [Phase 0 计划](../plans/phase-0-security.md)
- [ROADMAP](../../ROADMAP.md)
- [STATE](../STATE.md)
