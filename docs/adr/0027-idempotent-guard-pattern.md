# 0027. 幂等 guard 模式

> **Status**: ✅ Accepted
> **日期**: 2026-09-03
> **关联**: SH 编码规范

## Context and Problem Statement

ccconfig 的 SH 脚本执行非幂等操作（install / config write / symlink / service enable）时，重复执行可能导致问题：

1. **install 类**：`apt-get install` 重复执行不影响结果，但产生额外网络开销和磁盘 I/O。
2. **config write 类**：`conf/llm.json` 写入覆盖用户已修改的内容。
3. **symlink 类**：`ln -sf` 幂等，但 `ln -s`（无 `-f`）第二次执行失败。
4. **service enable 类**：`systemctl enable` 幂等，但 `systemctl start` 重复执行不会出错但浪费时间。

问题根源：脚本没有统一的"检查 -> 执行 -> 跳过"模式，每个脚本自定 guard 逻辑，风格不统一。

## Decision

### Guard 函数 API

在 `lib/guard.sh`（或 `lib/colors.sh` 内新增 guard 部分——根据实际大小决定）中定义统一 guard 模式：

```bash
# 已安装检查：command 是否存在
if _is_installed "jq"; then
    ok "jq 已安装"
else
    apt-get install -y jq
fi

# 文件存在检查
if _is_not_file "/etc/some-config"; then
    cp ...
fi
```

具体函数：

| 函数 | 语义 | 非幂等场景 |
|------|------|-----------|
| `_is_installed <cmd>` | `command -v <cmd>` 返回 0 | install |
| `_is_not_file <path>` | 文件不存在返回 0 | config write, symlink |
| `_is_not_dir <path>` | 目录不存在返回 0 | mkdir |
| `_is_executed <uid>` | 全局标记文件检测（`~/.ccconfig/guards/<uid>`） | 跨 session 幂等 |
| `_mark_executed <uid>` | 写入标记文件 | 配合 `_is_executed` |

### atomic_write 约定

config file 写入遵循 atomic write 模式：

```bash
# 写临时文件 → rename（原子操作）
# 非：
#   echo "$config" > /path/to/file
# 是：
#   echo "$config" > /tmp/ccconfig_${BASHPID}_tmpfile
#   mv /tmp/ccconfig_${BASHPID}_tmpfile /path/to/file
```

`stdbuf` / `flock` 级别 atomicity 视场景定，最小要求在 tmpfile + `mv`（POSIX 保证同文件系统 rename 原子）。

### 使用原则

1. 写操作的 shell 函数统一 source `lib/dry-run.sh`，使 `--dry-run` 时只输出不执行。
2. Guard 函数不包含业务逻辑——只回答"是否可安全执行"。
3. Guard 的"已满足"状态输出用 `ok`（`lib/colors.sh`），"正在执行"用 `info`。

## Consequences

### 正面

- ✅ 统一 guard 语义：所有脚本用同一套函数，减少重复代码。
- ✅ 幂等执行：多次运行安全。
- ✅ atomic write：避免写半文件导致配置解析错误。
- ✅ dry-run 兼容：guard 函数配合 dry-run 模式，预览将要执行的操作。
- ✅ 跨 session 幂等：`_is_executed` / `_mark_executed` 可用于只执行一次的初始化操作。

### 负面

- ❌ 迁移现有脚本到 guard 模式需要时间。
- ❌ 增加一个 source 依赖（`lib/guard.sh`），但所有脚本已 source `lib/colors.sh`，可合并。

## Related Decisions

- （无）

## Implementation

- `lib/guard.sh` 创建（或并入 `lib/colors.sh`）
- 现有 install 块逐步迁移到 guard 模式
- dry-run 与 guard 结合测试