# ccconfig 技术决策记录

> 从 Worklog 自动提取。每次 worklog 触发后更新。
> 数据来源: Worklog Base（配置见 `conf/f-logme.json`）

## 2026-06-15 | ccconfig 开源安全加固 | [recvmBdslqi2Mr]

**决策**: 所有隐私数据统一存放 ccprivate，ccconfig 通过 symlink 引用；git filter-repo 清洗历史
**影响**: 26 文件修改，1504 commits 重写，仓库可随时改公开
**关联**: hooks/session-end-aggregator.sh + merge_worklog.py 改为读 conf/*.json；f-doc/config.yaml 改为 symlink；新增 SECURITY.md

## 2026-06-14 | Vessel → Playwright 全线迁移

**决策**: 全线移除 Vessel，统一使用 Playwright（MCP + Python 脚本）
**影响**: 删 option-vessel/、bin/vessel-*、f-vessel skill、systemd vessel.service
**量化**: 删 1183 行 / 改 23 文件
**关联 ADR**: 项目 ADR 0016

## 2026-06-13 | ADR 0016 浏览器测试工具选型 | [recvmsOk3JFBfw]

**决策**: Playwright MCP 做主站（无障碍树 ~800 tokens/页），Vessel 保留给 Admin
**后续**: 2026-06-14 Vessel 也废弃，全线 Playwright
**关联文档**: 项目 docs/adr/0016-browser-testing-tool-selection.md

## 2026-06-13 | webapp-testing 移至用户级 skill | [recvmsYlrlKyxq]

**决策**: webapp-testing skill 从 ccconfig link/skills/ 移至用户级 ~/.claude/skills/
**原因**: 可被所有项目复用，不依赖 ccconfig 同步链路

## 2026-06-12 | session-end hook auto dedup + KR routing | [recvmpBHK85lUm]

**决策**: SessionEnd hook 自动去重（同 session 同主题合并）+ 智能 KR 路由
**影响**: worklog 自动写入更精准，减少重复记录

## 2026-06-12 | 移除 worklog 硬编码 KR_AUTO | [recvmpkqfTMwwD]

**决策**: 删除 worklog 自动写入时的硬编码 KR fallback，改为从 SessionEnd hook 智能路由
**原因**: 硬编码导致所有 auto 记录归到同一 KR，失去分类意义

## 2026-06-12 | fix: monitor 空变更输出 already up to date | [recvmpTLzaTc20]

**决策**: monitor.sh `git add -A` 后若无 diff，输出 "already up to date" 而非静默
**影响**: 减少 "unstaged changes" 导致的 pull --rebase 阻塞

## 2026-06-12 | 清理 context 占用 | [recvmp8H5K9Uzk]

**决策**: feishu-cli-cheatsheet 从 525 行瘦身到 77 行（85%）；移除 4 个 skill 专属文件
**原因**: 节省 ~4500 token context budget

## 2026-06-11 | f-ship (现 f-launch) 脚手架工具 | [recvmhFSra0CMr]

**决策**: 建立项目启动 skill，8 类项目模板
**关联**: f-launch SKILL.md

## 2026-06-11 | cc 全量清理 | [recvmjG0Wvnil8]

**决策**: 移除 ccconfig 中的 token、5 junk dir、6 loose file、papermaster
**量化**: 3 commits + 删 ~80MB

## 2026-06-10 | okr-worklog 成长系统框架 | [recvmeKf82FXWx]

**决策**: OKR + Worklog + Reflect 三层框架，PARA 方法融合 KR.PARA 字段
**关联**: f-logme skill / OKR Base v2

## 2026-06-07 | ccconfig docs 框架：4层追踪

**决策**: L1/L0 仓库 + L2/L3/L4 飞书 Base + ADR 决策层
**决策方法**: MADR (Markdown Architecture Decision Records)

## 2026-06-05 | ccconfig skill marketplace 重构 | [recvlJxGbGN85g]

**决策**: skills 双轨管理：ccconfig 工作副本 + claude-skills marketplace + sync 一体化
**关联**: setup-links.sh / publish.sh

## 2026-06-05 | f-skill 三层架构重组 | [recvlJKEDfyZFg]

**决策**: Layer 1 输出平台 / Layer 2 知识生产 / Layer 3 个人工作流
**影响**: f-search 抽出搜索原语、f-research→f-research-domain 瘦身、f-report-gen 替换 f-research-report

## 2026-06-03 | skill 产品化 Phase 0 | [recvlxho2A7sXO]

**决策**: 6 skill 审计 + Webify/marketplace 技术决策落地
**量化**: 1 决策文档(367行) + 1 废弃 skill 清理

## 2026-06-03 | 报告写作全链路升级 | [recvlxvt5gXiID]

**决策**: f-report-std 创建 + 3 模式 + 图子文档
**量化**: 12 文件 +689 行

---

## 更新机制

每次 f-logme worklog 触发时：
1. 搜索 worklog 中 ccconfig 相关记录（标题/说明含 ccconfig|skill|hook|init|mcp|monitor|sync|config|rules 关键词）
2. 识别技术决策类记录（含 修复|迁移|清理|框架|重构|决策|移除|统一|废弃|fix|feat|refactor|chore）
3. 提取标题、record_id、决策要点 → 写入本文件
4. Commit 到 ccconfig repo
