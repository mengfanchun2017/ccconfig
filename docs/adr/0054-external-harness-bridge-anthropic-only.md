# 0054. 外部 harness 接内网 LLM 只能走 bridge（pi-ai 走官方 SDK，TLS 校验无法关闭）

> **Status**: ✅ Accepted
> **日期**: 2026-10-27
> **关联**: `option-llmswitch/openai_bridge.py`、`ccprivate/conf/llmprivate.json`、ADR [0050](0050-bridge-structural-refactor.md)、[0053](0053-home-preset-derp-only-network-cap.md)、[0016](0016-tailscale-subnet-router.md)
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

2026-10-27，给 **DeepSeek Harness**（Windows 侧 Electron 应用，`dsh-desktop`）接入当前 preset
（内网 `deepseek-v4.1-flash-outside`，经 `home*` 链路）时，会话报：

```
404 {"detail":"Not Found"}   →   code PI_AI_ERROR
```

用户按其理解的"bridge 地址"配置失败。需要查清真实根因，并给出**可持续**的接法。

排错中解出 harness 自己的 session 日志（zstd 压缩），拿到原文证据：

```
turn 2/3/4: {"message": "404 {\"detail\":\"Not Found\"}", "code": "PI_AI_ERROR"}
turn 5:     {"message": "Connection error.", "code": "TRANSPORT"}   provider: "home"
```

两个关键事实：

1. `{"detail":"Not Found"}` 是 **FastAPI** 的 404 体 —— 请求确实落在 bridge 上
   （bridge 只有 `/v1/messages` + `/health` + `/admin/reload`，无 `/v1/chat/completions`、无 `/v1/models`）。
   原配置写的是 `api: openai-responses`，于是打 `/v1/responses` → 404。
2. `PI_AI_ERROR` 是**兜底错误码，不是协议判据**。harness 的分类器源码：
   `/5\d\d/`→SERVER、`timeout`→TIMEOUT、`ECONN/network|socket|fetch`→TRANSPORT，
   **其余全部落 `PI_AI_ERROR`**。盯着它猜原因无收益。

### 真正堵死的路：https + IP 直连

改成 IP 直连后报 `Connection error`（TRANSPORT）。根因是**证书校验关不掉**：

- pi-ai 的 `openai-completions` / `anthropic-messages` 都走官方 SDK：
  `new OpenAI({apiKey, baseURL, dangerouslyAllowBrowser, fetch, defaultHeaders})` ——
  **构造函数里没有 agent、没有任何 TLS 选项**，无 provider 级开关。
- 环境变量也救不了。dsh 源码把 CA/TLS 名放进 `BOOTSTRAP_NAMES`
  （`NODE_TLS_REJECT_UNAUTHORIZED` / `SSL_CERT_FILE` / `SSL_CERT_DIR` /
  `NODE_EXTRA_CA_CERTS` / `REQUESTS_CA_BUNDLE` / `CURL_CA_BUNDLE`），注释原文：

  > The CA and TLS names in the same group **stay refused everywhere**: they change what
  > is trusted, not where traffic goes.

  home 目录的 `.env` 只额外放开四个代理名（`HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY`/`NO_PROXY`），
  **CA/TLS 名连 home 层都拒**，写进 `.env` 直接抛错。

而内网 LLM 网关的证书签给的是**域名通配**（`*.<gateway-domain>`）：
- 走 **IP** → hostname 不在 SAN 里 → 校验必挂 → `Connection error`；
- 走 **域名** → 校验能过（实测 `verify=0` HTTP 200），但**公网 DNS 把域名指到公网 IP**
  （实测该公网 IP 完全不通），只有内网可达正确地址。

## Decision Drivers

- **D1 不引入新的提权/系统级改动**：改 hosts 需管理员，且本机 hosts 的该 IP 已被 Tailscale 段占用
- **D2 不依赖无法关闭的安全开关**：上游不可改，客户端 TLS 开关不存在，硬碰无用
- **D3 与既有 bridge 契约对齐**：bridge 已有能力，不应为接入新客户端重复造
- **D4 错误码不可作判据**：必须拿 harness 自己的日志定性，而非界面文案

## Considered Options

1. **https + IP 直连** — ❌ 证书校验关不掉（见上），必然 `Connection error`
2. **https + 域名直连** — ❌ 公网 DNS 指向公网 IP，该 IP 实测不通；且 Windows hosts 需管理员
3. **`NODE_TLS_REJECT_UNAUTHORIZED=0` 或 `NODE_EXTRA_CA_CERTS`** — ❌ 被 dsh 源码硬拒（`BOOTSTRAP_NAMES`）
4. **改 hosts 把域名指到内网 IP**（校验能过） — ⚠️ 可行但需管理员、与 Tailscale 段冲突、随网络位置漂移
5. **harness → bridge（`api: anthropic-messages`，http）** — ✅ bridge 原生即 Anthropic `/v1/messages`，无需 TLS

## Decision

**外部 harness 接内网 LLM，统一走本地 bridge，用 `api: anthropic-messages` + http。**

```yaml
- id: llm-pi-ai
  name: "@deepseek-ai/dsh-llm-pi-ai"
  config:
    providers:
      home:
        displayName: home (bridge)
        apiKeyEnv: HOME_API_KEY        # bridge 不校验，非空值即可
        api: anthropic-messages
        baseURL: http://127.0.0.1:8898 # 不带 /v1：SDK 自动补 /v1/messages
        models:
          - id: deepseek-v4.1-flash-outside
            name: deepseek-v4.1-flash-outside
```

成立前提（实测）：**WSL 为 mirrored 网络模式**，Windows 的 `127.0.0.1` 直达 WSL
（`curl.exe http://127.0.0.1:8898/health` = 200）。非 mirrored 时需改用 WSL 的 LAN IP 并放行端口。

### 为什么不是"换协议直连"

上游网关（one-api）**只提供 Chat Completions 与 `/responses`（非 `/v1/responses`）**，
不支持标准 OpenAI Responses API；且 pi-ai 三种协议里只有 `anthropic-messages` 能吃 bridge，
`openai-completions` 打 `/chat/completions` 而 bridge 无此路由。走 bridge 是唯一无 TLS 摩擦的路径。

### 两条并存的 provider（非冗余）

| provider | baseURL | 协议 | 适用网络位置 |
|---|---|---|---|
| `office` | `https://<office-llm-gateway>:18080/v1` | `openai-completions` | 单位（局域网直连，域名解析到内网，证书匹配 → 校验通过） |
| `home` | `http://127.0.0.1:<bridge-port>` | `anthropic-messages` | 家里/外网（经 bridge → `home*` preset 链路） |

## Consequences

- ✅ 接入**不需要**关证书、改 hosts、提权，也不需要动 bridge 代码
- ✅ 复用既有 `home*` 链路（含 0053 的 `max_concurrency` 并发闸），不新增传输栈
- ✅ 把"TLS 关不掉"这条硬约束固化，避免下次重走 IP 直连
- ❌ 依赖 bridge 常驻 + WSL mirrored 网络（非 mirrored 需额外配置）
- ❌ Windows 侧多一跳（Windows → WSL bridge → 上游）
- ⚠️ **model 名必须用别名**：网关 key 权限绑别名，用真实名报
  `403 该令牌无权使用模型`（实测 `-outside` 别名 200 / 真实名 403）
- ⚠️ 该上游是推理模型，`max_tokens` 过小会把预算烧在 reasoning 上、`content` 返回空串 ——
  客户端别手动压小输出上限
- ⚠️ 该接入方式**只在 harness 支持 Anthropic 协议时成立**；纯 OpenAI 协议客户端需先给
  bridge 加 `/v1/chat/completions` passthrough（当前无此路由）

## Implementation

- `C:\Users\<user>\.dsh\profiles\desktop\cordis.patch.yml` — `home` provider 改为
  `api: anthropic-messages` + http bridge（唯一编辑点；`cordis.yml` 是空根，别改）
- 端到端实测（Windows → bridge → 上游）：`message_start → content_block_delta{text:"pong"}
  → message_stop`，HTTP 200

## Related Decisions

- [0050](0050-bridge-structural-refactor.md) — bridge 传输/协议分离；本 ADR 是"协议形态决定可接入性"的
  又一事例（bridge 只会 Anthropic，故客户端协议须匹配）
- [0053](0053-home-preset-derp-only-network-cap.md) — `home*` 链路能力与并发闸；本 ADR 的 `home`
  provider 正是消费该链路
- [0016](0016-tailscale-subnet-router.md) — 同为"客户端/网络位置决定走哪条路"的选型；本 ADR 的判据是
  **协议 + TLS 能力**，而非路由可达性

## Notes

- harness 身份与配置落点、session 日志（zstd）排错手法、`provider` 字段全集
  （**无任何 TLS/证书字段**）记在私有仓 memory `dsh-harness-ops`，本文件按公开仓规范只留占位符。
- 用户界面上只显示 `PI_AI_ERROR`，**真实原因必须解 session 日志**：
  `~/.dsh/sessions/<workspace>/session-*/session.v4.jsonl.zstd`（需 `zstandard` 解压）。
- 下次同类症状的一分钟判据：凡 404 体是 `{"detail":"Not Found"}`（FastAPI 签名）→ 请求打在 bridge
  上但路径不对；凡 `Connection error` + https → 先怀疑证书校验（本 ADR 已证其不可关，直接改走 http bridge）。