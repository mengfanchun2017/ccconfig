# 0010. ADR 目录位置约定

> **Status**: ✅ Accepted
> **日期**: 2026-08-02
> **模板**: MADR 4.0 极简版
> **目的**: 修正 ADR 路径漂移，杜绝后续把新 ADR 放错目录

## Context and Problem Statement

ccconfig 曾出现两套 ADR 目录并存：
- **规范目录** `docs/adr/`：`0001`-`0007`，四位编号，MADR 4.0 格式（README.md 索引维护中）
- **错误目录** `adr/`（仓库根）：`001`（remote-connection，2026-07-31 误建）、`002`（token-cost-reduction，2026-08-02 误建），三位编号，未进 README 索引

根因：`docs/adr/README.md` 标题写 `# adr/`，与物理路径 `docs/adr/` 不一致；新增 ADR 时凭标题误判位置。

## Decision

1. **规范目录唯一化**：所有 ADR 存 `ccconfig/docs/adr/`，仓库根 `adr/` 目录删除（`git rm`）
2. **编号规则**：四位 `NNNN-kebab-case-topic.md`，从 `0001` 起**永不重用**；已存在 ADR 按时间顺序续编号（remote→0008，token→0009，本 ADR→0010）
3. **格式强制**：MADR 4.0 极简版，必含 `Status / Context and Problem Statement / Decision / Consequences` 四字段（详见 `docs/adr/README.md`）
4. **README 标题修正**：`docs/adr/README.md` 标题加物理路径标注，消除"标题=路径"歧义
5. **新 ADR 校验**：创建前先 `ls docs/adr/` 确认最新编号，避免重复

## Consequences

### Positive

- ✅ 单一路径，`find . -name 'adr'` 不再歧义
- ✅ 编号连续，索引可查
- ✅ MADR 格式统一，机器可解析

### Negative / Risks

- ❌ 已迁移 ADR 的 git 历史中断（文件重命名非 git mv）→ 用 `git log --follow` 追溯
- ❌ MEMORY.md 链接需同步更新（指向 `ccconfig/adr/` 的旧链接）
- ⚠️ 未来人仍可能按标题 `# adr/` 误建 → README 标题 + 本文档双保险

## Implementation

- `git rm adr/001-remote-connection.md adr/002-token-cost-reduction.md`
- 新写 `docs/adr/0008-remote-connection.md`、`docs/adr/0009-token-cost-reduction.md`、`docs/adr/0010-adr-directory-location.md`（本文档）
- 更新 `docs/adr/README.md` 索引 + 标题
- 更新 `docs/README.md` 的 `adr/` 路径引用为 `docs/adr/`
- 更新 MEMORY.md 的 ADR-001/002 链接

## Related Memory

- `ccconfig-refactor-v3` — 目录重构先例（remote→option-remote 同类归一化）
