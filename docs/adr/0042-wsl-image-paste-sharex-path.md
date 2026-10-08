# 0042. WSL 下 Claude Code 图像粘贴方案 — ShareX「复制文件路径」规避 WSLg BMP 解码坑

> **Status**: ✅ Accepted
> **日期**: 2026-10-08
> **关联**: Claude Code（WSL2 + Windows Terminal）；ShareX；WSLg
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

Claude Code 在 WSL2 + Windows Terminal 下无法直接 `Ctrl+V` 粘贴截图（ShareX / Win+Shift+S）到输入框。层层分析后，失败是两个独立坑叠加：

1. **坑 A（终端拦截）**：Windows Terminal 默认把 `Ctrl+V` 绑定为「粘贴文本」。剪贴板里是图像无文本，按键被终端消费，Claude Code 根本收不到。官方文档已说明 Windows/WSL 用 **`Alt+V`** 绕开。
2. **坑 B（WSLg 剪贴板桥）**：即使按键到达（Alt+V），WSLg 把 Windows 剪贴板图像**只**暴露为 `image/bmp`（且是 `BI_BITFIELDS` 压缩格式，Windows 截图工具产物）。Claude Code 的 BMP→PNG 转换链在此格式上静默失败，无论装不装 wl-clipboard/xclip，都报假阴性 **"No image found in clipboard"**。

ShareX 实测：截屏后 `Alt+V` 直接报 "no image"（卡在坑 B），`Ctrl+V` 同样。此问题上游多期未修（issue #50552 / #61609 / #89223，2026-04 至 08 仍在复现）。

## Decision Drivers

- **D1 避免 BMP 解码**：绕开 WSLg 的 `image/bmp` 链路，让剪贴板里不放图像数据
- **D2 零劫持**：不做 PATH 里拦截 `wl-paste` 的 hack（影响系统全局，需装 wl-clipboard + ImageMagick）
- **D3 零终端改**：不解绑 Windows Terminal 的 `Ctrl+V`（改全局终端行为，影响所有前台程序）
- **D4 链路最稳**：选「剪贴板 = 文件路径文本」这条路，纯文本在 WSL 零损耗，Claude Code 的 `@路径` 附件机制天然支持 `.png` 文件路径粘贴

## Considered Options

1. **方案 A: `Alt+V`** — 官方推荐。Pros: 一键。Cons: 只解决坑 A；坑 B 下报 "no image"，ShareX 实测已否决
2. **方案 B: 解绑终端 Ctrl+V**（`"command":"unbound"`）— Pros: 让按键穿透。Cons: 改全局终端行为，vim/bash 里 Ctrl+V 语义变；且只解决坑 A，坑 B 依旧，对 ShareX 场景无用
3. **方案 C: wl-paste 包装转换**（假 `wl-paste` 拦截 `--type image/png`，用 ImageMagick 现场转 BMP→PNG）— Pros: 原生粘贴体验。Cons: 劫持系统全部 wl-paste 调用、装依赖、维护 PATH hack，脏且脆
4. **方案 D: ShareX「复制文件路径到剪贴板」（选定）** — Pros: 存 PNG 文件 + 剪贴板放路径文本，纯文本链路零坑；`@/mnt/c/.../xxx.png` 直接挂附件；ShareX 全 GUI 配置无脚本。Cons: 粘后需手动把 Windows 路径 `C:\...` 转成 WSL 路径 `/mnt/c/...`，多一步

## Decision

选 **方案 D**：ShareX 截图后同时「保存图像到文件」+「复制文件路径到剪贴板」，并关闭「复制图像到剪贴板」。回到 Claude Code 输入框 `Ctrl+V` 得到路径文本，把 `C:\` 前缀改成 `/mnt/c/` 后加 `@` 前缀（`@/mnt/c/.../xxx.png`）作为附件挂载。

**ShareX 配置**（任务设置 → 捕获后任务）：勾 ✓ 保存图像到文件、✓ 复制文件路径到剪贴板、✗ 取消复制图像到剪贴板。

## Consequences

- ✅ 彻底绕开坑 A + 坑 B，不依赖上游修 `BI_BITFIELDS` 解码
- ✅ 全 GUI 配置，无脚本、无 PATH hack、无系统行为改动
- ✅ 存盘即留档，截图天然有文件可回溯
- ❌ 每次粘贴需手动改路径前缀（Windows → `/mnt/c`）
- ⚠️ 若嫌手动麻烦，后续可加个小壳：监听剪贴板路径文本→自动输出 WSL 路径（见 ADR Notes）；或等上游真修好 `BI_BITFIELDS` 后回到原生 `Ctrl+V`

## Implementation

- ShareX 任务设置 GUI，无代码改动

## Related Decisions

- （无既有 ADR 直接相关；`0038` Playwright MCP 属浏览器自动化，非同领域）

## Notes

- 上游 bug 线索：issue #50552（BI_BITFIELDS BMP 解码失败，closed not_planned）、#61609、#89223
- 备选再进一步：`clipaste`（hqhq1025）类工具可做剪贴板 watcher 全自动，但引入后台守护依赖，优先级低