# 0036. 删除 Token 用量本地组件（option-usage / token-usage / bill）

> **Status**: ✅ Accepted
> **日期**: 2026-09-28
> **关联**: `ccconfig/option-usage/`（删除）、`ccprivate/usage/`（删除）、`lib/init-llm-bill.sh`（删除）、`maintain.sh token`、`init-option.sh usage`、`docs/adr/README.md`
> **模板**: MADR 4.0 极简版
> **取代**: [0009](0009-token-cost-reduction.md) 中关于本地 token 聚合的落地部分

## Context and Problem Statement

ccconfig 维护一套**本地 token 用量统计**链路：

- `option-usage/token-usage.sh` 解析 `~/.claude/projects/**/*.jsonl`，按 session/day 聚合 token
- 每日 systemd timer（`ccconfig-token-usage.timer`）归档到 `ccprivate/usage/YYYY-MM-DD.csv`
- `lib/init-llm-bill.sh` 读 CSV 出"按 model+day"账单视图
- 入口散在 `maintain.sh token`、`init-option.sh usage`、`init-llm.sh bill`、菜单 1C-1F

痛点：
1. **跨终端不同步**：`ccprivate/.gitignore` 忽略 `/usage/`，每台机器只写本地 CSV。
   新终端看不到其他终端的历史用量（用户检查时只有本机 2026-09-24 一个文件）。
2. **维护成本与价值不符**：脚本 + timer + 菜单 + 测试 + 配置多套联动，
   产出却是"本地自档的 CSV"，真正权威的用量在 **Claude 自带 usage 视图**（CLI 内直接看）。
3. **复杂度冗余**：`init-llm-bill.sh` 为读 CSV 还维护了模型发现三源，
   与上游账单口径脱节（自算 cost 已随 pricing 一并移除）。

## Decision Drivers

- **D1 单一真相源**：Claude 官方 usage 统计已覆盖"按模型/天/任务看量"的需求，不再自建第二套
- **D2 减维护面**：删掉 script + timer + 菜单入口 + 测试 + 配置，少 5+ 联动点
- **D3 诚实对待数据**：本地 CSV 不同步 = 数据不完整，继续维护是自欺

## Considered Options

1. **恢复同步**（去掉 `/usage/` .gitignore）— 每终端推 CSV，但同名 `<day>.csv`
   跨终端互相覆盖（后写者胜），同一天数据互相踩，违背汇总意图
2. **按主机分目录**（`usage/<hostname>/<day>.csv`）— 无冲突，但要改 `token-usage.sh`
   OUTPUT_DIR 派生 + 迁移旧数据，为"已被官方替换的功能"再投入
3. **删除整个功能**（采纳）— 回归 Claude 自带 usage 统计，删净本地链路

## Decision

**删除整个本地 token 用量链路**，改用 Claude 自带 usage 统计看用量。

删除清单：
- `ccconfig/option-usage/` 整个目录（token-usage.sh / init.sh / timer / service / README）
- `ccprivate/usage/`（已有 CSV 数据）
- `lib/init-llm-bill.sh` 及 `init-llm.sh bill` 子命令、菜单 2B
- `maintain.sh token` 子命令、`menu-data-maintain.sh` 1C-1F 菜单项
- `init-option.sh` 中 `usage` 安装入口 / 状态行
- `conf/token-usage.json`、`conf/token-usage.json.example`
- `tests/test-token-usage.sh`
- 相关 README / docs 引用

## Consequences

- ✅ 维护面收敛：少掉一组脚本 + timer + 跨 4 文件菜单入口
- ✅ 用量数据不再有"本地假完整"的误导；跨终端看用量走 Claude 官方视图
- ❌ 损失"按 model 精确聚合每日 token"的自定义视角（官方 usage 粒度略粗）
- ⚠️ 若后续确需跨终端统一账目，重新评估"按主机分目录同步"方案；
  本次删除不阻碍未来重建（数据源 jsonl 始终在本地）

## Implementation

- 执行于 2026-09-28，涉及 ccconfig + ccprivate 两仓库
- 保留：`docs/adr/0009`、`docs/updates/20260919-bootstrap-review-and-config-layering.md`、
  `ccprivate/link/memory/menu-select-cancel-contract-20260831.md` 中的历史引用——它们是
  "当时决策/修 bug"的历史记录，删除功能不影响历史事实

## Related Decisions

- [0009](0009-token-cost-reduction.md) — 早期 baseline 优化（cache/ignore/compact），
  本地聚合部分由此 ADR 取代
- ADR README「决策时间线」本应同步——时间线已滞后（停在 2026-07-29），
  本次决策记录在索引，不回填滞后段

## Notes

- 用户改用 Claude 自带 usage 统计（CLI 内查看），原始 jsonl 仍在
  `~/.claude/projects/`，需要时随时可重新导出