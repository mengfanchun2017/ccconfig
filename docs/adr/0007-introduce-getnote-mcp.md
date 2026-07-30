# 0007. 引入 @getnote/mcp — 得到笔记 MCP 集成

> **Status**: ✅ Accepted
> **日期**: 2026-07-30
> **关联**: getnote skill (`skill/plugins/getnote/`)

## Context and Problem Statement

getnote skill 已注册 27 个 MCP tools 覆盖得到大脑（Get笔记）全部功能：笔记 CRUD、语义搜索、知识库管理、图片上传、博主内容、直播。但 MCP server（`@getnote/mcp`）未集成到 init-mcp.sh，用户需手动配 `~/.claude/settings.json`。

缺 MCP server = skill 的 tool 列表有名称无执行能力，调用任何 getnote tool 都失败。

同时需解决两个问题：

1. **配置集中化**：遵循已有 MCP 治理模式 — `ccprivate/conf/claude.json` 定义、`init-mcp.sh` 注册、`init-mcp.sh keys` 交互填 Key
2. **安全意识**：API Key 用于语义搜索和个人笔记 CRUD，泄露可被读取全部笔记内容

## Decision Drivers

- **D1 一致性**：遵循现有 MCP 治理流程（tavily、minimax、supabase 同模式）
- **D2 零代码变更**：init-mcp.sh 已自动读取 `mcp_servers` 列表，加 entry 即可
- **D3 最小泄露面**：Key 不进 git、不落 `ccprivate/skill-config/`、不走环境变量残留
- **D4 易用性**：用户只需一次粘贴 Key，后续 init-skill.sh sync 自动同步

## Considered Options

### Option A: 放入 skill-config（`ccprivate/skill-config/getnote.yaml`）

- Pros: 与 ffeishu 等其他 skill 配置风格一致
- Cons:
  - getnote 是 MCP server 而非 skill 配置，不属于 skill-config 治理域
  - MCP server 的 Key 统一由 `init-mcp.sh keys` 管理，分到两处增加混乱

### Option B: 仅环境变量（每次启动注入）

- Pros: Key 完全不落盘
- Cons:
  - Claude Code 重启后环境变量丢失，需重新注入
  - 与现有 MCP 治理流程不一致（tavily、minimax 都落 conf）

### Option C: 放入 `mcp_servers` 列表 + `init-mcp.sh keys` 交互填（**采纳**）

- Pros:
  - 零代码变更：init-mcp.sh 自动读取列表
  - 统一的交互填 Key 体验
  - 统一的 sync/status/toggle 管理
  - Key 存在 `ccprivate/conf/claude.json`（gitignored，不入公开仓）
- Cons:
  - Key 明文存 JSON（但 ccprivate 非公开仓，与已有 Key 同风险等级）

## Decision

**采纳 Option C**，在 `ccprivate/conf/claude.json` 的 `mcp_servers` 数组追加 getnote entry：

```json
{
  "name": "getnote",
  "description": "得到大脑(Get笔记) - 笔记 CRUD、语义搜索、知识库管理",
  "how_to_get": "打开 https://www.biji.com/openapi → 创建应用 → 获取 API Key 和 Client ID",
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@getnote/mcp"],
  "env": {
    "GETNOTE_API_KEY": "请到 https://www.biji.com/openapi 获取 API Key（格式：gk_live_xxx）",
    "GETNOTE_CLIENT_ID": "请到 https://www.biji.com/openapi 获取 Client ID（格式：cli_xxx）"
  }
}
```

## 安全性分析

### Key 存储路径

```
ccprivate/conf/claude.json  ← 真实 Key（.gitignore，不公开）
                          ↓ symlink / copy
~/.claude/settings.json   ← Claude Code 运行时读取
```

不在以下位置：skill-config（不属于 skill 配置域）、公开 git 仓、shell 历史、环境变量文件。

### Key 权限

Get笔记 API Key 的权限范围：

| 能力 | API Key 可做 |
|------|-------------|
| 读取笔记 | ✅ 全文搜索、获取笔记详情 |
| 写入笔记 | ✅ 创建/更新/删除 |
| 管理知识库 | ✅ 创建 Topic、组织笔记 |
| 删除账号 | ❌ 需 App 操作 |
| 查看账号信息 | ❌ 不返回邮箱/手机 |

**风险评级**：Key 泄露 = 攻击者可读取全部笔记内容。属于**敏感但不关键**（不能改密、不能提现、不能冒充身份）。

### 缓解措施

| 措施 | 说明 |
|------|------|
| 不入公开仓 | ccprivate 非公开，.gitignore 覆盖 |
| 可独立 revoke | 得到 App → 开发者页面 → 删除 Key，不影响账号 |
| 无持久 Token | @getnote/mcp 每次启动从环境变量读 Key，不写入任何持久状态文件 |
| 无网络端口 | stdio 模式运行，不监听端口、不引入 HTTP 攻击面 |
| 定期 rotate | 用户可在得到开发者页面随时创建新 Key、废弃旧 Key |
| 最小权限原则 | API Key 只绑定笔记域，不涉及支付/账号设置 |
| npx sandbox | 通过 npx 运行，包在 npm 生态沙箱中，非系统级 daemon |

### 对比其他 MCP Key

| MCP | Key 泄露影响 | 存储方式 | Revoke 方式 |
|-----|-------------|---------|------------|
| tavily | 消耗搜索额度 | conf/claude.json | 后台删除 |
| minimax | 消耗 API 额度 | conf/claude.json | 后台删除 |
| supabase | 数据库读写 | conf/claude.json | 后台删除 |
| **getnote** | 笔记读写 | conf/claude.json | App 删除 Key |

getnote Key 泄露风险等价于 tavily（额度消耗类），但泄露内容（笔记）的私密性高于 tavily（搜索结果）。不引入新风险等级。

## Consequences

### Positive

- ✅ init-mcp.sh 零代码变更，加 entry 即生效
- ✅ 统一管理：status/sync/keys/toggle 全支持
- ✅ Key 配置流程与用户已有认知一致（tavily 怎么填，getnote 就怎么填）
- ✅ 与 getnote skill 的 27 个 MCP tools 配套，装完即可使用

### Negative

- ❌ 当前 `init-mcp.sh keys` 流程不检查 Key 有效性（与 tavily/minimax 同缺陷，非新引入）
- ❌ Key 明文存 JSON 文件（与已有 Key 同级风险，非新引入）

## Implementation

1. `ccprivate/conf/claude.json` 追加 getnote entry ✅ (已执行)
2. 用户运行 `bash init-mcp.sh keys` 填入 Key
3. getnote skill 的 SKILL.md 配置指引已更新（指向 MCP server 而非 CLI）

## Related Decisions

- [0001. 真实配置文件不入 git 仓](0001-secret-strategy.md) — 本决策依赖此安全模型
- [0005. 废弃运行时 /mcp 命令](0005-remove-slash-mcp-runtime-command.md) — getnote 使用 stdio 模式，不涉及 /mcp 运行时注册