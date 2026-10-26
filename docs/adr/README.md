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
| [0007](0007-introduce-getnote-mcp.md) | 引入 @getnote/mcp — 得到笔记 MCP 集成 | 2026-07-30 | 🚫 Superseded by [0041](0041-getnote-cli-skill-migration.md) | getnote skill |
| [0008](0008-remote-connection.md) | Remote 远程连接方案（自 `adr/001` 迁入） | 2026-07-31 | ✅ Accepted | option-remote |
| [0009](0009-token-cost-reduction.md) | Token 成本优化：不装 caveman/rtk/headroom | 2026-08-02 | ✅ Accepted | — |
| [0010](0010-adr-directory-location.md) | ADR 目录位置约定 | 2026-08-02 | ✅ Accepted | — |
| [0011](0011-git-auth-fine-grained-pat.md) | GitHub git 认证统一为 fine-grained PAT + HTTPS | 2026-08-09 | ⚠️ 部分 Superseded by [0023](0023-pat-expiry-on-failure-only.md)（Layer 1 过期巡检部分） | 认证 |
| [0012](0012-interact-p0-no-gum.md) | SH 交互规范化：lib/interact.sh P0 + 弃用 gum | 2026-08-10 | ✅ Accepted | Phase 1-3 |
| [0013](0013-bridge-selfheal-sessionstart.md) | OpenAI bridge 自愈：SessionStart hook + env guard | 2026-08-13 | ⚠️ 部分 Superseded by [0031](0031-init-llm-consolidation-2026.md) | Bridge |
| [0014](0014-tailscale-jump-server.md) | Tailscale 跳板机部署方案 | 2026-08-21 | ✅ Accepted | — |
| [0015](0015-llm-0731-deprecation.md) | 废弃 altllm0731 preset — 停止自改 bridge 适配网关不兼容 | 2026-08-23 | ✅ Accepted | — |
| [0016](0016-tailscale-subnet-router.md) | Tailscale Subnet Router — 适用 WSL + Windows：通过 RFC1918 私有段自动触发 `--use-win-curl` | 2026-08-29 | ✅ Accepted | — |
| [0017](0017-tailscale-serve-https.md) | Tailscale Serve HTTPS — 内网 LLM API 远程访问（流式兼容） | 2026-08-28 | ⚠️ Superseded by [0016](0016-tailscale-subnet-router.md) | — |
| [0018](0018-permission-mode-strategy.md) | 权限模式策略 — defaultMode 用 auto，bypass 仅 flag 触发 | 2026-09-01 | ⚠️ Superseded（模式选择）by [0049](0049-auto-mode-discards-allow-rules.md) | 权限 |
| [0019](0019-bridge-win-curl-wsl-vpn.md) | OpenAI bridge 三层修复：WSL 网络栈隔离 + DNS 污染 + ARG_MAX 溢出 | 2026-08-14 | ✅ Accepted | — |
| [0020](0020-llm-current-local-per-machine.md) | LLM 运行时配置本地化 — 每台机器独立选择 LLM | 2026-09-01 | ✅ Accepted | — |
| [0021](0021-skill-creation-workflow.md) | Skill 创建工作流 — fskillcreat 交互 + link-single 增量注册 | 2026-09-01 | ✅ Accepted | — |
| [0022](0022-batch-translate-workflow.md) | 批量文档翻译工作流 — DOCX 中间格式 + python-docx 原地替换文本 | 2026-09-01 | ✅ Accepted | python-docx → init-option |
| [0023](0023-pat-expiry-on-failure-only.md) | GitHub PAT 失效检测改为 on-failure-only — 删主动过期天数巡检 | 2026-09-02 | ✅ Accepted | supersedes 0011 Layer 1 |
| [0026](0026-bats-test-framework.md) | bats 测试框架引入 — bats_run 代替 run，test/ 统一测试目录 | 2026-09-03 | ⚠️ 已复核：三条 Decision 与现状不符（见正文）。方向保留 | 测试 |
| [0027](0027-idempotent-guard-pattern.md) | 幂等 guard 模式 — _is_installed/_is_not_file/atomic_write 统一 API | 2026-09-03 | ⛔ Superseded（2026-10-25：`guard_*` 已删） | — |
| [0028](0028-unified-cli-entry.md) | 统一 CLI 入口 — bin/ccconfig subcommand 路由 | 2026-09-03 | ✅ Accepted | CLI 基础设施 |
| [0029](0029-init-llm-target-2026.md) | init-llm 目标文档化 + 删 gateway 整层 + 3 个稳定性增强 + bill 简化为用量读取 + 合并 altllm preset 4→2 | 2026-09-17 | ✅ Accepted | LLM 管理 |
| [0030](0030-gateway-deprecation-2026.md) | Gateway 模式废弃 — 删 gateway 层（init.sh/proxy.py/watchdog.sh），保留 openai_bridge.py 作 bridge | 2026-09-17 | ✅ Accepted | LLM 管理 |
| [0031](0031-init-llm-consolidation-2026.md) | init-llm 收敛：修桥接链路 P0（流式包装器/transport/守护层）+ 探测统一 + 四层守护模型 + 删交互式编辑 | 2026-09-17 | ✅ Accepted | LLM 管理 |
| [0032](0032-config-layering.md) | 配置分层：共享预设 vs 本机选择 — 切换零写入 + setup.sh 单一模板真相源（原「模板拆分」决策已撤销） | 2026-09-17 | ⚠️ Decision 4 已修正 | 配置 |
| [0033](0033-bridge-collapse-usage-delta.md) | 收窄 bridge 流式 usage message_delta 为收尾一次 — 逐 token 冗余事件致 CC 误判重试 | 2026-09-20 | ✅ Accepted | Bridge |
| [0034](0034-bridge-block-index-and-thinking-switch.md) | bridge 块索引唯一化 + 重复投递丢弃 + thinking 开关（enable_thinking） | 2026-09-22 | ✅ Accepted | Bridge |
| [0035](0035-api-aggregator-platform-selection.md) | 数据 API 聚合平台选型 — 用 APIVerve（AnyAPI 备选，apitree 暂缓） | 2026-09-25 | ✅ Accepted | — |
| [0036](0036-drop-token-usage-feature.md) | 删除本地 Token 用量链路（option-usage / token-usage / bill）— 改用 Claude 自带 usage 统计 | 2026-09-28 | ✅ Accepted | — |
| [0037](0037-skill-pip-venv-auto-install.md) | Skill pip 依赖经自建 venv 自动安装 — pip 分支改由 skill setup.sh 建隔离 venv，同步即装好 | 2026-10-03 | ✅ Accepted | init 能力 |
| [0038](0038-playwright-mcp-browser-automation.md) | Playwright MCP 浏览器自动化 — 4 层安装 + `--executable-path` symlink 解耦版本 + headed 登录持久 profile | 2026-10-03 | ✅ Accepted | option-playwright |
| [0039](0039-llm-three-tier-config.md) | 三层 LLM 配置 — `llmnormal.json`(公开内置预设) + `llmprivate.json`(私有自定义) + `llm.json`(纯 key)，合并缓存 `~/.cache/llm-merged.json` | 2026-10-07 | ✅ Accepted | LLM 管理 |
| [0040](0040-remote-file-transfer-channels.md) | 远程服务器文件传输通道选型 — Taildrop 直落「下载」文件夹为主，飞书(20MB内)为补充，SSH 为好友跨账号备用 | 2026-10-07 | ✅ Accepted | option-remote |
| [0041](0041-getnote-cli-skill-migration.md) | 得到大脑集成从 MCP 切换为 CLI + Skill（OAuth 授权）— 卸载 `@getnote/mcp`，改用官方 `@getnote/cli` + 5 原子 Skill | 2026-10-08 | ✅ Accepted | 取代 [0007](0007-introduce-getnote-mcp.md) |
| [0042](0042-wsl-image-paste-sharex-path.md) | WSL 图像粘贴方案 — ShareX「复制文件路径」规避 WSLg BMP 解码坑，弃 Alt+V/解绑 Ctrl+V | 2026-10-08 | ✅ Accepted | — |
| [0043](0043-writing-system-architecture.md) | 文档撰写系统架构 — 四层分层（路由/编排/规范/机械）+ 声明式体裁注册表 + 统一命名（fworch/forch*/fwstd-*） | 2026-10-10 | ✅ Accepted | 撰写系统 |
| [0044](0044-agent-smb-file-bridge.md) | agent 跨机取件通道 — SMB `C$` + tsxfer 专用账户（反向拉取 + 回写），补 0040 的 agent 主动方向 | 2026-10-12 | ✅ Accepted | option-filepull（待建） |
| [0045](0045-llm-context-window-config.md) | LLM 上下文窗口可配置 — 预设 `max_context_tokens`（单位 k）+ 菜单/CLI 输入 + 全局默认 + 内置薄覆盖 | 2026-10-13 | ✅ Accepted | LLM 管理 |
| [0046](0046-remote-multi-window-tmux.md) | 远程多窗口连接 — Tailscale SSH + tmux（`new -A -s` 复用 session）+ PowerShell 客户端封装；多连接用不同 `-s` 名各自独立 | 2026-10-14 | ✅ Accepted | — |
| [0047](0047-tailscale-subnet-vs-office-intranet.md) | 开发机不做 tailscale subnet router — subnet 模式抢走单位内网路由致 office* LLM 慢/报错（DNS 通 + TCP `conn=0` 黑洞判据）；先查 `Find-NetRoute` 而非 bridge | 2026-10-16 | ⚠️ 结论部分被 [0051](0051-tailscale-accept-routes-blackholes-office-intranet.md) 修正 | — |
| [0048](0048-wsl-large-upload-stall.md) | ⚠️ 证伪：「WSL2 大 body 断流」实为超时误判 — 各传输栈均 ~90s，瓶颈是网关后端 ~3.3KB/s；撤销 force_win_curl，附「失败须先确证是真失败」归因教材 | 2026-10-16 | ⚠️ 原结论已推翻 | — |
| [0049](0049-auto-mode-discards-allow-rules.md) | auto 模式丢弃宽泛 allow 规则（`Bash(*)` 在 auto 下失效 → 一切命令送分类器被拦）→ 改 `bypassPermissions` + 补全 allowlist；新增 `claudebys` 别名 | 2026-10-16 | ✅ Accepted | — |
| [0050](0050-bridge-structural-refactor.md) | bridge 结构性重构 — 传输/协议分离、判定单点化（4份→1）、spawn 共用（setsid 取代 /tmp wrapper，不再落明文 Key）、协议层 8 类缺陷修复 + 新增 26 项单测 | 2026-10-16 | ✅ Accepted | — |
| [0051](0051-tailscale-accept-routes-blackholes-office-intranet.md) | tailscale accept-routes 让单位内网变黑洞（0047 的反向：查了 AdvertiseRoutes 漏了 RouteAll）— 新增 `lib/tailscale-guard.sh` 按 preset 自动关 accept-routes，接入 switch_llm / maintain fix / status / option-remote | 2026-10-16 | ✅ Accepted | — |
| [0052](0052-option-submenu-return-contract.md) | option 子菜单不再坠入 — `init-option.sh` 交互分支显式派发一次性子命令（getnote `install` / evalscope·skill·officecli·… `--install`），evalscope·skill 尾递归改 while，filepull 补 `--install` 且「已配置但离线」由 MISSING 降 WARN；顺带修 status 组件漏项与 `skill` 重复 | 2026-10-24 | ✅ Accepted | — |
| [0053](0053-home-preset-derp-only-network-cap.md) | 某些网络位置下 home\* preset 只能走 DERP（~18KB/s）— 三层 NAT（两层本地 + 运营商 CGNAT）+ 对端对称 NAT + 对端国际出口被封 → P2P 无解；换 DERP 区/放宽超时均实测无效；新增 preset 字段 **`max_concurrency`**（bridge 并发闸，`home*`=1）把"并发必挂"变成"排队可用"（4×100KB：50% 失败 → 4/4），附一分钟判据 | 2026-10-27 | ✅ Accepted | — |

> **编号 0024 / 0025 未使用**：编号永不重用（见[命名约定](#命名约定)），这两号在 0023 之后被跳过、没有对应文件，也没有正文引用。新增 ADR 从**当前最大号 +1** 起，不要去填这个空档。
>
> ADR 收录门槛见 [「何时写 ADR」](#何时写-adr)。轻量变更（bug fix / 单文件重构 / 样式调整）只在下方「决策时间线」一行记录。

### ⚠️ 已失效 / 待修（2026-10-25 三仓联合 review 复核）

下表是复核出的「描述与代码现状不符」的 ADR。**不是要删**（历史决策有归因价值），而是标注，
避免后来者照着失效内容做：

| ADR | 问题 | 现状 |
|-----|------|------|
| [0004](0004-officecli-skill-architecture.md) | `npx` 安装路径 | 已移除，只剩 base + 运行时 `load_skill` 概念成立 |
| [0006](0006-feishu-communication-strategy.md) | `cc-connect` / `option-cconnect/` | 组件与目录**均不存在**；不引入飞书 MCP 的策略仍成立 |
| [0009](0009-token-cost-reduction.md) | `commands/should-compact.md` | 文件与命令已不存在 |
| [0013](0013-bridge-selfheal-sessionstart.md) | 执行点已由 0031 接手 | 状态已改「部分 Superseded」 |
| [0018](0018-permission-mode-strategy.md) | 「日常用 auto」结论 | **已被 0049 推翻**（auto 丢弃宽泛 allow）→ 改 `bypassPermissions` |
| [0022](0022-batch-translate-workflow.md) | `translate-weekly.js` | 不存在；现为工作流 `transliter` |
| [0026](0026-bats-test-framework.md) | 三条 Decision（唯一框架 / `test/` / `bats_run`） | **全部与现状不符**（6 `.bats` + 20 `.sh`、`tests/`、零 `bats_run`） |
| [0027](0027-idempotent-guard-pattern.md) | 承诺 `lib/guard.sh` + `guard_*` 统一 API | **已 Superseded（2026-10-25）**：`guard_*` 已删除（`atomic_write` 保留）；统一封装决议放弃 |
| [0029](0029-init-llm-target-2026.md) | `lib/init-llm-bill.sh` | 随 0036 删除整条用量链 |
| [0032](0032-config-layering.md) | Decision 4「模板拆分」 | **决策本身是错的且从未实施**，已改「不拆」 |
| [0035](0035-api-aggregator-platform-selection.md) | 交叉引用 `0036-api-aggregator-comparison.md` | 该文件不存在（0036 号被占用），已改指新编号 |
| [0037](0037-skill-pip-venv-auto-install.md) | 两处 Decision（人工边界 / 幂等探测） | **均与代码相反**（已自动化 / 改 import 自检） |
| [0047](0047-tailscale-subnet-vs-office-intranet.md) | 结论 | 只查 `AdvertiseRoutes` 漏了 `RouteAll`，被 0051 修正 |
| [0050](0050-bridge-structural-refactor.md) | 「不再写 wrapper」+ 行数矩阵 | 看门狗层仍写 wrapper（不含 Key）；行数为当时快照 |

**另注**：本页「决策时间线」段**自述滞后**（最后一条 2026-07-29，而索引已有到 2026-09-17 的 ADR），
且其中多条引用已删路径（`docs/tech-decisions.md`、`ROADMAP.md`、`f-ship`/`f-research-domain` 等）。
补全需重跑 `flogme extract-decisions` 或手工回填。

## 决策时间线（worklog 提取，按日期倒序）

> 此前在 `docs/tech-decisions.md` 自动维护，已合并至此。轻量变更只在此处一行记录，重大决策进 [索引](#索引) 段。
> 数据来源: Worklog Base（配置见 `ccprivate/conf/flogme.json`），flogme skill 自动同步。
> 更新机制: worklog → `flogme extract-decisions` → 本段。
>
> ⚠️ **本段已滞后**：最后一条停在 2026-07-29，而[索引](#索引)已有到 2026-09-17 的 ADR。这一段时间的轻量决策没有回填，属已知缺口 —— 补全需重跑 `flogme extract-decisions`（或手工补齐）。不要据此认为 7 月底之后没做过决策。

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

复制 [`template.md`](template.md)（MADR canonical form 精简版）。不要拿 0001 当模板 —— 它是正式 ADR，正文会被连带抄进新文件。

标题格式统一为 `# NNNN. 标题`，头部统一用 `>` 引用块的四行（见 template.md）。

## 链接

- [架构设计](../architecture.md)
