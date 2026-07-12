# Cloudflare Claude Code 插件

> `cloudflare@cloudflare` v1.0.0 — Cloudflare 开发者平台官方插件

## 安装

```bash
claude plugin marketplace add cloudflare/skills
claude plugin install cloudflare@cloudflare
# 重启 Claude Code 或 /reload-plugins 生效
```

卸载：
```bash
claude plugin uninstall cloudflare@cloudflare
```

## 构成

插件是一个 bundle，同时安装 skills + commands + rules + MCP 服务器。

### Skills（11 个，按需自动加载）

| Skill | 用途 |
|-------|------|
| cloudflare | Workers/Pages/KV/D1/R2/AI/网络/安全/IaC 综合 |
| agents-sdk | 构建有状态 AI agent（state/scheduling/RPC/MCP/email/streaming） |
| durable-objects | 有状态协调（chat/games/booking）、RPC、SQLite、alarms、WebSocket |
| sandbox-sdk | 安全代码执行（AI code execution、code interpreter、CI/CD） |
| wrangler | 部署管理 Workers/KV/R2/D1/Vectorize/Queues/Workflows |
| web-perf | 审计 Core Web Vitals（FCP/LCP/TBT/CLS） |
| workers-best-practices | Workers 最佳实践 |
| turnstile-spin | Turnstile 验证码集成 |
| cloudflare-one | Cloudflare One 部署配置（Access/Gateway/WARP/Tunnel） |
| cloudflare-one-migrations | 从 Zscaler/Palo Alto 等迁移到 Cloudflare One |
| cloudflare-email-service | Cloudflare 邮件服务 |

### Commands（2 个）

| Command | 用途 |
|---------|------|
| `/cloudflare:build-agent` | 用 Agents SDK 构建 AI agent |
| `/cloudflare:build-mcp` | 在 Cloudflare 上构建 MCP 服务器 |

### Rules（1 个）

`workers.mdc` — Workers 项目规范，自动应用于 `wrangler.jsonc` 所在目录。

### MCP 服务器（5 个，HTTP remote）

| 服务器 | URL | 认证 |
|--------|-----|------|
| cloudflare-api | `https://mcp.cloudflare.com/mcp` | OAuth |
| cloudflare-docs | `https://docs.mcp.cloudflare.com/mcp` | 公开 |
| cloudflare-bindings | `https://bindings.mcp.cloudflare.com/mcp` | OAuth |
| cloudflare-builds | `https://builds.mcp.cloudflare.com/mcp` | OAuth |
| cloudflare-observability | `https://observability.mcp.cloudflare.com/mcp` | OAuth |

MCP 服务器均为 HTTP 远程类型，无持久进程。OAuth 在首次调用 CF tool 时自动触发。

## 启动模式

默认安装后所有组件启用。MCP 为 HTTP 类型无法 `autoStart: false`（该配置仅适用于 stdio 进程型 MCP）。4/5 MCP 需 OAuth，实际为自然的手动门槛。

如需完全禁用插件：
```json
// settings.json
"enabledPlugins": { "cloudflare@cloudflare": false }
```

## Token 影响

- Skills：~600-800 tokens（按需加载，不调用不消耗）
- MCP tools：~2-3k tokens（OAuth 完成前更少）
- Rule：workers.mdc 仅在 `wrangler.jsonc` 目录加载

## 使用建议

- 从 `wrangler.jsonc` 所在目录启动 Claude Code，插件自动读取 binding 配置
- 首次使用需 OAuth 认证（浏览器弹窗）
- 做小项目推荐装，构建 Workers/R2/D1 等场景效率提升明显

## 源

- GitHub: <https://github.com/cloudflare/skills>
- 插件市场: <https://pluginmarketplace.ai/blog/cloudflare-claude-plugin-marketplace-mcp>
- 官方文档: <https://developers.cloudflare.com/agent-setup/claude-code>

---

## ccconfig 落地页 (`www/` → Cloudflare Pages)

> **维护者参考**：此章节为项目维护者的 Cloudflare Pages 部署记录，包含个人域名和项目名。Fork 用户请替换为自己的 CF 配置。

**仓库**：`ccconfig/www/` 静态站 → Cloudflare Pages 部署

**关键配置**（Dashboard → Workers & Pages → &lt;your-cf-project&gt; → Settings）：
- **Build configuration → Root directory**：`www`
- **Build command / Build output directory**：留空（纯静态）
- **Source → Path includes**：`www/**`（监控 www 下变更触发 deploy）
- **Source → Production branch**：`main`

**部署触发**：push 到 main 分支且 `www/**` 有变更 → CF GitHub App webhook → 自动 build + deploy。新 deploy 自动成为 production；自定义域 alias 跟着切换。

**手动 retry / rollback**：
```bash
# API retry（重新 build 最新 commit）
curl -X POST "https://api.cloudflare.com/client/v4/accounts/<account_id>/pages/projects/&lt;your-cf-project&gt;/deployments" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
  -d '{}'

# API rollback（切 alias 到指定 deploy）
curl -X POST "https://api.cloudflare.com/client/v4/accounts/<account_id>/pages/projects/&lt;your-cf-project&gt;/deployments/<short_id>/rollback" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" -d '{}'
```

**踩坑（v1.4.7 修复）**：
- Dashboard 早期误设 `root_dir: "sites/config"` + `path_includes: ["sites/config/**"]`，导致 www/ 变更全部 `is_skipped: true`（`skip_reason: "path_config"`）。正确：`root_dir: "www"` + `path_includes: ["www/**"]`。
