# 0014. OpenAI bridge 三层修复：WSL 网络栈隔离 + DNS 污染 + ARG_MAX 溢出

> **Status**: ✅ Accepted
> **日期**: 2026-08-14
> **关联**: `lib/ensure-bridge.sh`、`option-llmswitch/openai_bridge.py`、`conf/llm.json`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

用户在办公室内网使用 `AltDeepSeekV4Flash`（openaialt preset）正常。回家后：
1. 开零信任 VPN 连接到公司内网
2. 同时开翻墙 VPN（Clash）
3. 切到 openaialt → bridge 启动 → Claude 报 500 Internal Server Error / ECONNRESET

### 测试数据

- **Windows PowerShell** `Test-NetConnection aiplus.airchina.com.cn -port 18080` → TCP 通（`RemoteAddress: 100.12.0.1`）
- **WSL curl** → 超时（WSL 网络栈看不到 VPN 路由）
- **Windows curl.exe** → 200 OK

### 三层根因

| 层 | 问题 | 现象 |
|---|---|---|
| DNS 污染 | WSL `socket.getaddrinfo` 被翻墙 VPN Clash fake-ip 劫持，`aiplus.airchina.com.cn` 返回错误 IP | bridge 连到错误 IP → SSL 失败 |
| WSL 网络栈隔离 | WSL2 网络栈与 Windows 分离，VPN 分配的 IP 路由在 WSL 看不到 | WSL 到 `100.12.0.1` 超时，Windows 到 `100.12.0.1` 正常 |
| ARG_MAX 溢出 | `curl.exe -d <body>` argv 传递 body，Claude 真实请求 600KB+ 超 Linux 128KB 限制 | `OSError: Argument list too long` → bridge 500 |

### 设计目标

- **零手动配置**：回家连 VPN 后自动工作，不要求用户改配置
- **自动双模式**：办公室 WSL 直连，VPN 环境 Windows curl 转发，自动检测切换
- **单套代码**：不改 Claude 自身行为，不改 init-llm.sh 调用方式

## Decision

采用方案：**在 `ensure-bridge.sh` + `openai_bridge.py` 中加四层修复，自动适应网络栈变化**。

### 1. DNS 预解析（绕 Clash fake-ip）

`ensure-bridge.sh` 启动 bridge 前通过 Windows PowerShell 解析 upstream 域名：

```bash
powershell.exe -NoProfile -Command "Resolve-DnsName <domain> -Type A"
```

优先使用 `OPENAI_BRIDGE_WIN_DNS` 环境变量指定的 DNS 服务器（公司 VPN DNS），兜底 Windows 默认 DNS。得到的 IP 替换 upstream URL 中的域名。

**为什么用 PowerShell**：Windows 侧的 DNS 解析走 Windows 网络栈（受 VPN 分配的 DNS 影响），绕开 WSL 的 Clash fake-ip DNS 污染。

### 2. SNI 兼容（IP 直连 SSL）

bridge 接收 `--upstream-host`（原始域名），在 httpx 请求中：
- 加 `Host: <原始域名>` header
- 加 `extensions={"sni_hostname": <原始域名>}` 让 SSL 握手 SNI 使用域名而非 IP

解决 IP 直连时 SSL 证书验证失败（`certificate is not valid for IP`）。

### 3. WSL 网络检测 + win-curl 转发

`ensure-bridge.sh` 启动 bridge 前用 `socket.create_connection` 5s 探测 WSL 是否能直连上游 IP：
- 通 → httpx 直连（办公室场景）
- 不通 → 启用 `OPENAI_BRIDGE_USE_WIN_CURL=1`，bridge 通过 Windows 侧 `curl.exe` 转发请求

bridge 的 health endpoint 暴露 `use_win_curl` 和 `upstream_original` 字段，每次 `ensure_bridge` 都重评估网络状态：
- win-curl 状态变化（True↔False 翻转）→ 自动重启 bridge 切换模式
- `upstream_original`（原始域名 URL）保证字符串匹配一致性
- 匹配 + 状态正确 → 做 5s HTTP 快速可达性测试（502/000 触发重启）

### 4. stdin pipe 喂 body（避 ARG_MAX）

```bash
# 错误：body 在 argv 中，超 128KB 爆
curl.exe -d '<600KB body>' ...
# 正确：body 从 stdin 读，无尺寸限制
curl.exe -d @- ...
```

`asyncio.create_subprocess_exec` 配合 `subprocess.PIPE` 把 body bytes 喂给 curl.exe stdin。

### 隐私设计

- **无硬编码域名/IP**：`aiplus.airchina.com.cn:18080` 和 API key 来自 `ccprivate/conf/llm.json`，不在 ccconfig 公开仓库
- **无硬编码 DNS 服务器**：`10.255.255.254` 改为环境变量 `OPENAI_BRIDGE_WIN_DNS`，由 ccprivate 配置
- 脚本通用：别人 fork ccconfig 只需要配自己的 llm.json 即可使用

## Consequences

### Positive

- ✅ **零手动切换**：回家连 VPN → 开 Claude → SessionStart 自愈 → bridge win-curl 自动启用
- ✅ **自动双模式**：公司 WSL httpx 直连 ≠ 回家 Windows curl 转发，5s 探测自动适应
- ✅ **幂等重启**：`upstream_original` 字符串匹配 + 可达性测试 → 不必要的重启降至接近零
- ✅ **无 body 尺寸限制**：Claude 真实请求 600KB+ 正常流过 stdin pipe
- ✅ **可公开**：敏感信息（域名/API Key/DNS）全部在 ccprivate 配置中，ccconfig 脚本无硬编码

### Negative / Risks

- ⚠️ **Windows 依赖**：win-curl 模式需要 Windows 侧 `curl.exe`（Win10 1803+ 自带）
- ⚠️ **DNS 服务器硬编码**：`10.255.255.254` 是 WSL 默认 DNS，已改环境变量可配
- ⚠️ **PowerShell 延迟**：每次 `ensure_bridge` 调一次 PowerShell（~500ms），仅启动时
- ⚠️ **运维复杂度增加**：`openai_bridge.py` 新增 80 行转发逻辑 + `ensure-bridge.sh` 新增 40 行检测逻辑

## Implementation

### 文件变更

- `lib/ensure-bridge.sh` — DNS 预解析（PowerShell）+ WSL 网络可达性探测 + win-curl 自动切换 + `upstream_original` 幂等匹配
- `option-llmswitch/openai_bridge.py` — `upstream_host`/`upstream_original`/`use_win_curl` 状态 + `sni_hostname` + stdin pipe 转发

### 运行流程（完整）

```
用户切 openaialt
  → init-llm.sh switch_llm
    → 检测 OpenAI-only 端点（非 /anthropic、非本地）
      → ensure_bridge(upstream, model, key)
        → 检查已有 bridge health
          ├─ 无 bridge → 继续
          └─ 有 bridge → 检查 upstream_original 匹配
               ├─ 不匹配 → pkill + 重启
               └─ 匹配 → 检查 win-curl 状态变化
                    ├─ 状态翻转 → pkill + 重启
                    └─ 状态不变 → HTTP 可达性 5s 测试
                         ├─ 502/000 → pkill + 重启
                         └─ 200 → return 0（幂等）
        → DNS 预解析：PowerShell Resolve-DnsName → IP
        → WSL 网络探测：socket.create_connection 5s
          ├─ 通 → httpx 直连模式启动
          └─ 不通 → win-curl 模式启动（OPENAI_BRIDGE_USE_WIN_CURL=1）
        → nohup openai_bridge.py --upstream <IP:port> --upstream-host <domain>
        → 等待 5s health endpoint 响应
      → base_url 改为 http://127.0.0.1:8898
    → 写入 settings.json
  → 切换完成

Claude 请求流程（win-curl 模式）：
  Claude → POST http://127.0.0.1:8898/v1/messages
  → bridge 转换 Anthropic→OpenAI 协议
  → _post_via_win_curl / _stream_via_win_curl
    → asyncio.create_subprocess_exec("curl.exe", "-d", "@-", ...)
    → stdin.write(body_bytes) → stdin.close()
    → Windows 侧 curl.exe → 100.12.0.1:18080 → DeepSeek API
  → 响应回传给 Claude
```

### 配置项

| 环境变量 | 位置 | 说明 |
|---|---|---|
| `OPENAI_BRIDGE_USE_WIN_CURL` | bridge env | 强制 win-curl 模式（自动检测） |
| `OPENAI_BRIDGE_HOST` | bridge env | 原始域名（SNI/Host header） |
| `OPENAI_BRIDGE_UPSTREAM_ORIGINAL` | bridge env | 原始域名 URL（幂等匹配） |
| `OPENAI_BRIDGE_WIN_DNS` | ensure-bridge env | 公司 VPN DNS 服务器（可选） |

## Related Decisions

- [[0013-bridge-selfheal-sessionstart]](0013-bridge-selfheal-sessionstart.md) — OpenAI bridge 自愈（本 ADR 叠加其方案之上）
- [[0012-interact-p0-no-gum]](0012-interact-p0-no-gum.md) — SH 交互规范化
