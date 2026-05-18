---
name: unified-research
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

## 搜索策略

遵循 `rules/search.md`（单一真相源）：
- 三源并行：WebSearch + minimax（中文）+ tavily（英文）+ tavily research（深度）
- Python 过滤：原始数据保存 `/tmp/search_{timestamp}.json`，只保留 print() 输出
- 按 URL 去重，标注来源 `[tavily]` / `[minimax]` / `[websearch]`
- Tavily 参数速查 → `rules/search.md#tavily-search-参数速查`

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
遵循 `rules/search.md`，同时执行 WebSearch + minimax + tavily

### Step 3: 聚合去重
按 URL 去重，标注来源，检测领域偏差自动修正

### Step 4: 输出
根据 RESEARCH_OUTPUT 配置：feishu（默认）/ file / both

---

## 关联 Skills

- `/unified-research-deep` — 深度研究
- `/unified-research-report` — 报告生成
