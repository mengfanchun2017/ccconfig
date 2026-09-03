#!/usr/bin/env bats
# test-dry-run.bats — lib/dry-run.sh 单元测试
#
# 覆盖：run()/would()/dispatch() 在 CCC_DRY_RUN 下的行为
#
# 注意：dry-run.sh 定义了 run() 函数，会覆盖 bats 内置的 run。
# 测试中用 bats_run 调用 bats 的 run。

load "setup"

setup() {
    unset CCC_DRY_RUN
    source "$LIB_DIR/dry-run.sh"
}

@test "run() executes normally without CCC_DRY_RUN" {
    bats_run run echo hello
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "run() prints would: with CCC_DRY_RUN=1" {
    CCC_DRY_RUN=1 bats_run run echo hello
    [[ "$output" == *"would:"* ]]
}

@test "run() strips --dry-run flag" {
    CCC_DRY_RUN=1 bats_run run echo hello --dry-run
    echo "$output"
    [[ "$output" == *"hello"* ]]
}

@test "would() prints formatted message" {
    bats_run would "install" "pkg-a pkg-b"
    [ "$output" = "would: install pkg-a pkg-b" ]
}

@test "dispatch() calls dry_fn when CCC_DRY_RUN=1" {
    CCC_DRY_RUN=1 bats_run dispatch real_fn dry_fn
    [ "$output" = "would: dry_fn" ]
}

@test "dispatch() calls real_fn without CCC_DRY_RUN" {
    my_real() { echo "real-called"; }
    my_dry() { echo "dry-called"; }
    bats_run dispatch my_real my_dry
    [ "$output" = "real-called" ]
}
