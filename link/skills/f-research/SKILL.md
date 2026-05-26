---
name: f-research
user-invocable: true
description: |
  统一研究框架 - 自动判断领域，三源并行搜索，Python过滤优化，输出到飞书wiki。
  支持 generic/customer/market/technical 四个领域，自动路由无需用户指定。
allowed-tools: Read, Write, Glob, Bash, WebSearch, Task, AskUserQuestion,
  mcp__tavily__tavily_search, mcp__tavily__tavily_research,
  mcp__tavily__tavily_extract, mcp__minimax__web_search
---

# Unified Research Framework

统一研究框架，自动判断领域类型，三源并行搜索，Python过滤优化，输出到飞书wiki。

## 搜索策略（可执行详细版）

> 方向性规则在 `rules/search.md`，本文件提供可执行的详细方法。

### 三源并行（必须同时执行）

1. **WebSearch** — 通用主力
2. **mcp__minimax__web_search** — 中文搜索
3. **mcp__tavily__tavily_search** — 英文搜索
4. **mcp__tavily__tavily_research** — 深度综合

### Python 过滤（避免原始数据污染 context）

原始搜索结果不直接进入 context，通过 Python 过滤后只保留 print() 输出。原始数据保存到 `/tmp/tavily_search_{timestamp}.json`。

```python
# WRONG — 300K 原始数据污染 context
tvly search "query" --json

# RIGHT — 只有 print() 输出进 context
tvly search "query" --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data['results']:
    print(f'[{r[\"score\"]:.2f}] {r[\"title\"]}')
    print(f'  {r[\"url\"]}')
    print(f'  {r[\"content\"][:200]}')
"
```

### Tavily 工作流

```
search → extract → map → crawl → research
```

| 阶段 | 用途 | MCP 调用 |
|------|------|----------|
| search | 查找信息 | `mcp__tavily__tavily_search(query, search_depth, max_results)` |
| extract | 提取 URL 内容 | `mcp__tavily__tavily_extract(urls, extract_depth)` |
| map | 发现网站 URL 结构 | `mcp__tavily__tavily_map(url, max_depth)` |
| crawl | 批量爬取 | `mcp__tavily__tavily_crawl(url, max_depth)` |
| research | 深度综合 | `mcp__tavily__tavily_research(input, model)` |

### Tavily Search 参数速查

| 参数 | 可选值 | 说明 |
|------|--------|------|
| `search_depth` | `basic` / `advanced` / `fast` / `ultra-fast` | fast=低延迟高相关; ultra-fast=极低延迟 |
| `topic` | `general` / `news` / `finance` | 新闻/金融场景用对应 topic |
| `time_range` | `day` / `week` / `month` / `year` | 时间范围过滤 |
| `start_date` / `end_date` | `YYYY-MM-DD` | 自定义日期范围 |
| `include_images` | `true` / `false` | 返回源链接图片 |
| `include_image_descriptions` | `true` / `false` | AI 生成的图片描述 |
| `include_raw_content` | `false` / `markdown` / `text` | 原始页面内容 |
| `country` | ISO 国家代码 | 地域约束搜索 |
| `max_results` | `5`-`20` | 结果数量 |
| `include_domains` / `exclude_domains` | 域名列表 | 限定/排除特定来源 |

默认推荐：普通搜索 `search_depth=basic`；需要速度用 `fast`；新闻类用 `topic=news` + `time_range=week`。

### 聚合去重

```python
def deduplicate_by_url(results):
    seen = set()
    unique = []
    for r in results:
        url = r.get('url', '')
        if url and url not in seen:
            seen.add(url)
            unique.append(r)
    return unique
```

来源标注：`[tavily]` / `[minimax]` / `[websearch]`

### 搜索来源清单（必须输出到文档末尾）

每次研究输出飞书文档时，**必须在文档末尾附加搜索清单**：

```markdown
## 搜索清单

> 非正文，不出现在目录

### WebSearch
| # | 标题 | 链接 |
|---|------|------|
| 1 | 标题 | [链接](url) |

### minimax（中文）
| # | 标题 | 链接 |
|---|------|------|
| 1 | 标题 | [链接](url) |

### tavily（英文）
| # | 标题 | 链接 |
|---|------|------|
| 1 | 标题 | [链接](url) |

### 核心引用
| 来源 | 标题 | 用途 |
|------|------|------|
| [web] | ... | 定义 |
| [mm] | ... | 案例 |
| [tv] | ... | 对比 |
```

**规则**：
- 三源分开展示，每个源 5 条以内
- 核心引用表选前 3 条，标注在正文中的用途（定义/案例/对比/数据）
- 目的：检查各源搜索质量，方便追溯
- 格式：`> 引用` 包裹，不污染飞书目录

---

## 自动领域判断

| 领域 | 触发关键词 | 典型场景 |
|------|-----------|----------|
| `generic` | 调研/研究/分析/对比 | 通用市场/技术概况 |
| `customer` | 用户/客户/竞品/JTBD/饮水点 | 用户研究、竞品用户分析 |
| `market` | 市场/TAM/份额/趋势 | 市场规模、竞争分析 |
| `technical` | 技术/框架/库/选型 | 技术评估、库对比 |

---

## 领域方法论

### customer 领域（整合自 customer-research）

用户研究框架，基于 JTBD (Jobs to Be Done) 和饮水点理论。

**两种模式**：
- Mode 1: 分析已有素材（访谈、问卷、客服记录）
- Mode 2: 在线挖掘（Reddit、G2、社区、论坛）

**饮水点优先级**：

| ICP类型 | 主要来源 |
|---------|----------|
| B2B SaaS | Reddit (r/sales, r/startups), G2, LinkedIn |
| 开发者 | r/devops, r/programming, Hacker News |
| SMB/创始人 | Indie Hackers, Product Hunt, Reddit |
| 消费者 | App Store评论, Reddit, TikTok评论 |

**提取框架**：
1. **Jobs to Be Done** — 功能性/情感性/社交性工作
2. **Pain Points** — 痛点（优先未提示的、有情感语言的）
3. **Trigger Events** — 触发事件（团队增长、新员工、错过目标）
4. **Desired Outcomes** — 期望结果（用客户原话）
5. **Language** — 客户实际用语（copy金矿）
6. **Alternatives** — 考虑过的替代方案

**置信度标注**：
- High: 3+独立来源，未提示，一致
- Medium: 2个来源，仅提示
- Low: 单来源，可能是异常值

**聚合步骤**：
1. 按主题聚类
2. 频率+强度评分
3. 按客户画像分段
4. 识别"金钱引言"（5-10条代表性原话）
5. 标记矛盾点

### generic 领域

- name, description, category, tags
- overview: what_is_it, key_characteristics, current_status
- performance: metrics, benchmarks, comparison
- adoption: user_scale, market_share, growth_rate

### market 领域

- market_overview: market_name, market_size, growth_rate
- tam_sam_som: tam, sam, som
- competitive_landscape: key_players, market_share
- drivers: growth_drivers, market_trends
- challenges: risks, constraints

### technical 领域

- basic_info: project_name, version, license
- capabilities: core_features, integrations
- adoption: github_stars, contributors
- ecosystem: third_party_packages, community_activity

---

## 流程

### Step 1: 领域判断
根据关键词判断领域

### Step 2: 三源并行搜索
同时执行 WebSearch + minimax + tavily，使用 Python 过滤

### Step 3: 聚合去重
按 URL 去重，标注来源，检测领域偏差自动修正

### Step 4: 输出
根据 RESEARCH_OUTPUT 配置：feishu（默认）/ file / both

---

## 关联 Skills

- `f-research-deep` — 深度研究
- `f-research-report` — 报告生成
