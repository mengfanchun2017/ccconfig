# 0048. WSL2 大 body 上传断流 — office\* 走 win_curl 而非 httpx

> **Status**: ✅ Accepted
> **日期**: 2026-10-16
> **关联**: `lib/ensure-bridge.sh`、`option-llmswitch/openai_bridge.py`、`docs/adr/0047-tailscale-subnet-vs-office-intranet.md`、`docs/adr/0019-bridge-win-curl-wsl-vpn.md`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

2026-10-16 单位内网排查 office\* preset「很慢还会报错」。第一层根因（tailscale subnet 抢路由）见 [0047](0047-tailscale-subnet-vs-office-intranet.md)，修复后故障仍在。

### 关键观察：body 大小决定成败

| body 大小 | 表现 |
|---|---|
| 20KB | 200，3.2s |
| 50KB | 200，19.7s |
| 110KB | 200，36.3s |
| 200KB | 200，45.7s |
| 250KB ~ 300KB | **挂死，直至超时** |

阈值在 200~250KB。bridge 侧表现为 `ReadError` / `WriteTimeout` → 529。

### 归因过程（含一次错误归因）

**第一次归因（错误）**：认为网关有 200KB 硬阈值。依据是「直连 curl 挂死」+「经 bridge 也挂死」两条对照同时失败，判定为服务端限制。

**这个推理是错的** —— 两条对照组共享了被测变量：**curl 和 httpx 都跑在 WSL 内**。它们失败不能区分「网关限制」与「WSL 网络栈限制」，因为两者共享同一网络栈。gzip 压缩后能过也被误读为「限制在传输层 WAF」，实际上只是把 body 压到阈值以下，绕过了 WSL 侧的上传问题。

**证伪**：用户反馈「家里用 home\* 一直没事，一定不是网关限制」。该反馈直接命中推理漏洞。补测传输栈对照：

| 传输栈 | 300KB 结果 |
|---|---|
| WSL `curl`（Linux） | 挂死超时 |
| WSL `httpx`（bridge 默认） | 挂死超时 |
| Windows `curl.exe`（`--use-win-curl`） | **200 OK，95.7s** |
| Windows `curl.exe` 直连（非 bridge） | **200 OK** |

**结论**：同一份 body、同一网关、同一 key，差别只在运行位置。**限制在 WSL2 网络栈，不在网关**。

### 为什么家里一直没事

home\* 系列 `base_url` 是字面 tailscale IP，命中 `ensure_bridge` 的私网段正则 → 自动启用 `--use-win-curl`，请求交 Windows 网络栈发出。office\* 系列 `base_url` 是域名，正则不命中 → 走 httpx 在 WSL 内发出，撞上大上传断流。

**这就是同一个网关、同一份配置体系下 home\* 正常而 office\* 挂死的全部原因。**

### MTU 已排除

WSL eth0 MTU 1280，小于 Windows WLAN 的 1500 —— 更小的 MTU 不会导致大包卡死，实测 1200B 不分片包也能通。排除 MTU 假设。

### 附带发现：后端处理大 prompt 极慢

即使走 win_curl 成功，耗时仍与 body 大小强相关：50KB→19.7s，170KB→49.0s，300KB→90s（约 0.25s/KB）。gzip 到 443 字节仍需 92s，说明**延迟来自网关后端处理，非传输**。此项本地无法优化。

## Decision Drivers

- **D1 对照实验必须正交**：对照组之间不能共享被测变量，否则结论无效
- **D2 尊重现场经验**：「家里没事」是对照实验设计的反向信号，应优先触发复检而非辩解
- **D3 修复要能生效**：改配置后必须真的重启 bridge，否则改动形同虚设

## Considered Options

1. **认定网关限制，要求网关方调 WAF** — 归因错误，方向完全错
2. **减小 `max_context_tokens` 规避大 body** — 能缓解但治标；且用户反馈家里 400k 声明下照常使用，说明真实瓶颈不是窗口声明
3. **让 office\* 也走 win_curl** — 直击差异本身，且 home\* 已验证该路径可靠
4. **bridge 加 gzip 上行** — 可压过阈值，但 win_curl 已经能过，属于冗余；暂不实施

## Decision

**选方案 3**：为域名形式的上游增加 `force_win_curl` opt-in 字段，让 office\* 走 Windows 网络栈。

同时补上一个必要的配套修复（原实现缺失）：

### 修复 1：`force_win_curl` opt-in 字段

`llmprivate.json` 的 office\* 三个 preset 增加 `force_win_curl: true`。

在 `ensure_bridge` 中，私网段正则判定之后追加 opt-in 判定。**为何不改成「解析域名再判私网段」**：那种做法依赖 DNS，上游解析结果变化（如改用 CDN）会让行为不可预期，且单位/家里的 DNS 结果不保证一致。显式字段是确定性选择。

### 修复 2：复用分支必须比对传输栈

原实现中，`ensure_bridge` 发现 upstream 与 model 都匹配就**直接复用旧 bridge 并返回**，`win_curl` 期望值在重启段才计算 —— 结果是**改完配置 bridge 不会重启，health 看着一切正常，但故障依旧**。

改动：
1. `win_curl` 判定移到 health 比较之前
2. 复用分支增加 `use_win_curl` 比对，不一致则重启

## Consequences

- ✅ **office\* 大 context 可用**：300KB / 38,433 tokens 实测 200 OK（此前必挂）
- ✅ **配置改动真正生效**：修复 2 消除了「改了等于没改」的静默失效
- ✅ **零风险默认**：不配 `force_win_curl` 的 preset 行为完全不变
- ✅ **幂等性保持**：重复调用 `ensure_bridge` 复用不重启（实测验证）
- ❌ **速度不会变快**：后端 0.25s/KB 的处理延迟仍在，300KB 仍需 90s
- ❌ **绑定 Windows**：`--use-win-curl` 依赖 Windows `curl.exe`，纯 Linux 环境下 opt-in 字段会被忽略（已加 `command -v curl.exe` 前置检查）

## Implementation

### 验证矩阵

```bash
# 1. 判定生效：health 应显示 use_win_curl=true
curl -s http://127.0.0.1:8898/health

# 2. 大 body 端到端（此前必挂）
curl -s --max-time 150 -o /dev/null -w "http=%{http_code} total=%{time_total}\n" \
  -H "Content-Type: application/json" -H "x-api-key: t" \
  -d @big_body.json http://127.0.0.1:8898/v1/messages

# 3. 幂等性：再调一次 ensure_bridge 应复用不重启
```

实测结果：`use_win_curl=true`，300KB / 38,433 tokens → 200 OK / 90.4s，重复调用复用成功。

### 排查顺序（下次同样症状）

1. **路由层** —— [0047](0047-tailscale-subnet-vs-office-intranet.md)
2. **传输栈层** —— 本 ADR（先看 `/health` 的 `use_win_curl` 是否符合预期，再做大 body 对照）
3. **服务端层** —— 只有在同一 body 换传输栈结果**不同**时，才能归因服务端

### 归因方法论（比修复本身更重要）

出现「某操作失败」时，**对照组必须与被测组在关键维度上正交**。本案例的反面教材：

- ❌ 「直连失败 + 经 bridge 也失败」→ 两者都在 WSL，共享 WSL 网络栈，不能证明是服务端的锅
- ✅ 「Windows 失败/成功 vs WSL 失败/成功」→ 唯一分离了被测变量

推论：**当同一故障在两个场景（一处有、一处无）出现时，优先假设两者的差异项，而非共同项。** 用户凭日常经验指出的「家里没事」正是差异项信号。

## Related Decisions

- [0047](0047-tailscale-subnet-vs-office-intranet.md) — tailscale subnet 抢路由（同一次故障的第一层）
- [0019](0019-bridge-win-curl-wsl-vpn.md) — bridge win-curl 双模式（本文档修复的正是其判定覆盖面）
- [0013](0013-bridge-selfheal-sessionstart.md) — bridge 自愈

## Notes

1. `force_win_curl` 是 opt-in，默认关闭。若未来出现更多走 WSL 直连但大 body 失效的上游，逐个 preset 打开即可。
2. 本 ADR 最初以「网关 200KB 硬阈值」为题，结论错误，已按实测更正。保留此记录是因为**错误归因的过程本身就是教训**。
