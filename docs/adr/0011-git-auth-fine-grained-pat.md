# 0011. GitHub git 认证统一为 fine-grained PAT + HTTPS

> **Status**: ✅ Accepted
> **日期**: 2026-08-09
> **关联**: `bootstrap-gh-auth.sh`、`init-ccprivate-repo.sh`、`init-ubuntu.sh`、`lib/monitor.sh`、`lib/status.sh`、`bin/refresh-gh-auth.sh`、`BOOTSTRAP.md`；ccprivate `rules/git.md`；`~/.gitconfig`
> **模板**: MADR 4.0 极简版
> **备注**: 见 [[0001-secret-strategy]](0001-secret-strategy.md)（token 存储策略）。

## Context and Problem Statement

SSH push 失败后调研 GitHub 认证路径。原方案 classc PAT `repo` scope 权限过大（等同所有私有仓全权，泄露影响面广）；`gh auth` 让用户选 A/B 交互散乱；仓库创建与 push 的权限需求未分离；90 天强制轮换无到期感知。

## Decision Drivers

- **D1 最小权限**：push/clone 仅需 Contents `Read and write` + Metadata `Read-only`，Account 权限全 No access
- **D2 建仓手动**：fine-grained PAT 无 `repo create` 能力，仓库由用户在 GitHub 页面手动建，init 脚本引导
- **D3 本地存储**：token 仅存本地 `~/.config/gh/hosts.yml`（600 权限），不加密不进 ccprivate 同步
- **D4 到期可感知**：90 天强制轮换，到期前 30 天可 Regenerate 继承权限；三层检测不遗漏
- **D5 代理依赖**：大陆网络 `github.com` SNI 被 GFW 阻断（TCP 通、TLS ClientHello 被丢包），push 需走本机 Clash `127.0.0.1:7897`

## Considered Options

### Option A: classic PAT `repo` scope — 拒绝

- `repo` scope 等同所有私有仓库全权（含 admin 读写），泄露影响面最大。
- 保留 `repo create` 能力，但建仓已改手动（Option D 下 init 引导 deep link），无此需要。
- 无到期（No-Expiration）→ 无法强制轮换。

### Option B: Web OAuth — 备选

- 首次配置最简单，浏览器授权。
- token 有 TTL，过期需重新 `gh auth login`，跨机器每台独立。
- 非交互场景（CI）不可用。

### Option C: SSH key — 降级为可选

- push 走 `github.com:22` / `ssh.github.com:443`，同样面临被墙风险，无代理时同样失败。
- 当前 HTTPS + 代理已全链路验证通，SSH 仅作加速可选（`SETUP_SSH=1` 强制配）。
- 不依赖 `gh auth`，保留作为 git push 不依赖 gh token 的兜底。

### Option D: fine-grained PAT + HTTPS — 采纳

- 最小权限、可设 90 天到期、泄露影响单仓范围。
- `github_pat_` 前缀 + `github-authentication-token-expiration` 响应头 → 到期检测可行。

## Decision

**采纳 Option D**，git 认证统一走 fine-grained PAT + HTTPS + gh credential helper：

1. **PAT 配置**（bootstrap-gh-auth.sh）：Token name `ccconfig-push`，Expiration 90 days，Repository access `All repositories`，Contents `Read and write` + Metadata `Read-only`，Account 全 No access。
2. **建仓手动**：init-ccprivate-repo.sh 删除 `gh repo create`，改为 `github.com/new?name=...` deep link 引导 + 检测确认。
3. **credential helper**：`gh auth setup-git` 接管，push/clone 免密。
4. **三层过期检测**：
   - Layer 1（status）：`maintain.sh status` 新增 GitHub PAT 章节，现场 curl expiration header，<10 天红、<30 天黄，顶部 pat-warn 醒目提示。
   - Layer 2（monitor）：`check_pat_status()` + 6h cache，git_push 检测 auth error 时强制刷新。
   - Layer 3（refresh）：`bin/refresh-gh-auth.sh` 一键续期，引导 Regenerate → 粘新 token → 验证 push → 清 flag。
5. **SSH 降级**：init-ubuntu.sh 标"可选加速"，默认跳过；`SETUP_SSH=1` 强制配。
6. **代理**：git 全局 per-host proxy `http.https://github.com.proxy = http://127.0.0.1:7897`（仅 github.com 走 Clash，不影响 gitee/gitlab 等）。

## Consequences

### Positive

- ✅ 最小权限：泄露影响限定单仓 + Contents，非全仓 admin
- ✅ token 仅本地，不加密不进同步仓库
- ✅ 到期可感知：status/monitor/refresh 三层覆盖，不依赖用户盯 log
- ✅ push 稳定：代理 3/3 通（0.26s），直连 5/5 超时（SNI 阻断）

### Negative

- ❌ 无法自动建仓（fg PAT 无 `repo create`）→ 手动 30s，init 引导
- ❌ Clash 不在时 push 秒级失败（proxy 连接拒绝）→ 需启动 Clash 或临时 `git -c http.https://github.com.proxy= push`
- ❌ 多机器各需独立 PAT → 每台配置一次，token 不跨机器同步

### Risks

- **R1** Clash 端口变更（非 7897）→ 更新 `~/.gitconfig` + `rules/git.md` 两处
- **R2** GitHub 变更 fine-grained 权限模型 → 重新勾选，更新 bootstrap 提示
- **R3** monitor 进程跑旧代码 → 改动后需 kill + 重启 monitor 才生效（`kill -0` 存在性检查不替换存活进程）

## Implementation

- ccconfig `8e99d33`（7 文件）：bootstrap-gh-auth.sh PAT 提示改 fine-grained；init-ccprivate-repo.sh 删 `gh repo create` 改手动引导；init-ubuntu.sh SSH 降可选 + `SETUP_SSH=1`；BOOTSTRAP.md 阶段 3 重写；lib/monitor.sh + lib/status.sh 三层检测；bin/refresh-gh-auth.sh 新建
- ccprivate `1e5a4d2`：`rules/git.md` 新增认证 + 代理章节
- `~/.gitconfig`：`http.https://github.com.proxy` 指向本机 Clash 7897

## Verification

2026-08-09 实测：
- push `8e99d33`（HTTPS + fg PAT + credential helper + 代理）成功：`845b621..8e99d33 main -> main`
- `git ls-remote origin` 走代理返回 8e99d33
- 直连 `github.com` curl 5/5 超时（7s）；代理 3/3 通（0.26-0.57s）
- TCP connect 通、openssl 偶发握手成功 → 确认为 TLS/SNI 层间歇阻断，非连接层
- `api.github.com` 直连通（0.55s）→ 仅 `github.com` 域名被阻断

## Related Decisions

- [[0001-secret-strategy]](0001-secret-strategy.md) — token 本地存储策略
- [[0010-adr-directory-location]](0010-adr-directory-location.md) — ADR 目录位置约定

## Related Memory

- `rules/git.md`（ccprivate）— 认证/代理/续期固化用法，symlink 到 `~/.claude/rules`
