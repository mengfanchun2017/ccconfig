---
name: unified-research-deep
user-invocable: true
description: |
  基于 unified-research 框架的深度研究。使用 outline.yaml 中的 items 列表，
  三源并行搜索，输出结构化 JSON 到 results/ 目录。
allowed-tools: Read, Write, Glob, Bash, WebSearch, Task,
  mcp__tavily__tavily_search, mcp__tavily__tavily_research,
  mcp__tavily__tavily_extract, mcp__minimax__web_search
---

# Unified Research Deep

## 工作流程
1. 定位 outline.yaml
2. 恢复检查（跳过已完成）
3. 批量执行（batch_size=3）
4. 三源并行搜索
5. 输出 JSON 到 results/
6. 验证字段覆盖