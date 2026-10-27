# docs/updates/ — 变更流日志索引

> 每次大改动一篇 `YYYYMMDD-主要内容.md`。**新增文件必须在此登记**，否则从索引不可达 = 等于没写。
> 日志记录「为什么改」，不是「改了什么」——改了什么看 git 历史。

| 日期 | 文件 | 内容 |
|------|------|------|
| 2026-09-19 | [bootstrap review 与配置分层](20260919-bootstrap-review-and-config-layering.md) | P0 保密脱敏、CI 补测试、文档路径修正、配置三层分层 |
| 2026-09-20 | [auto-sync 独占提交权](20260920-autosync-owns-commits.md) | **session 不 commit/push 的决策归因**（起因/代价/补偿措施）；规则本身见 `CLAUDE.md`「版本管理」段 |
| 2026-09-20 | [init 安装恢复可靠性](20260920-init-install-restore-reliability.md) | init 安装/恢复流程的可靠性修复 |
| 2026-09-20 | [maintain 扁平菜单](20260920-maintain-flat-menu.md) | maintain 菜单扁平化重构 |
| 2026-09-20 | [状态域恢复分类](20260920-status-restore-category.md) | 「状态」域重构 + 一键恢复。⚠️ 菜单编号已被 [20261018 菜单重构](20261018-menu-restructure.md) 推翻，保留作设计记录 |
| 2026-09-20 | [移除 ccbridge 菜单项](20260920-drop-ccbridge-menu-entries.md) | 删 `lib/menu-feishu.sh`，ccbridge 转独立仓 |
| 2026-10-18 | [菜单重构](20261018-menu-restructure.md) | 6 域 31 项的新菜单结构（取代 20260920 的编号） |
| 2026-10-27 | [新增 option-botmux](20261027-add-option-botmux.md) | 飞书 ↔ AI 编程 CLI 桥接入；弃用 ccbridge（上游停更 2 月、272 open issues），ccbridge 仓保留作参考 |
