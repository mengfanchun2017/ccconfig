#!/usr/bin/env bats
# test-dry-run.bats — lib/dry-run.sh 单元测试
#
# 覆盖：run()/would()/dispatch() 在 CCC_DRY_RUN 下的行为

load "setup"

setup_file() {
    # 全局：一次 source，所有测试共享
    export TEST_LIB="$CCCONFIG_DIR/lib"
}

setup() {
    # 每个 test 前重置 dry-run 状态
    unset CCC_DRY_RUN
}

@test "run() executes normally without CCC_DRY_RUN" {
    source "$TEST_LIB/dry-run.sh"
    run run echo hello
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "run() prints would: with CCC_DRY_RUN=1" {
    CCC_DRY_RUN=1 export CCC_DRY_RUN
    source "$TEST_LIB/dry-run.sh"
    run run echo hello
    # 在 dry-run 下只打印 would:，不执行
    [[ "$output" == *"would:"* ]]
}

@test "run() strips --dry-run flag before printing" {
    CCC_DRY_RUN=1 export CCC_DRY_RUN
    source "$TEST_LIB/dry-run.sh"
    run run echo hello --dry-run
    # --dry-run 不应出现在 would: 输出中
    [[ "$output" != *"--dry-run"* ]]
}

@test "would() prints formatted message" {
    source "$TEST_LIB/dry-run.sh"
    run would "install" "pkg-a pkg-b"
    [ "$output" = "would: install pkg-a pkg-b" ]
}

@test "dispatch() calls dry_fn when CCC_DRY_RUN=1" {
    CCC_DRY_RUN=1 export CCC_DRY_RUN
    source "$TEST_LIB/dry-run.sh"

    dry_called=0
    real_called=0

    run dispatch real_fn dry_fn
    [ "$output" = "would: dry_fn" ]
}

@test "dispatch() calls real_fn without CCC_DRY_RUN" {
    unset CCC_DRY_RUN
    source "$TEST_LIB/dry-run.sh"

    my_real() { echo "real-called"; }
    my_dry() { echo "dry-called"; }

    run dispatch my_real my_dry
    [ "$output" = "real-called" ]
}
