---
name: f-search
user-invocable: true
description: |
  搜索活动统一原语 — 三源并行搜索（tavily/minimax/websearch）、Python 过滤避免 context 污染、
  聚合去重、来源标注、搜索清单输出。被 f-research-domain / f-research-deep / f-logme 等需要外部调研的 skill 委托调用。
  不含领域方法论（领域解读由 f-research-domain 负责）。
allowed-tools: Read, Write, Bash, WebSearch,
  mcp__tavily__tavily_search, mcp__tavily__tavily_research,
  mcp__tavily__tavily_extract, mcp__tavily__tavily_crawl, mcp__tavily__tavily_map,
  mcp__minimax__web_search, mcp__minimax__understand_image
---

# f-search — 搜索活动统一原语

完整的"搜索活动"：query 规划 → 调工具 → 过滤 → 聚合 → 标注 → 搜索清单输出。

**不含领域方法论**。领域方法论（customer JTBD / market sizing / technical eval）由 `f-research-domain` 负责。

## 何时用

| 触发 | 调用方 |
|------|--------|
| "调研 XX" / "搜 XX 资料" | 任何 skill / 用户直接调用 |
| f-research-domain 调方法论前的数据收集 | f-research-domain |
| f-research-deep 批量研究 | f-research-deep |
| f-logme 行业调研 | f-logme |
| f-doc 文档调研（如 PDF 翻译查背景） | f-doc |

## 三源并行（必须同时执行）

1. **WebSearch** — 通用主力
2. **mcp__minimax__web_search** — 中文搜索
3. **mcp__tavily__tavily_search** — 英文搜索
4. **mcp__tavily__tavily_research** — 深度综合

## Python 过滤（避免原始数据污染 context）

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

## Tavily 工作流

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

### 内容提取优先级

```
Tavily extract（主力）→ 拿到内容 → 直接用
                      → 空壳/被拦截/需要登录/JS渲染 → Vessel 浏览器提取
```

- **Tavily extract** 速度快、成本低、可并行，适合所有公开静态页面
- **Vessel** 是最后 fallback，仅用于 Tavily 无法提取的页面：登录墙、SPA（Vue/React 渲染）、需要交互才能展示内容、反爬页面
- Vessel 不是搜索工具，是浏览器操控工具。搜索本身始终用 Tavily

### 双语搜索

同时执行中英文查询，自行转换关键词并聚合结果。

## 聚合去重

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

## 搜索清单（必须输出到调用方）

每次搜索完成后，**必须输出搜索清单**给调用方，由调用方决定是否附加到文档末尾。

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

## 关联 Skills

- `f-research-domain` — 4 领域方法论（最常调用方）
- `f-research-deep` — 批量研究
- `f-logme` — OKR/SUM 总结前的行业调研
- `f-doc` — 文档调研（如 PDF 翻译查背景）
