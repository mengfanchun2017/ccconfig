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

## 实施经验（2026-08-10 收尾）

迁移过程中踩到的 4 个核心坑，作为后续维护者参考。详见 memory `menu-migration-pitfalls-20260810`。

1. **menu_select 显示走 stderr**：items 文本若走 stdout 会被 `c=$(menu_select ...)` 命令替换整个截走，菜单列表不显示。修正：所有 `echo ""` / `section` / `printf "  %2d) ..."` 都加 `>&2`，只把选中序号 echo 到 stdout。
2. **read -p 必须从 /dev/tty 读**：stdin 是管道时 read 阻塞/EOF 失败，set -e 让脚本整个退出。修正：`if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then read -p "..." < /dev/tty || var=""; fi`，否则走 fallback。
3. **while+case 不能用 `*) continue` 重入菜单**：每次循环重入会重新打印完整列表 + case 上下文丢失。修正：去掉 `while true`，子菜单拆成独立函数；「返回」项 case 用 `${#items[@]}) return 0 ;;`。
4. **interact.sh 不依赖外部 menu_num**：maintain.sh 用了 inline colors fallback 但没 inline menu_num，导致 menu_select 崩。修正：interact.sh 内联 `[[ "$sel" =~ ^[0-9]+$ ]]`，删 colors.sh 的 menu_num。

API 决策补充：
- **items 传纯文本**（不带数字），函数内部加 "1) 2) 3)"。比 items 带数字重复（"1) 状态检查" 显示成 "1) 1) 状态检查"）更干净。
- **返回选中序号**（"5"）而非文本（"组件升级"），让 caller `case "$c" in 1) ... ;; 5) ... ;; esac` 直接用，省一层文本→数字解析。
- **「返回」项必须在 items 末尾**，caller 用动态 `${#items[@]} + N` 算 case 分支。**不要混用 0 + 字母**（a/k/l/n/r/d）+ 数字序号，混乱必出 bug。

## P0 教训：Edit replace 后必跑 bash -n（2026-08-10 review 发现）

review 时发现 `init-ccprivate-repo.sh` collect_info 重构中三处 case 分支首行被合并：
```bash
# 错（Edit 后实际写入）
[ -z "$DEEPSEEK_KEY" ]                 DEFAULT_LLM="deepseek"                DEFAULT_LLM="deepseek" DEEPSEEK_KEY=$(prompt_password ...)
```
运行时报 `[: missing ']'`——bash `-n` 不报（语法合法），但语义崩溃。

**根因**：Edit tool replace 时 old/new 字符串包含换行，user/repo 文件实际存的是单行含大量空格的合并结果。

**预防**：
1. 每次 Edit 后立即 `bash -n <file>` 跑语法检查（语法能过但语义仍可能崩，所以**还要读文件确认**）
2. 涉及多行替换时，优先用 Read 看当前实际内容再 Edit，不要凭记忆里的"应该是几行"
3. 测试覆盖：每个改动文件跑一遍 `tests/test-syntax.sh`（58 个 sh 全检，0.3s）

**已修**：详见 commit `init-ccprivate-repo.sh` 三 case 分支行合并 bug修复 + tests/test-interact.sh 新增 EOF/OOR/双前缀回归用例。

## Related

- [colors.sh](../lib/colors.sh)
- [interact.sh](../lib/interact.sh)
- [CLAUDE.md](../../CLAUDE.md) — SH 交互规范段