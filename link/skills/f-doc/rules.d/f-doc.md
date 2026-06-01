# 文档操作规范（全局约束）

> 飞书文档硬约束，始终加载。完整规则+工作流 → `f-doc` skill；参考手册 → `skills/f-doc/references/write-checklist.md`

## 高危禁止
- **含嵌入资源（白板/图片/电子表格）的文档禁止 overwrite** — 会重建全部 token，图表永久丢失
- **标题禁止手动编号** — `一、` `1.1` `(1)` 等前缀会与飞书自动编号重复
- **表格必须用 `<lark-table>` XML**，禁止 Markdown 表格。colgroup 列宽之和 = 822
- **编辑后必须 fetch 验证** — `ok: true` 不代表生效

## 入口
所有文档操作由 `f-doc` skill 编排。写操作关键检查已内联在 SKILL.md 工作流步骤中。

## 常用 wiki 节点
| 用途 | Token |
|------|-------|
| Claude 工作 wiki（默认父目录） | `<your-feishu-wiki-token>` |
| OKR/SUM 文档父目录 | `VPsDw42KsixH77kugfcc8FyInCh` |
