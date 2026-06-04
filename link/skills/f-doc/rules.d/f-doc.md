# 文档操作规范（全局约束）

> 飞书文档硬约束，始终加载。完整规则+工作流 → `f-doc` skill；参考手册 → `skills/f-doc/references/write-checklist.md`

## 高危禁止
- **含嵌入资源（白板/图片/电子表格）的文档禁止 overwrite** — 会重建全部 token，图表永久丢失
- **标题禁止手动编号** — `一、` `1.1` `(1)` 等前缀会与飞书自动编号重复
- **表格必须用 `<lark-table>` XML**，禁止 Markdown 表格。colgroup 列宽之和 = 822
- **编辑后必须 fetch 验证** — `ok: true` 不代表生效

## 入口
所有文档操作由 `f-doc` skill 编排。写操作关键检查已内联在 SKILL.md 工作流步骤中。

## 图子文档约定（数据/分析图）
- **何时用**：数据图/分析图/对比图。架构/流程图仍走 Mermaid 白板
- **子文档**：父文档作图 → 建独立子文档（命名 = 图名，简洁中文）
- **子文档结构 3 段**：
  1. **图**（PNG 嵌入）
  2. **解读**（含分析、对比、洞察、注意点）
  3. **代码**（完整 python 脚本，可重跑）
- **父文档嵌入**：用 `block_insert_after` 把图块嵌入到指定位置，**绝不复制图**
- **关系**：子文档 = 详细档案（唯一源），父文档 = 摘要嵌入
- **python 选型**：常规图 matplotlib + seaborn；交互图 plotly。详见 `../f-research-report/SKILL.md` 工作流 G
- **保存位置**：`/tmp/figs/<图名>.{py,png}`（脚本可追溯）

## 常用 wiki 节点
| 用途 | Token |
|------|-------|
| Claude 工作 wiki（默认父目录） | `<your-feishu-wiki-token>` |
| OKR/SUM 文档父目录 | `VPsDw42KsixH77kugfcc8FyInCh` |
