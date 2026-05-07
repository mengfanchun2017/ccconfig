---
paths:
  - "ccconfig/feishu/**"
  - "ccconfig/link/agents/feishucreate.md"
---

# 飞书集成规范

## 工具选择
- lark-cli --as user: 文档创建、Base 写入、日历
- feishu MCP: 仅用于机器人消息发送（bot 无法读 wiki）

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
- 通过 feishucreate agent 自动路由
