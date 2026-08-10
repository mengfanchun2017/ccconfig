# 0012. SH 交互规范化：lib/interact.sh P0 + 弃用 gum

> **Status**: ✅ Accepted
> **日期**: 2026-08-10
> **关联**: `lib/colors.sh`、`lib/interact.sh`、`lib/dry-run.sh`、全部 `*.sh`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

ccconfig 60+ 个 sh 脚本存在风格不统一的问题：21 个脚本自行定义颜色变量（RED/GREEN 等），12 个脚本手写 read -p + while 循环的菜单。调研了 gum/charmbracelet，发现 gum 版本 API 不兼容、需要外部安装、全屏刷新与 inline 日志风格冲突。

## Decision

1. **弃用 gum**：interact.sh 移除 gum 检测和 fallback，只保留纯 sh 实现
2. **lib/interact.sh 定位**：纯 sh 函数库，零依赖
3. **分 3 阶段迁移**：Phase 1 清理颜色变量 -> Phase 2 菜单迁移 -> Phase 3 maintain.sh 改造
4. **颜色入口唯一**：所有脚本统一 source colors.sh

## Decision Drivers

- 零外部依赖：ccconfig 自身不应引入运行时依赖
- 迁移风险：脚本多是初始化/运维关键路径
- 逐步可验收：每阶段独立可测试

## Considered Options

| 选项 | 结论 |
|------|------|
| gum 原生 | ❌ 拒绝 |
| interact.sh + gum fallback | ❌ 拒绝（维护两套实现）|
| interact.sh 纯 sh | ✅ 采纳 |
| 纯 sh 手写 | ❌ 拒绝（风格继续散乱）|

## Consequences

- 好：所有交互行为可预测、零依赖
- 好：新脚本 source interact.sh 即可
- 好：Phase 1 零风险
- 差：无 fuzzy search / spinner / 进度条
- 差：demo-inter.sh / demo-gum.sh / maintain-gum.sh 成为垃圾文件待清理

## Related

- [colors.sh](../lib/colors.sh)
- [interact.sh](../lib/interact.sh)
- [CLAUDE.md](../../CLAUDE.md) — SH 交互规范段