# 0023 — GitHub PAT 失效检测改为 on-failure-only

- **Status**: ✅ Accepted
- **Date**: 2026-09-02
- **Supersedes**: [0011](0011-git-auth-fine-grained-pat.md) 的 Layer 1 过期天数巡检部分

## Context and Problem Statement

[0011](0011-git-auth-fine-grained-pat.md) 建立了主动 PAT 过期巡检：monitor 每次 commit/push 后 curl `github-authentication-token-expiration` header、算剩余天数、写 `pat-warn` flag（<10 天 critical / <30 天 warn），status.sh 顶部读 flag 弹醒目横幅 + 现场倒计时天数。

问题：

- bootstrap 引导本身就推荐 `Expiration: No expiration`——无过期 token 占绝大多数，巡检永远输出"✅ classic PAT（无过期）"，是死代码噪声。
- fine-grained PAT 的 expiration header 对 No-expiration token 不返回，天数逻辑跑不到。
- GitHub 对设了过期的 token 会在到期前主动发邮件提醒，工具内倒计时冗余。
- 巡检在 monitor 主循环 + 每次 commit_and_push 末尾跑 curl，额外网络开销 + 6h cache 机制（73 行代码）维护成本高。
- 真正需要人工介入的唯一时机是 **push 失败（401/auth error）**——那时才提示续期即可。

## Decision

删主动过期天数巡检，改为 on-failure-only：

1. **bootstrap** 引导 `Expiration: No expiration（推荐；GitHub 过期前会邮件提醒）`。
2. **monitor.git_push** push 返回 401/bad credentials/auth error → `do_log` 续期命令（`bash ~/git/ccconfig/bin/refresh-gh-auth.sh`），不重试。其余网络错误仍走重试。
3. **status.sh check_pat_expiry** 简化为 `gh api user` 通→✅ 认证有效，不通→❌ + 续期命令。删 `check_pat_warn` 顶部横幅（flag 不再写）。
4. **refresh-gh-auth.sh** 保留为 on-demand 续期工具（`maintain.sh pat`），删天数倒计时显示，只报"认证有效/失效"。
5. 删 `check_pat_status` / `log_pat_warn` / `PAT_CACHE_FILE` / `PAT_WARN_FILE` / 6h cache。

## Consequences

- ✅ 删 ~110 行巡检代码 + cache 机制，monitor 主循环少一次 curl。
- ✅ 用户认知简化：PAT 只在"push 失败"或"`maintain.sh status` 显式查"时出现，无倒计时噪声。
- ✅ 与 `No expiration` 推荐配置自洽。
- ⚠️ 设了短期过期的 token 不再有工具内提前警告——但 GitHub 邮件提醒覆盖，且这不是推荐配置。
- ⚠️ `pat-warn` / `pat-status` flag 文件可能残留旧设计产物；refresh-gh-auth.sh 续期时 `rm -f` 清理。

## Related Decisions

- [0011](0011-git-auth-fine-grained-pat.md) — 原主动巡检设计，Layer 1 部分被本 ADR 取代
- [0001](0001-secret-strategy.md) — token 本地存储策略
