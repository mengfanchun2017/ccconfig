# 0018. 权限模式策略 — defaultMode 用 auto，bypass 仅 flag 触发

> **Status**: ✅ Accepted
> **日期**: 2026-09-01
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

## Related

- settings.json `skipDangerousModePermissionPrompt: true` 配合 bypass flag 跳过启动确认提示，保留
