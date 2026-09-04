#!/usr/bin/env bats
# test-path-helper.bats — lib/path-helper.sh 单元测试
#
# 覆盖：resolve_conf / get_version / ensure_config / find_node_bin

load "setup"

setup() {
    source "$LIB_DIR/path-helper.sh"
}

@test "resolve_conf fails for ccprivate file when no ccprivate" {
    run resolve_conf "versions.json"
    [ "$status" -eq 1 ]
}

@test "resolve_conf fails for nonexistent file" {
    run resolve_conf "nonexistent-file-xyz.json"
    [ "$status" -eq 1 ]
}

@test "get_version returns version for known component" {
    run get_version "node"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "get_version returns empty for unknown component" {
    run get_version "nonexistent-component-xyz"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "get_gh_version returns gh version" {
    run get_gh_version
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "ensure_config returns 0 when file exists" {
    run ensure_config "$CCCONFIG_DIR/conf/versions.json"
    [ "$status" -eq 0 ]
}

@test "ensure_config returns 1 for missing file" {
    run ensure_config "/tmp/nonexistent-xyz-test-123.json"
    [ "$status" -eq 1 ]
}

@test "find_node_bin runs without crash" {
    run find_node_bin
    # CI runner 可能没有 node，不断言 status，只要不 crash