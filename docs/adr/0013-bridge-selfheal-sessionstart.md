# 0013. OpenAI bridge 自愈：SessionStart hook + env guard

> **Status**: ✅ Accepted
> **日期**: 2026-08-13
> **关联**: `lib/ensure-bridge.sh`、`lib/status.sh`、`lib/init-llm.sh`、`option-llmswitch/openai_bridge.py`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

`openaialt` 等 OpenAI-only 端点（如 `https://aiplus.airchina.com.cn:18080/v1`）切换时，`init-llm.sh` 启动 `openai_bridge.py`（127.0.0.1:8898）并把 `ANTHROPIC_BASE_URL` 持久化为 `http://127.0.0.1:8898`。bridge 是 `nohup` 后台进程，**无 systemd 服务、无开机自启**，watchdog.sh 只盯 8899 gateway 不管 8898。

**重启后**：bridge 进程没了，settings.json 仍指向 8898 → claude 启动连不上 → 报错。用户需手动"先切别的 LLM 再切回 openaialt"重拉 bridge。bridge 中途被 kill 也有同样问题。

## Decision

采用方案 A：**在已有 SessionStart hook（status.sh）里加 bridge 自愈检查，用 env guard 条件化**。桥接拉起逻辑抽到 `lib/ensure-bridge.sh`，与 `init-llm.sh` 共用。

### 1. env guard 隐式开关（核心）

判断条件 = settings.json 的 `ANTHROPIC_BASE_URL` 是否含 `127.0.0.1:8898`：

- minimax/deepseek 直连、gateway → env 永不含 8898 → grep 短路，零动作
- openaialt → env 指 8898 → 进入检查

**"配置了"本身就是开关**。用户无 OpenAI-only 预设 → 永远不会切过去 → 检查永不执行。无显式配置项，别的用户零感知。

### 2. 检查时机

`check_bridge_selfheal()` 挂在已有 SessionStart hook（`bash lib/status.sh`，全局已存在，非新增 hook）。claude 是 8898 的 client，hook 在 claude 连 8898 前跑完，时机天然正确。

### 3. 拉起逻辑复用

`_ensure_openai_bridge` 从 `init-llm.sh` 迁至 `lib/ensure-bridge.sh`（`ensure_bridge` / `read_bridge_config` / `_bridge_supported`），两处调用。`_bridge_supported` 内置 OpenAI-only 校验（非 `/anthropic`、非本地、非空），防错配预设被错误拉起。

### 4. 最小代价保证

- guard 用 `grep`（1ms），不配置用户多 1 次 grep 即短路
- `ensure-bridge.sh` **延迟 source**：guard 命中才加载，普通用户不加载该库

## Consequences

### Positive

- ✅ 重启后 claude 启动自动拉起 bridge，无需手动切换
- ✅ 未配置 OpenAI-only 端点的用户零开销（1 次 grep）
- ✅ 桥接逻辑单点维护（lib/ensure-bridge.sh），init-llm.sh 瘦身 ~50 行

### Negative / Risks

- ⚠️ 只覆盖"会话启动时"，bridge 在会话运行中崩溃不自愈（低频，接受）
- ⚠️ env 与 llm.json current 错配时（手动改配置）可能拉起错误 upstream，`_bridge_supported` 校验可挡大部分

## Implementation

- `lib/ensure-bridge.sh` — **新增**：`ensure_bridge` / `read_bridge_config` / `_bridge_supported`
- `lib/init-llm.sh` — 删 `_ensure_openai_bridge`（迁出），`source ensure-bridge.sh`，调用改 `ensure_bridge`
- `lib/status.sh` — **新增** `check_bridge_selfheal()`，main 调用处追加
- 验证：`bash -n` 三文件；`status.sh --quick` 无回归；`ensure_bridge` 端到端拉起 + upstream 复用 + 清理

## Related Decisions

- [[0012-interact-p0-no-gum]](0012-interact-p0-no-gum.md) — SH 交互规范化（本 ADR 沿用 lib/ 结构约定）
