---
name: unified-research
user-invocable: true
description: |
  统一研究框架 - 自动判断领域，三源并行搜索，Python过滤优化，统一输出到飞书wiki。
  支持 generic/customer/market/technical 四个领域，自动路由无需用户指定。
allowed-tools: Read, Write, Glob, Bash, WebSearch, Task, AskUserQuestion,
  mcp__tavily__tavily_search, mcp__tavily__tavily_research,
  mcp__tavily__tavily_extract, mcp__minimax__web_search
---

# Unified Research Framework

统一研究框架，自动判断领域类型，三源并行搜索，Python脚本过滤，输出到飞书wiki。

## 自动领域判断

| 领域 | 触发关键词 | 典型场景 |
|------|-----------|----------|
| `generic` | 调研/研究/分析/对比 | 通用市场/技术概况 |
| `customer` | 用户/客户/竞品/JTBD | 用户研究、竞品分析 |
| `market` | 市场/TAM/份额/趋势 | 市场规模、竞争分析 |
| `technical` | 技术/框架/库/选型 | 技术评估、库对比 |

## 流程

### Step 1: 领域判断
根据关键词判断领域，加载 `domains/{domain}.md` 字段定义

### Step 2: 三源并行搜索（Python过滤）
- mcp__tavily__tavily_search (英文)
- mcp__minimax__web_search (中文)
- mcp__tavily__tavily_research (深度)
原始数据存 /tmp/，过滤后内容进 context

### Step 3: 聚合去重
- 按 URL 去重
- 标注来源 [tavily]/[minimax]/[research]
- 检测领域偏差自动修正

### Step 4: 输出
根据 RESEARCH_OUTPUT 配置：feishu（默认）/ file / both

## 关联 Skills
- `/unified-research-deep` - 深度研究
- `/unified-research-report` - 报告生成