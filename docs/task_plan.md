# task_plan — 当前 Phase 详细计划

> **L2 追踪层（飞书主，仓库镜像）**。当前 active phase 的全部任务、DoD、风险、验证。
> **主权威**: 飞书 Base OKR_KR 表（含 `类别=action` 子集 + Hill Chart 3 态）
> **本文件**: 设计说明 + 验证清单 + 退出标准；具体每条任务看飞书
> **历史**: Tasks 表已合并入 OKR_KR，详情见 [ADR-0002](adr/0002-merge-kr-and-task.md)
> 多 phase 时：每 phase 一个独立文件（如 `phase-1-cicd.md`），本文件始终指向 active。
> 模板参考: [planning-with-files](https://github.com/OthmanAdi/planning-with-files)（147k★，Manus 风格 3 文件规划）
> 进度模型: **Hill Chart**（unknown → known → done，3 态替代 0-100%）

## 当前 Phase

**Phase 0 — 安全 + 公开化**

- **状态**: 🚧 进行中
- **开始**: 2026-06-08
- **预计完成**: 2026-06-15
- **关联**: [ROADMAP.md Phase 0](../ROADMAP.md), OKR O.「ccconfig 正式化」/KR1
- **决策**: [ADR-0001](adr/0001-secret-strategy.md)
- **下次 session 入口**: [progress.md](progress.md)

## Hill Chart（3 态进度）

> **权威**: 飞书 OKR_KR 表的 `Status (Hill)` 字段（过滤 `类别=action`）。Dashboard view 实时显示。
> 本节是手写快照，下次 session 开始时对照飞书刷新。

| 状态 | 任务 | 说明 |
|---|---|---|
| 🔴 unknown | 任务 #2-#10 | 还没动手研究 |
| 🟡 known | (空) | — |
| 🟢 done | 任务 #1 | 改 `.gitignore` 5 行 + `git rm --cached` 5 conf，commit，**已完成** |

> **进度计算**: 0 known + 1 done = 1/10 ≈ 10% (按 3 态分桶)
> 不用 0-100% 是因为「做了 30%」是 fake precision；3 态更诚实。

## 飞书 OKR_KR 表（合并后）

- **Base URL**: `https://<your-tenant>.feishu.cn/base/<your-base-token>`
- **Table ID**: `<your-okr-kr-table-id>`（OKR_KR，含 outcome/process/action 3 类）
- **关联 O**: O.ccconfig-正式化
- **记录数**: 36 条（26 旧 KR + 10 新 action）

**合并后字段**: 标题 / 说明 / 类型 / 类别（NEW: outcome/process/action） / Status (Hill)（NEW）/ 关联ADR（NEW）/ Estimated (min)（NEW）/ 周期 / 进度 / 信心 / 关联O / 创建日期 / 更新日期 / 最终评分 / 编号

**10 条 Phase 0 任务**已迁入 OKR_KR，类别=action，每条 `关联O` 字段填 `O.ccconfig-正式化 record_id`。

**Worklog.关联Action** 字段 link → OKR_KR（过滤 `类别=action` 视图）

**Dashboard 视图建议**（待用户在飞书 UI 手动建）：
- 默认全部：36 条
- `类别=action` 日常看板：10 条
- `类别=outcome` 季度视图：26 条
- Hill Chart 进度：过滤 `Status (Hill) != done`

## 任务清单

| # | 任务 | 优先级 | 预计 | 状态 | 实际开始 | 实际完成 | 备注 |
|---|---|---|---|---|---|---|---|
| 1 | `.gitignore` 加 5 个真实 conf | P0 | 15min | 🟡 known | 06-08 |  | 当前在改 |
| 2 | `init.sh` 加 key 缺失检测 + 引导 | P0 | 1h | 🔴 unknown |  |  | 模式 2 |
| 3 | Rotate MiniMax key | P0 | 15min | 🔴 unknown |  |  | MiniMax 后台 |
| 4 | Rotate DeepSeek key | P0 | 15min | 🔴 unknown |  |  | DeepSeek 后台 |
| 5 | Rotate 飞书 app_secret | P0 | 15min | 🔴 unknown |  |  | 飞书开放平台 |
| 6 | 建 `.github/workflows/secret-scan.yml` | P0 | 30min | 🔴 unknown |  |  | gitleaks |
| 7 | `git filter-repo` 改写历史 | P1 | 1h | 🔴 unknown |  |  | defense in depth |
| 8 | 验证所有脚本在 conf 缺失时 fallback | P0 | 30min | 🔴 unknown |  |  | status.sh 等 |
| 9 | CHANGELOG 加 Unreleased 段落 | P0 | 10min | 🔴 unknown |  |  |  |
| 10 | 抽 f-ship skill 雏形 v0.1（`link/skills/f-ship/`）| P1 | 4h | 🔴 unknown |  |  | Phase 0 末尾执行；含 SKILL.md + 4 模板 + init.sh |

**总工时**: ~8.5h（任务 #1-9: 4.5h + 任务 #10: 4h）

## 退出标准（Definition of Done）

- [ ] 5 个 JSON conf 全在 `.gitignore`
- [ ] 3 把 key 全部 rotate 完成（旧 key 已 revoke）
- [ ] `init.sh` 在 conf 缺失时引导用户输入
- [ ] CI secret-scan workflow 配置 + 触发通过
- [ ] `init.sh all` 在新机器（清 HOME）跑通
- [ ] CHANGELOG 加 Unreleased 段落
- [ ] ADR-0001 引用本文
- [ ] Hill Chart 全 done 状态

## 风险

| ID | 风险 | 缓解 |
|---|---|---|
| R1 | hook/monitor 脚本在 conf 缺失时挂 | 加 fallback 到 `.example`，1 周迁移期 |
| R2 | `link/.config.json` 多处引用 | 先备份到 `.local`（gitignore），验证完再删 |
| R3 | `git filter-repo` 影响协作者 | 单人仓库零风险；多人 fork 时单独通知 |
| R4 | 飞书 bot 可能被滥用 | rotate 后立即 audit 飞书后台调用日志 |

## 验证清单

```bash
# 1. .gitignore 生效
git check-ignore -v conf/llm.json conf/claude.json conf/feishu.json link/.config.json

# 2. .example 可用
diff conf/llm.json.example conf/llm.json  # 应只剩 key 字段差异

# 3. 清 HOME 状态跑 init.sh
TMPHOME=$(mktemp -d)
HOME=$TMPHOME bash init.sh status  # 应引导输入 key
rm -rf $TMPHOME

# 4. secret-scan
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks detect --source /repo --no-git

# 5. status.sh 正常路径
bash status.sh
```

## Phase 切换

完成后：
1. 在本文件顶部更新状态 → ✅ done
2. 创建新 `docs/task_plan-<N+1>-<topic>.md` 或原地更新
3. 旧 phase 文件归档到 `docs/plans/phase-N-<topic>-archive.md`
4. 更新 [ROADMAP.md](../ROADMAP.md) 阶段总览
5. 更新 [progress.md](progress.md) 状态变迁日志

## 相关

- [ROADMAP.md](../ROADMAP.md) — L1 阶段总览
- [progress.md](progress.md) — L3 当前状态
- [findings.md](findings.md) — L2.5 研究笔记
- [adr/0001-secret-strategy.md](adr/0001-secret-strategy.md) — 决策依据

## 任务 #10 详情：f-ship skill 雏形 v0.1

**触发**: Phase 0 任务 #1-#9 全部 done 后立即执行
**目的**: 把 4 层结构抽成可复用 skill，让其他项目能 1 条命令起手

**最小交付物** (`link/skills/f-ship/`):
```
link/skills/f-ship/
├── SKILL.md                # 上面 spec 的实现
├── rules.d/                # 全局规则（输出风格）
├── references/
│   ├── 4-layer-model.md
│   ├── hybrid-default.md   # 为什么推荐 hybrid
│   └── feishu-setup.md     # 飞书 Tasks 表建表指南
├── templates/
│   ├── ROADMAP.md.tmpl
│   ├── progress.md.tmpl
│   ├── findings.md.tmpl
│   └── ADR.md.tmpl
└── init.sh                 # scaffold 4 文件 + 引导飞书建 Tasks 表
```

**依赖**:
- `f-logme` (OKR 联动) — 已存在
- `f-doc` (飞书操作) — 已存在
- `lark-cli` (Base 操作) — 已存在

**DoD**:
- [ ] SKILL.md 含 4 Q 决策点 + 5 步工作流
- [ ] 4 模板可直接 `cp` 使用
- [ ] init.sh 跑通（创建 4 markdown + 输出飞书建表命令）
- [ ] 在 ccconfig 本身上跑 1 次 init.sh 验证 idempotent

**未做**（Phase 2 v0.2）:
- references/ 详细文档
- 多场景适配（无飞书 fallback / 多项目）
- 自动 session 恢复 hook
- marketplace 发布
