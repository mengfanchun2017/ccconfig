# 0001. 真实配置文件不入 git 仓

> **Status**: ✅ Accepted
> **日期**: 2026-06-08
> **关联**: [Phase 0 安全 + 公开化](../../.github/task_plan.md)
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

ccconfig 仓库需要公开同步（GitHub 公开 dotfiles 风格），但当前 5 个 JSON conf 文件含真实 API key / token：

| 文件 | 含敏感字段 |
|---|---|
| `conf/llm.json` | LLM API key（MiniMax / DeepSeek / Claude 等） |
| `conf/claude.json` | Claude API key（如有） |
| `conf/feishu.json` | 飞书 app_secret / verification token |
| `conf/ubuntu.json` | （通常无，防御性纳入）|
| `link/.config.json` | `ANTHROPIC_AUTH_TOKEN`（明文）|

这些 key 在 2026-05-21 仓库初始化时已 commit 到 main。GitHub bot 实时爬取公开仓库的 key 概率 ≈ 100%。即使后续 `.gitignore` 删文件，已 commit 的历史永久保留在 GitHub + forks + 镜像中。

## Decision Drivers

- **D1 简单性**：标准 Git 工作流，零新依赖
- **D2 通用性**：跨平台（Linux / macOS / WSL）、跨工具（claude / lark-cli / cc-connect）一致
- **D3 透明性**：conf 文件 diff 可读，code review 正常
- **D4 单人项目**：避免企业级密钥管理工具的过度工程（git-crypt / SOPS / KMS）
- **D5 兼容 flogme**：key 不进 git 也不进飞书 Base

## Considered Options

### Option A: git-crypt / SOPS 加密文件

- **Pros**: 仓库仍含真实文件，无需 bootstrap 引导
- **Cons**:
  - 单人项目过度工程
  - 私钥分发问题（首次仍要 bootstrap）
  - 加密文件 diff 不可读，code review 困难
  - 增加系统层依赖

### Option B: 环境变量 + 运行时注入

- **Pros**: 完全不写文件，泄露面最小
- **Cons**:
  - Claude Code settings.json / hooks 引用 env 语法不一致
  - 跨工具各自管 env，配置碎片化
  - `init-base.sh` 检测不到 env 是否已设，错误提示不友好

### Option C: 1Password CLI / Keychain 拉取

- **Pros**: 单点管理，跨机器自动同步
- **Cons**:
  - 强依赖外部账号 / 客户端
  - macOS 专属（Linux 需 pass / bitwarden）→ 跨平台不一致
  - `init-base.sh` 调用 `op read` 增加外部依赖
  - 用户未装时引导路径复杂

### Option D: `.gitignore` + `.example` + `init-base.sh` 引导（**采纳**）

- **Pros**:
  - 简单：标准 Git 工作流
  - 通用：跨平台、跨工具一致
  - 透明：diff 可读
  - 与 flogme 兼容
- **Cons**:
  - 每台新机器首次要手动填 key（5 秒操作）
  - 多机器时 key 漂移（每台独立 update，不自动同步）
  - 未来 rotate 流程需手写文档

## Decision

**采纳 Option D**，具体执行：

1. `.gitignore` 5 个真实文件（`conf/*.json` 非 `*.example` + `link/.config.json`）
2. 公开仓库仅含 `.example` 模板
3. `init-base.sh` bootstrap 阶段加检测分支：缺失 → `cp .example 真实文件` + 提示用户编辑
4. 每台机器一份真实 key，跨机器不传播
5. 给现有 1 周迁移期：旧机器跑 `init-base.sh` 自动补齐

## Consequences

### Positive

- ✅ 仓库完全干净，可公开
- ✅ 配置结构（schema）跨机器同步
- ✅ 真实 key 一台机器一份，独立 revoke
- ✅ 任何 dev 看 `.example` 即可理解配置结构
- ✅ `git diff` 不会泄露任何敏感信息

### Negative

- ❌ 首次新机器需手动填 key（5 秒）
- ❌ 多机器时 key 漂移
- ❌ key 轮换靠人记 / CHANGELOG 记录
- ❌ `link/.config.json` 移走会断一些 hook 引用

### Risks

- **R1** hook/monitor 脚本在 conf 缺失时挂 → 加 fallback 给 1 周迁移期
- **R2** 多处引用 `.config.json` → 备份到 `.local`（gitignore）验证完再删
- **R3** 飞书 bot 可能被滥用 → rotate 后立即 audit 飞书后台

## Implementation

详见 [Phase 0 task_plan.md](../../.github/task_plan.md) 任务 #1-#9。

## Notes

- 调研时（2026-06-08）发现 Option C（1Password CLI）其实是更优长期方案，但当前 flogme 还没自动 rotate 提醒机制，先用最简 D 方案
- 未来若个人 tool 增多、key 轮换频繁，可升级到 Option C（增补 ADR）

## Related Decisions

- (none yet)

## Related Memory

- `feishu-cross-tenant-access` (cross-tenant 不踩同样的 key 泄露坑)
