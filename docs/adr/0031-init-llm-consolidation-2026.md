# 0031. init-llm 收敛：桥接链路修复、探测统一与四层守护模型

> **Status**: ✅ Accepted
> **日期**: 2026-09-17
> **关联**: `lib/init-llm.sh`、`lib/ensure-bridge.sh`、`lib/bridge-restart.sh`、`option-llmswitch/openai_bridge.py`、`lib/status.sh`、`tests/test-openai-bridge.sh`、`tests/test-init-llm-switch.sh`
> **模板**: MADR 4.0 极简版
> **承接**: [ADR-0029](./0029-init-llm-target-2026.md)（目标）、[ADR-0030](./0030-gateway-deprecation-2026.md)（删 gateway）
> **关键 commit**: `3925ad0` `5203a5b` `d624a56` `74b4cfd` `72aa81f` `3cef3b4` `44779bc`（ccconfig main）

## Context and Problem Statement

### 起因：可用性事故

2026-09-17 重构（ADR-0029/0030）之后，用户报告：**两个走 bridge 的 preset（officedsflash / homedsflash）全部不可用，只有直连能跑**。且 `init-llm.sh test` 仍返回 HTTP 200 —— 即长期困扰用户的"**探测 OK 但实际挂**"。

> 注：上述 preset key 在 ADR-0029 时为 `office-deck-flash` / `home-deck-flash`，2026-09-17 后续重命名为 `officedsflash` / `homedsflash`，本文以现状为准。

事故的直接触发是 ADR-0029 中"3 个稳定性增强"里的 SSE 心跳包装器；深入排查后又暴露出同一批代码中若干独立缺陷。

### 为什么"探测成功"而实际全挂

`test` 有两个盲区，任一都足以掩盖真实故障：

1. **绕开 bridge 直接打上游** —— 测的是上游可达性（当然通），而不是会挂的协议转换链路
2. **用非流式请求** —— Claude Code 全程 `stream:true`，流式路径的故障一个都暴露不出来

### 待解决的架构问题

ADR-0029 定下的简化目标尚未落地：探测函数有两个且行为不一致、交互式 preset 编辑与"手改 json"的实际用法重复、守护职责散落且边界模糊。

## Decision Drivers

- **D1 可靠性优先**：用户明确"init-llm 决定我能否正常工作，稳定性非常重要"
- **D2 删冗余优于加抽象**：减少代码路径本身就是可靠性收益（ADR-0029 §简化原则的延续）
- **D3 每处修复必须能被测试抓住**：不接受"改完看着没问题"
- **D4 生产环境不可用于试错**：验证一律在隔离环境完成

## 修复的缺陷（按严重度）

### P0 — 导致本次事故

| # | 缺陷 | 后果 |
|---|------|------|
| 1 | **SSE 心跳包装器用 `asyncio.wait_for(anext())`** | ① 流正常结束时 `StopAsyncIteration` 从 async generator 冒出，被 CPython 转成 `RuntimeError` **掐断整条流**（curl 退出码 18）；② 超时 cancel 掉 `anext` 直接**弄死 async generator，剩余 chunk 全丢**。每个走 bridge 的请求必挂 |
| 2 | **`--skip-tls-verify` 从未生效** | httpx 一旦传入自定义 transport，`AsyncClient(verify=/limits=/trust_env=)` 被**静默忽略**。之前能通纯属侥幸：office 靠域名匹配证书、home 靠 `host_header` 改 SNI |
| 3 | **watchdog 绑死启动时的 preset 参数** | 切 preset 后仍用旧 upstream 重启 bridge，把用户刚选的 preset **覆盖回旧地址**（在家切 tailscale 被打回单位域 → SSL mismatch）。另：PID 文件单点覆盖致老 watchdog 失联后永久残留 |

### P1 — 静默错误与崩溃

| # | 缺陷 | 后果 |
|---|------|------|
| 4 | **`test_llm` 的 `IFS read` 缺 `local`** | bash 动态作用域下改写调用者 `switch_llm` 的 `base_url`，把已设好的 bridge 地址覆盖成上游地址 → **settings.json 写成 OpenAI 端点直连**，Claude Code 报 `SSL certificate hostname mismatch` |
| 5 | **菜单引用已删除的 `${route_str}`** | `set -u` 下每次渲染都 `unbound variable` 崩溃 —— **交互菜单实际上不可用** |
| 6 | **`ensure_bridge` 不创建 `~/.cache`** | 日志重定向失败 → bridge 根本起不来（生产碰巧有该目录故未暴露） |
| 7 | **`selfheal_bridge` 读 `llm.json.current`** | ADR-0020 后 current 权威来源是本地 `llm-current`，llm.json 里的是副本、可能过时 → 用错 preset 起 bridge |
| 8 | **`status.sh` 冷启动自愈被误删** | `855ba92` 声称"搬到 init-llm.sh"，实际只留函数无调用点 → 系统重启后 bridge 再也起不来 |
| 9 | **`/health` 明文吐 API key** | 直接 `**state` 返回，任何能访问 8898 的进程都能读到上游 key |
| 10 | **上游探测失败即重启 bridge**（旧 watchdog） | 探测失败 ≠ bridge 故障；网络问题重启修不了，反而**杀掉正在服务的进程、打断进行中的请求** |

### P2 — 死代码与冗余

- WSL MTU 检测查 `/proc/sys/fs/ostype` —— 该文件在标准内核不存在，**从未触发过**
- `_llm_status_header` 的 tailscale 检测只认 RFC1918，而 home preset 用 100.64/10 CGNAT → 对当前所有 preset 都不触发
- `init-llm-bill.sh` 读 `pricing` 只为产出一个调用方从不使用的列
- gateway 删除后遗留：`monitor.sh` 整段 gateway 状态检查、`ccprivate-upgrade.sh` 无用 symlink、README/架构文档、测试用例

## Decision

### 决策 1：SSE 心跳改用 queue + 独立 pump task

`anext()` **绝不能**被 `wait_for` 包裹（超时 cancel 会破坏 generator；迭代结束的 `StopAsyncIteration` 会变 `RuntimeError`）。改用独立生产者 task 推 queue，主循环带超时取件 —— 超时只影响心跳注入，不影响生产者。

### 决策 2：watchdog 只守护进程存活，且跟随「当前」preset

**不做 upstream 主动探测。** 理由：探测失败 ≠ bridge 故障；重启修不了网络问题，只会打断请求。watchdog 的唯一职责是"bridge 进程没了就按当前 preset 拉起"，每次现场读 `llm-current` + `llm.json`（`bridge-restart.sh`），并用 `pgrep` 兜底清理残留实例。

### 决策 3：探测统一，且必须复现真实请求形态

删除 `verify_endpoint`，切换路径复用 `test_llm`。判据三合一：

```
成功 = 收到终止标记（message_stop / [DONE]）
     且 响应无 "type":"error"
     且 curl 退出码为 0        ← 区分"收完"与"被掐断"
```

bridge preset 必须**经 bridge**探测，且一律用 `stream:true`。401/403 判为鉴权问题放行（链路是通的），000 判不可达并中止切换。

### 决策 4：移除交互式 preset 编辑与批量探测

实际用法是手改 `conf/llm.json` + 菜单选 preset，交互式表单（`switch_custom` / `edit_preset`）与批量探测（`test_all`）是纯负担，删除。菜单保留 `2A 删除模型 / 2B 用量统计`。

### 决策 5：确立四层守护模型（职责边界）

| 层 | 触发 | 职责 | 实现 |
|----|------|------|------|
| `ensure_bridge` | 切换 preset | 按目标 upstream 起/重启 bridge，探 `/health` | `lib/ensure-bridge.sh` |
| `watchdog` | 运行时 | **只**守护进程存活，按当前 preset 拉起 | `lib/ensure-bridge.sh` |
| SessionStart | Claude 启动 | 冷启动兜底（系统重启后 watchdog 也没了） | `lib/status.sh` `_bridge_cold_start` |
| `selfheal_bridge` / `heal` | 手动 | 同上，可手动触发 | `lib/ensure-bridge.sh` |

**约束**：watchdog 不做 upstream 探测；守护层不得写入配置。

## 代码结构变化

### 规模

| 文件 | 变化 |
|------|------|
| `lib/init-llm.sh` | **927 → 687 行（-240）** |
| `lib/ensure-bridge.sh` | watchdog 由"测活+重启"改为"仅守护进程"，自我修复读配置来源 |
| `lib/bridge-restart.sh` | 重写：由"接收调用方参数"改为"自行读当前 preset" |
| `option-llmswitch/openai_bridge.py` | 流式包装器重写 + transport 参数修正 + 流异常补发 error + `/health` 脱敏 |

### init-llm.sh 删除清单

| 删除项 | 行数 | 理由 |
|--------|------|------|
| `verify_endpoint()` | ~41 | 与 `test_llm` 行为不一致且更弱，统一到后者 |
| `switch_custom()` | ~53 | 手改 json 更直接 |
| `edit_preset()` | ~78 | 同上 |
| `test_all()` + `ok/err/warn_color()` | ~66 | 预设变少后批量探测价值低 |
| `_llm_status_header` tailscale 段 | ~14 | 判据对当前 preset 永不成立（死代码） |

### 新增

| 项 | 作用 |
|----|------|
| `_bridge_health()` | bridge `/health` 解析，`show_status` 与菜单头共用（去重） |
| `lib/status.sh` `_bridge_cold_start()` | 补回被误删的 SessionStart 自愈 |

## 测试

| 测试 | 覆盖 |
|------|------|
| `tests/test-openai-bridge.sh`（新增，5 用例） | 流式链路：正常收完 / 停顿不丢数据 / 截断显式报错 / 空响应快速报错 / key 不泄露。用 mock upstream 造四种故障形态 |
| `tests/test-init-llm-switch.sh`（新增，4 用例） | 切换写出 settings.json 的 BASE_URL 正确性（bridge preset → 127.0.0.1:PORT；直连 preset 不被误改）。隔离 HOME + 非默认端口，不碰生产 |

### 测试有效性验证（D3 的落实）

两个测试都做了**反向验证**：拿修复前的代码跑，必须失败。

- `test-openai-bridge.sh`：对修复前版本 5/5 全失败（`curl rc=18` 掐断）
- `test-init-llm-switch.sh`：故意移除 `test_llm` 的 `local` 后，T1 精确失败并指出 `got=上游地址`

**关键认识**：`test-openai-bridge.sh` 初版只用内容判据（`grep message_stop`），带 bug 的版本照样"通过" —— 因为 `message_stop` 在收到 `[DONE]` 瞬间就发出了，`RuntimeError` 发生在其后。**必须加 curl 退出码才能区分"收完"与"被掐断"**。

## Consequences

### 正面

- 两个 bridge preset 恢复可用，实测流式完整（office / home 均通过）
- 探测结果可信：能抓住"流被掐断"这类故障，不再假阳性
- 守护边界清晰，四层各司其职，不再互相覆盖
- 代码减少 240 行，删除的功能都有明确替代路径（手改 json）
- 两条回归测试 + 反向验证，事故形态被钉住

### 代价与取舍

- **探测变慢**：`test` 现在发起真实流式请求（最长 60s），不再是廉价 HTTP HEAD。这是可信度的必要代价
- **切换前多一次真实请求**：切换耗时增加，但换来"不会切到跑不通的配置"
- **watchdog 不再"自愈"网络问题**：网络断了 bridge 保持原样，交由 Claude Code 自身重试 / 用户手动切换 —— 这是刻意的，因为重启 bridge 对网络问题无效且有害

### 不再做的事

**不继续拆分 `init-llm.sh`。** 687 行、单一入口、职责虽多但都属"LLM 切换"一件事，守护边界已文档化。再抽文件只增加跨文件跳转成本而无可靠性收益（D2）。

## 关键教训（已落 memory）

| 陷阱 | 一句话 |
|------|--------|
| bash 动态作用域 | 被调函数 `IFS read` 不加 `local` 会改写调用者同名变量 |
| `pgrep -f` 自匹配 | pattern 会匹配到执行它的 shell 自身（命令行含该字符串）→ 自杀，症状像"卡住" |
| 探测假阳性 | 探测必须复现真实请求形态（路径 + 流式 + 连接完整性判据） |
| httpx 自定义 transport | 传入 transport 后 `verify`/`limits`/`trust_env` 被静默忽略 |

详见 ccprivate memory：`bash-dynamic-scope-read-pollution-20260917`、`pgrep-f-self-match-20260917`、`llm-probe-false-positive-20260917`、`sse-async-gen-waitfor-pitfall-20260917`。

## 相关

- [ADR-0029](./0029-init-llm-target-2026.md) — init-llm 2026 目标决策（本 ADR 是其落地）
- [ADR-0030](./0030-gateway-deprecation-2026.md) — gateway 废弃
- [ADR-0020](./0020-llm-current-local-per-machine.md) — llm-current 本地化（决策 2 中"读当前 preset"的依据）
- [ADR-0019](./0019-bridge-win-curl-wsl-vpn.md) — win_curl WSL/VPN 方案
- [`docs/init-llm.md`](../init-llm.md) — 目标文档（能力清单 / 四层守护 / 配置 schema）
