# 搜索策略

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

| 阶段 | 用途 |
|------|------|
| search | 查找信息 |
| extract | 提取 URL 内容 |
| map | 发现网站 URL 结构 |
| crawl | 批量爬取 |
| research | 深度综合 |

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
