# agents/ — 自定义 Agents

> Claude Code 自动路由的 agent 定义，通过自然语言触发。

## Agent 列表

| Agent | 触发条件 | 路由目标 |
|-------|---------|---------|
| `assistant.md` | 通用意图识别 | 自动路由到对应 skill |
| `learnchinese.md` | 高考古文复习 | 古诗搜索、默写生成 |
| `knowledge-expander.md` | 知识扩展 worker | 三源搜索 + 飞书内容创建 |

## 注意

feishucreate agent 已合并到 `f-doc` skill。所有飞书文档创建/更新/管理统一由 f-doc 编排。
