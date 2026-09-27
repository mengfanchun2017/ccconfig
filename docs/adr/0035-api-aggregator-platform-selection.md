# 0035. 数据 API 聚合平台选型（AnyAPI / APIVerve / apitree）

> **Status**: ✅ Accepted
> **日期**: 2026-09-25
> **关联**: `docs/adr/`（调研记录）；后续正式使用（注册 / 配 MCP / 接 skill）时更新
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

需要频繁查询各类**数据 API**（社交、搜索、地图、邮箱、富化、工具类），
痛点：每个 API 单独注册、单独 key、单独订阅、单独账单，集成成本高（"每个 api 都注册太麻烦了"）。

需求边界：
- **不是** LLM 模型网关（OpenRouter 那类已调研过，单列 ADR 0036）
- 要**一个 key / 一个余额池**调多个查询类数据 API
- **按需付费**，不要一堆订阅
- 优先能接入 MCP（AI agent / Claude Code 直调）

## Decision Drivers

- **D1 统一接入**：一个 key 覆盖尽量多的数据 API，免逐家注册
- **D2 按需计费**：无订阅或订阅价值清楚，闲置不烧钱
- **D3 MCP 支持**：能直连 Claude Code / agent 调用
- **D4 数据面**：要覆盖社交/搜索/地图/邮箱/富化等常见查询
- **D5 可靠性**：故障转移、统一 schema，少写胶水

## Considered Options

三家均为新一代"统一网关"式平台（区别于老牌 RapidAPI 的逐 API 订阅模式，已排除）。

| 维度 | APIVerve | AnyAPI | apitree |
|------|----------|--------|---------|
| 官网 | apiverve.com | getanyapi.com | apitree.ai |
| 覆盖 | 367+ 生产 API | 402 API / 78 平台 | ~1.7K API（含韩国 450 + scraping 654） |
| 计费 | 统一 credits 池，无 per-endpoint rate | **按请求 $0.001+，无订阅无月费** | 统一信用额，1 token 全通 |
| 免费档 | 200 credits/月，免卡 | ~150 次请求，免卡（$0.10 起充） | 10K calls，免卡 |
| MCP | ✅ MCP-ready（/mcp 端点） | ✅ 远程 MCP server + skill + CLI | ✅ 核心架构：全 catalog auto-wrap 成 MCP tool |
| 统一 schema | ✅ 所有端点 status/data/error | ✅ 统一 schema | 部分 |
| 故障转移 | SLA（paid，99.9%） | ✅ 自动 failover，失败请求不计费 | ✅ Self-Healing Gateway（15min 健康检查） |
| AI-native | 部分（MCP-ready） | 无特别强调 | **是**（详见下） |
| 特色 | 统一 SDK（Node/Py/.NET/Go/PHP）+ 统一 schema | 真·按需付费、唯一按调用扣钱 | 自然语言意图→自动匹配 API；batch 调用 |

### apitree 的 "AI-native" 含义

核心一句话：**"APIs were built for humans. The future is built for Agents."**
整个平台以 AI Agent 为**主要消费者**重新设计（而非人类开发者），落地表现：

1. **自然语言意图匹配**：agent 用自然语言描述意图，平台语义匹配 API（4 因子排序）
2. **全 catalog 自动 wrap 成 MCP tool**：每个 API 都是 MCP 工具，agent 无需读文档
3. **Self-Healing Gateway**：15 分钟健康检查，schema 变化自动修复字段映射
4. **Auto-API Factory**：数据商连 DB 即自动生成 REST API + 文档 + MCP 工具

### 其他两家 MCP 状态

**三家都支持 MCP**。差别在深度：
- APIVerve：MCP-ready，作为附加能力
- AnyAPI：远程 MCP server，接入即用，定位实用
- apitree：MCP 是核心架构（这就是它 AI-native 的体现）

## Decision

**初始试用选 APIVerve**（免费 200 credits/月，覆盖通用开发需求，
统一 schema 省心）。**暂时排除 apitree**（韩国数据占比较大，国内数据
适用性未知，留作后续观察）。**AnyAPI 作为按需付费的备选**（按请求计费，
唯一闲置 $0 的选项，若 APIVerve 覆盖/计费不合适再切）。

## Consequences

- ✅ APIVerve 一个 key 覆盖 367+ API，统一 schema + 统一 SDK，集成成本最低
- ✅ 免费档 200 credits/月，验证期零成本
- ❌ 按 credits 而非按请求，量大后不如 AnyAPI 的按请求计费直观
- ⚠️ apitree 排除是**暂时的**：其 MCP 深度 + Self-Healing 是最优的；
  若后续 agent 场景增多（自然语言调度 API），重评估 apitree
- ⚠️ 正式使用（注册、配 MCP endpoint、建 skill）时的配置/密钥 → `ccprivate/conf/`，
  公开仓库只留占位模板

## Implementation

- [ ] 注册 APIVerve，验证要查的数据 API 是否覆盖（社交/搜索/地图/邮箱/富化）
- [ ] 配 MCP endpoint 接入 → 评估延迟、命中率、schema 一致性
- [ ] 记录正式账号配置到 `ccprivate/conf/`，公开处留 `.example`

## Related Decisions

- 单列 `0036-api-aggregator-comparison.md`（若后续把 OpenRouter 与数据 API 平台对比写成 ADR）
- 模型网关选型（OpenRouter）→ 另行调研记录

## Notes

- 调研时间 2026-09-25，数据来自各官网 + Exa 搜索；平台数据（API 数、免费额度、费率）
  会变，正式用前以官网结算页为准
- 免费模型的共性代价（上下文阉割/稳定性差/提示词可能被训练）适用于 APIVerve 免费档，
  敏感数据走付费或零留存 provider