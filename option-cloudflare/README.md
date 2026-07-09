# Cloudflare Claude Code 插件

> 可选组件 — 适用 Workers/R2/D1/Pages 等 CF 小项目开发

## 安装

```bash
bash ccconfig/option-cloudflare/init.sh --install
```

通过 Claude Code 插件系统安装 `cloudflare@cloudflare`：
- **11 skills**（按需加载）：cloudflare, wrangler, agents-sdk, durable-objects, web-perf 等
- **2 commands**：`/cloudflare:build-agent`, `/cloudflare:build-mcp`
- **5 HTTP MCP 服务器**：api, docs, bindings, builds, observability（4 需 OAuth）

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
- MCP tools ~2-3k tokens（4/5 需 OAuth，未认证时更少）

## 详文档

`docs/cloudflare-plugin.md`
