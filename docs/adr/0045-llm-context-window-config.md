# 0045. LLM 上下文窗口可配置 — 预设 `max_context_tokens`（单位 k）+ 菜单/CLI 输入 + 全局默认

> **Status**: ✅ Accepted
> **日期**: 2026-10-13
> **关联**: `lib/init-llm.sh`、`lib/menu-data-maintain.sh`、`conf/llmnormal.json`、`ccprivate/conf/llmprivate.json`、`templates/settings.json.example`、`tests/test-init-llm-switch.sh`、`tests/test-init-llm-merge.sh`、`tests/test-json-schema.sh`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

Claude Code v2.1.257 起引入 model catalog：模型名不在内置 catalog 时（本项目所有第三方上游：`deepseek-*`、`glm-*`、`mimo-*`、`MiniMax-*`），auto-compact **默认按 200k 假设窗口**并打印 `unrecognized_model` 警告。第三方模型真实窗口往往更大（如 400k），按 200k 处理会导致过早 auto-compact、白白浪费上下文。

Claude Code 提供 env `CLAUDE_CODE_MAX_CONTEXT_TOKENS` 声明真实窗口（该 env **全局生效**，与 preset 无关）。此前实现把它挂在 preset 定义的 `max_context_tokens` 字段上，但存在三个问题：

1. **值必须手改 JSON、含义不直观**：字段历史单位是绝对 token（`262144`），用户想设「400k」要自己换算，且无任何输入界面——只能手改 `llmprivate.json`。
2. **无全局默认**：未声明该字段的预设直接回落 CC 的 200k 假设，想统一窗口得逐个 preset 补字段。
3. **内置预设改不了**：内置预设定义在公开的 `ccconfig/conf/llmnormal.json`（随仓库分发），改它会被下次 `self config` 覆盖；而旧合并逻辑里 private 同名条目 = 整条覆盖并翻成「自定义」（`_src=private`），既会与 ccconfig 更新漂移，又会让内置预设「变成可删」。

## Decision Drivers

- **D1 可输入**：窗口值应能从运维菜单/CLI 输入，不必手改 JSON。
- **D2 单位直观**：用户按「k tokens」思考（400 = 400k），定义文件就该存 400，不存 400000。
- **D3 有默认**：预设不声明时应有可配置的全局默认，覆盖 CC 的 200k 兜底。
- **D4 内置可改而不漂移**：改内置预设窗口不能整条复制内置定义（会被更新覆盖 / 语义漂移）。
- **D5 可见性**：当前窗口是多少，状态视图一眼可见。
- **D6 生效路径清晰**：改完提示用户怎么让改动生效。

## Considered Options

1. **新增独立配置文件存窗口**（如 `conf/llm-context.json`）— 要新开一套读写 + 合并，与三层 LLM 配置重复，且窗口本就是「预设属性」，拆出去语义别扭。
2. **沿用 preset 字段 + 只加菜单输入** — 解决 D1/D5，但 D3/D4 仍在。
3. **preset 字段（单位改为 k）+ 全局默认文件 + 字段级薄覆盖**（选中）— 复用三层配置与合并缓存，改动集中。

## Decision

把窗口建模为**预设属性 + 全局默认**，全部经 `lib/init-llm.sh` 读写：

1. **单位统一为 1000 tokens**（k）。预设字段 `max_context_tokens: 400` 表示 400k。写进 CC env 时乘 1000 → `400000`。
2. **全局默认**：`DEFAULT_MAX_CONTEXT_TOKENS`（默认 400）。优先级 env > 本机文件 `~/.claude/llm-context-default` > 400。预设未声明该字段时套用。
3. **每个预设切换都写 env**：`get_max_context_tokens <preset>` 解析出绝对 token 数，`switch_llm` 写入 `CLAUDE_CODE_MAX_CONTEXT_TOKENS`（不再「未声明就 pop」——未声明落全局默认）。
4. **内置预设薄覆盖**：改内置窗口时在 `llmprivate.json` 写**只含 `max_context_tokens`** 的条目；合并改字段级，薄条目只覆盖该字段且 `_src` 保持 `normal`（内置仍不可删）。含其它字段的 private 同名条目仍是整条重定义（`_src` 翻 `private`）。
5. **输入界面**：运维菜单 `4H`（`./maintain.sh llm ctx`）+ LLM 交互菜单 `3c`。先选目标（顶部为「全局默认」，其余为各预设，显示各自当前值），再输入 k 值。非交互 `bash init-llm.sh ctx <preset|default> [<k>]`。
6. **可见性**：`init-llm status`（菜单 `4C`）显示「预设声明窗口」与「env.MAX_CONTEXT_TOKENS」；交互菜单头显示「窗口 Nk」。
7. **生效提示**：改完提示——窗口随切换写入 env；若改的是当前预设需重切一次再 `/exit` 重启 Claude。

## Consequences

- ✅ 窗口值可菜单/CLI 输入，单位直观（k），有全局默认兜住未声明预设。
- ✅ 内置预设窗口可改且不与 ccconfig 更新漂移（薄覆盖条目只有一行字段）。
- ✅ 每个预设切换都显式写 env，杜绝「残留上一个预设窗口」。
- ✅ 状态视图暴露预设声明值 + env 实际值，便于核对。
- ❌ 合并逻辑复杂化：需区分「薄覆盖（仅 max_context_tokens）」与「整条重定义」。用 `set(spec.keys()) - {'max_context_tokens'}` 判定，并加 T7 回归兜住。
- ⚠️ 单位从绝对 token 改为 k 是一次性 schema 变更：旧机器若残留 `262144` 会被当成 262144k → ×1000 溢出。缓解：本项目两份定义文件（`llmnormal.json` / `llmprivate.json`）已同步改为 k 单位（`400`）；schema 测试新增 range 校验（1–10000），越界即失败。
- ⚠️ 全局默认文件 `~/.claude/llm-context-default` 是本机级（不入 git），多机需各自设置；未设置时回落常量 400。

## Implementation

- `lib/init-llm.sh`
  - `DEFAULT_MAX_CONTEXT_TOKENS`（env > `~/.claude/llm-context-default` > 400）
  - `get_max_context_raw()`（k 单位原始值，未声明为空）/ `get_max_context_tokens()`（绝对 token，未声明落默认）
  - `set_max_context_tokens()` / `_edit_preset_ctx()` / `_set_global_default_ctx()` / `_ctx_howto_apply()`
  - `_llms_merged_py()`：字段级合并 + `_src` 薄覆盖判定
  - `write_llm_config`（不再 pop）、`show_status` / `_llm_status_header`（显示窗口）
  - 子命令 `ctx`；交互菜单 `3c`
- `lib/menu-data-maintain.sh`：新增 `4|H|设置上下文窗口`
- `conf/llmnormal.json`：4 个内置预设 `max_context_tokens: 400`
- `ccprivate/conf/llmprivate.json`：6 个自定义预设 `max_context_tokens: 400`
- `templates/settings.json.example` / `ccprivate/link/settings.json.example`：补 `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
- 测试：`test-init-llm-switch.sh` T8（写 env，声明值 + 默认）、T9（ctx 写入 + 内置薄覆盖）、`test-init-llm-merge.sh` T7（薄覆盖 `_src` 保持 normal）、`test-json-schema.sh`（`max_context_tokens` range 校验）、`test-init-llm-switch.sh` 端口可用 env 覆盖（`TEST_BRIDGE_PORT`）

## Related Decisions

- `ADR-0039`（`0039-llm-three-tier-config.md`）— 本决策扩展其三层配置：定义文件新增 k 单位 `max_context_tokens`，合并语义从「整条覆盖」细化为「字段级 + 薄覆盖」。
- `ADR-0020`（`0020-llm-current-local-per-machine.md`）— 全局默认文件与 `llm-current` 同为「本机级」，不跨机同步。

## Notes

- 若上游真实窗口小于所设值，超长请求会被上游截断/报错；设值应 ≤ 上游真实窗口。
- `max_context_tokens` 只对「CC 未识别模型名」有意义；识别为 `claude-*` 的模型由 CC 内置 catalog 定窗口，此 env 不参与。
