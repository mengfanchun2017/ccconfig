# Cloudflare Claude Code 插件 — 安装

> 可选组件 — 适用 Workers/R2/D1/Pages 等 CF 小项目开发。

## 安装

```bash
bash ccconfig/option-cloudflare/init.sh --install
```

通过 Claude Code 插件系统安装 `cloudflare@cloudflare`（v1.0.2）：
- **19 skills**（按需加载）：cloudflare, wrangler, agents-sdk, durable-objects, web-perf 等
- **1 rule**：`workers.mdc`（自动应用于 wrangler.jsonc 所在目录）
- **1 HTTP MCP 服务器**：`cloudflare` → `https://mcp.cloudflare.com/mcp`（docs/search/execute/whoami 4 个工具）

> 注：v1.0.0 时代的「5 MCP + 2 commands」在本版本已不存在。历史文档保留在 README.md 仅供参考，以实际安装内容为准。

## 操作

```bash
bash ccconfig/option-cloudflare/init.sh --status     # 检查安装状态
bash ccconfig/option-cloudflare/init.sh --update     # 更新到最新版
bash ccconfig/option-cloudflare/init.sh --uninstall  # 卸载
```

## 集成

`update.sh` 菜单 → 可选组件 10) Cloudflare 插件

```bash
bash ccconfig/update.sh 10    # 单独更新
bash ccconfig/update.sh all   # 不包含（需显式选择）
```

## Token 影响

- Skills ~600-800 tokens（按需加载）
- MCP tools ~2-3k tokens

## MCP 认证（两种方式）

插件自带的 `cloudflare` MCP 走 OAuth（首次调用浏览器弹窗）。若不想走 OAuth，
或 OAuth 在本机网络下不可用，可用 **API token** 替代：把同名 `cloudflare`
server 加到 user scope（带 `Authorization: Bearer <token>` header），它会**覆盖**
插件自带的那个（同名时 user 级优先）。token 从 `conf/cloudflare.json` 读：

```bash
TOK=$(python3 -c "import json;print(json.load(open('$HOME/git/ccprivate/conf/cloudflare.json'))['tokens']['claude'])")
claude mcp add --transport http cloudflare https://mcp.cloudflare.com/mcp -H "Authorization: Bearer $TOK" -s user
```

更省事的做法是把它注册进 `conf/mcp-servers.json`（模板见 `conf/mcp-servers.json.example`），
跑 `bash lib/init-mcp.sh sync` 一次到位。

> 完整插件说明（skills / MCP / 安装步骤）见 [README.md](README.md)。
