# 0041. 得到大脑集成从 MCP 切换为 CLI + Skill（OAuth 授权）

> **Status**: ✅ Accepted
> **日期**: 2026-10-08
> **关联**: 0007（被废弃，原 MCP 方案）；getnote 官方 CLI（`@getnote/cli` v1.6+）
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

getnote skill 曾以 MCP server（`@getnote/mcp`）驱动，45 个 `mcp__getnote__*` tool 覆盖笔记 CRUD、语义搜索、知识库、图片上传、博主、直播。凭证用开放平台 API Key（`gk_live_*`）+ Client ID。

2026-10 官方把主推方案收敛为：**一条命令 `npm install -g @getnote/cli@latest && getnote setup`**——CLI 自动识别本机 AI 平台、装 5 个原子 Skill、引导 OAuth 授权。MCP 降为并列选项。

触发切换的直接原因：ccprivate 里存的 API Key（`gk_live_a3b1...`）在服务端失效——curl 直连官方接口（`openapi.biji.com/open/api/v1/...`）也返回 10004 unauthorized / HTTP 401，四个配置源（getnote-accounts.json / settings / mcp-servers / CLI config）key 完全一致，排除配置问题。key 被作废或绑定失效，且无法用命令行恢复，只能 OAuth 或去平台重建。

## Decision Drivers

- **D1 官方主推**：CLI+Skill 是官方首页唯一主推（`npm i -g @getnote/cli@latest && getnote setup`），MCP 降级为选项
- **D2 OAuth 免管理 key**：浏览器扫码授权，自动生成 API key（名 OAuthxxx，有效期 1 年），不碰 `gk_live_*` 手动 key，避开手工 key 失效问题
- **D3 认证复用**：skill 与 CLI 共用 `~/.getnote/config.json` 同一份授权，跨工具复用
- **D4 官方维护**：5 个原子 Skill（getnote-auth/kb/note/search/tag）随 CLI 分发、`getnote update` 一键升级+同步，不再维护第二套自建 skill
- **D5 诊断完善**：`getnote doctor -o json` 提供结构化四层诊断（安装/授权/连通/集成），优于 MCP 无对应工具

## Considered Options

### Option A: 保留 MCP + 自建 skill，换新 key

- Pros: 零变更，upload_image 等 MCP 独占链路在
- Cons: key 需手动去 openapi 平台重建；MCP 非官方主推；自建 skill 要维护 45 tool 映射

### Option B: OAuth 授权修复现有 CLI（选定）

- Pros: 官方推荐、一次扫码、key 自动管理；CLI 覆盖全部功能（含 upload、原文直读 transcript/original、知识库文件夹）；doctor 诊断闭环
- Cons: 放弃 MCP 专属 upload_image 链路（CLI 的 `getnote upload` 需配合 MCP 拿临时 token，日常本地场景基本用不到）；脚本态多账号切换能力丢失（CLI 单账号）

### Option C: 双轨（CLI + MCP 并存）

- Pros: 两套都可用
- Cons: 凭证两套独立、维护两份；违背官方「选一即可，非都要装」

## Decision

选 **Option B**：卸载 `@getnote/mcp`，删除自建 getnote skill，改用官方 `@getnote/cli` + `getnote setup` 装的 5 个官方原子 Skill，OAuth 浏览器授权。

## Consequences

**落地清单**

- 卸载 `@getnote/mcp`（npm 全局 + `getnote-mcp` bin symlink）
- 删自建 getnote skill（`~/.claude/skills/getnote/`，原 45 MCP tool 映射）
- 装官方：`npm i -g @getnote/cli@latest && getnote setup`（5 skill: getnote-auth/kb/note/search/tag 装到 `~/.claude/skills/`）
- `npm` 全局 bin 不在 PATH 时，在 `$HOME/.local/bin` 建 `getnote`/`gnote` symlink
- 配置清理：settings.json / .config.json / ccprivate mcp-servers.json / claude.json 的 getnote MCP 段全删
- ccprivate 失效 key 文件 `getnote-accounts.json` 不再需要（CLI 用 `~/.getnote/config.json`）
- `option-getnote/` 重写为 CLI 引导（init.sh：--status/install/auth/doctor/update），删 getnote-switch.sh 多账号切换
- `maintain.sh`、`init-option.sh` 的 getnote 引用改为 CLI 授权状态检查

**正向**

- 安装/升级/授权一条命令闭环（`getnote setup` / `getnote update`）
- doctor 四层诊断：`doctor -o json` 出 `ready/status/issues/next_actions/integrations`
- 免手动 key 管理，OAuth key 有效期 1 年

**代价**

- MCP 专属 upload_image 链路失去（本地单机会话用不到 OSS 直传）
- CLI 单账号，无 getnote-switch 多账号切换

## 相关

- 官方 CLI 仓库: https://github.com/iswalle/getnote-cli
- OpenAPI 文档: https://www.biji.com/openapi?tab=docs
- 记忆: `getnote-cli-skill-architecture`（CLI + 官方原子 Skill 现状）