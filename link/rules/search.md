# 搜索策略

> 本文件是搜索策略的**单一真相源**。Skills（如 unified-research）通过引用本规则获取搜索方法，不应重复定义。

## 分流规则
- 中文搜索: minimax web_search MCP
- 英文搜索: tavily search MCP
- 深度调研: tavily research + extract
- 图片解析: minimax understand_image

## 双语搜索
所有搜索同时执行中英文查询，自行转换关键词并聚合结果。搜索结果需标注来源。

## 三源并行（必须同时执行）
1. LLM 内置 WebSearch/WebFetch — 通用搜索主力
2. mcp__minimax__web_search — 中文搜索扩展
3. mcp__tavily__tavily_search — 英文搜索
4. mcp__tavily__tavily_research — 深度综合（如需）

## Python 过滤模式

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

## 来源标注
- `[tavily]` — Tavily 英文搜索/研究
- `[minimax]` — Minimax 中文搜索
- `[websearch]` — LLM 内置 WebSearch

## Windows 路径
图片等文件路径: /mnt/c/Users/...
