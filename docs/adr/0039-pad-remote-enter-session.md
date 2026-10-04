# 0039. iPad/平板远程进入指定 session：用 /exit 回 fleet view + 手动点击，不用 ←

> **Status**: ✅ Accepted
> **日期**: 2026-10-04
> **关联**: `option-remote`, `docs/adr/0008-remote-connection.md`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

从 iPad/平板（Termius）经 Tailscale SSH 远程进入 WSL 的 Claude Code。当前会话切到 fleet/agent view 想进入另一个 session，按 `←` 方向键不生效 —— Termius 后退键行为异常，`←` 的切换有前置门槛，导致无法从当前 session 回到 session 列表。

需要一条在移动端可靠、不用方向键的「回 fleet view → 进特定 session」路径。

## Decision Drivers

- **D1 移动端无物理方向键或方向键序列不稳定**：Termius 后退键不标准，`←` 无法触发 Claude Code 的 view 切换
- **D2 Claude Code 的 `←` 切 view 有前置条件**：仅在输入框为空时触发；v2.1.218+ 误触保护要求删除/历史操作后隔 2s 二次确认
- **D3 目标**：跨设备一致的进入指定 session 方式，不依赖特定终端键

## Considered Options

1. **`←` 切 view** — 触发的官方键，但移动端序列不稳定 + 空框/防误触前置，实测失败
2. **`/exit` 退出当前会话回 fleet view + 手动点击/回车进入目标 session** — 全文本命令 + 点击，无方向键依赖，跨终端一致
3. **`claude agents` 另开视图** — 等效于 fleet view，但仍在同一 SSH 会话内叠加，多一层状态

## Decision

**移动端进入指定 session 的统一路径：`/exit` 退出当前会话回到 fleet view，再手动点击目标 session 进入。** 不用 `←`。

- `/exit` 是 Claude Code 内置命令，退出当前 session 返回 view 层面，任何终端（含 Termius 软键盘）都能输入
- fleet view 里用点击/Up-Down+Enter 选择目标 session，避开移动端方向键与 `←` 切换的不兼容

## Consequences

- ✅ 不依赖方向键，pad/平板 Termius 可用
- ✅ `/exit` 语义直观：退出 = 回列表，符合直觉
- ⚠️ `←` 仍保留作桌面端便捷路径；移动端视为不可靠不采用

## Related Decisions

- `ADR-0008`（`0008-remote-connection.md`）— Remote 远程连接方案，SSH/Tailscale 链路

## Notes

- Termius 移动端方向键可经由 extended keyboard / 长按拖动模拟，但 `←` 切换 view 的触发门槛（空输入框 + 防误触）在实际使用中仍是主要障碍