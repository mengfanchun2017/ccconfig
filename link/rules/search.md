# 搜索策略

> 方向性规则。详细搜索方法（Tavily 参数、Python 过滤代码、去重逻辑）→ `skills/unified-research/SKILL.md`

## 分流规则
- 中文搜索: minimax web_search MCP
- 英文搜索: tavily search MCP
- 深度调研: tavily research + extract
- 图片解析: minimax understand_image

## 三源并行
搜索时同时执行：WebSearch（主力）+ minimax（中文）+ tavily（英文）+ tavily research（深度）。

## 双语搜索
同时执行中英文查询，自行转换关键词并聚合结果。

## 来源标注
- `[tavily]` — Tavily 英文搜索/研究
- `[minimax]` — Minimax 中文搜索
- `[websearch]` — LLM 内置 WebSearch

## Windows 路径
图片等文件路径: /mnt/c/Users/...
