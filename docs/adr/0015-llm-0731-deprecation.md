# 0015. 废弃 altllm0731 preset — 停止自改 bridge 适配网关不兼容

> **Status**: ✅ Accepted
> **日期**: 2026-08-23
> **关联**: `lib/init-llm.sh`、`option-llmswitch/openai_bridge_*.py`、`ccprivate/conf/llm.json`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

### 起因

2026-08-20 起，用户尝试接入公司内部 DeepSeek-V4-Flash-0731 模型，作为 LLM 预设 `altllm0731`。该端点是 OpenAI 兼容格式（非 Anthropic 格式），需要 bridge 层做协议转换。

### 3 天踩坑过程

| 日期 | 现象 | 修复尝试 |
|------|------|----------|
| 08-20 | 初次接入，bridge 启动后 message_delta 无 `delta` 字段 | Claude Code 2.1.228 报 `delta.stop_details undefined` |
| 08-21 | 拆独立 bridge 文件 `openai_bridge_0731.py` + 端口 8897，避免污染原版 | 写 `_ensure_bridge_0731()` 单独启动 |
| 08-22 | tail 版 `if _fr or _usage:` 在 for 循环外 → `UnboundLocalError` 崩溃 | 三次写 apply_*.py 重写 SSE 解析函数 |
| 08-22 | 空 choices 的 usage chunk 漏 content_block_stop + 漏 usage | 改成累积 state + `[DONE]` 统一收尾 |
| 08-23 | Claude Code 仍报 stop_details 缺失 + 流中断 | — |

### 核心未解问题

1. **provider 行为变异**：DeepSeek-V4-Flash-0731 的 SSE 末尾格式与 flash 版本不同（最后一个 chunk 带 `finish_reason`、独立的空 choices usage chunk、不同的 `[DONE]` 时机）
2. **Claude Code 2.1.228 client 校验严格**：`message_delta` 必须带 `delta.stop_details`，缺字段直接报错流中断
3. **bridge 层 patch 边际收益递减**：每修一个症状冒两个新症状，apply_*.py 改了三轮仍未稳
4. **不同模型 chunk 格式差异固化**：不能用同一份 SSE 解析函数兼 flash + 0731，单文件+if-else 分支会失控

## Decision

### 1. 废弃 altllm0731 preset

删除：
- `option-llmswitch/openai_bridge_0731.py`（0731 独立 bridge）
- `option-llmswitch/test_stop_details.py`（0731 专用测试）
- `option-llmswitch/apply_sse.py` / `apply_sse_fix.py` / `apply_robust_sse.py`（三日三轮 patch 脚本）
- `option-llmswitch/new_sse_fn.py` / `sse_fn_new.py`（patch 辅助文件）
- `lib/init-llm.sh` 中的 `_ensure_bridge_0731()` 函数（约 55 行）
- `lib/init-llm.sh` 中 switch_llm 的 `if [[ "$name" == "altllm0731" ]]` 分支（约 6 行）

`ccprivate/conf/llm.json` 中 `altllm0731` 配置块保留（属用户私有，不动）。

### 2. 战略转向：不再为网关兼容性自改 bridge

未来遇到：
- LLM provider 仅 OpenAI 兼容、非 Anthropic 兼容
- provider SSE 格式异常（缺字段、chunk 顺序不同、usage 单独 chunk 等）
- Claude Code client 版本升级要求新字段

**应对原则**：
- ❌ 不再 patch bridge 适配 provider — 投入产出比太低，3 天只调通一个 model
- ✅ 直接用 Anthropic 兼容的 provider（如 Anthropic API 自身、MiniMax 的 `/anthropic` 端点）
- ✅ 或者降级使用通用 OpenAI bridge，跳 tool_use 等高级功能
- ✅ 真正遇到 Anthropic 协议不符，再考虑回退方案；不在 bridge 层打补丁

## Decision Drivers

- **投入产出**：3 天调试 → 0 个稳定 preset，沉没成本已高
- **替代充足**：现有 `minimax`、`deepseek_flash` 均 Anthropic 兼容，工作良好
- **战略选择**：ccconfig 是配置基础设施，不应深入每个 provider 的边角行为
- **风险隔离**：bridge bug 一改影响所有切换路径，牵连面太大

## Considered Options

| 选项 | 结论 |
|------|------|
| **继续修 0731 bridge** | ❌ 拒绝 — 3 天三轮未稳，撞墙 |
| **废弃 0731 + 不再自改 bridge** | ✅ 采用 — 本 ADR |
| 找公司 IT 修 provider 协议 | ❌ — 不归 ccconfig 管 |
| 切到其他 Anthropic 兼容模型 | ✅ 顺势 — 可选替代，无需修代码 |

## Consequences

### Positive

- ✅ **零 bridge 边际故障**：0731 相关的 `delta.stop_details`、`UnboundLocalError`、content_block_stop 漏发全部消失
- ✅ **降低维护负担**：`init-llm.sh` 简化 60+ 行；移除 apply_*.py 调试工件
- ✅ **战略清晰**：未来类似问题直接拒绝 patch

### Negative / Risks

- ⚠️ **0731 用户**：在公司用 DeepSeek-V4-Flash-0731 的用户失去一键切换能力（仍可直接配 base_url，但失去一键 preset）
- ⚠️ **决策僵化风险**："不再自改 bridge"是策略性决策，未来若遇到真实必接 Anthropic 不兼容 provider，可能错失机会
  - 缓解：策略可由后续 ADR 推翻，本 ADR 不阻塞技术进展
- ⚠️ **apply_*.py 历史**：3 天的 patch 脚本作废，但脚本中的 SSE 解析已手动整合进 `openai_bridge_*.py`（独立版本，不在此 PR 范围）

## Implementation

### 文件变更（本 ADR 落地）

| 文件 | 变更 |
|------|------|
| `lib/init-llm.sh` | 删 `_ensure_bridge_0731()` 函数；删 switch_llm 的 altllm0731 分支（保存条件合并到 else） |
| `option-llmswitch/openai_bridge_0731.py` | 删 |
| `option-llmswitch/test_stop_details.py` | 删 |
| `option-llmswitch/apply_sse.py` | 删 |
| `option-llmswitch/apply_sse_fix.py` | 删 |
| `option-llmswitch/apply_robust_sse.py` | 删 |
| `option-llmswitch/new_sse_fn.py` | 删 |
| `option-llmswitch/sse_fn_new.py` | 删 |
| `option-llmswitch/__pycache__/openai_bridge_0731.cpython-314.pyc` | 删 |

### 用户私有配置（不动）

`ccprivate/conf/llm.json` 的 `altllm0731` 配置块保留。用户如仍要用，可手动配 base_url 经通用 bridge，无需 preset 名（`init-llm.sh` 会自动按非 /anthropic 走通用 bridge 路径）。

### 未来如需重启 0731

直接反对。需新开 ADR 论证为什么策略反转。

## Related Decisions

- [[0014-bridge-win-curl-wsl-vpn]](0014-bridge-win-curl-wsl-vpn.md) — OpenAI bridge 的 WSL/VPN 修复（仍有效，本 ADR 不影响）
- [[0013-bridge-selfheal-sessionstart]](0013-bridge-selfheal-sessionstart.md) — bridge 自愈机制（仍有效）
- 内存 [[altllm-tail-separate-file]] — 需更新：去掉 0731 行（改为只记录 altllm/altllm_tail 两 preset）
