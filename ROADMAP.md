# ccconfig Roadmap

> 最后更新: 2026-07-11
> 目标: 2026 Q3 末前从「个人 dotfiles」升级到「正式开源项目」基线
> 关联 OKR: 飞书 Base OKR_O 表中 O.「ccconfig 正式化」
> 设计来源: [Shape Up](https://basecamp.com/shapeup)（pitch + cycle 概念）

## 愿景

ccconfig 成为 Claude Code 配置管理的事实标准开源项目 — 任何新机器 10 分钟拉起，多设备配置一致，可被社区审查与贡献。

## 阶段总览

| 阶段 | 时间 | 主题 | 状态 | 详细计划 |
|---|---|---|---|---|
| Phase 0 | 2026-06 上 | 安全 + 公开化（.gitignore / ccprivate 拆分 / filter-repo / pre-commit）| ✅ 完成 | |
| Phase 1 | 2026-07 上 | 架构审核 + 三仓库文档补齐 + 产品化发布 | ✅ 完成 | |
| Phase 2 | 2026-07 中 | 文档/ADR + 简化发布模型（main 即 stable）+ Cloudflare Pages 产品站 | ✅ 完成 | |
| Phase 3 | 2026-07 下 | 架构重构 + 文件清理 + 文档更新 | 🔄 进行中 | |

## 当前状态

Phase 3 进行中 — 架构重构、文件清理、文档更新。进度见 git log。

## 关键决策

见 [docs/adr/](docs/adr/)。每个非可逆决策一条 MADR 4 字段 ADR（status / context / decision / consequences）。

## 关联 OKR（飞书 Base）

O.「ccconfig 正式化」
- KR1: Phase 0-3 全部完成（2026-07-31）
- KR2: 首次 v1.0.0 tag 发布 + CHANGELOG（2026-07-05）→ ✅ 完成
- KR3: GitHub ⭐ > 10（2026-09-30）

每次 ccconfig 工作 session 开头明示「关联 O.ccconfig-正式化/KR1」，hook 自动写 worklog 到飞书。

## 关键决策

见 [docs/adr/](docs/adr/)。
