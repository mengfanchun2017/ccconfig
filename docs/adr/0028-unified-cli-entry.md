# 0028. 统一 CLI 入口

> **Status**: ✅ Accepted
> **日期**: 2026-09-03
> **关联**: CLI 基础设施

## Context and Problem Statement

ccconfig 的功能入口分散在多个独立脚本中，缺乏统一入口：

| 脚本 | 用途 | 入口路径 |
|------|------|---------|
| `bin/init-base.sh` | 初始化入口 | `bash init-base.sh` |
| `maintain.sh` | 运维主菜单 | `bash maintain.sh` |
| `bin/refresh-gh-auth.sh` | GH PAT 续期 | `bash bin/refresh-gh-auth.sh` |
| `lib/init-llm.sh` | LLM 切换 | `bash lib/init-llm.sh` |
| `scripts/sync-marketplace.py` | Skill 同步 | `python3 scripts/sync-marketplace.py` |

问题：

1. **发现性差**：新用户不知道有哪些入口可用，只能读目录结构或问 Claude Code。
2. **记忆负担**：每个入口的路径、语言（bash vs python）、参数约定都不同。
3. **PATH 碎片**：`bin/` 下的脚本已在 `$PATH`，但 `lib/` 和根目录的不在，用户必须 `bash lib/...`。
4. **autocomplete 不统一**：bash 原生 autocomplete 无法覆盖分散的入口。

## Decision

### bin/ccconfig 统一入口

创建 `bin/ccconfig` 作为唯一 CLI 入口，subcommand 路由到各功能：

```
ccconfig init          # init-base.sh
ccconfig maintain      # maintain.sh
ccconfig auth          # refresh-gh-auth.sh
ccconfig llm           # init-llm.sh
ccconfig sync-market   # sync-marketplace.py
```

### 设计原则

1. **`bin/ccconfig` 是脚本，非二进制**：用 bash 实现，source 子命令对应的脚本，不引入新语言。
2. **短名称优先**：常用操作尽量短（`ccconfig init`，`ccconfig llm`）。
3. **`--help` / `-h` 支持**：顶层和子命令都支持。
4. **非破坏性 subcommand 直接执行**，破坏性操作走 subcommand 自己的 `--dry-run` / confirm。
5. **`ccconfig` 已在 PATH 中**（`bin/` 通过 `setup.sh` 加入 `$PATH`）。

### 迁移策略

- 旧脚本保留，`bin/ccconfig` 作为 forwarder 调用它们。
- 不强制迁移——用户仍可直接 `bash maintain.sh`。
- 新功能优先以 subcommand 方式添加到 `ccconfig`，不创建新的独立入口脚本。

### 不纳入范围

- 不重新实现 `maintain.sh` 的交互菜单——`ccconfig maintain` 直接调用 `maintain.sh`。
- 不改子脚本内部逻辑，`ccconfig` 只是路由层。

## Consequences

### 正面

- ✅ 单入口发现：`ccconfig --help` 列出所有可用功能。
- ✅ 统一 PATH：所有功能通过 `bin/ccconfig` 暴露，无需单独加 `lib/` 到 PATH。
- ✅ 增量迁移：旧入口保留，不 break 现有工作流。
- ✅ 低实现成本：bash 实现路由，每个 subcommand 一行 source/exec。
- ✅ 可扩展：新功能以 subcommand 方式添加，不膨胀顶层命名空间。

### 负面

- ❌ 多一层间接调用：`ccconfig llm` → `lib/init-llm.sh`，调用栈深一层。
- ❌ 旧脚本直接调用的用户需要养成用 `ccconfig` 的习惯。

## Related Decisions

- （无）

## Implementation

- `bin/ccconfig` 创建
- 首批 subcommand 覆盖：init, maintain, auth, llm, sync-market
- `bin/ccconfig --help` 输出帮助信息
- README 文档更新入口指引