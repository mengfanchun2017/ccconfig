# Phase 0 — 安全 + 公开化

> **状态**: 🚧 进行中
> **开始**: 2026-06-08
> **预计完成**: 2026-06-15
> **关联**: [ROADMAP.md Phase 0](../../ROADMAP.md), OKR O.「ccconfig 正式化」/KR1
> **决策依据**: [ADR-0001](../adr/0001-secret-strategy.md)

## 目标

消除所有公开仓库的密钥泄露风险，建立 secret-scan 防护，让 ccconfig 真正可公开。

## 任务清单

| # | 任务 | 优先级 | 预计 | 状态 | 实际开始 | 实际完成 | 备注 |
|---|---|---|---|---|---|---|---|
| 1 | `.gitignore` 加 5 个真实 conf | P0 | 15min | 🚧 | 06-08 |  | 当前在改 |
| 2 | `init.sh` 加 key 缺失检测 + 引导 | P0 | 1h | ⏳ |  |  | 模式 2 |
| 3 | Rotate MiniMax key（`sk-cp-OjTA4...`） | P0 | 15min | ⏳ |  |  | MiniMax 后台 |
| 4 | Rotate DeepSeek key（`sk-abc...`） | P0 | 15min | ⏳ |  |  | DeepSeek 后台 |
| 5 | Rotate 飞书 app_secret | P0 | 15min | ⏳ |  |  | 飞书开放平台 |
| 6 | 建 `.github/workflows/secret-scan.yml` | P0 | 30min | ⏳ |  |  | gitleaks |
| 7 | `git filter-repo` 改写历史 | P1 | 1h | ⏳ |  |  | defense in depth |
| 8 | 验证所有脚本在 conf 缺失时 fallback | P0 | 30min | ⏳ |  |  | status.sh 等 |
| 9 | CHANGELOG 加 Unreleased 段落 | P0 | 10min | ⏳ |  |  |  |

**总工时**: ~4.5h

## 退出标准（Definition of Done）

- [ ] 5 个 JSON conf 全在 `.gitignore`
- [ ] 3 把 key 全部 rotate 完成（旧 key 在 MiniMax/DeepSeek/飞书 后台已 revoke）
- [ ] `init.sh` 在 conf 缺失时引导用户输入（不直接挂）
- [ ] CI secret-scan workflow 配置 + 触发通过
- [ ] 任意 `init.sh all` 在新机器（清 HOME 状态）跑通
- [ ] CHANGELOG 加 Unreleased 段落记录
- [ ] ADR-0001 落地 + 引用本文

## 关键设计（来自 ADR-0001）

- `conf/*.json`（非 `*.example`）+ `link/.config.json` 全部 `.gitignore`
- 真实 key 一台机器一份，bootstrap 阶段引导输入
- `init.sh` 检测缺失 → 复制 `.example` + 提示编辑
- 公开仓库仅含 `.example` 模板
- 不引入 `git-crypt` / SOPS（单人项目过度工程）

## 风险

| ID | 风险 | 缓解 |
|---|---|---|
| R1 | `init.sh` 检测真实文件缺失时，已运行的 hook/monitor 脚本会立即挂 | 先支持 fallback 到 `.example`，给 1 周迁移期；同时改 hook/monitor 让其检测缺 conf 时优雅退出 |
| R2 | `link/.config.json` 被多处引用，移走会断 | 先备份到 `link/.config.json.local`（gitignore），确认所有引用改完再删原文件 |
| R3 | 改写历史（task #7）可能影响其他协作者 | 当前仓库单人使用，零风险；多人 fork 时单独通知 |
| R4 | 飞书 app_secret 公开后，飞书 bot 可能被滥用 | rotate 后立即去飞书后台 audit bot 调用日志 |

## 验证清单（任务完成后做）

```bash
# 1. 确认 .gitignore 生效
git check-ignore -v conf/llm.json conf/claude.json conf/feishu.json link/.config.json

# 2. 确认 .example 可用
diff conf/llm.json.example conf/llm.json  # 应只剩 key 字段差异

# 3. 跑 init.sh 在清 HOME 状态
TMPHOME=$(mktemp -d)
HOME=$TMPHOME bash init.sh status  # 应引导输入 key
rm -rf $TMPHOME

# 4. 跑 secret-scan
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks detect --source /repo --no-git

# 5. 跑 status.sh（正常路径应全绿）
bash status.sh
```

## 回看（阶段结束填）

- **完成情况**: 9/9 = 100%（实际数）
- **超期原因**:
- **学到的**:
- **下阶段输入**: Phase 1 起点

## 相关文件

- [ADR-0001: 真实配置文件不入 git 仓](../adr/0001-secret-strategy.md)
- [STATE.md: 当前进度](../STATE.md)
- [ROADMAP.md: 全局视图](../../ROADMAP.md)
- [init.sh](../../init.sh)（待改）
- [.gitignore](../../.gitignore)（待改）
