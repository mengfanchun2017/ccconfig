---
name: f-research-domain
user-invocable: true
description: |
  4 领域研究方法论 — customer（JTBD）/ generic / market / technical。
  收到调研主题后自动判断领域，调 f-search 收集数据，再按对应领域框架解读。
  搜索工具调用委派 f-search，本 skill 不直接调 API。
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# f-research-domain — 4 领域研究方法论

按领域给"调研方法"，搜索工具调用委派 f-search。

## 何时用

| 触发 | 行为 |
|------|------|
| "调研 XX" / "分析 XX 用户" | 自动判断领域 → 调 f-search → 按框架解读 |
| f-report-gen 需要调研素材 | 委派本 skill（不在模式 1 中直接调 f-search） |
| f-research-deep 批量研究 | 委派本 skill 做单 item 的领域判断 + 框架 |

## 自动领域判断

| 领域 | 触发关键词 | 典型场景 |
|------|-----------|----------|
| `generic` | 调研/研究/分析/对比 | 通用市场/技术概况 |
| `customer` | 用户/客户/竞品/JTBD/饮水点 | 用户研究、竞品用户分析 |
| `market` | 市场/TAM/份额/趋势 | 市场规模、竞争分析 |
| `technical` | 技术/框架/库/选型 | 技术评估、库对比 |

## 领域方法论

### customer 领域

用户研究框架，基于 JTBD (Jobs to Be Done) 和饮水点理论。

**两种模式**：
- Mode 1: 分析已有素材（访谈、问卷、客服记录）
- Mode 2: 在线挖掘（Reddit、G2、社区、论坛）— 委派 f-search

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

## 流程

### Step 1: 领域判断
根据关键词判断领域

### Step 2: 委派 f-search 收集数据
调 f-search 做三源并行搜索（中文/英文/深度），拿回搜索结果 + 搜索清单

### Step 3: 按领域框架解读
按对应领域的提取框架处理数据：
- 客户原话、痛点、触发事件（customer）
- 市场大小、份额、趋势（market）
- 性能基准、生态、采用率（technical）
- 概览 + 关键特征（generic）

### Step 4: 输出
输出结构化领域数据 + 置信度标注，交给调用方（f-report-gen / f-research-deep / 用户）

## 关联 Skills

- `f-search` — 搜索工具（必调用）
- `f-research-deep` — 批量研究（委托本 skill 做单 item）
- `f-report-gen` — 报告生成（用本 skill 的输出做素材）
