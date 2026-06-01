# 文档操作规范（全局约束）

> 飞书文档格式硬约束，始终加载。完整写前检查清单（含执行步骤+验证）→ `skills/f-doc/references/write-checklist.md`

## 格式
- 标题：`# ## ###` 三级，**不加手动编号**（飞书自动生成目录），禁止 H4+
- 表格：`<lark-table>` XML，禁止 Markdown 表格。colgroup 列宽之和 = 822px
- 图表：Mermaid 代码块或 whiteboard，禁止 ASCII 字符画
- 缩写：首次 DFN 格式 `中文全称（English Full Name, ABBR）`
- 链接：`www.feishu.cn` 域名，非 `open.feishu.cn`
- 非正文用 `>` 引用包裹，不污染目录；禁止 `<hr/>` 分割线

## 父目录
- 子文档（用户给父URL）→ 提取 token 作 `--parent-token`，禁止套用默认
- 独立文档 → `--parent-token <your-feishu-wiki-token>`（Claude 工作 wiki）

## 入口
所有文档操作统一由 `f-doc` skill 编排。操作时必读 `references/write-checklist.md`（检查清单）。

## 常用 wiki 节点
| 用途 | Token |
|------|-------|
| Claude 工作 wiki（默认父目录） | `<your-feishu-wiki-token>` |
| OKR/SUM 文档父目录 | `VPsDw42KsixH77kugfcc8FyInCh` |
