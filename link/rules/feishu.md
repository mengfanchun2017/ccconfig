---
paths:
  - "ccconfig/feishu/**"
  - "ccconfig/link/skills/f-doc/**"
---

# 飞书集成规范

## 工具选择
- **lark-cli --as user**：所有飞书操作（文档、Base、日历、白板、表格）
- feishu MCP 已删除，不需要任何 MCP 调用

## 文档操作 → f-doc skill
所有飞书文档的创建/更新/合并/拆分/转换/对比，统一由 `f-doc` skill 编排。
f-doc 委托底层操作给 lark-doc/lark-drive/lark-wiki，PPT 给 f-ppt。

## 文档创建
```bash
cat << 'EOF' | lark-cli docs +create --wiki-node CyZ6wmItQiso3AkbjZBcP3vtnAb --as user --markdown - --title "标题"
内容
EOF
```
常见错误: ❌ --folder-token | ❌ --markdown "内容" | ✅ --markdown - + heredoc

## worklog 规则
- 写入 Base: Tq1ebqPA7aT0cSsSA8GcADZQnqd，表: tblpkMMzVHTTomp1
- 成长类: `claudecode 英文标识 中文描述`（自动分类到成长）
- 工作类: `中文描述` 无前缀（自动分类到工作）
- ❌ 不用【】括号，不用【LLM架构】这类前缀

## @res 研究
- 写入 CC编程大虾 wiki: CyZ6wmItQiso3AkbjZBcP3vtnAb
- 中英文双语搜索 → 聚合 → 创建文档（含白板SVG图表）→ 验证
- 通过 f-doc skill 自动编排
