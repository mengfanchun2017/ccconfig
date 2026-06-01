# 文档操作规范（全局约束）

> 飞书文档格式硬约束，始终加载。完整工作流、命令示例 → 调用 `f-doc` skill。

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

## 关键陷阱
- 编辑后 MUST fetch 验证（`--scope range`），`ok: true` 不代表生效
- `<lark-table>` colgroup 总和必须 = 822
- `replace_range` 不支持含空行内容，用 `delete_range` + `insert_after`
- `drive +search` 参数是 `--query` 不是 `--keyword`
- json 文件路径必须相对；lark-cli pipe 前先 `sed '/^\[lark-cli\]/d'`

## 入口
所有文档操作统一由 `f-doc` skill 编排。详细工作流 → `skills/f-doc/SKILL.md`。
