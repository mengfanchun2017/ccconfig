# docs/adr/ — Architecture Decision Records

> ⚠️ **物理路径 `docs/adr/`**（不是 `adr/`）。新增 ADR 前先 `ls docs/adr/` 取最新编号。规范见 [0010-adr-directory-location](0010-adr-directory-location.md)。

> 记录 ccconfig 正式化过程中的所有非可逆决策。
> 模板: **MADR 4.0**（[madr/](https://adr.github.io/madr/)）极简版。
> 强制字段: 4 个（status / context / decision / consequences），其他可选。
> 机器可解析: 每条 ADR 必含可被 `lark-cli docs +search` 搜的关键词。

## 索引

| 编号 | 标题 | 日期 | 状态 | 关联 Phase |
|---|---|---|---|---|
| [0001](0001-secret-strategy.md) | 真实配置文件不入 git 仓 | 2026-06-08 | ✅ Accepted | Phase 0 |
| [0002](0002-merge-kr-and-task.md) | 合并 KR + Task 为单一交付实体 | 2026-06-08 | ✅ Accepted | Phase 0 |
| [0003](0003-deprecate-tasks-and-kr-progress.md) | 废弃 Tasks + KR_Progress 表 | 2026-06-09 | ✅ Accepted | Phase 0 |
| [0004](0004-officecli-skill-architecture.md) | OfficeCLI skill 架构：base + load_skill | 2026-07-07 | ✅ Accepted | — |
| [0005](0005-remove-slash-mcp-runtime-command.md) | 废弃运行时 /mcp 命令，迁移至 CLI 子命令 | 2026-07-27 | ✅ Accepted | — |
| [0006](0006-feishu-communication-strategy.md) | 飞书通信策略：cc-connect + lark-cli，不引入飞书 MCP | 2026-07-29 | ✅ Accepted | — |
| [0007](0007-introduce-getnote-mcp.md) | 引入 @getnote/mcp — 得到笔记 MCP 集成 | 2026-07-30 | ✅ Accepted | getnote skill |
| [0008](0008-remote-connection.md) | Remote 远程连接方案（自 `adr/001` 迁入） | 2026-07-31 | ✅ Accepted | option-remote |
| [0009](0009-token-cost-reduction.md) | Token 成本优化：不装 caveman/rtk/headroom | 2026-08-02 | ✅ Accepted | — |
| [0010](0010-adr-directory-location.md) | ADR 目录位置约定 | 2026-08-02 | ✅ Accepted | — |
| [0012](0012-interact-p0-no-gum.md) | SH 交互规范化：lib/interact.sh P0 + 弃用 gum | 2026-08-10 | ✅ Accepted | Phase 1-3 |
| [0013](0013-bridge-selfheal-sessionstart.md) | OpenAI bridge 自愈：SessionStart hook + env guard | 2026-08-13 | ✅ Accepted | — |
| [0014](0014-tailscale-jump-server.md) | Tailscale 跳板机部署方案 | 2026-08-21 | ✅ Accepted | — |
| [0015](0015-llm-0731-deprecation.md) | 废弃 altllm0731 preset — 停止自改 bridge 适配网关不兼容 | 2026-08-23 | ✅ Accepted | — |
| [0016](0016-tailscale-subnet-router.md) | Tailscale Subnet Router — 适用 WSL + Windows：通过 RFC1918 私有段自动触发 `--use-win-curl` | 2026-08-29 | ✅ Accepted | — |
| [0017](0017-tailscale-serve-https.md) | Tailscale Serve HTTPS — 内网 LLM API 远程访问（流式兼容） | 2026-08-28 | ✅ Accepted | — |
| [0018](0018-permission-mode-strategy.md) | 权限模式策略 — defaultMode 用 auto，bypass 仅 flag 触发 | 2026-09-01 | ✅ Accepted | — |

> ADR 收录门槛见 [「何时写 ADR」](#何时写-adr)。轻量变更（bug fix / 单文件重构 / 样式调整）只在下方「决策时间线」一行记录。

## 决策时间线（worklog 提取，按日期倒序）

> 此前在 `docs/tech-decisions.md` 自动维护，已合并至此。轻量变更只在此处一行记录，重大决策进 [索引](#索引) 段。
> 数据来源: Worklog Base（配置见 `conf/flogme.json`），flogme skill 自动同步。
> 更新机制: worklog → `flogme extract-decisions` → 本段。

| 日期 | 决策 | 关联 ADR |
|------|------|---------|
| 2026-07-29 | cc-connect v1.4 + init-option 集成，飞书通信统一：cc-connect + lark-cli 双组件，不引入飞书 MCP | [ADR-0006](0006-feishu-communication-strategy.md) |
| 2026-07-07 | 删 officecli-pptx 冗余 skill，只保留 officecli base（npx），运行时 load_skill pptx/word/excel | [ADR-0004](0004-officecli-skill-architecture.md) |
| 2026-06-15 | ccconfig 开源安全加固：所有隐私数据统一存放 ccprivate，ccconfig 通过 symlink 引用；git filter-repo 清洗历史；26 文件 / 1504 commits 重写 | [ADR-0001](0001-secret-strategy.md) |
| 2026-06-14 | Vessel → Playwright 全线迁移：删 option-vessel/、bin/vessel-*、f-vessel skill、systemd vessel.service（删 1183 行 / 改 23 文件） | —（其他项目独立 ADR 系统） |
| 2026-06-13 | Playwright MCP 做主站（无障碍树 ~800 tokens/页），Vessel 保留给 Admin | —（其他项目独立 ADR 系统） |
| 2026-06-13 | webapp-testing skill 从 ccconfig link/skills/ 移至用户级 ~/.claude/skills/（可被所有项目复用，不依赖 ccconfig 同步链路） | — |
| 2026-06-12 | SessionEnd hook 自动去重（同 session 同主题合并）+ 智能 KR 路由 | — |
| 2026-06-12 | 移除 worklog 自动写入时的硬编码 KR fallback，改为从 SessionEnd hook 智能路由 | — |
| 2026-06-12 | monitor.sh `git add -A` 后若无 diff，输出 "already up to date" 而非静默（修复 pull --rebase 阻塞） | — |
| 2026-06-12 | feishu-cli-cheatsheet 从 525 行瘦身到 77 行（85%）；移除 4 个 skill 专属文件（节省 ~4500 token context budget） | — |
| 2026-06-11 | 建立 f-ship（现 f-launch）项目启动 skill，8 类项目模板 | — |
| 2026-06-11 | cc 全量清理：移除 ccconfig 中的 token、5 junk dir、6 loose file、papermaster（3 commits + 删 ~80MB） | — |
| 2026-06-10 | OKR + Worklog + Reflect 三层框架，PARA 方法融合 KR.PARA 字段 | — |
| 2026-06-07 | ccconfig docs 框架：L1/L0 仓库 + L2/L3/L4 飞书 Base + ADR 决策层，决策方法用 MADR | —（即本目录的起源） |
| 2026-06-05 | skills 双轨管理：ccconfig 工作副本 + skill marketplace + sync 一体化（setup-links.sh / publish.sh） | — |
| 2026-06-05 | f-skill 三层架构重组：Layer 1 输出平台 / Layer 2 知识生产 / Layer 3 个人工作流（f-search 抽出搜索原语、f-research→f-research-domain 瘦身、f-report-gen 替换 f-research-report） | — |
| 2026-06-03 | 6 skill 审计 + Webify/marketplace 技术决策落地（1 决策文档 367 行 + 1 废弃 skill 清理） | — |
| 2026-06-03 | 报告写作全链路升级：f-report-std 创建 + 3 模式 + 图子文档（12 文件 +689 行） | — |

> 工作流（实现细节）：

```
Worklog Base
  └─ flogme skill "extract-decisions" 触发
       └─ 匹配含 修复|迁移|清理|框架|重构|决策|移除|统一|废弃|fix|feat|refactor|chore 的记录
            └─ 写本段 + commit
```

## 强制 4 字段（每条 ADR 必含）

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| **Status** | 枚举 | ✅ | `Proposed` / `Accepted` / `Rejected` / `Superseded by NNNN` |
| **Context and Problem Statement** | 段落 | ✅ | 面对什么情况、什么痛点 |
| **Decision** | 段落 | ✅ | 决定怎么做（一句话能讲清）|
| **Consequences** | 列表 | ✅ | 正面 / 负面 / 风险 / 缓解 |

## 可选字段（推荐含）

| 字段 | 用途 |
|------|------|
| Decision Drivers | 决策时考虑的关键因素 |
| Considered Options | 替代方案 + pros/cons |
| Implementation | 链接到 phase plan 的具体任务 |
| Related Decisions | 链接到其它 ADR |
| Notes | 后续观察、补充 |

## 何时写 ADR

✅ **要写**：
- 改了架构方向（拆/合模块）
- 拒绝了某个明显方案（用 A 不用 B，why）
- 引入了新工具/库/平台
- 改了用户接口（CLI 行为、配置 schema）
- 改了发布/部署流程

❌ **不写**（只在「决策时间线」一行记录）：
- bug 修复（commit message 够）
- 单文件重构（commit message 够）
- 琐碎样式调整

## 状态机

```
Proposed ──> Accepted ──> Superseded by NNNN
    │
    └─> Rejected
```

## 命名约定

- 文件名：`NNNN-kebab-case-topic.md`
- 编号：4 位数，从 0001 起，**永不重用**
- 即使状态变 Rejected/Superseded，文件保留（不删）

## 模板

复制 `0001-secret-strategy.md` 当模板。这是 MADR canonical form 的精简版（5 字段 + 2 可选）。

## 链接

- [ROADMAP](../../ROADMAP.md)
- [架构设计](../architecture.md)
