# 0018. 权限模式策略 — defaultMode 用 auto，bypass 仅 flag 触发

> **Status**: ⚠️ Superseded（模式选择部分）by [0049](./0049-auto-mode-discards-allow-rules.md)
> **日期**: 2026-09-01
> **注**: 本 ADR 的「日常用 auto」结论**已被推翻** —— 实测 auto 模式主动丢弃 `Bash(*)` 等宽泛
> allow 规则，一切命令送分类器被拦。2026-10-16 由 [0049](./0049-auto-mode-discards-allow-rules.md)
> 改为 `bypassPermissions` + 补全 allowlist（`templates/settings.json.example` 已按新结论落盘）。
> 本 ADR 保留：权限模式分层思路、为什么不能「配了就算」的分析仍成立。
> **模板**: MADR 4.0 极简版
> **目的**: 纠正 settings.json `defaultMode: bypassPermissions` 无效配置，确立日常用 auto、bypass 按需 flag 启用的策略

## Context and Problem Statement

settings.json 里设了 `"permissions.defaultMode": "bypassPermissions"`，但实际行为：

- **启动时被忽略并降级到 default**。Claude Code 2.1.236 二进制字符串证据：
  ```
  setMode:'bypassPermissions' is session-scoped; not persisting as defaultMode to
  [externalMetadataToAppState] Refusing restored mode 'bypassPermissions'
  (disabled by settings/policy or session not launched with --dangerously-skip-permissions);
  falling back to 'default'
  ```
  即 bypassPermissions 是 **session 级**，不允许通过 settings.json 持久化为默认模式。
- **Shift+Tab 循环里不显示 bypass 选项**。循环序列为 `default → acceptEdits → plan → bypassPermissions → auto → default`，其中 `bypassPermissions` 和 `auto` 仅在该 session 可用时才出现。bypassPermissions 可用的前提是启动带了 flag。
- **background job / 子 session 声明 bypassPermissions 会被拒**，保持父模式。

导致用户在新终端直接 `claude` 启动时，既没进入 bypass，Shift+Tab 也切不出 bypass。

## Decision Drivers

- 核心工具已全 allow（`Bash(*)` + `Edit/Write/Read/Glob/Grep` 全开），日常零打扰
- 保留 deny 名单 + hooks 安全网
- 不依赖无效配置

## Considered Options

### A — defaultMode 保持 bypassPermissions（原配置，无效）

**优点**：意图是"啥都不问"。**缺点**：被 Claude Code 忽略降级，实际不生效，误导。

### B — defaultMode 改 default（manual）

已 allow 的放行，未 allow 的弹提示。**优点**：安全网最全。**缺点**：遇到未列的新工具/MCP 会弹提示，单人 WSL 偶尔烦。

### C — defaultMode 改 auto（选定）

未 allow 的也自动放行，但仍尊重 deny 名单 + hooks。

**优点**：
- ✅ 体感≈bypass（未设 deny 名单），日常完全无打扰
- ✅ 保留 deny 管道，未来想拦某操作可加 deny 规则仍生效
- ✅ hooks 仍生效（bypass 会绕过部分 hooks）
- ✅ 是合法可持久化的 defaultMode 值

**缺点**：
- ⚠️ 遇到未 allow 的新工具自动放行，不像 default 会提示确认（单人环境可接受）

## Decision

选 C。settings.json `defaultMode` 改为 `auto`。

**后续不再特别启用 bypass**——auto 已满足"无打扰"需求，且保留安全网。bypass 仅在明确需要跳过 deny/hooks 时按需 flag 启用。

## 如何进入 bypass 模式（按需）

bypassPermissions 不能通过 settings.json 启用，只能命令行 flag：

```bash
# 启动直接进 bypass（跳过所有权限检查，含 deny + 部分 hooks）
claude --dangerously-skip-permissions

# 让 bypass 出现在 Shift+Tab 循环里，手动切（不自动启用）
claude --allow-dangerously-skip-permissions
```

`--permission-mode` 也可指定任意模式，合法值：`acceptEdits` / `auto` / `bypassPermissions` / `manual` / `dontAsk` / `plan`。

> ⚠️ background job / 子 session 即使声明 bypassPermissions，若父 session 不在隔离无网络环境也会被拒、保持父模式。bypass 仅适合可信环境的无人值守场景。

## 模式对比

| 模式 | 已 allow | 未 allow | deny 名单 | hooks | 适合 |
|------|---------|---------|----------|-------|------|
| default(manual) | 放行 | 弹提示 | 拦截 | 生效 | 想要新工具提示 |
| **auto** | 放行 | 自动放行 | 拦截 | 生效 | **日常主力** |
| acceptEdits | 放行 | 编辑自动通过，其他弹提示 | 拦截 | 生效 | 纯写代码 |
| plan | 禁止写/执行 | — | — | — | 规划探索 |
| bypassPermissions | 放行 | 放行 | **忽略** | 部分绕过 | 无人值守 |

## Consequences

### Positive

- ✅ 清掉无效配置，defaultMode 真正生效
- ✅ 日常零打扰（auto + 全 allow）
- ✅ 保留 deny/hooks 安全网，未来可加规则
- ✅ ADR 记录 bypass flag 用法，后续需要时可查

### Negative / Risks

- ⚠️ auto 对未列新工具自动放行，失去确认时机（单人 WSL 可接受）
- ⚠️ bypass 仍可用于无人值守，需自觉只在可信环境用

## 附：auto 模式的分类器有独立模型变量（2026-10-14 补）

auto 模式不是纯放行 —— 它对每条命令调一个**分类器模型**判安全：判安全自动过，判不了（超时/报错/响应不兼容）→ **fail-closed 拦截**。分类器模型**不读 `ANTHROPIC_DEFAULT_HAIKU_MODEL`**（haiku 变量只管后台小任务：生成标题、路径补全等），由独立变量控制：

| 变量 | 作用 |
|------|------|
| `CLAUDE_CODE_AUTO_MODE_MODEL` | auto 权限模式分类器模型 |
| `CLAUDE_CODE_BG_CLASSIFIER_MODEL` | 后台分类器模型 |

**外部 LLM + 自建 bridge 场景的坑**：分类器默认走 Anthropic 服务端分类器（模型 `claude-sonnet-5`）。`ANTHROPIC_BASE_URL` 指向 bridge 时，`claude-sonnet-5` 被透传到上游 → 上游无此模型 → 报错 → fail-closed **拦一切命令**（含只读 grep）。症状：`Auto mode could not evaluate this action and is blocking it for safety`。

**修**：`init-llm.sh` 的 `write_llm_config` 切 preset 时一并写 `CLAUDE_CODE_AUTO_MODE_MODEL`（值取 `small_model`，缺省回退主模型），分类器改用真实可用的外部模型名。

**二进制证据（2.1.287）**：
- 模式排序常量 `acceptEdits:1, plan:2, auto:3, bypassPermissions:4`
- 决策函数 `Mbt(e){if(e==="auto")return"classify"; if(e==="bypassPermissions")return"allow"; ...}`
- 分类器日志 `Auto mode classifier: skipping server-configured classifier model`
- bypass 标注 `(bypasses classifier)` / 字段 `classifierRouted:false`

即 **bypass 直接 allow、完全跳过分类器**；只有 auto 走 classify。这也是日常用 `claudeby`（bypass）可完全绕开此问题的原因。

## Related

- settings.json `skipDangerousModePermissionPrompt: true` 配合 bypass flag 跳过启动确认提示，保留
- memory `auto-mode-classifier-model-20261014`（分类器模型变量与本修法）
- `claudeby` alias（`~/.claude/shell_init.sh`）：`claude agents --dangerously-skip-permissions`（2026-10-15 起直进 FleetView，bypass 作 dispatch default，派发 session 启动即 bypass；旧版 `claude --dangerously-skip-permissions` 不给子 session 传 flag，输入文字后回落 auto），日常绕过分类器抖动；维护入口 `./maintain.sh 1C`
