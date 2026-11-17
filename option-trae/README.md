# option-trae — 让 Claude Code 直接吃 Trae 订阅

`trae_bridge.py` 是一个常驻本机的 **Anthropic Messages ↔ Trae SOLO 私有 SSE** 网关。
Claude Code 说 Anthropic 协议，Trae 只说自己的 `llm_utils_chat` 私有流式协议，
这个网关站在中间做双向翻译。

```
Claude Code ──POST /v1/messages──▶ trae_bridge.py ──llm_utils_chat──▶ trae-api-cn.mchost.guru
            ◀──Anthropic SSE──────            ◀──Trae 命名 SSE────────┘
```

和 DSH 的 `dsh-connect-trae` 插件是**两条独立的通道**，共用同一份 Trae 登录态
（`C:\Users\franc\.dsh\.trae-auth.cn.json`）与同一台设备的身份指纹，互不依赖：
DSH 关掉、插件卸载，本网关照常工作。

## 为什么不能直接用插件的 shim

插件的 loopback shim 是 `server.listen(0, "127.0.0.1")`（随机端口）+
`randomBytes(32)`（进程内随机 secret），而且没有 CLI 入口 —— 它天生只服务
DSH 进程内的 PiAiAdapter，外部进程拿不到端口也拿不到 token。

## 快速使用

```bash
# 服务（systemd user，已 enable，开机自启）
systemctl --user status  trae-bridge.service
systemctl --user restart trae-bridge.service
tail -f ~/.cache/trae-bridge.log

# 健康检查
curl -s --noproxy '*' http://127.0.0.1:8899/anthropic/health
```

在 ccconfig 里切预设（`trae-` 开头的预设都在 `ccprivate/conf/llmprivate.json` 里）：

```bash
cd ~/git/ccconfig
bash lib/init-llm.sh traeglm53        # glm-5.3
bash lib/init-llm.sh traeds41flash    # deepseek-v4.1-flash
```

切完必须 `/exit` 退出当前 Claude 会话再 `claude -c` 续上 —— Claude Code 只在
启动时读 `settings.json` 的 env。

不想走 ccconfig 也可以一次性用环境变量：

```bash
ANTHROPIC_BASE_URL=http://127.0.0.1:8899 \
ANTHROPIC_MODEL=kimi-k2.6 \
ANTHROPIC_AUTH_TOKEN=trae-local \
claude
```

## 端点

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 上游/默认模型/账号/access token 剩余秒数 |
| GET | `/v1/models` | Trae 真实模型目录（过滤掉工具行），id 加 `claude-trae-` 前缀 |
| POST | `/v1/messages` | 主入口，流式/非流式都支持 |
| POST | `/v1/messages/count_tokens` | 按 ~3.2 字符/token 粗估，只为客户端显示上下文百分比 |

所有路径都同时接受 `/anthropic` 前缀（`/anthropic/v1/messages` 等价于
`/v1/messages`）。这不是装饰：ccconfig 的 `preset_bridge_mode` 靠 base_url 里
有没有 `/anthropic` 判断端点是不是原生 Anthropic，带上它才会走 direct 而不是
去拉 8898 的 `openai_bridge`。

## 实现要点（都是真机踩出来的）

**认证与身份**
- 20 个请求头缺一不可。最小集（只 `X-Cloudide-Token` + `x-uid` + 身份头）会 **401**；
  必须补 `Authorization: Cloud-IDE-JWT <token>`、`X-Ide-Token`、
  `x-plugin-channel: icube-ai`、`User-Agent: Trae/<appVersion>`。
- `x-app-version-code` / `x-ide-version-code` **必须是纯数字**（用 `"20260716"`）。
  把 `iCubeLastVersion`（`2.3.99396`，带点）塞进去，上游回
  `4001 binding: expr_path=app_version_code`。

**凭据**
- 从 Trae 的 `storage.json` 解出 ECDSA P-256 设备密钥对（AES-128-CBC，
  SALT_A/B/C/D 四组 64 字节常量 xor 派生）。
  **坑**：官方 JS 在明文前 64 字节放了 `sha512(body)` 校验，但真机数据里那 64 字节
  并不是正文的 sha512 —— 校验必失败，必须跳过，只取 `pt[64:]`。
- refresh 走 **legacy 契约**：`POST https://api.trae.cn/cloudide/api/v3/trae/oauth/ExchangeToken`，
  body `{ClientID, ClientSecret:"-", RefreshToken, UserID}`。当前契约
  `/trae/api/v3/oauth/ExchangeToken` 需要 `DeviceProof` 签名，真机实测一律
  `20403 Token device not match.` —— 不可用。
- **refresh token 是轮换的**：DSH 插件和本网关共用同一个 auth 文件，谁刷新谁让
  对方的 refresh token 失效。所以 `CredentialStore.ensure()` 每次使用前都
  `reload_if_changed()` 重读盘上文件；盘上 `expiresAtMs` 比内存更旧则保留内存版。

**请求体**
- `assistant.tool_calls[].function` 必须改名 **`function_call`**。用 `function`
  会被上游拒：`*idecopilot.ToolCall read field 4 'FunctionCall' error: required
  field Name is not set`。
- `tools[].function.parameters` 必须是 **JSON 字符串**，传对象解析失败。
- `role:"tool"` 的 `content` 必须是 `[{type:"text",text}]` 数组，不能是裸字符串；
  且必须带 `tool_call_id`。
- 图片按模型+通道区别对待：`deepseek-v4.1-flash`（`solo_work_remote` 通道）、
  `Doubao-Seed-2.1-Turbo`、`kimi-k2.6` 能看图；`glm-5.3` 与默认
  `solo_work_lite` 通道报参数错误。网关侧 `_flatten_content` 默认仍降级成
  `[image omitted]` 占位，仅 trae 视觉路由（`keep_images=True`）放行原图。
  带图请求整体分流见「视觉路由」一节。

**响应**
- 工具调用走 `event:output`，首帧带完整 `id`/`name`，后续增量帧的 `id`/`type`/`name`
  是**空串**，只有 `index` + `arguments` 增量 —— 不能拿空串覆盖已有 id。
- **`event:done` 的 `finish_reason` 即便有 tool_calls 也是 `"stop"`**，必须自己
  记 `saw_tool` 再改写成 `"tool_calls"`，否则 Claude Code 不会去执行工具。

**Claude Code 侧**
- 会调 `/v1/messages/count_tokens?beta=true`，不实现会走兜底。
- gateway model discovery 只认 id 匹配 `/(claude|anthropic)/i` 的条目 —— 所以对外
  模型 id 加 `claude-trae-` 前缀，进来再剥掉。
- 但这**不是必需的**：`ANTHROPIC_MODEL=kimi-k2.6` 直接也能用，只是会打印
  `[claude-code:unrecognized_model]` 与"assumes a context window of 200k"两条
  无害警告。`CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` 同样非必需。

## 视觉路由（全局配置，与 LLM 预设正交）

带图请求由网关**分流到视觉后端**，纯文本请求照旧走当前 LLM 预设。分流判定用
`openai_bridge._body_has_image`（顶层消息和 `tool_result` 内层都算）。

```
带图请求 ──▶ /v1/messages ──▶ 视觉后端
纯文本   ──▶ /v1/messages ──▶ Trae llm_utils_chat
```

**视觉后端是全局设定**（7B 配置，落在 `~/git/ccprivate/conf/vision.json`），
不跟 LLM 预设排列组合 —— 主模型切什么都不影响视觉后端。两个后端：

| provider | 模型 | 机制 | 额度 |
|---|---|---|---|
| `zhipu` | glm-4.6v-flash | 外部智谱，OpenAI 协议改发 | 独立 key，免费档限流（`1305` 频发，重试即过） |
| `trae` | deepseek-v4.1-flash | Trae 订阅内直发（`keep_images`） | 走订阅额度，无需 key |

**Trae 上游吃图是按模型+通道的**：`deepseek-v4.1-flash` 在它真实使用的
`solo_work_remote` 通道能看图（8/8 实测答色正确），在默认 `solo_work_lite`
通道报参数错误。`Doubao-Seed-2.1-Turbo` / `kimi-k2.6` 默认通道即可。
`glm-5.3` 不吃图。所以 trae provider 走 `function_for_model()` 的模型级通道
规则，与主模型同源。

**为什么不做成外部套 8898 openai_bridge**：`_bridge_supported()` 显式拒绝
loopback 端点与 `/anthropic` 路径，而本网关只提供 Anthropic 协议、没有
`/chat/completions` —— 协议层就接不上。所以路由必须在网关内部做。

**配置来源**：启动时读 `~/git/ccprivate/conf/vision.json`
（`{"provider","model","upstream","key_preset"}`；zhipu 的 key 靠
`key_preset` 查 `mlayer.json` → `llm.json`，缺 `key_preset` 会静默空 key 401）。
**key 不写进 systemd unit** —— unit 常被复制分享，明文密钥不该落 `~/.config`。

改完 7B 要 `systemctl --user restart trae-bridge.service` 才重新加载
（配置只在启动时读一次；7B 菜单会自动重启）。临时覆盖用
`TRAE_VISION_PROVIDER` / `TRAE_VISION_MODEL` / `TRAE_VISION_UPSTREAM`
/ `TRAE_VISION_KEY` 环境变量。

**代价**：zhipu 后端视觉走非流式（拿完整响应再转 SSE），单轮看图不值得维护
第二条 SSE 状态机；trae 后端复用主链路 SSE（流式直通）。8898 openai_bridge
侧无 Trae 通道：7B 选 `trae` 时 8898 视觉路由显式清空，选 `zhipu` 时全局
vision.json 覆盖 per-preset 旧字段（`lib/ensure-bridge.sh` 三态叠加）。

## 复用关系

`anthropic_to_openai_req` / `openai_chunk_to_anthropic_sse` / `_iter_complete_lines`
等转换层直接 `import openai_bridge`（取自 `option-llmswitch/` 原件），本文件只实现
"OpenAI 请求 → Trae 请求 + Trae SSE → OpenAI chunk"这一段。**不要再往本目录拷
`openai_bridge.py` 副本**，两份会各自漂移。

## 已知限制

- Trae 吃图按模型+通道区分（见「视觉路由」），不吃图的模型/通道网关无法补救。
- `count_tokens` 是估算，长上下文时百分比会偏。
- 只实现国内版（CN）。国际区（`coresg-normal.trae.ai`）网关常量里留了 env 覆盖
  入口，但未实测。
- 企业租户池（请求体额外带 `session_id`）未实现。
