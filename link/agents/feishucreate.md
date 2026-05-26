---
name: feishucreate
description: 飞书内容创建 — 已合并到 f-doc skill。保留此 agent 用于向后兼容，实际执行委托给 f-doc。
tools: Bash, Read, Write, Edit, Grep, Glob, mcp__minimax__understand_image, mcp__minimax__web_search, mcp__tavily__tavily_search, mcp__tavily__tavily_research, mcp__tavily__tavily_extract
model: inherit
---

# 飞书内容创建（已合并到 f-doc）

**所有飞书文档创建/更新/管理操作已统一由 `f-doc` skill 编排。** 此 agent 仅作为向后兼容的入口，实际执行时加载 `f-doc` skill。

> 2026-05-26: feishucreate agent 的文档创建逻辑已合并到 f-doc skill。
> 旧路由 `assistant → feishucreate → lark-doc/f-ppt` 已简化为 `assistant → f-doc → lark-doc/f-ppt`。
