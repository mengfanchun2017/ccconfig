# 0034. bridge 块索引唯一化 + 重复投递丢弃 + thinking 开关（enable_thinking）

> **Status**: ✅ Accepted
> **日期**: 2026-09-22
> **关联**: `option-llmswitch/openai_bridge.py`、`tests/test-openai-bridge.sh`（T11–T13）

## Context and Problem Statement

用内网 LLM 网关（OpenAI 协议，`deepseek-v4-flash`）经 `openai_bridge.py` 接 Claude Code 跑 agent 任务，三个症状：

1. **输出一段文字后回退、再输出一次**；`tool_use` 被**执行两次**（Read 两次、Bash 两次，副作用翻倍）。
   现场 transcript（`~/.claude/projects/-home-francis-git-ccconfig/2c94fe32-*.jsonl`）证据：
   连续两条 assistant 记录 `msgid=msg_bridge`、`apiBlockIndex=0`、**同一个 tool_use id**、同一 usage，
   间隔 34ms；对照正常直连会话每条记录的 `apiBlockIndex` 逐块递增（0/1/2）。
2. **模型把思维链当正文吐出来**，并在里面卡成重复循环
   （"我现在执行。发送！执行。Send the calls now." → 13.5KB 未完成消息，用户手动打断）。
   现场 `[71]` 记录 `stop=None`、`usage` 全 0，即流被掐断在中途。
3. `message_start.usage.input_tokens` 恒为 **0**（CC 侧上下文余量/自动压缩全失灵），
   长会话跑到撞上游真实窗口才报错。

## Root Cause

### R1 块索引撞号（症状 1 的根因）

`openai_chunk_to_anthropic_sse` 里文本块**硬编码 index 0**，工具块从 `state["block_idx"]`
（初值 0）开始分配。一条"先说话再调工具"的响应（实测很常见：66/466 分片里前 15 片是正文）
于是产生 `start(0,text) … start(0,tool) … stop(0) stop(0)` —— **同一个 message 里两个同 index 的
content_block_start**，Anthropic 协议不允许。CC 按 index 收尾，把正文块重放/丢弃，工具块重复收尾 → 工具执行两次。

复现证据（旧码 f1f70d3 vs 新码，同一输入）：

| | 旧版 | 新版 |
|---|---|---|
| 文本+工具一条响应 | `block_start=[0,0]` `block_stop=[0,0]` | `[0,1]` / `[0,1]` |
| 收尾后重复投递 | 又发一遍 `[0,0]` 块 | 0 新事件 |
| `input_tokens` | `0` | `42`（上游真值） |

### R2 `reasoning_effort` 不打开思考（症状 2 的根因）

实测单位网关对 `deepseek-v4-flash`（A/B，同一 prompt）：

| 请求参数 | reasoning_content | reasoning_tokens | content |
|---|---|---|---|
| 无 | 0 字 | 0 | 直接给答案 |
| `reasoning_effort: high` | 0 字 | 0 | 思路混进正文 |
| `thinking: {type:"enabled"}` | 0 字 | 0 | — |
| **`enable_thinking: true`** | **628–1113 字** | **143–278** | 干净正文 |
| `enable_thinking: true` + `reasoning_effort: high/medium` | 688 / 192 字 | 173 / 44 | 干净正文 |

即：**开关是 `enable_thinking`，`reasoning_effort` 只调深度**。只发 `reasoning_effort` 时模型不思考，
把推理当 `content` 吐出来 → CC 把它渲染成回答 → 模型看着自己上一轮的空转叙述继续空转，直至卡死循环。
另外 CC 2.1.274 发的是 `thinking: {"type":"adaptive","display":"omitted"}`（没有 `budget_tokens`），
原 bridge 只认 `type == "enabled"`，那条分支对现版本 CC 是**死代码**。

### R3 收尾后内容未丢弃（症状 1 的放大条件）

`[DONE]` 之后仍有内容到达时（网关重复投递/收尾后补发），原 bridge 没有任何守卫：
块已 `stop` 又会 `_close_text_block`/`_close_tool_blocks` 之外重开，且 `[DONE]` 分支只防了自身重复。

## Decision

1. **块索引唯一化**：`_alloc_idx()` 单调递增，文本块与工具块共用；文本块不再硬编码 0，
   模型"工具后再说话"时开**新 index**（协议允许），彻底消除撞号。
2. **收尾后内容丢弃**：`terminal = finished or stopped` 时丢弃 text/tool 增量并计入 `dup_blocks`；
   工具块索引已关闭后再被投递同样丢弃。usage 不丢（仍累计 `output_tokens`）。
3. **thinking 开关**：`thinking.type in ("enabled","adaptive")` → 上游 `enable_thinking: true`；
   `reasoning_effort` 继续按 `output_config.effort`（用户显式 effort）优先、`budget_tokens` 兜底映射深度。
4. **真 `input_tokens`**：usage 提前到 `_ensure_started` 之前记账，`message_start` 带上游 `prompt_tokens`。
5. **思考期心跳**：reasoning 分片被 bridge 丢弃时 CC 侧零字节，按"距上次真正输出 ≥10s"补 `: ping` 注释
   （`quiet_pings` 计数），避免长思考撞 tailscale 75s / 网关 idle cap。
6. **观测设施**：`OPENAI_BRIDGE_DUMP=<dir>` 落盘每请求上游原始 chunk；
   每请求一行摘要 `[bridge] stream done req=N text_blocks=… tool_blocks=… dup_blocks=… stop=… quiet_pings=…`；
   `message id` 由常量 `msg_bridge` 改为 `msg_bridge_<req>`（两条独立响应此前无法区分）。

## Consequences

- 工具不再重复执行，回退重放消失；先前被吞的正文（text 块）正常呈现。
- 模型思考回到 `reasoning_content`（bridge 丢弃），CC 侧正文干净，空转循环的土壤消失。
- 长会话的上下文统计恢复可信（`input_tokens` 真值）。
- 思考深度会随 `reasoning_effort` 变化 → 高 effort 下上游输出 token 变多、延迟变长（实测硬推理任务 76s、
  `out_tok=4779`），这是"真思考"的代价，心跳保证期间不断流。
- `enable_thinking` 是 OpenAI 兼容栈（vLLM/SGLang 系）的通用开关；其它 preset（如 `glm53flash`/智谱 paas/v4）
  实测带上该字段仍正常返回（未识别字段被忽略），无需按 preset 配置。
- 回归覆盖：`tests/test-openai-bridge.sh` T11（开关）、T12（索引不撞号 + stop + input_tokens）、
  T13（重复投递丢弃），共 13 项。

## 已知局限

- 上游**只在末尾**带 `usage.prompt_tokens` 的网关（智谱 paas/v4 实测如此），
  `message_start.usage.input_tokens` 仍是 0（首块无真值）。未把 `input_tokens` 塞进收尾
  `message_delta` —— 怕 CC 重复累加导致上下文虚高、提前压缩。
