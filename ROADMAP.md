# ccconfig Roadmap

> 最后更新: 2026-06-08
> 目标: 2026 Q3 末前从「个人 dotfiles」升级到「正式开源项目」基线
> 关联 OKR: 飞书 Base OKR_O 表中 O.「ccconfig 正式化」

## 愿景

ccconfig 成为 Claude Code 配置管理的事实标准开源项目 — 任何新机器 10 分钟拉起，多设备配置一致，可被社区审查与贡献。

## 阶段总览

| 阶段 | 时间 | 主题 | 状态 | 计划文档 |
|---|---|---|---|---|
| Phase 0 | 2026-06 上 | 安全 + 公开化（rotate key / .gitignore / secret scan） | 🚧 进行中 | [phase-0-security.md](docs/plans/phase-0-security.md) |
| Phase 1 | 2026-06 下 | CI/CD + 测试 + lint 基础 | ⏳ 未开始 | phase-1-cicd.md（待建）|
| Phase 2 | 2026-07 上 | 文档/ADR/发布流程 | ⏳ 未开始 | phase-2-docs.md（待建）|
| Phase 3 | 2026-07 下 | 社区健康 + 首次发布 | ⏳ 未开始 | phase-3-release.md（待建）|

## 阶段详情的滚动指针

当前阶段详情见 [docs/plans/phase-0-security.md](docs/plans/phase-0-security.md)。

完成后在本表「状态」列更新，**不删旧阶段**。

## 关键决策

见 [docs/adr/](docs/adr/)。每个非可逆决策一条 ADR，含背景/方案/后果。

## 关联 OKR（飞书 Base）

O.「ccconfig 正式化」
- KR1: Phase 0-3 全部完成（2026-07-31）
- KR2: 首次 v2.0.0 tag 发布 + CHANGELOG（2026-07-31）
- KR3: GitHub ⭐ > 10（2026-09-30）

每次 ccconfig 工作 session 开头明示「关联 O.ccconfig-正式化/KR1」，hook 自动写 worklog 到飞书。

## 冷启动 ritual

每次新 session 前 30 秒：

```
1. 读 docs/STATE.md       ← 一眼定位「上次干到哪」
2. 读 ROADMAP.md         ← 确认阶段没变
3. 读当前 phase plan     ← 找「下次 session 入口」
4. 跟 Claude 说「接着 phase N 任务 #X 继续」
```
