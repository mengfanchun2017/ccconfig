# 0006. 飞书通信策略：cc-connect + lark-cli，不引入飞书 MCP

> **Status**: ✅ Accepted
> **日期**: 2026-07-29
> **关联**: [决策时间线 § 2026-07-29](../adr/README.md#决策时间线worklog-提取按日期倒序)
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

飞书开放平台提供三种 AI 交互方式，需要统一策略：

1. **lark-cli**（飞书官方 CLI）— 主动文档/Base/日历/任务/Wiki/Drive 操作
2. **cc-connect**（第三方 Bridge）— 飞书 Bot ↔ Claude Code 双向对话
3. **飞书 OpenAPI MCP**（`@larksuiteoapi/lark-mcp`）— AI 直调飞书 API

2026-04 已初步决策不用飞书 MCP。当前需要：

- **更新 cc-connect 版本到 1.4.0**（依赖 `conf/versions.json` 管理）
- **正式写入 ADR**：cc-connect + lark-cli 对比 MCP 的完整判断，供后续参考
- **关联 init-option.sh**：cconnect 已作为可选组件集成到统一安装入口

## Decision Drivers

- **D1 功能覆盖**：方案能否覆盖飞书文档/消息/日历/任务/Base 全部场景
- **D2 双向通信**：能否被动接收飞书消息（Bot 场景）
- **D3 维护成本**：安装/更新/多账号管理的复杂度
- **D4 协议对齐**：是否匹配 ccconfig 现有架构模式

## Considered Options

### Option A: cc-connect + lark-cli 双组件（采纳，已实现）

```
  ┌────────────────────────────────────────────────┐
  │  feishu.json（单一配置源，ccprivate/conf/）       │
  ├────────────────┬───────────────────────────────┤
  │  lark-cli      │  cc-connect                    │
  │  (主动操作)     │  (双向对话)                      │
  │  docs / base   │  飞书 Bot → Claude Code         │
  │  calendar /    │  WebSocket 长连接                │
  │  task / wiki   │  systemd --user 后台服务          │
  │  drive         │  流式回复 / 会话管理              │
  ├────────────────┴───────────────────────────────┤
  │  option-larkcli/init.sh    option-cconnect/     │
  │  (init-option.sh 可选组件)                       │
  └────────────────────────────────────────────────┘
```

- **安装入口**: `init-option.sh` 交互菜单 / `init-option.sh cconnect` / `init-option.sh larkcli`
- **版本管理**: `conf/versions.json` 统一管控
- **cc-connect 当前版本**: 1.4.0

#### Pros

- ✅ 完整覆盖飞书交互场景（主动 + 被动）
- ✅ 单一配置源（`ccprivate/conf/feishu.json`），lark-cli + cc-connect 共用
- ✅ 零公网 IP 依赖（WebSocket 长连接）
- ✅ 流式回复、session 管理、附件传输（MCP 做不到）
- ✅ 多账号优雅切换（`lark-switch.sh`）
- ✅ shell/CI/cron 可用（lark-cli 不依赖 Claude 运行时）
- ✅ 版本通过 `versions.json` 管控，升级只需改一个字段

#### Cons

- ❌ 多一个 systemd 服务（cc-connect）需要维护
- ❌ 二进制独立下载（不如 npx 零安装方便）
- ❌ lark-cli 无内置 WebSocket 能力，不能接收消息

### Option B: 飞书 OpenAPI MCP 替代两者

```
@larksuiteoapi/lark-mcp  (npx 零安装)
  ├─ im.v1.*          消息收发
  ├─ bitable.v1.*     Base CRUD
  ├─ docx.v1.*        文档操作
  ├─ calendar.v4.*    日历管理
  ├─ task.v2.*        任务管理
  ├─ wiki.v2.*        知识库
  └─ contact.v3.*     通讯录
```

#### Pros

- ✅ npx 零安装，配置一行 JSON
- ✅ MCP 原生集成，Claude 自动管理
- ✅ 用户身份 OAuth（`user_access_token`），以用户身份操作
- ✅ 群管理/通讯录/协作者权限（lark-cli 无对应命令）

#### Cons

- ❌ **不能被动接收消息** — 无 Bot 能力，只能 AI 主动调 API
- ❌ **不能流式回复** — MCP 协议不设计做这个
- ❌ **无 session 管理** — 每次调用独立，无上下文
- ❌ **无附件传输** — 官方文档明确说不支持文件上传下载
- ❌ **依赖 Claude 运行时** — MCP 只能 Claude 拉起后使用，不能独立执行
- ❌ **多账号需多实例配置** — settings.json 多个 mcpServers 段
- ❌ **配置源分散** — App ID/Secret 散落在 settings.json，不走 ccconfig 统一管理

### Option C: @china-mcp/feishu-mcp（第三方包，已废弃）

早期试用过的第三方 MCP（2026-04），功能更少：

- 仅 8 个工具（send_message / get_messages / create_doc / get_doc / calendar / task）
- 无 Base 操作
- 第三方维护，更新不可控
- 2026-06 随 feishu MCP 全线清理删除

## Decision

**维持 cc-connect + lark-cli 双组件策略，不引入飞书 MCP。**

具体状态：

| 组件 | init-option.sh | versions.json | 状态 |
|------|----------------|---------------|------|
| lark-cli | ✅ `larkcli` | ✅ npm 管理，`update.sh` 自动检查 | 启用中 |
| cc-connect | ✅ `cconnect` | ✅ v1.4.0 (2026-07) | 可选，按需安装 |
| 飞书 MCP | ❌ | ❌ | 不引入 |

cc-connect 已升级至 1.4.0，下载 URL 模板和 binary 名均已在 `conf/versions.json` 配置。

## Consequences

### Positive

- ✅ 主动 + 被动全覆盖，单一配置源
- ✅ cc-connect v1.4.0 通过 versions.json 管控，升级只需改版本号
- ✅ MCP 不做的事不做，避免三方 MCP 依赖风险
- ✅ init-option.sh 统一入口，用户无需记忆多套安装命令
- ✅ 保持架构简洁：cconnect 是 option（可选），不增加 core 复杂度

### Negative

- ❌ 失去用户身份 OAuth 的便利（以用户身份发消息/管理群）
- ❌ cc-connect 服务异常时需手动排查（systemctl --user status）
- ❌ 没有飞书 MCP 的 preset 精细化过滤功能

### Risks

- **R1** cc-connect 是第三方项目，上游停更或 breaking change → 缓解：binary 下载失败有 fallback 提示手动下载
- **R2** 飞书 MCP 成为未来标配，生态成熟度超越 cc-connect → 缓解：维持「可选+零耦合」，切换成本低
- **R3** 需要「以我身份在群里发通知」的场景 → 当前用 lark-cli 手动处理；如果需求频率升高，可单独加飞书 MCP 的 `im.v1.message.create` 而非全量

## Implementation

### 当前实现状态（2026-08 更新）

> **重要**: `option-cconnect/` / `cconnect` 二进制在本 ADR 起草后**未实际落地**。Bridge 实际由 `option-larkbridge/`（lark-channel-bridge，npm 包 `@larksuiteoapi/lark-channel-bridge`）承担。本 ADR 的决策结论（双组件策略：lark-cli + bridge）仍正确，但实现路径与原文不同。

实际代码：

- `option-larkbridge/init.sh` → npm install -g @larksuiteoapi/lark-channel-bridge + systemd profile 管理
- `option-larkcli/init.sh` + `option-larkcli/lark-switch.sh` → 多账号 lark-cli
- `conf/versions.json` → `lark_cli` 走 npm，`lark_channel_bridge` 由 init.sh 内置
- `init-option.sh` → AUTO_MANAGED 包含 `llmswitch`，可选项含 `larkcli` / `larkbridge` / `larkcli` / `officecli` / `cloudflare` / `remote` / `skill` / `usage`

### ADR-0006 历史结论保留

- ✅ 双组件策略（lark-cli + bridge）
- ✅ 不引入飞书 MCP（评估仍正确：缺被动接收 / 流式回复 / session 管理）
- ⚠️ 具体实现是 larkbridge，非 cc-connect

## Related Decisions

- **ADR 0001**：真实配置文件不入 git 仓 → feishu.json 走 ccprivate symlink

## Notes

- 2026-07 重新评估飞书 MCP：飞书官方 MCP（`@larksuiteoapi/lark-mcp`）比第三方 `@china-mcp/feishu-mcp` 功能更全面（18+ 工具 vs 8 个），但核心缺陷不变：无被动消息接收、无流式回复、无 session 管理。这些是对话场景的硬需求，不是 API 层面能解决的
- 如果未来需要「AI 以用户身份自动在飞书群发通知」之类用户身份 OAuth 场景，可以单独引入飞书 MCP 的 `im.v1.message.create` 工具（非全量 preset），不影响当前架构