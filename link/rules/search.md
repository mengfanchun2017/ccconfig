# 搜索策略

> 方向性规则。详细搜索方法（Tavily 参数、Python 过滤代码、去重逻辑）→ `skills/f-search/SKILL.md`

## 分流规则
- 中文搜索: minimax web_search MCP
- 英文搜索: tavily search MCP
- 深度调研: tavily research + extract
- 图片解析: minimax understand_image

## 三源并行
搜索时同时执行：WebSearch（主力）+ minimax（中文）+ tavily（英文）+ tavily research（深度）。

## 内容提取优先级

```
Tavily extract（主力）→ 拿到内容 → 直接用
                      → 空壳/被拦截/需要登录/JS渲染 → Playwright 浏览器提取
```

- **Tavily extract** 速度快、成本低、可并行，适合所有公开静态页面
- **Playwright** 是最后 fallback，仅用于 Tavily 无法提取的页面：登录墙、SPA（Vue/React 渲染）、需要交互才能展示内容、反爬页面
- Playwright 不是搜索工具，是浏览器操控工具。搜索本身始终用 Tavily

## 双语搜索
同时执行中英文查询，自行转换关键词并聚合结果。

## 来源标注
- `[tavily]` — Tavily 英文搜索/研究
- `[minimax]` — Minimax 中文搜索
- `[websearch]` — LLM 内置 WebSearch

## Windows 路径
图片等文件路径: /mnt/c/Users/...
