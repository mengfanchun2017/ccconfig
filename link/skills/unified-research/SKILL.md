---
name: unified-research
user-invocable: true
description: |
  统一研究框架 - 自动判断领域，三源并行搜索（Python过滤），统一输出到飞书wiki。
  支持 generic/customer/market/technical 四个领域，自动路由无需用户指定。
allowed-tools: Read, Write, Glob, Bash, WebSearch, Task, AskUserQuestion,
  mcp__tavily__tavily_search, mcp__tavily__tavily_research,
  mcp__tavily__tavily_extract, mcp__minimax__web_search
---

# Unified Research Framework

统一研究框架，自动判断领域类型，三源并行搜索，Python过滤优化，输出到飞书wiki。

## 三源搜索策略

详细规则见 `memory/search_bilingual.md`：

1. **WebSearch** — 通用主力
2. **mcp__minimax__web_search** — 中文搜索
3. **mcp__tavily__tavily_search** — 英文搜索
4. **mcp__tavily__tavily_research** — 深度综合

### Python过滤模式

**核心**：原始数据存 /tmp/，过滤后内容进 context

```bash
tvly search "..." --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data['results']:
    print(f'[{r[\"score\"]:.2f}] {r[\"title\"]}')
    print(f'  {r[\"content\"][:200]}')
"
```

### Tavily 工作流

```
search → extract → map → crawl → research
```

| 阶段 | 用途 | 命令 |
|------|------|------|
| search | 查找信息 | `tvly search "query" --max-results 10 --json` |
| extract | 提取URL内容 | `tvly extract "url" --query "focus" --json` |
| map | 发现URL | `tvly map "site" --instructions "find docs" --json` |
| crawl | 批量爬取 | `tvly crawl "site" --max-depth 2 --output-dir ./docs/ --json` |
| research | 深度综合 | `tvly research "topic" --model auto --json` |

## 自动领域判断

| 领域 | 触发关键词 | 典型场景 |
|------|-----------|----------|
| `generic` | 调研/研究/分析/对比 | 通用市场/技术概况 |
| `customer` | 用户/客户/竞品/JTBD | 用户研究、竞品分析 |
| `market` | 市场/TAM/份额/趋势 | 市场规模、竞争分析 |
| `technical` | 技术/框架/库/选型 | 技术评估、库对比 |

## 流程

### Step 1: 领域判断
根据关键词判断领域（generic/customer/market/technical）

### Step 2: 三源并行搜索
同时执行：
- WebSearch — 通用主力
- mcp__minimax__web_search — 中文搜索
- mcp__tavily__tavily_search — 英文搜索
- mcp__tavily__tavily_research — 深度综合（如需）

### Step 3: Python过滤 + 聚合去重
- 按 URL 去重
- 标注来源 [tavily]/[minimax]/[websearch]
- 检测领域偏差自动修正

### Step 4: 输出
根据 RESEARCH_OUTPUT 配置：feishu（默认）/ file / both

## 领域字段（内嵌）

**generic**: name, description, category, tags, overview, performance, adoption

**customer**: persona, jobs_to_be_done, pains, triggers, language, alternatives

**market**: market_overview, tam_sam_som, competitive_landscape, drivers, challenges

**technical**: basic_info, capabilities, adoption, ecosystem, roadmap

## 关联 Skills

- `/unified-research-deep` — 深度研究
- `/unified-research-report` — 报告生成