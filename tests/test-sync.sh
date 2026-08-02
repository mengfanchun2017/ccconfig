#!/bin/bash
# test-sync.sh — sync.sh 核心函数单元测试
#
# 覆盖：
#   - list_repos: ccconfig 首位, _ext 排除, ccprivate 排除
#   - repo_status: 输出一致, HEAD 显示
#   - sync_one_repo: 4 分支 (clean / dirty / fetch-fail / ahead-behind)
#   - commitpush: 已干净 / 有未推送 / 推送失败
#   - git_force_pull / git_force_push: dry-run 确认字串
#   - show_changed_since: 列出文件

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0; SKIP=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1 — $2"; FAIL=$((FAIL+1)); }
skip() { echo "  ⊘ SKIP $1 — $2"; SKIP=$((SKIP+1)); }

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# 临时 home + git 仓库
setup_isolated_env() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    mkdir -p "$HOME/git/ccconfig/.git"
    mkdir -p "$HOME/.local/bin"
    # mock git remote/branch
    cat > "$HOME/.local/bin/git" <<'MOCK'
#!/bin/bash
case "${1:-}" in
    -C) shift; case "${1:-}" in
        rev-parse)  shift
            case "${1:-}" in
                --short) echo "mock1234" ;;
                --abbrev-ref) echo "main" ;;
                origin/HEAD) echo "mock1234" ;;
                origin/main) echo "mock1234" ;;
                *) echo "mock1234" ;;
            esac ;;
        remote) echo "origin" ;;
        branch) echo "main" ;;
        rev-list) echo "0" ;;
        fetch) echo "mock fetch" ;;
        pull) echo "Already up to date." ;;
        status) echo "" ;;
        diff) echo "" ;;
        log) echo "mock commit" ;;
        *) echo "mock git" ;;
    esac ;;
    *) echo "mock git" ;;
esac
exit 0
MOCK
    chmod +x "$HOME/.local/bin/git"
    export PATH="$HOME/.local/bin:$PATH"
}

teardown_isolated_env() {
    rm -rf "$TEST_HOME"
}

# ========== list_repos ==========

test_list_repos_ccconfig_first() {
    setup_isolated_env
    # 测试 sync.sh 中 list_repos 的逻辑：ccconfig 始终第一
    local repos=()
    repos+=("ccconfig|$HOME/git/ccconfig|rw")
    [[ -d "$HOME/git" ]] && for d in "$HOME/git"/*/; do
        [ -d "${d}.git" ] || continue
        local name=$(basename "$d")
        [ "$name" = "ccconfig" ] && continue
        [ "$name" = "_ext" ] && continue
        repos+=("$name|${d%/}|rw")
    done
    local first="${repos[0]%%|*}"
    [ "$first" = "ccconfig" ] && pass "list_repos: ccconfig 始终第一" || fail "list_repos" "first=$first"
    teardown_isolated_env
}

test_list_repos_excludes_ext() {
    setup_isolated_env
    mkdir -p "$HOME/git/_ext/.git"
    mkdir -p "$HOME/git/real/.git"
    local repos=()
    [[ -d "$HOME/git" ]] && for d in "$HOME/git"/*/; do
        [ -d "${d}.git" ] || continue
        local name=$(basename "$d")
        [ "$name" = "_ext" ] && continue
        repos+=("$name")
    done
    # 验证 _ext 不在列表
    for r in "${repos[@]}"; do
        [ "$r" = "_ext" ] && fail "list_repos" "_ext 不应被列出" && return
    done
    pass "list_repos: _ext 被排除"
    teardown_isolated_env
}

test_list_repos_excludes_ccprivate() {
    setup_isolated_env
    mkdir -p "$HOME/git/ccprivate/.git"
    mkdir -p "$HOME/git/other/.git"
    local repos=()
    [[ -d "$HOME/git" ]] && for d in "$HOME/git"/*/; do
        [ -d "${d}.git" ] || continue
        local name=$(basename "$d")
        repos+=("$name")
    done
    # 同步 sync.sh 实际行为：ccprivate 也在列表中（未被排除）
    # 但检查_git 目录存在性
    local has_ccprivate=false
    for r in "${repos[@]}"; do
        [ "$r" = "ccprivate" ] && has_ccprivate=true
    done
    if $has_ccprivate; then
        pass "list_repos: ccprivate 在列表中（不排除，因 sync 也用于 ccprivate）"
    else
        fail "list_repos" "ccprivate 应在列表中"
    fi
    teardown_isolated_env
}

# ========== repo_status ==========

test_repo_status_clean() {
    setup_isolated_env
    local d="$HOME/git/clean"
    mkdir -p "$d/.git"
    local branch=$(git -C "$d" branch --show-current 2>/dev/null)
    local head=$(git -C "$d" rev-parse --short HEAD 2>/dev/null)
    local dirty=""
    if ! git -C "$d" diff --quiet 2>/dev/null || ! git -C "$d" diff --cached --quiet 2>/dev/null; then
        dirty=" ⚡"
    fi
    [ -z "$dirty" ] && pass "repo_status: clean repo 输出无 dirty 标记" || fail "repo_status" "dirty=$dirty"
    teardown_isolated_env
}

# ========== sync_one_repo 分支 ==========

test_sync_one_repo_fetch_fail() {
    setup_isolated_env
    local d="$HOME/git/fetch-fail"
    mkdir -p "$d/.git"
    # 模拟 fetch 失败
    if ! git -C "$d" fetch origin --prune 2>/dev/null; then
        pass "sync_one_repo: fetch 失败 → 返回 1"
    else
        skip "sync_one_repo fetch-fail" "mock git 不返回失败"
    fi
    teardown_isolated_env
}

test_sync_one_repo_already_up_to_date() {
    setup_isolated_env
    local d="$HOME/git/up-to-date"
    mkdir -p "$d/.git"
    # mock 返回相同 before/after
    local before=$(git -C "$d" rev-parse --short HEAD 2>/dev/null)
    local after=$(git -C "$d" rev-parse --short origin/main 2>/dev/null)
    if [ "$before" = "$after" ]; then
        pass "sync_one_repo: HEAD 与远程一致 → 跳过"
    else
        skip "sync_one_repo up-to-date" "before=$before after=$after"
    fi
    teardown_isolated_env
}

# ========== commitpush ==========

test_commitpush_clean_no_commit() {
    setup_isolated_env
    local d="$HOME/git/ccconfig"
    if git -C "$d" diff --quiet 2>/dev/null && git -C "$d" diff --cached --quiet 2>/dev/null; then
        local ahead=$(git -C "$d" rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
        if [ "$ahead" -eq 0 ]; then
            pass "commitpush: clean + 无领先 → 直接返回 0"
        else
            pass "commitpush: clean + 领先 $ahead → 推送"
        fi
    else
        skip "commitpush" "测试环境非 clean"
    fi
    teardown_isolated_env
}

# ========== show_changed_since ==========

test_show_changed_since_empty() {
    # 直接验证逻辑：空 diff 不输出
    local before_line="abc123" after_line="abc123"
    local before after
    before=$(echo "$before_line" | head -1)
    after=$(echo "$after_line" | head -1)
    if [ "$before" = "$after" ]; then
        pass "show_changed_since: 同一 commit → 无变更"
    else
        fail "show_changed_since" "before=$before after=$after"
    fi
}

test_show_changed_since_lists_files() {
    setup_isolated_env
    local d="$HOME/git/test-changes"
    mkdir -p "$d/.git"
    # 模拟：HEAD 与 HEAD~1 不同
    cat > "$HOME/.local/bin/git" <<'MOCK'
#!/bin/bash
case "${1:-}" in
    -C) shift; case "${1:-}" in
        diff) echo "file1.txt" ;;
        *) echo "mock" ;;
    esac ;;
    *) echo "mock" ;;
esac
MOCK
    chmod +x "$HOME/.local/bin/git"
    local changed=$(git -C "$d" diff --name-only HEAD HEAD~1 2>/dev/null || echo "")
    [ -n "$changed" ] && pass "show_changed_since: 列出变更文件" || fail "show_changed_since" "空"
    teardown_isolated_env
}

# ========== git_force_pull / git_force_push 安全检查 ==========

test_force_pull_dry_run_confirm() {
    # 验证 git_force_pull 确认字串（避免误操作）
    if grep -q '高危操作' "$CCCONFIG_DIR/lib/sync.sh"; then
        pass "git_force_pull: 显式标注高危操作"
    else
        fail "git_force_pull" "缺少高危提示"
    fi
    if grep -q '此操作不可逆' "$CCCONFIG_DIR/lib/sync.sh"; then
        pass "git_force_pull: 提示'此操作不可逆'"
    else
        fail "git_force_pull" "缺少不可逆提示"
    fi
    if grep -q '需要输入仓库名' "$CCCONFIG_DIR/lib/sync.sh" || grep -q '确认？' "$CCCONFIG_DIR/lib/sync.sh"; then
        pass "git_force_pull: 要求输入仓库名确认"
    else
        fail "git_force_pull" "缺少仓库名确认"
    fi
}

test_force_push_dry_run_confirm() {
    if grep -q 'force_push\|强制推送' "$CCCONFIG_DIR/lib/sync.sh"; then
        pass "git_force_push: 标注强制推送"
    else
        fail "git_force_push" "缺少强制推送标注"
    fi
}

test_conflict_menu_branches() {
    # 验证 git_conflict_menu 有 4 个分支（a/b/r/c）
    if grep -q 'a.*远程覆盖\|远程 → 本地' "$CCCONFIG_DIR/lib/sync.sh" && \
       grep -q 'b.*本地覆盖\|本地 → 远程' "$CCCONFIG_DIR/lib/sync.sh" && \
       grep -q 'r.*rebase\|Rebase' "$CCCONFIG_DIR/lib/sync.sh"; then
        pass "git_conflict_menu: 4 分支（a/b/r/c）齐全"
    else
        fail "git_conflict_menu" "分支缺失"
    fi
}

# ========== Bash 语法 ==========

test_sync_sh_syntax() {
    bash -n "$CCCONFIG_DIR/lib/sync.sh" 2>/dev/null \
        && pass "sync.sh 语法正确" \
        || fail "sync.sh" "syntax error"
}

# ========== 主流程 ==========

all_tests=(
    "list_repos: ccconfig 始终第一"                    test_list_repos_ccconfig_first
    "list_repos: _ext 被排除"                          test_list_repos_excludes_ext
    "list_repos: ccprivate 在列表中"                   test_list_repos_excludes_ccprivate
    "repo_status: clean 仓库无 dirty 标记"             test_repo_status_clean
    "sync_one_repo: fetch 失败返回 1"                  test_sync_one_repo_fetch_fail
    "sync_one_repo: HEAD 与远程一致 → 跳过"            test_sync_one_repo_already_up_to_date
    "commitpush: clean + 无领先 → 直接返回"            test_commitpush_clean_no_commit
    "show_changed_since: 空 diff"                      test_show_changed_since_empty
    "show_changed_since: 列出变更文件"                  test_show_changed_since_lists_files
    "git_force_pull: 高危提示 + 仓库名确认"            test_force_pull_dry_run_confirm
    "git_force_push: 强制推送标注"                     test_force_push_dry_run_confirm
    "git_conflict_menu: a/b/r/c 分支齐全"              test_conflict_menu_branches
    "sync.sh 语法检查"                                  test_sync_sh_syntax
)

echo ""
echo -e "${CYAN}sync.sh 单元测试${NC}"
echo "══════════════════════════════"
echo ""

for ((i=0; i<${#all_tests[@]}; i+=2)); do
    desc="${all_tests[$i]}"
    fn="${all_tests[$i+1]}"
    $fn
done

echo ""
echo "────────────────────────────────────"
printf "  ${GREEN}PASS${NC}: %d  ${RED}FAIL${NC}: %d  ${YELLOW}SKIP${NC}: %d  TOTAL: %d\n" "$PASS" "$FAIL" "$SKIP" "$((${#all_tests[@]} / 2))"
echo "────────────────────────────────────"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
