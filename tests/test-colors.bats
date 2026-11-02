#!/usr/bin/env bats
# test-colors.bats — lib/colors.sh 单元测试
#
# 覆盖：函数存在性验证、输出到正确 fd

load "setup"

setup() {
    # bats 的 `run` 把 stdout 捕获进管道 → 非 tty → colors.sh 默认清空色变量。
    # 断言色码的用例需要强制保留，故此处设 CCCONFIG_FORCE_COLOR。
    export CCCONFIG_FORCE_COLOR=1
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

# 色码断言不写死 256/16 —— 具体档位取决于宿主 tput colors，写死会让测试
# 在另一台机器上必挂。改为断言「确实带了前景色」+ 档位切换行为。
@test "ok includes a foreground color code" {
    run ok "test"
    [[ "$output" == *"[0;32m"* || "$output" == *"38;5;"* ]]
}

@test "err includes a foreground color code" {
    run err "test"
    [[ "$output" == *"[0;31m"* || "$output" == *"38;5;"* ]]
}

@test "warn is not the harsh bold-yellow tier" {
    run warn "test"
    # 1;33 是 16 色里最刺眼的一档，已降为 0;33
    [[ "$output" != *"[1;33m"* ]]
    [[ "$output" == *"[0;33m"* || "$output" == *"38;5;"* ]]
}

@test "256 tier uses palette indices, not 16-color codes" {
    run env CCCONFIG_COLOR_DEPTH=256 bash -c "source '$LIB_DIR/colors.sh'; ok t; err t; warn t"
    [[ "$output" == *"38;5;71m"* ]]    # green
    [[ "$output" == *"38;5;167m"* ]]   # red
    [[ "$output" == *"38;5;179m"* ]]   # yellow/amber
}

@test "16 tier is forced when depth override is 16" {
    run env CCCONFIG_COLOR_DEPTH=16 bash -c "source '$LIB_DIR/colors.sh'; warn t"
    [[ "$output" == *"[0;33m"* ]]
    [[ "$output" != *"38;5;"* ]]
}

@test "NO_COLOR strips all color even when forced" {
    run env NO_COLOR=1 CCCONFIG_FORCE_COLOR=1 bash -c "source '$LIB_DIR/colors.sh'; ok t"
    [[ "$output" != *"[38;5;"* ]]
    [[ "$output" != *"[0;32m"* ]]
}

@test "CLICOLOR_FORCE keeps color on non-tty" {
    run env CLICOLOR_FORCE=1 bash -c "source '$LIB_DIR/colors.sh'; ok t"
    [[ "$output" == *"[0;32m"* || "$output" == *"38;5;"* ]]
}

@test "non-tty without any force flag emits no escapes" {
    run env -u CCCONFIG_FORCE_COLOR -u CLICOLOR_FORCE -u FORCE_COLOR bash -c "source '$LIB_DIR/colors.sh'; ok t; err t; warn t"
    [[ "$output" != *$'\033'* ]]
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

@test "section prefixes with newline and a color code" {
    run section "测试"
    [[ "$output" == *"[0;36m"* || "$output" == *"38;5;"* ]]
}