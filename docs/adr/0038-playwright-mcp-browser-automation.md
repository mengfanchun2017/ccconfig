# 0038. Playwright MCP 浏览器自动化（WSL 落地）

> **Status**: ✅ Accepted
> **日期**: 2026-10-03
> **关联**: `option-playwright/init.sh`, `conf/mcp-servers.json.example`, `ccprivate/conf/mcp-servers.json`, 飞书文档「通道选型 — AI 浏览器自动化调研（meshwork）」
> **模板**: MADR 4.0 极简版
> **相关选型**: [[ai-browser-use-selection-20261101]]

## Context and Problem Statement

Claude Code 需要浏览器控制能力：fmashwork 图生 3D 走网页通道、抓取个人数据（如 bilibili 观看历史）。选什么工具、如何在 Win11 + WSL2 环境落地，需要确定性结论。

选型已定：**Playwright MCP**（微软维护，36K★，接入 Claude Code 的 stdio MCP，把浏览器手交给现有 agent）。本 ADR 记录**落地决策**，不重复选型对比。

## Decision Drivers

- **D1 最小侵入**：不引入第二个规划循环（agent 框架），用 MCP 直接给现 agent 加能力
- **D2 WSL 环境**：WSL2 无 DISPLAY GUI（除 WSLg）、系统 .so 库缺失、微软 CDN 下载慢
- **D3 升级不破**：chromium 版本升级不能导致 MCP 配置失效
- **D4 登录态复用**：headless 自动化需要登录态，不能每次重新登录

## Considered Options

1. **MCP 默认参数（`--browser chromium`）** — 官方帮助推荐，但语义歧义
2. **MCP `--executable-path` 直指二进制** — 显式、确定
3. **CDP 桥接 Windows Chrome** — 复用 Windows 登录态，但 NAT/端口转发复杂、低保真

## Decision

**① `--executable-path` 显式指稳定 symlink，不用 `--browser chromium`**

- `@playwright/mcp` 的 `--browser` 参数帮助写「browser or chrome channel」，实测 `--browser chromium` 仍找 `/opt/google/chrome/chrome`（chrome channel），必须 `--executable-path` 直指 playwright 自装二进制
- symlink `~/.local/state/pw-chromium/chrome` → 当前 chromium 二进制，由 `option-playwright/init.sh` 的 `refresh_chromium_symlink()` 每次 install/update 后重建
- MCP args 里 `--executable-path <symlink>` 永不改 → chromium 升级（1243→1244）不破 MCP

**② 登录态：headed 一次性登录 + 持久 profile**

- MCP 用 `--headless` + `--user-data-dir ~/.cache/pw-bilibili-profile`
- 登录：`launchPersistentContext(profile, {headless:false, executablePath, args:['--no-sandbox']})` 开 headed 窗口（WSLg 弹 Windows 桌面），扫码/密码+手机验证，SESSDATA cookie 存 profile
- 判定登录成功：`b.cookies()` 出现 `SESSDATA`（不能靠 URL 离开 login —— 会跳到 riskVerify 页未完成）

**③ WSL 安装走镜像 + `--executable-path` 解耦版本**

- chromium 下载：`PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright/` 绕过微软 CDN 卡死
- 系统 .so：`sudo env "PATH=$PATH" npx --yes playwright install-deps chromium`（唯一 sudo 步；npx 在 user-local 路径，sudo 需显式传 PATH）
- 全部封装进 `option-playwright/init.sh`（--status/--install/--update），注册进 `init-option.sh` 菜单「--浏览器自动化--」组

## Consequences

- ✅ 浏览器能力随 ccconfig pull 自动出现（`option-playwright/` + 菜单项已入库）
- ✅ chromium 升级只需 `--update`，MCP 不破（symlink 重建）
- ✅ 登录一次永久复用（持久 profile），headless 自动化直接带登录态
- ❌ chromium 二进制大（~660MB），缓存在 `~/.cache/ms-playwright`；symlink 硬编码在 MCP args，删除用户目录会断
- ⚠️ `--executable-path` 需要 playwright 已下载 chromium；新机器先跑 `init.sh --install`
- ⚠️ 持久 profile 是单例锁：headed 登录窗口与 headless MCP 不能同时开同一 profile（`SingletonLock`，残留锁需 `rm profile/Singleton*`）

## Implementation

- `option-playwright/init.sh`：4 层检查（npx → chromium → .so → MCP 注册）+ 镜像下载 + symlink 维护
- `conf/mcp-servers.json.example`：playwright 条目（`--executable-path` + `--user-data-dir`）
- `ccprivate/conf/mcp-servers.json`：真实注册（同模板，真实路径）
- `init-option.sh`：菜单组「--浏览器自动化--|playwright」

## Related Decisions

- 选型对比见飞书文档「通道选型 — AI 浏览器自动化调研（meshwork）」
- 图生 3D 落地：`fmashwork` skill 依赖此浏览通道

## Notes

- 抓 bilibili 观看历史：网页 `bilibili.com/account/history`（302 → `/history`），waitForTimeout 等 JS 渲染后 `textContent` 解析最稳；API `/x/web-interface/history` 参数易 404
- chromium 版本查询：`npx playwright install --dry-run` 显示正确 build 号