#!/usr/bin/env bats
# test-guard.bats — lib/dry-run.sh guard 幂等函数测试

load "setup"

setup() {
    unset CCC_DRY_RUN
}

@test "guard_mkdir creates directory if missing" {
    source "$LIB_DIR/dry-run.sh"
    local d; d=$(mktemp -d)
    local sub="$d/new-dir"
    guard_mkdir "$sub"
    [ -d "$sub" ]
    rm -rf "$d"
}

@test "guard_mkdir no-op if directory exists" {
    source "$LIB_DIR/dry-run.sh"
    local d; d=$(mktemp -d)
    guard_mkdir "$d"
    [ -d "$d" ]
    rm -rf "$d"
}

@test "guard_append_line adds line if absent" {
    source "$LIB_DIR/dry-run.sh"
    local f; f=$(mktemp)
    guard_append_line "$f" "test-line"
    run grep -qxF "test-line" "$f"
    [ "$status" -eq 0 ]
    rm -f "$f"
}

@test "guard_append_line no-op if line exists" {
    source "$LIB_DIR/dry-run.sh"
    local f; f=$(mktemp)
    printf 'existing-line\n' > "$f"
    guard_append_line "$f" "existing-line"
    run wc -l < "$f"
    [ "$output" = "1" ]
    rm -f "$f"
}

@test "guard_command_exists returns 0 for existing command" {
    source "$LIB_DIR/dry-run.sh"
    guard_command_exists bash
}

@test "guard_command_exists returns 1 for missing command" {
    source "$LIB_DIR/dry-run.sh"
    run guard_command_exists nonexistent-cmd-xyz
    [ "$status" -eq 1 ]
}

@test "atomic_write writes content atomically" {
    source "$LIB_DIR/dry-run.sh"
    local f; f=$(mktemp -u)
    printf 'hello' | atomic_write "$f"
    run cat "$f"
    [ "$output" = "hello" ]
    [ -f "$f" ]
    rm -f "$f"
}

@test "guard_symlink creates symlink" {
    source "$LIB_DIR/dry-run.sh"
    local d; d=$(mktemp -d)
    local target="$d/target" link="$d/link"
    touch "$target"
    guard_symlink "$target" "$link"
    [ -L "$link" ]
    [ "$(readlink "$link")" = "$target" ]
    rm -rf "$d"
}

@test "guard_symlink updates stale symlink" {
    source "$LIB_DIR/dry-run.sh"
    local d; d=$(mktemp -d)
    local old="$d/old" new="$d/new" link="$d/link"
    touch "$old" "$new"
    ln -s "$old" "$link"
    guard_symlink "$new" "$link"
    [ "$(readlink "$link")" = "$new" ]
    rm -rf "$d"
}

@test "guard_symlink no-op if already correct" {
    source "$LIB_DIR/dry-run.sh"
    local d; d=$(mktemp -d)
    local target="$d/target" link="$d/link"
    touch "$target"
    ln -s "$target" "$link"
    guard_symlink "$target" "$link"
    [ -L "$link" ]
    rm -rf "$d"
}
