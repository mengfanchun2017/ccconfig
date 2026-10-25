#!/usr/bin/env bats
# test-guard.bats — lib/dry-run.sh 原子写入测试
#
# 注意：dry-run.sh 定义了 run() 覆盖 bats 内置 run。
# 测试中不用 bats 的 run 命令，用 $() 或直接断言。
#
# 历史：本文件曾测 5 个 guard_* 幂等函数（ADR-0027 描述的 guard 模式）。
# 2026-10-25 三仓 review 实证：guard_mkdir/guard_symlink/guard_append_line/
# guard_write_file/guard_command_exists 生产代码零调用（仅本测试引用），
# ADR-0027 从未落地 —— 已删除那 5 个函数与其用例。atomic_write 有生产调用
# （lib/ensure-uv.sh），保留并继续测。ADR-0027 已标注 Superseded。

load "setup"

setup() {
    unset CCC_DRY_RUN
    source "$LIB_DIR/dry-run.sh"
}

@test "atomic_write writes content atomically" {
    local f; f=$(mktemp -u)
    printf 'hello' | atomic_write "$f"
    local content; content=$(cat "$f")
    [ "$content" = "hello" ]
    [ -f "$f" ]
    rm -f "$f"
}

@test "atomic_write replaces existing file" {
    local f; f=$(mktemp)
    printf 'old' > "$f"
    printf 'new' | atomic_write "$f"
    [ "$(cat "$f")" = "new" ]
    rm -f "$f"
}

@test "atomic_write leaves no temp residue" {
    local d; d=$(mktemp -d)
    printf 'x' | atomic_write "$d/out"
    local extra; extra=$(find "$d" -name 'out.*' | wc -l)
    [ "$extra" = "0" ]
    rm -rf "$d"
}