# 0033. 收窄 bridge 流式 usage message_delta 为收尾一次

> **Status**: ✅ Accepted
> **日期**: 2026-09-20
> **关联**: `option-llmswitch/openai_bridge.py`

## Context and Problem Statement

用单位网关（国航 AI+，`deepseek-v4-flash`）经 `openai_bridge.py` 接 Claude Code 时，
处理过程中经常「输出一半就回退又重新输出」。

排查发现两个叠加因素，根因在 bridge 的**流量放大**，不在 CC 端：

1. **每个 token 一个 usage message_delta**：上游（DeepSeek 系）在每个 chunk 都带完整 `usage.completion_tokens`，
   bridge 逐 chunk 转成一个 `message_delta(usage)`。实测 200 字响应：302 个事件里 154 个是 usage-only delta，
   ≈ 与正文 token 数同量级的冗余事件。
2. **上游输出很慢**：长输出实测要 60s+（撞 curl 超时），上游吐 token 节奏慢。

两者叠加：慢速上游 + 海量冗余（且每个都带 `delta.stop_reason=None`）的事件流，
CC 端容易把「慢 / 事件模式异常」误判为超时或坏流，触发**自动重试** —— 表现正是
「输出一半，回退重新开始」。

CC 侧的 `POST /v1/messages` 在一次处理里出现几十次，就是 CC 自己发的重试/多轮，
bridge 每次都正常收尾交付，掐断的决定是 CC 做的。bridge 侧零错误帧，
`stop_reason` 唯一、收尾完整。所以根因不是截断，是**冗余事件 + 慢速**给了 CC 误判的空间。

## Decision Drivers

- **D1** 减少下游事件量，降低 CC 误判慢流/坏流的概率
- **D2 改动风险要小** —— 收尾语义（真实 `stop_reason`、`message_stop`、usage 最终值）必须保持
- **D3** 兼容前两次 bridge bug 记录（stop_reason 覆盖、non-SSE 归因）不能被这次改坏

## Considered Options

1. **usage message_delta 只在收尾 `[DONE]` 发一次**（采用）— pros：流量降到 ~1/154，收尾语义完整；
   cons：流式过程中没有 usage 增量（Claude Code 不依赖每步输出 token 数，可接受）。
2. **保留每 token usage，靠 CC 侧放宽超时** — cons：改 CC 二进制/文档，绕且不可控，未解决流量问题。

## Decision

`openai_chunk_to_anthropic_sse` 里 usage 分支**只记账不发事件**：
```python
if usage:
    state["output_tokens"] = usage.get("completion_tokens", 0)
```
最终 usage 合并进 `[DONE]` 分支发出的收尾 `message_delta`：
```python
stop_delta = {"type": "message_delta", "delta": {...stop_reason...}}
if state.get("output_tokens"):
    stop_delta["usage"] = {"output_tokens": state["output_tokens"]}
```
事件序列由
`content_block_stop → message_delta(usage) ×N → message_delta(stop_reason) → message_stop`
变为
`content_block_stop → message_delta(usage + stop_reason) → message_stop`。

usage-only delta（`delta.stop_reason=None`）被移除，也顺带消除了「usage 覆盖真实 stop_reason」的隐患。

## Consequences

- ✅ 下游事件量从 ~154 降为 **1**（长输出尤甚），CC 误判重试的概率下降
- ✅ 真实 `stop_reason` 保持唯一，`message_stop` 仍在
- ✅ 回归测试 `test-openai-bridge.sh` 9 项全通过
- ❌ 流式过程中不再有 usage 增量事件（CC 不依赖，无实际影响）
- ⚠️ 这缓解的是「流量放大导致 CC 误判重试」这一条。若 CC 仍因**输出太慢撞 CC 侧硬超时**而重试，
  还需另查 CC 等待超时/输出窗口；本 ADR 不覆盖那部分。

## Implementation

- `option-llmswitch/openai_bridge.py`：usage 分支只记账 + `[DONE]` 合并发送
- 验证：`bash ccconfig/tests/test-openai-bridge.sh`（9/9 过）+ 真实网关请求
  （`usage 块=2`、正文完整、`stop_reason` 唯一、0 error）

## Related Decisions

- `0020` 附近桥接相关 — bridge 稳定性系列
- [[bridge-stop-reason-overwrite-20260920]] — 收尾 stop_reason 语义，本次改动仍遵守（真实 stop_reason 排最后且不覆盖）
- [[bridge-nonsse-error-misreported-20260917]] — 错误归因，未受影响

## Notes

后续如果「输出一半回退」仍出现，方向转向 **CC 侧输出窗口/等待超时**——
`deepseek-v4-flash` 对 CC 是不知名模型，走 fallback 窗口，且 `max_tokens` 传多少网关都不拒
（实测 16384/32768 均正常）。那才是另一条独立链路。