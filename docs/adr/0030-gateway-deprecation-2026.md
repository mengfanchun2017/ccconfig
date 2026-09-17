# 0030. Gateway 模式废弃（option-llmswitch 整层删除）

> **Status**: ✅ Accepted
> **日期**: 2026-09-17
> **关联**: `option-llmswitch/`（已删）、`lib/init-llm.sh`、`maintain.sh`、commit `9696e4b`
> **模板**: MADR 4.0 极简版
> **取代**: 早期 gateway 模式整套（init.sh + proxy.py + watchdog.sh + llmswitch.json）

## Context and Problem Statement

### 起因

2026-09-17 用户决策：在家只用 1 种模型，gateway 模式（peak/off-peak 自动路由）无用处。详见 [ADR-0029](./0029-init-llm-target-2026.md)。

### Gateway 模式曾解决的问题

用户在多 provider 场景下，希望按时间段（peak/off-peak）自动切模型：
- 高峰时段（peak_hours 配置）→ 走贵的备用模型
- 非高峰（off_peak）→ 走便宜的默认模型

### 为什么不再需要

1. **场景消失**：用户当前只有 1 种主模型（home-deck-flash / office-deck-flash），不存在"自动路由"需求
2. **复杂度高**：~1500 行代码（init.sh + proxy.py + watchdog.sh + llmswitch.json 模板）维护成本远超价值
3. **配置分散**：gateway 配置独立于 llm.json，导致 LLM 切换逻辑两套
4. **替代充足**：用户备用直连走 `minimax` / `deepseek_flash` builtin preset，手动切 0 成本

## Decision Drivers

- **D1 单一职责**：init-llm.sh 只负责切 provider，路由交给上游 provider 自己
- **D2 文档优于代码**：删代码前先在 ADR 留底，未来要加回可参考本文件
- **D3 不破坏现有功能**：commit 9696e4b 已验证 init-llm.sh list/status/test/switch 全部正常

## 删除的内容（commit 9696e4b）

### 文件层（已 git rm）

| 文件 | 行 | 内容 |
|------|----|------|
| `option-llmswitch/init.sh` | 798 | Gateway 启动管理 + 配置 UI（`--config`）+ peak_hours/route 配置交互 |
| `option-llmswitch/proxy.py` | 439 | FastAPI 网关代理（HTTP 透传 + model 字段重写）|
| `option-llmswitch/watchdog.sh` | 108 | Gateway watchdog（30s 周期 health check + 自动重启）|
| `option-llmswitch/README.md` | 141 | Gateway 文档 |
| `option-llmswitch/conf/llmswitch.json.example` | 17 | Gateway 配置模板 |

**总删除 ~1503 行**。

### init-llm.sh 函数层（-148 行）

删除：
- `is_proxy_running()` — 检 pid 文件
- `get_gateway_status()` — 读 :8899/health
- `read_gateway_routes()` — 读 llmswitch.json 路由摘要
- `stop_gateway()` — 停 gateway 进程 + watchdog
- `switch_to_gateway()` — 起 gateway + 写 settings.json env 块
- `switch_llm` 内 `gateway` case 分支
- `switch_custom` 内 `stop_gateway` 调用
- `verify_endpoint` gateway 探测豁免
- `show_status` 内 `elif is_proxy_running` 分支
- `show_list` 内 `[[ "$current" == "gateway" ]]` 渲染
- 菜单渲染 `2D Gateway 切换规则`
- `BUILTIN_PRESETS` 去 `gateway`
- 顶部变量 `LLMSWITCH_CONF/INIT/WATCHDOG`

### maintain.sh 入口层（-2 行）

删除：
- `llmswitch|llm-switch|gate)` case 分支（指向已删 init.sh）

### llm.json schema 层（ccprivate）

删除：
- `llms.gateway` preset
- `llms.altllm / altllmtail / altllmdsp / altllmdsp_tail` 合并为 `office-deck-flash / home-deck-flash / home-deck-pro`（详见 [ADR-0029](./0029-init-llm-target-2026.md) §Decision Commit 5）

## Decision

**删除整套 gateway 模式**，不留 fallback 代码。本 ADR 作为未来找回的唯一参考。

### 未来如需重启 Gateway 模式

#### 触发条件
- 多 provider 切换场景重新出现（>2 个真在用）
- 用户希望按时间段自动路由（peak/off-peak）
- 商业网关（OpenRouter/LiteLLM）方案被否决后自建需求回归

#### 恢复步骤（按依赖顺序）

1. **git revert 9696e4b** — 恢复 option-llmswitch/ 整目录 + init-llm.sh gateway 段 + maintain.sh case
2. **重写 init-llm.sh switch_to_gateway** — 当前实现依赖已删除的 `is_proxy_running` / `get_gateway_status` 链
3. **更新 BUILTIN_PRESETS** — 重新加入 `gateway` 项
4. **ccprivate/conf/llm.json** — 重新添加 `gateway` preset + `routes.llmgateway.peak/off_peak` 配置
5. **重启 init-llm 菜单** — 验证菜单 `2D Gateway 切换规则` 显示正常
7. **重新评估依赖**：proxy.py 用 FastAPI + httpx，需 Python 3.10+ + httpx + fastapi + uvicorn（详见 `lib/deps-check.sh` 是否还在检测这些）

#### 恢复前必做的调研

- **不要直接 revert 代码** — 9696e4b 之后 init-llm.sh 大量重构（5 个 stability 增强），直接 merge 会冲突
- **重新评估 OpenRouter/LiteLLM 商业网关方案** — 2026-09 调研报告：商业网关成本 < 自研（详见 [docs/init-llm.md §四 架构决策](../init-llm.md#四架构决策基于-2026-09-调研)）
- **优先 fork empero-org/claude-code-proxy**（Agent 1 调研结论）替代自研 proxy.py

## Consequences

### Positive

- ✅ 删除 ~1500 行无用代码（option-llmswitch + init-llm gateway 段 + maintain.sh 入口）
- ✅ init-llm.sh 单一职责（切 provider + 起 bridge）
- ✅ llm.json schema 精简（preset 9 → 7，砍 gateway）
- ✅ 配置集中（LLM 配置只在 llm.json，无 llmswitch.json 平行）

### Negative / Risks

- ⚠️ **代码不可恢复（除 git revert）**：删除是 init script 的即用代码，需新 ADR 论证为什么策略反转才能恢复
- ⚠️ **用户多 provider 自动路由需求回归**：本 ADR §"未来如需重启" 是唯一参考
- ⚠️ **git revert 冲突风险**：9696e4b 后 init-llm.sh 有 5 次稳定性增强 commit（211b2ba + others），直接 revert 3696e4b 会冲突

### 如何缓解

- ✅ 本 ADR 留底，git log 可查 commit 9696e4b
- ✅ [docs/init-llm.md §四 架构决策](../init-llm.md#四架构决策基于-2026-09-调研) 保留替代方案调研结论
- ✅ [docs/init-llm.md §十一 未来工作](../init-llm.md#十一未来工作) 记录可能的演进路径

## Related

- [ADR-0029 init-llm 目标](./0029-init-llm-target-2026.md) — 本删除的父决策
- [docs/init-llm.md](../init-llm.md) — 目标文档
- commit `9696e4b` — 删除实施
- commit `a0e1f99` — 目标文档落地
- commit `c6168ed` — ADR-0029
- commit `2779911` — llm.example 同步
- commit `e7ff235` — ccprivate preset 合并
- memory `init-llm-2026-target-doc` — 本次决策汇总
- memory `windows-tailscale-not-wsl-20260917` — 相关设计假设