# ai-agent-tool — AI Agent / 工具调用项目

> 场景:AI Agent / LLM 工具调用 / 智能助手
> 复杂度:★★★

## 适用

- 单一用途 AI 工具(摘要 / 翻译 / 分类)
- 多步 Agent(ReAct / Tool Use)
- RAG(检索增强生成)应用
- 工作流自动化(LLM 决策 + 工具执行)

## 默认技术栈

| 组件 | 选型 | 理由 |
|------|------|------|
| 语言 | Python 3.12 | AI 生态最厚 |
| LLM SDK | anthropic-sdk (Claude) / openai-sdk | 官方 SDK |
| Agent 框架 | LangChain / LangGraph / 直接调 API | 复杂度递增 |
| 验证 | Pydantic v2 | 类型 + 验证 |
| 工具调用 | Anthropic Tool Use / OpenAI Function Calling | 原生 |
| 观测 | LangSmith / Langfuse | 调试 + 监控 |
| 测试 | pytest + respx(mock HTTP) | 离线可重放 |
| 部署 | Docker + Render/Railway/Fly.io | 容器化 |

## 不适用

- 简单 LLM 包装(只用 1-2 个 prompt)→ 考虑 serverless function
- 训练/微调模型 → 看 data-pipeline 类型

## 脚手架结构

```
<代号>/
├── src/
│   ├── agent.py           # Agent 主逻辑
│   ├── tools/             # 工具定义
│   │   ├── search.py
│   │   ├── calculator.py
│   │   └── ...
│   ├── prompts/           # Prompt 模板
│   │   └── system.md
│   ├── llm/               # LLM 客户端
│   │   └── client.py
│   └── main.py
├── tests/
│   ├── test_agent.py
│   └── fixtures/
├── data/                  # 知识库(RAG 用)
│   └── corpus/
├── .env.example           # ANTHROPIC_API_KEY=...
├── pyproject.toml
├── README.md
└── LICENSE
```

## 关键决策

- **Agent vs 单一 prompt**:复杂决策(> 3 步)用 Agent;简单任务用单次调用
- **同步 vs 流式**:UI 实时反馈用流式(`stream=True` / SSE)
- **工具选择**:Anthropic 2026 工具调用规范(Tool Use)
- **记忆**:短期(对话 history)+ 长期(vector store / 知识库)
- **成本控制**:用 `claude-haiku-4-5` 做分类/简单任务,`claude-sonnet-4-6` 做主决策
- **错误处理**:API 限流(429)→ 指数退避;工具失败 → 重试 + 降级

## 风险点

1. **LLM 输出不稳定** — 同一 prompt 不同结果。缓解:加 JSON schema 约束 + 重试 + 人工 spot check。
2. **成本失控** — 长对话 / 多步 agent 烧 token 快。缓解:用小模型 + token 计数 + budget 限制。
3. **工具调用错误传播** — 一个工具失败可能让 agent 卡死。缓解:超时 + 错误返回 + 降级路径。
4. **Prompt 注入** — 用户输入可能覆盖系统 prompt。缓解:输入清洗 + system prompt 优先级 + 工具权限分离。
5. **API 变更** — 模型版本/SDK 升级会破坏代码。缓解:锁版本 + 定期重测 + 灰度。

## 学习路径(3-4 周)

| 周 | 任务 |
|----|------|
| 1 | Claude API + 单次 prompt + 流式输出 + Pydantic 解析 |
| 2 | 工具调用(2-3 个工具) + 错误处理 + 重试 |
| 3 | 多步 Agent(ReAct 循环) + 记忆 + 观测(Langfuse) |
| 4 | 测试(pytest + respx)+ 部署(Docker + Render) |

## 关联资源

- Anthropic 文档:https://docs.anthropic.com/
- Claude API SDK (Python):https://github.com/anthropics/anthropic-sdk-python
- LangChain:https://python.langchain.com/
- Langfuse:https://langfuse.com/
