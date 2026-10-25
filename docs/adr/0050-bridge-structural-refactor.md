# 0050. bridge 结构性重构：传输与协议分离、判定单点化、spawn 共用

> **Status**: ✅ Accepted
> **日期**: 2026-10-16
> **关联**: `option-llmswitch/openai_bridge.py`、`lib/ensure-bridge.sh`、`lib/bridge-restart.sh`、`lib/init-llm.sh`、`lib/status.sh`、`maintain.sh`、`tests/test-bridge-protocol.py`
> **模板**: MADR 4.0 极简版
> **2026-10-25 复核**: 「不再写 `/tmp/*.sh` wrapper」结论需限定 —— `_bridge_spawn` 确实改为 setsid 直起、不落明文 Key；但**看门狗层**仍生成 `~/.cache/bridge-watchdog-*.sh` wrapper（`lib/ensure-bridge.sh`），该 wrapper 只用于自记 PID，**不含 Key**。另：文中行数矩阵（`ensure-bridge.sh 454` 等）为当时快照，现已增长。

## Context and Problem Statement

office/home 接入内网 LLM 的链路经多轮事故驱动修补后，出现了典型的**补丁堆积**形态。一次针对该链路的系统性复查发现：功能可用，但结构上同一决策有 2~4 份实现、同一逻辑有 2~4 份拷贝，且**已经漂移过至少一次**。

### 复查发现的重复与漂移

| 逻辑 | 原有份数 | 位置 | 漂移后果 |
|---|---|---|---|
| 「是否需要 bridge」 | **4** | `_bridge_supported` / `bridge-restart.sh` / `switch_llm` / `test_llm` | 规则已不一致 |
| win_curl 判定 | 2（逐字重复） | `ensure_bridge` / `bridge-restart.sh` | domain 上游首启走 win_curl、watchdog 重启退回 httpx，**静默漂移** |
| bridge spawn | 2 | 同上 | kill/skip-tls/env-strip/cd/log 六段重复 |
| 传输 × 流式分支 | 4 | `messages()`（win_curl/httpx × 流式/非流式） | 非流式两份错误处理逐字重复，**已漏过状态码检查** |
| finish_reason 映射表 | 2 | 流式 / 非流式 | 改一处必漂移 |

### 协议层缺陷（同批修复）

端到端测试用 mock upstream 只造 `delta.content + [DONE]` 一种形态，因此以下缺陷**全部落在盲区外**，长期存在且无告警：

- `[DONE]`-only 空流发出**没有 `message_start`** 的 delta+stop（协议非法）
- 文本块未在工具块前关闭 → 块 index 交错；`_alloc_idx` 早于守卫 → index 空洞
- `tool_calls` 无 `index` 时并行工具全落 `tool_0` → name 覆盖、arguments 拼接损坏
- usage 覆盖写而非取 max → 缺字段的 chunk 把已累计输出清零
- 未请求 `stream_options.include_usage` → input_tokens 可能恒 0
- `stop_sequences` 因字段名与 OpenAI 不一致（`stop`）从未透传
- `tool_result.is_error` 丢弃、多 text 块只取第一个、`url` 型图片整块丢弃、多段 system 只第一段生效
- 错误路径不闭合已开块 → 悬空 `content_block_start`

## Decision Drivers

- **D1 单点化**：同一决策只能有一份实现，否则必然再次漂移
- **D2 关注点分离**：传输（怎么送到上游）与协议（Anthropic↔OpenAI）不应互相渗透
- **D3 测试要能守住**：不在测试盲区里的缺陷才算修完

## Decision

### 1. 传输与协议分离（Python）

新增 `_upstream_stream()` / `_upstream_post()` 两个统一入口，把 win_curl/httpx 的差异收进函数内部。`messages()` 从「四种组合各写一遍」变为**每条路径一份**，非流式的状态码检查等逻辑不再有重复可漏。

### 2. 判定单点化（Shell）

新增 `preset_bridge_mode <preset> <cfg>`（三态：`bridge`/`direct`/`conflict`）与 `bridge_win_curl <upstream> <cfg> <preset>`，原先 4 份 + 2 份实现全部改为调用它们。

### 3. spawn 共用

新增 `_kill_by_port` / `_bridge_spawn`，`ensure_bridge` 与 `bridge-restart.sh` 共用。

**`_bridge_spawn` 改用 `setsid` 直起，不再写 `/tmp/*.sh` wrapper**：原 wrapper 机制的存在理由是"裸 `( cd; nohup ... & )` 会被 SIGHUP 杀掉"，而 `setsid` 给新会话（无控制终端 → 收不到 SIGHUP）解决同一问题，同时**不必把 API Key 落盘**（旧 wrapper 含明文 Key，脚本被中断就残留在 /tmp）。

### 4. 生命周期缺陷同批修复

| 缺陷 | 修法 |
|---|---|
| `selfheal_bridge` 三处"其实没检查"却报健康 | 引入第三态 `10=N/A`，调用方据此区分"通过"与"跳过" |
| watchdog PID 文件写的是 `setsid` 的 pid（已 fork），长期失效 | wrapper 自写 `$$` |
| 并发 `ensure_bridge` 产生双 watchdog → kill/spawn 抖动 | `flock` 串行化 |
| 删除的 preset 令 watchdog 以 60s 上限无限空转 | `bridge-restart.sh` 引入 `rc=2`（永久性错误），watchdog 长退避 |
| `llm-current` 在 bridge 启动之后才写 → 窗口期 watchdog 按旧 preset 复活 | 提前落盘 + 探测失败回滚 |
| `bridge-restart.sh` 无条件 `exit 0`，启动失败学不到 | 等 health 确认，失败返回 1 |
| 三处"桥在跑但 preset 已切直连"的孤儿无人检查 | 新增 `bridge_state_check [--fix]`，接进 `maintain.sh fix` 与 `status.sh` |

### 5. 补测试盲区

新增 `tests/test-bridge-protocol.py`（26 项）：直接驱动转换函数，逐条钉住上述协议行为。端到端用例守不住的部分由它守。

## Consequences

- ✅ **消除漂移面**：判定/传输栈/spawn 各自单点，加字段只需改一处
- ✅ **协议层缺陷归零**：8 类问题修复，26 项单测覆盖
- ✅ **不再有明文 Key 落盘**：wrapper 机制退场
- ✅ **孤儿与不一致可被自动发现**：`maintain.sh fix` 一键修，`status.sh` 启动时提示
- ✅ **回归有据**：既有 4 个测试套件 + 新增 1 个全部通过
- ⚠️ **`flock` 必须带 `9>&-`**：首版漏了，watchdog 常驻继承 fd 9 导致锁永不释放，`start_bridge_watchdog` 直接挂死（实测让测试套件卡 7 分钟）。已修，并给 flock 加 `-w 30` 超时兜底把「挂死」降级为「跳过本轮」
- ⚠️ **`setsid` 替换 wrapper 改变了进程父子关系**：已验证 health、kill、watchdog 复活三条路径正常

## Implementation

### 验证矩阵（全部实测通过）

| 项 | 结果 |
|---|---|
| `py_compile` / `bash -n` | 全通过 |
| `tests/test-bridge-protocol.py` | 26/26 |
| `tests/test-openai-bridge.sh` | 19/19 |
| `tests/test-init-llm-switch.sh` | 10/10 |
| `tests/test-syntax.sh`、`test-maintain.sh` | rc=0 |
| `ensure_bridge` 端到端 | health OK，`use_win_curl=False`（office 直连 httpx） |
| `bridge-restart.sh` 三态 | 正常 rc=0 / 不需 bridge rc=0 / preset 不存在 rc=2 |
| watchdog 自动复活 | 杀掉 bridge 后 8s 内恢复 |
| `bridge_state_check --fix` | 正确识别孤儿并停用，复检 rc=0 |

### 规模变化

| 文件 | 变化 |
|---|---|
| `openai_bridge.py` | 1052 → 1141 行（+传输抽象/-死代码/+协议修复） |
| `ensure-bridge.sh` | 281 → 454 行（+共用 helper/+一致性检查） |
| `bridge-restart.sh` | 64 → 51 行（判定与 spawn 外移） |

行数上升主要来自注释：本链路每一次改动都伴随事故，注释记录的是"为什么不能改回去"。若只看代码，重复逻辑实际显著减少。

## Related Decisions

- [0019](0019-bridge-win-curl-wsl-vpn.md) — bridge win-curl 双模式（本 ADR 保留其设计，仅收敛实现）
- [0031](0031-init-llm-consolidation-2026.md) — init-llm 合并（本 ADR 继续同一方向的收敛）
- [0048](0048-wsl-large-upload-stall.md) — 本 ADR 顺带撤销其无效结论
- [0049](0049-auto-mode-discards-allow-rules.md) — 同环境另一层问题

## Notes

- `_bridge_supported`（URL 级守卫）保留：它是 `ensure_bridge` 内部的安全网（防止误把 Anthropic 原生端点过桥），与决策层 `preset_bridge_mode` 职责不同，不重复。
- `get_use_bridge` 因决策单点化而完全失去引用，已删除。
