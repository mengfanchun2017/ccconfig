# 0043. 文档撰写系统架构 — 四层分层 + 声明式体裁注册表 + 统一命名

> **Status**: ✅ Accepted
> **日期**: 2026-10-10
> **关联**: `~/git/skill/plugins/`（公开 skill）、`~/git/ccprivate/skill-local/`（私有 skill）、`~/git/ccprivate/conf/writing/`（注册表真值）、`lib/init-skill.sh`
> **模板**: MADR 4.0 极简版
> **取代**: 无（本 ADR 整合既有 fcourse / fcaselib / freportstd / fresearchreport / ffeishu 三条线）

## Context and Problem Statement

用户在 ccconfig 生态上开发了一批「撰写类」skill，用于自动化生成课程、案例库、报告：

- **课程线**：`fcourse`（orchestrator）+ 5 个子 skill（research/syllabus/lesson/exercise/summary）+ `references/*.md` 模板 + 配置镜像 `conf/fcourse/<slug>.yaml`
- **案例线**：`fcaselib`（飞书 Base + wiki 三层 + MinerU 解析 + 检索工具层 `lark_env.sh`）
- **报告线**：`freportstd`（内容规范 + 4 模板）+ `fresearchreport`（工作流 3 模式）+ `fresearchframe`/`fsearch`（研究支撑）
- **平台机械层**：`ffeishu`（唯一碰 lark-cli 的层，含 `write-checklist.md`）+ `fdiagram`/`fpptx`/`fxlsx`/`fdocx`

三条线**范式不统一**，且共性问题没有抽象：

1. **三套心智模型**：报告线 = 机械/规范/工作流三层分工；课程线 = orchestrator + 子 skill 树；案例线 = 数据库 + 协议。同一个系统里三种。
2. **只有一套规范层**：`freportstd` 是唯一「写得好长啥样」的 skill；课程、案例的内容规范全散在各 SKILL.md。
3. **格式规则三处重复**：飞书格式硬约束（`<lark-table>` colgroup=822、禁手动编号、H1-H3）同时存在于 `ffeishu/references/write-checklist.md`、`freportstd`、`fcaselib` 正文模版，必漂移。
4. **契约只有一份**：`fcourse/references/comm-contract.md` 只服务课程线，报告线/案例线无统一返回契约。
5. **无统一入口**：用户须记住「做课程找 fcourse / 写报告找 freportstd / 加案例找 fcaselib」，系统无法按需求自动路由。
6. **职责重叠**：`fcourse-research`（调 fsearch+fresearchframe）与 `fresearchreport 大纲模式`（也调 fresearchframe）边界模糊。
7. **命名无规律**：`fcourse`/`fcaselib`/`freportstd`/`fresearchreport` 看不出层级；编排器与规范器同用 `f` 前缀。

三条线的**共性需求**明确：① 都落飞书文档、父目录不同；② 各体裁内容架构要求不同；③ 需多格式输出、均以飞书为根。

## Decision Drivers

- **D1 单一真相源**：格式约束、契约定一份，其余引用，不复制。
- **D2 层内一致**：同层 skill 命名与职责同构，跨体裁可迁移。
- **D3 需求路由**：用户只描述需求，系统自动判体裁派发。
- **D4 公开/私有纪律**：真实 token / 父目录 / 根文档绝不进公开仓库（`~/git/skill`）。
- **D5 零行为破坏**：收编现状优先，重命名不改变既有可用性。

## Considered Options

1. **每体裁独立一套 skill，各自为战（维持现状）** — pros：无迁移成本。cons：格式/契约重复持续漂移，无统一入口，问题 1-7 全部保留。
2. **合并为单一巨型 skill** — pros：一处定义。cons：单 SKILL.md 膨胀，context 成本高，与 skill 按需加载的设计相悖；体裁差异塞进一个文件难维护。
3. **四层分层 + 声明式体裁注册表 + 统一命名（采纳）** — pros：层内同构、跨体裁共享底座，差异收敛到「体裁规范 + 委派表」，新增体裁只加一份声明。cons：一次重命名/迁移工作量。

**Chosen**: 3

## Decision

### 一、四层架构

```
L4 路由层      fworch                       读注册表 → 判体裁 → 派编排器（fworch-<genre>）
L3 编排层      fworch-course / fworch-report / fworch-case   统一编排器契约（配置+进度+委派表+comm-contract）
L2 规范层      fstd-<genre>                     各体裁内容规范/模板（飞书格式走 ffeishu）
L1 步骤细则    fworch-<genre>/references/step-*.md   单步执行（不再独立成 skill）
L0 机械层      ffeishu / fdiagram / fpptx / fxlsx / fdocx   唯一碰 lark-cli 与 Office
```

共享底座：L0/L1/契约/进度机制全层复用；**差异只落 L2 体裁规范 + L3 委派表**。

### 二、统一命名

| 层 | 模式 | 成员 |
|----|------|------|
| L4 路由 | `fworch` | 唯一入口 |
| L3 编排 | `fworch-<genre>` | `fworch-course` / `fworch-report` / `fworch-case` |
| L2 规范 | `fstd-<genre>` | `fstd-report` / `fstd-course` / `fstd-case` |
| L1 步骤 | `fworch-<genre>/references/step-*.md` | 编排器内 references，不再独立成 skill |
| L0 机械 | 保持 `f*` 工具名 | `ffeishu`/`fdiagram`/`fpptx`/`fxlsx`/`fdocx` |

**一级/二级规范切分**：L2 规范**不**用命名堆叠（`fstd-course-lesson` 易被误读为并列体裁）。改用**目录深度**表达：
- 一级 = `fstd-<genre>/SKILL.md`（体裁规范总纲：内容架构 + 骨架 + 引用规则）
- 二级 = `fstd-<genre>/references/*.md`（各产物模板）

一个体裁一个 skill，模板收 references，层级清晰且 skill 数量不爆炸。

### 三、声明式体裁注册表（真值落 ccprivate）

注册表描述每种体裁的完整接口，**真实值（父目录/根文档 token）存 `ccprivate/conf/writing/`，公开仓库零真实值**：

```
ccprivate/conf/writing/
  registry.yaml    # 体裁索引 + 每体裁编排器/规范/配置指针（通用，可公开）
  report.yaml      # 报告体裁真值（feishu_root 等）
  case.yaml        # 案例体裁真值（Base/wiki token）
  course.yaml      # 课程体裁真值（parent_root_node 等）
```

`fworch-course`/`fworch-report`/`fworch-case`/`fworch` 运行时读对应 yaml；缺失则优雅降级（用内置默认 / 直派）。模式同 `fsyncdoc`（私有映射存在→全开，不存在→降级）。

**统一约定（全体裁）**：飞书在线文档 = 唯一真相源；本地 yaml（如 `conf/fcourse/<slug>.yaml`）仅为缓存镜像。

### 四、重命名映射（本 ADR 生效）

| 旧名 | 新名 | 层 |
|------|------|----|
| `fcourse` | `fworch-course` | L3 |
| `fcourse-{research,syllabus,lesson,exercise,summary}` | `fworch-course-{...}` | L1 |
| `fresearchreport` | `fworch-report` | L3 |
| `fcaselib` | `fworch-case`（编排/检索） + `fstd-case`（内容规范） | L3/L2 |
| `freportstd` | `fstd-report` | L2 |

不重命名（保留）：`ffeishu`/`fdiagram`/`fpptx`/`fxlsx`/`fdocx`（L0）、`fsearch`/`fresearchframe`（研究支撑）、`flogme`/`fmoocrec`/`fmashwork` 等无关线。

## Consequences

- ✅ 三条线同构，格式/契约单一真相源，漂移消除。
- ✅ 需求单入口（`fworch`），新增体裁 = 加一份 `fstd-<genre>` + 一条注册表。
- ✅ 真实配置集中 `ccprivate/conf/writing/`，公开仓零泄露。
- ❌ 一次性迁移成本（重命名 + symlink 重建 + 引用更新）。
- ⚠️ 重命名后 Claude session 需重启注册表才刷新（workflow/ skill 名缓存于 session 启动）。
- ⚠️ 迁移期新旧名并存可能混淆 → 每阶段完成即 `init-skill.sh link-only` 重建并验证。

## Implementation

- **P1** 本 ADR + `ccprivate/conf/writing/registry.yaml`（声明现状，零行为改动）
- **P2** 格式规则收敛：初建 `fstd-core` 作真相源，后因与 `ffeishu/references/write-checklist.md` §2 双份而**删除**，真相源定为 write-checklist §2
- **P3** `lark_env.sh` 共享化（`lark_auth_check`/`lark_call` → 公开 `ffeishu/references/lark_env.sh`）
- **P4** 建 `fworch` 路由入口
- **P5** 三线重命名 + 契约统一 + 拆 `fstd-course`/`fstd-case` + `fcourse-research`/`fresearchframe` 划界
- **P6（未做）** 注册表 `outputs` 声明驱动的统一多格式导出通道

## Related Decisions

- `ADR-0021`（`0021-skill-creation-workflow.md`）— skill 创建走交互 + `link-single`；本 ADR 的公开/私有归属沿用其分层
- `ADR-0006`（`0006-feishu-communication-strategy.md`）— lark-cli 为飞书操作唯一通道；本 ADR 的 L0 机械层即其实现
- `memory:skill-source-layering-20260831` — 公开上游 + 私有 `skill-local` 两层源，私有覆盖上游
- `memory:fmashwork-skill-scaffold` — 「公开 skill + ccprivate/skill/<name>.yaml」分离模式，本 ADR 扩展到 `conf/writing/`

## Notes

- 编号 0043 由当前最大号 0042 顺延（0024/0025 空档不重用）。
- 本节是方向性架构；具体 skill 内容以后续 P2-P5 的落地为准。
