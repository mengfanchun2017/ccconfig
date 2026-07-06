# ccconfig Roadmap

> 最后更新: 2026-07-06
> 目标: 2026 Q3 末前从「个人 dotfiles」升级到「正式开源项目」基线
> 关联 OKR: 飞书 Base OKR_O 表中 O.「ccconfig 正式化」
> 设计来源: [Shape Up](https://basecamp.com/shapeup)（pitch + cycle 概念）

## 愿景

ccconfig 成为 Claude Code 配置管理的事实标准开源项目 — 任何新机器 10 分钟拉起，多设备配置一致，可被社区审查与贡献。

## 阶段总览

| 阶段 | 时间 | 主题 | 状态 | 详细计划 |
|---|---|---|---|---|
| Phase 0 | 2026-06 上 | 安全 + 公开化（.gitignore / ccprivate 拆分 / filter-repo / pre-commit）| ✅ 完成 | [task_plan.md](docs/task_plan.md) |
| Phase 1 | 2026-07 上 | 架构审核 + 三仓库文档补齐 + 产品化发布 | ✅ 完成 | (CI workflow 已加) |
| Phase 2 | 2026-07 中 | 文档/ADR/发布流程 + **完善 f-ship skill v0.2** | ⏳ 未开始 | |
| Phase 3 | 2026-07 下 | 社区健康 + 后续迭代 | ⏳ 未开始 | |

## 阶段详情的滚动指针

**当前 active phase**：[docs/task_plan.md](docs/task_plan.md)

完成后：
1. `docs/task_plan.md` 顶部更新为 ✅ done
2. 旧文件归档到 `docs/plans/phase-N-<topic>-archive.md`
3. 原地创建新 phase 内容（仍在 `task_plan.md`）
4. 本表「状态」列更新
5. 更新 [docs/progress.md](docs/progress.md) 状态变迁日志

## 关键决策

见 [docs/adr/](docs/adr/)。每个非可逆决策一条 MADR 4 字段 ADR（status / context / decision / consequences）。

## 关联 OKR（飞书 Base）

O.「ccconfig 正式化」
- KR1: Phase 0-3 全部完成（2026-07-31）
- KR2: 首次 v1.0.0 tag 发布 + CHANGELOG（2026-07-05）→ ✅ 完成
- KR3: GitHub ⭐ > 10（2026-09-30）

每次 ccconfig 工作 session 开头明示「关联 O.ccconfig-正式化/KR1」，hook 自动写 worklog 到飞书。

## 冷启动 ritual

每次新 session 前 30 秒：

```
1. 读 docs/progress.md      ← 一眼定位「上次干到哪」
2. 读 ROADMAP.md            ← 确认阶段没变
3. 读 docs/task_plan.md     ← 找「下次 session 入口」
4. 跟 Claude 说「接着 phase N 任务 #X 继续」
```

## 未来 f-ship skill

本仓库的 4 层追踪结构是 **`f-ship` skill**（"想法 → shipped 端到端循环"）的种子和第一实例。

**抽取计划**:
- **v0.1**（Phase 0 末尾，2026-06-15）— 雏形：SKILL.md + 4 文件模板 + init.sh scaffold
- **v0.2**（Phase 2，2026-07 上）— 完善：references/ 完整 + 飞书 Tasks 表建表指南 + 多场景适配
- **v1.0**（Phase 3，2026-07 下）— 首发：发布到 claude-skills marketplace

**默认结构**（hybrid 模式 — 2026-06-08 决策）:
- L1 ROADMAP.md → repo（git 跟踪，公开）
- L0 adr/ → repo（MADR 4 字段，公开）
- L2 Tasks 表 → 飞书 Base（f-logme 扩展，联动 OKR）
- L4 Worklog 表 → 飞书 Base（现有 f-logme，hook 自动）
- L3 = L2 + L4 的飞书 Base Dashboard 视图
- L2.5 findings.md → repo（自由研究笔记）
- L3 镜像 progress.md → repo（手写 5 行快查 + 飞书 view 指针）
