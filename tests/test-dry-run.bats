#!/usr/bin/env bats
# test-dry-run.bats — lib/dry-run.sh 单元测试
#
# 覆盖：run()/would()/dispatch() 在 CCC_DRY_RUN 下的行为
#
# 注意：dry-run.sh 定义了 run() 会覆盖 bats 内置 run 命令。
# 测试中直接用 $() 捕获输出，不用 bats 的 run。

load "setup"

setup() {
    unset CCC_DRY_RUN
    source "$LIB_DIR/dry-run.sh"
}

@test "run() executes normally without CCC_DRY_RUN" {
    local out; out=$(run echo hello 2>/dev/null)
    [ "$out" = "hello" ]
}

@test "run() prints would: with CCC_DRY_RUN=1" {
    CCC_DRY_RUN=1
    local out; out=$(run echo hello 2>&1)
    [[ "$out" == *"would:"* ]]
}

@test "would() prints formatted message" {
    local out; out=$(would "install" "pkg-a pkg-b")
    [ "$out" = "would: install pkg-a pkg-b" ]
}

@test "dispatch() calls dry_fn when CCC_DRY_RUN=1" {
    CCC_DRY_RUN=1
    local out; out=$(dispatch real_fn dry_fn 2>&1)
    [ "$out" = "would: dry_fn" ]
}

@test "dispatch() calls real_fn without CCC_DRY_RUN" {
    my_real() { echo "real-called"; }
    my_dry() { echo "dry-called"; }
    local out; out=$(dispatch my_real my_dry 2>&1)
    [ "$out" = "real-called" ]
}
