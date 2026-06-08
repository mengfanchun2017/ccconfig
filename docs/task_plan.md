# task_plan — 当前 Phase 详细计划

> **L2 追踪层**。当前 active phase 的全部任务、DoD、风险、验证。
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

| 状态 | 任务 | 说明 |
|---|---|---|
| 🔴 unknown | 任务 #2-#9 | 还没动手研究 |
| 🟡 known | 任务 #1 | 改 `.gitignore` 5 行，明日 commit，**已知道怎么干** |
| 🟢 done | (空) | — |

> **进度计算**: 1 known + 0 done = 1/9 ≈ 11% (按 3 态分桶)
> 不用 0-100% 是因为「做了 30%」是 fake precision；3 态更诚实。

## 任务清单

| # | 任务 | 优先级 | 预计 | 状态 | 实际开始 | 实际完成 | 备注 |
|---|---|---|---|---|---|---|---|
| 1 | `.gitignore` 加 5 个真实 conf | P0 | 15min | 🟡 known | 06-08 |  | 当前在改 |
| 2 | `init.sh` 加 key 缺失检测 + 引导 | P0 | 1h | 🔴 unknown |  |  | 模式 2 |
| 3 | Rotate MiniMax key（`sk-cp-OjTA4...`） | P0 | 15min | 🔴 unknown |  |  | MiniMax 后台 |
| 4 | Rotate DeepSeek key（`sk-abc...`） | P0 | 15min | 🔴 unknown |  |  | DeepSeek 后台 |
| 5 | Rotate 飞书 app_secret | P0 | 15min | 🔴 unknown |  |  | 飞书开放平台 |
| 6 | 建 `.github/workflows/secret-scan.yml` | P0 | 30min | 🔴 unknown |  |  | gitleaks |
| 7 | `git filter-repo` 改写历史 | P1 | 1h | 🔴 unknown |  |  | defense in depth |
| 8 | 验证所有脚本在 conf 缺失时 fallback | P0 | 30min | 🔴 unknown |  |  | status.sh 等 |
| 9 | CHANGELOG 加 Unreleased 段落 | P0 | 10min | 🔴 unknown |  |  |  |

**总工时**: ~4.5h

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
