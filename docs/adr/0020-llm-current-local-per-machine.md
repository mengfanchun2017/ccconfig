# 0020. LLM 运行时配置本地化 — 每台机器独立选择 LLM

> **Status**: ✅ Accepted
> **日期**: 2026-09-01
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

ccconfig 跨两台（或多台）机器使用：

- A 机（笔记本）：日常主力工作，频繁切换 LLM（内网 DeepSeek、阿里 glm 等）
- B 机 / S 台式机（24h 云电脑）：跑 ccbridge 处理微信/飞书消息，固定用便宜预设（如 deepseek_flash），不修改文件

当前架构下，`ccprivate/conf/llm.json` 的 `current` 字段和 `~/.claude/settings.json` 的 `env.ANTHROPIC_*` 变量**通过 ccprivate 同步**。A 机切 LLM → auto-sync 推 → B 机拉到 A 的配置 → B 机的 LLM 被覆盖，反之亦然。

两机工作范围不同假设不会编辑同一文件，但 LLM 运行时选择是每台机器独立的配置——不应当同步。

## Decision Drivers

- LLM provider 列表（minimax、deepseek_flash、gateway 等）和 pricing 是通用配置，应跨机共享
- **选哪个 provider 作为当前 LLM** 是机器本地偏好，不应同步
- `settings.json` 的 `ANTHROPIC_BASE_URL`、`ANTHROPIC_MODEL`、`ANTHROPIC_AUTH_TOKEN` 等运行时变量由当前 LLM 决定，也应本地化
- `settings.json` 的 `permissions`、`hooks`、`mcpServers`、`disabledMcpServers` 等是通用配置，应跨机共享
- 改动最小化，不破坏现有 init-llm.sh 的切换流程

## Considered Options

### A — 完整拆出 llm.json + settings.json 同步

两者全部移出 ccprivate 同步，每台机器各自维护完整文件。

**Pros**: 最简单。**Cons**: provider 列表和 pricing 也需要每台机器单独维护，浪费。

### B — 环境变量覆盖（OS env 覆盖 settings.json）

不改同步，把 LLM 变量写 ~/.bashrc，期望 OS 环境变量优先级高于 settings.json。

**Pros**: 不改架构。**Cons**: Claude Code 文档明确 `settings.json env 段优先级高于 OS 环境变量`，环境变量不能覆盖。且 .bashrc 在非交互式 shell 不加载。

### C — `llm-current` 本地文件 + settings.json 停止同步（选定）

- `ccprivate/conf/llm.json` 保留同步（provider 列表 + pricing 共享）
- `~/.claude/llm-current` 新增本地文件，只存当前 preset 名，不参与同步
- `ccprivate/link/settings.json` 停止同步（`git rm --cached` + `.gitignore`）
- `~/.claude/settings.json` 改为独立文件（setup.sh 首次 cp，之后各机独立）
- init-llm.sh 写 current 时改写 `llm-current`，不再写 `llm.json.current`

**Pros**: provider 列表共享，current 选择本地化，改动小。**Cons**: settings.json 中非 LLM 配置（permissions/hooks 等）模板更新后不会自动同步到已有机器。

## Decision

选 C。具体实现：

### 数据流

```
ccprivate/conf/llm.json（同步）           ~/.claude/llm-current（本地）
├── llms.minimax                          → 存 {"current": "deepseek_flash"}
│   ├── base_url
│   ├── model               init-llm.sh   由 init-llm.sh 读写
│   ├── key                     │          
│   └── ...                    │           ~/.claude/settings.json（本地）
├── llms.deepseek_flash       │            ├── env.ANTHROPIC_BASE_URL
│   └── ...                   ├── 读 ───── ├── env.ANTHROPIC_MODEL
├── pricing                   │            ├── env.ANTHROPIC_AUTH_TOKEN
├── fx                        │            ├── env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
└── current（不再写入 ◀────  ┘            ├── permissions
    保留但不再使用）                       ├── hooks
                                           ├── mcpServers
                                           └── ...
```

### settings.json 生命周期

- **新机器**：setup.sh 首次 `cp ccprivate/link/settings.json → ~/.claude/settings.json`
- **使用中**：init-llm.sh 写 LLM 变量 + 改 permissions/hooks 等
- **模板更新**：ccprivate/link/settings.json 作为"干净模板"保留同步，已有机器需要时手动合并或重新 cp

### 受影响文件的改动

| 文件 | 操作 |
|------|------|
| `ccprivate/.gitignore` | 追加 `link/settings.json` |
| `ccprivate/link/settings.json` | `git rm --cached` 停止跟踪，保留文件作为新机器模板 |
| `ccprivate/setup.sh` | settings.json 从 symlink 改为 `cp`（首次复制） |
| `ccconfig/lib/init-llm.sh` | `write_llc_config` 不再写 `llm.json.current`，改读写 `~/.claude/llm-current`；`list_llms`/`show_status` 改读 `llm-current` |

## Consequences

### Positive

- ✅ A 机切 LLM 不影响 B 机，互不覆盖
- ✅ provider 列表 + pricing 继续跨机同步，不用重复维护
- ✅ LLM 运行时切换流程不变（`init-llm.sh switch <name>`）
- ✅ auto-sync 不再因 settings.json 的 LLM 变量变化而触发不必要的同步
- ✅ S 台式机只需首次 setup 选一次 LLM，之后永远不碰

### Negative / Risks

- ⚠️ settings.json 中非 LLM 通用配置（permissions/hooks 等）的模板更新不再自动同步到已有机器。需要手动合并或 `cp + re-init-llm`。
  - **缓解**：这类配置变更频率极低（季度级别），可接受手动操作
- ⚠️ 已有机器（A 机）迁移时需要备份 settings.json → 删 symlink → 重新 setup.sh → re-init-llm → `git rm --cached` 三步
- ⚠️ init-llm.sh 需要兼容旧文件：`llm-current` 不存在时 fallback 读 `llm.json.current`

## Implementation

详见 ADR-0020 对应 commit 和 ccconfig/lib/init-llm.sh 的 git diff。

新机器初始化流程：

```bash
git clone https://github.com/mengfanchun2017/ccconfig.git
git clone https://github.com/mengfanchun2017/ccprivate.git
bash ~/git/ccprivate/setup.sh        # → cp settings.json 模板
bash ~/git/ccconfig/init-llm.sh      # → 选 LLM → 写 llm-current + settings.json
```

## Related Decisions

- [ADR-0001](0001-secret-strategy.md)：隐私配置不入公开仓，ccprivate 承认真实配置
- [ADR-0012](0012-interact-p0-no-gum.md)：SH 交互规范化
- [ADR-0018](0018-permission-mode-strategy.md)：settings.json 权限模式策略