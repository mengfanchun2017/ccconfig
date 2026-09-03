#!/usr/bin/env bats
# test-interact.bats — lib/interact.sh 单元测试
#
# 覆盖：confirm() / menu_select() / prompt() 的 NONINTERACTIVE 分支

load "setup"

setup() {
    source "$LIB_DIR/colors.sh" 2>/dev/null || true
    source "$LIB_DIR/interact.sh"
}

@test "confirm returns 0 when NONINTERACTIVE and default=y" {
    NONINTERACTIVE=true
    run confirm "测试" y
    [ "$status" -eq 0 ]
}

@test "confirm returns 1 when NONINTERACTIVE and default=n" {
    NONINTERACTIVE=true
    run confirm "测试" n
    [ "$status" -eq 1 ]
}

@test "confirm returns 1 when NONINTERACTIVE and default omitted (default=n)" {
    NONINTERACTIVE=true
    run confirm "测试"
    [ "$status" -eq 1 ]
}

@test "confirm returns 0 when NONINTERACTIVE and default=Y" {
    NONINTERACTIVE=true
    run confirm "测试" Y
    [ "$status" -eq 0 ]
}

@test "confirm returns 0 when NONINTERACTIVE and default=y with stdin yes" {
    NONINTERACTIVE=true
    run confirm "测试" y
    [ "$status" -eq 0 ]
}

@test "menu_select returns '0' when NONINTERACTIVE" {
    NONINTERACTIVE=true
    run menu_select "选择" "项一" "项二" "返回"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "menu_select returns 0 status with any items and NONINTERACTIVE" {
    NONINTERACTIVE=true
    run menu_select "测试" "单个"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "prompt returns default when NONINTERACTIVE" {
    NONINTERACTIVE=true
    run prompt "输入" "默认值"
    [ "$status" -eq 0 ]
    [ "$output" = "默认值" ]
}

@test "prompt returns empty when NONINTERACTIVE and no default" {
    NONINTERACTIVE=true
    run prompt "输入"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "prompt returns empty default when NONINTERACTIVE with empty string default" {
    NONINTERACTIVE=true
    run prompt "输入" ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}