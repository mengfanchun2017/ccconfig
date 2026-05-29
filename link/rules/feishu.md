# 飞书集成规范

## 工具选择
- **lark-cli --as user**：所有飞书操作（文档、Base、日历、白板、表格）
- feishu MCP 已删除，不需要任何 MCP 调用

## 文档操作 → f-doc skill
所有飞书文档的创建/更新/合并/拆分/转换/对比，统一由 `f-doc` skill 编排。
格式化规则见 `rules/f-doc.md`（始终加载）。

## lark-cli 输出解析
lark-cli 在 stdout 输出日志行（非 JSON），pipe 给 `python3 -c "json.load(sys.stdin)"` 会解析失败。
**规则：先 `tail -n +2` 或 `sed '/^\[lark-cli\]/d'` 跳过日志行。**

```bash
lark-cli ... 2>&1 | tail -n +2 | python3 -c "import json,sys; ..."
```
