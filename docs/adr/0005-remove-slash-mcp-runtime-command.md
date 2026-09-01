# 0005. 废弃运行时 `/mcp` 命令，迁移至 CLI `claude mcp` 子命令

> **Status**: ✅ Accepted
> **日期**: 2026-07-27
> **关联**: [upgrade-guide.md](../upgrade-guide.md)
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

Claude Code v2（当前 v2.1.212+）移除了运行时 `/mcp` 命令。该命令原本在 session 内以聊天 slash 命令形式提供 MCP 管理功能：

- `/mcp list` — 列出当前 MCP 服务
- `/mcp add` — 添加新 MCP 服务
- `/mcp remove` — 删除 MCP 服务

移除后，session 内无法再操作 MCP。用户必须退出 session 或在另一个终端使用 CLI 子命令 `claude mcp`。

直接影响：
1. fleetview 模式下无法运行时管理 MCP
2. 旧习惯 `/mcp add  xxx` → 报错无此命令
3. 新用户不知道替代入口

## Decision Drivers

- **D1 架构清晰**：配置管理（MCP 增删改）是 CLI 层职责，不是对话层职责
- **D2 非交互式兼容**：CI/CD、脚本化环境需要纯 CLI 接口管理 MCP
- **D3 全局跨 session**：配置变更应影响所有 session，而非当前 session
- **D4 生态对齐**：CLI 管理扩展是 MCP 生态趋势（vs code、JetBrains 均通过 settings.json / CLI 管理）

## Considered Options

### Option A: CLI `claude mcp` 子命令（上游采纳）

```bash
# 添加
claude mcp add my-server -e API_KEY=xxx -- npx my-mcp
claude mcp add --transport http my-server https://example.com/mcp --header "Authorization: Bearer xxx"

# 查看
claude mcp list
claude mcp get my-server

# 删除
claude mcp remove my-server
```

- **Pros**:
  - 跨 session 生效，非交互式环境可用
  - 支持 stdio、HTTP、SSE 多种传输层
  - 支持环境变量、header 等高级配置
- **Cons**:
  - 运行时无法操作，需另开终端或退出 session
  - 不直观（slash 命令用户习惯被破坏）

### Option B: 继续用 session 内 slash 命令

- **Pros**: 用户习惯保持，fleetview 可用
- **Cons**: 上游已移除，不在控制范围内

### Option C: 在 conf/claude.json 中封装管理脚本

自定义 `ccmcp` shell 包装 `claude mcp`。

- **Pros**: 短别名，降低认知负担
- **Cons**: 多一层封装，版本漂移风险，非标准接口

## Decision

**采纳 Option A**，接受上游设计。`/mcp` 已移除且不再恢复，标准操作路径改为：

```bash
# 查看当前 MCP 服务
claude mcp list

# 添加
claude mcp add <name> -e KEY=val -- <command>

# 删除
claude mcp remove <name>
```

## Consequences

### Positive

- ✅ 配置跨 session 生效，改一次所有 session 受益
- ✅ 非交互环境（CI/CD、cron、脚本）可管理 MCP
- ✅ 支持多种传输层（stdio / HTTP / SSE），不再局限于 stdio
- ✅ 支持高级配置（header、OAuth login/logout）

### Negative

- ❌ session 内无法操作 MCP，需另开终端
- ❌ fleetview 用户习惯破坏
- ❌ 上游强制迁移，无选择权

### Risks

- **R1** 用户不知道 `claude mcp` 存在 → 缓解：记录 ADR + 更新 upgrade-guide
- **R2** 部分旧版（< v2.0）仍支持 `/mcp`，但 ccconfig 统一管理版本，用户始终运行最新
- **R3** 多终端切换不便是真实痛点 → 缓解：考虑在 ccconfig 内封装 `ccmcp` 别名（Option C 作为补充）

## Notes

- v2.1.212 实测确认 `/mcp` 已移除
- `claude settings.json` 中 `mcp_servers` 字段仍为配置真相源，`claude mcp add` 实际写入 settings.json
- 当前 session 中已有 MCP 服务（tavily、getnote、exa）不受影响

## Related Decisions

- (none yet)

## Related Memory

- [[claude-code-v2-mcp-cli]] (本次决策)
