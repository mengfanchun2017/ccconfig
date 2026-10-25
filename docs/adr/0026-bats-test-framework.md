# 0026. bats 测试框架引入

> **Status**: ✅ Accepted
> **日期**: 2026-09-03
> **关联**: 测试基础设施
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

ccconfig SH 脚本缺乏系统性测试，现有测试散落在两种形式：

1. **手写 `test_*.sh` 文件**：每个脚本独立写 `if/else` + `exit 1` 断言，无统一 test runner，无 setup/teardown 约定，无 diff 比较能力。测试之间无隔离——一个测试的副作用可能影响下一个。
2. **`bats/` 目录下的少数 bats 测试**：已有零星 bats 使用，但未统一约定，未标准化 `run` 的替代函数。

问题：
- 测试框架不统一，bats 和手写 test 并存，新人不知道用哪个。
- `run` 在 bats 中是保留关键字（`run` 命令执行被测试命令并捕获输出），但 ccconfig 内部有自己名为 `run()` 的函数——在 bats 上下文中会冲突。
- 测试文件散落在不同目录，无统一 test runner 入口。

## Decision

> ⚠️ **本节三条 Decision 均与现状不符（2026-10-25 复核）**，保留原文如下并在每条后标注实际做法：
> 1. 「bats 作为**唯一**框架」→ 实际 **6 个 `.bats` + 20 个 `test_*.sh` 并存**（手写 `.sh` 测试未迁移完，也未再强推迁移）
> 2. 「统一目录 `test/`」→ 实际目录是 **`tests/`**（复数）
> 3. 「用 `bats_run` 代替 `run`」→ **全库零命中 `bats_run`**，`.bats` 里直接裸用 `run`（bats 原生关键字）
> 4. 「`npm test` 入口」→ 无 `package.json`
>
> 仍然成立的部分：bats 作为**新测试**的首选框架（`tests/README.md` 仍要求"新测试一律用 bats"）、
> 不写依赖真实配置的测试。即：**方向保留，强制性与具体命名未落地**。

### 框架：bats（Bash Automated Testing System）

- bats-core（https://github.com/bats-core/bats-core）作为唯一 SH 测试框架。
- 通过 `npm init-option` 安装为 devDependency（`bats` CLI）。
- `test/` 作为统一测试目录，`*.bats` 作为测试文件后缀。

### 约定：bats_run 代替 run

在 bats 测试中，禁止裸 `run`（bats 保留关键字），统一用辅助函数 `bats_run` 替代：

```bash
# 用这个
bats_run ls -la
echo "$output" | grep "some_file"

# 不用这个
run ls -la
```

`bats_run` 的语义与 `run` 一致：设置 `$output` / `$status` / `$lines`。

### 测试文件约定

- 测试文件：`test/<script-name>.bats`
- fixture/数据：`test/fixtures/<script-name>/`
- helper：`test/helpers/`（.bash 文件，bats `load` 加载）
- 运行入口：`npm test` → `bats test/`（可在 `package.json` 配置）

### 禁止

- 不再新增手写 `test_*.sh` 文件（已有文件逐步迁移或删除）。
- 测试中不写依赖真实配置的测试（如 `conf/llm.json` 内容）——mock 或 fixture 替代。

## Consequences

### 正面

- ✅ 统一框架：所有新 SH 测试写 `.bats` 文件，`bats` 运行。
- ✅ 测试隔离：bats 每个 `@test` 块在新 shell 中执行，无副作用泄露。
- ✅ 避免冲突：`bats_run` 消除 `run` 函数名冲突风险。
- ✅ 断言丰富：bats 内置 `[ "$output" = "..." ]` + 社区 `bats-assert` 可用。
- ✅ 可 CI：bats 退出码符合预期，可直接接入 GitHub Actions。

### 负面

- ❌ 需安装 bats 作为 dev 依赖（npm install --dev=... 或 brew install bats-core）。
- ❌ 迁移现有手写测试需投入时间。

## Related Decisions

- （无）

## Implementation

- `conf/versions.json` 新增 bats 版本条目
- `test/` 目录存在性确认或创建
- 已有 bats 测试检查并迁移 `run` → `bats_run`
- 手写 `test_*.sh` 文件逐步迁移到 `.bats`