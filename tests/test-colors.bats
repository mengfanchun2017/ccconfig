#!/usr/bin/env bats
# test-colors.bats — lib/colors.sh 单元测试
#
# 覆盖：函数存在性验证、输出到正确 fd

load "setup"

setup() {
    source "$LIB_DIR/colors.sh"
}

@test "ok function exists" {
    type ok
}

@test "err function exists" {
    type err
}

@test "warn function exists" {
    type warn
}

@test "info function exists" {
    type info
}

@test "section function exists" {
    type section
}

@test "banner function exists" {
    type banner
}

@test "ok outputs to stdout" {
    run ok "成功"
    [ "$status" -eq 0 ]
    [[ "$output" == *"成功"* ]]
}

@test "err outputs to stdout" {
    run err "失败"
    [ "$status" -eq 0 ]
    [[ "$output" == *"失败"* ]]
}

@test "warn outputs to stdout" {
    run warn "警告"
    [ "$status" -eq 0 ]
    [[ "$output" == *"警告"* ]]
}

@test "info outputs to stdout" {
    run info "信息"
    [ "$status" -eq 0 ]
    [[ "$output" == *"信息"* ]]
}

@test "section outputs to stdout" {
    run section "章节"
    [ "$status" -eq 0 ]
    [[ "$output" == *"章节"* ]]
}

@test "banner outputs to stdout" {
    run banner "标题"
    [ "$status" -eq 0 ]
    [[ "$output" == *"标题"* ]]
}

@test "color variables are defined" {
    [ -n "$RED" ]
    [ -n "$GREEN" ]
    [ -n "$YELLOW" ]
    [ -n "$CYAN" ]
    [ -n "$NC" ]
    [ -n "$BOLD" ]
}

@test "ok includes green color code" {
    run ok "test"
    [[ "$output" == *"[0;32m"* ]]
}

@test "err includes red color code" {
    run err "test"
    [[ "$output" == *"[0;31m"* ]]
}

@test "warn includes yellow color code" {
    run warn "test"
    [[ "$output" == *"[1;33m"* ]]
}

@test "compat aliases ok/good/success" {
    run good "兼容"
    [ "$status" -eq 0 ]
    run success "兼容"
    [ "$status" -eq 0 ]
}

@test "compat aliases err/bad/error" {
    run bad "兼容"
    [ "$status" -eq 0 ]
    run error "兼容"
    [ "$status" -eq 0 ]
}

@test "section prefixes with newline and cyan" {
    run section "测试"
    [[ "$output" == *"[0;36m"* ]]
}