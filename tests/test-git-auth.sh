#!/bin/bash
# test-git-auth.sh — lib/git-auth.sh 纯逻辑单元测试
#
# 覆盖认证状态机的可 mock 部分（不联网、不改真实 gitconfig）：
#   - _redact_user   : Windows 用户名脱敏
#   - _find_gcm_path : gitconfig helper 优先 / 排除模板用户目录
#   - _gcm_status    : ok / not_configured / bad_path 三态
#   - _pat_status    : 无 gh → not_logged_in
#   - 入口守卫       : source 时不触发 main
#
# 手法：GIT_CONFIG_GLOBAL 指向沙箱文件控制 helper 输入。
# 注意：_find_gcm_path 会 fallback 扫真实 /mnt/c/Users（WSL），故 bad_path 用例
# 只断言「函数返回 bad_path 或 ok」之一（取决于本机是否装了 GCM），不断言具体值。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1 — $2"; FAIL=$((FAIL+1)); }

TEST_HOME=""
setup_env() {
    TEST_HOME=$(mktemp -d)
    export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig"
    : > "$GIT_CONFIG_GLOBAL"
}
teardown_env() { [ -n "$TEST_HOME" ] && rm -rf "$TEST_HOME"; }

src_git_auth() { source "$CCCONFIG_DIR/lib/git-auth.sh" >/dev/null 2>&1 || true; }

# ---------- _redact_user ----------
test_redact() {
    setup_env; src_git_auth
    local got
    got=$(_redact_user "/mnt/c/Users/franc/AppData/gcm.exe")
    [ "$got" = "/mnt/c/Users/<user>/AppData/gcm.exe" ] \
        && pass "redact: 用户名已脱敏" || fail "redact" "got=$got"
    got=$(_redact_user "/mnt/c/Program Files/Git/gcm.exe")
    [ "$got" = "/mnt/c/Program Files/Git/gcm.exe" ] \
        && pass "redact: 无用户段原样保留" || fail "redact" "got=$got"
    teardown_env
}

# ---------- _find_gcm_path ----------
test_find_from_gitconfig() {
    setup_env; src_git_auth
    local fake="$TEST_HOME/gcm.exe"; printf '#!/bin/bash\n' > "$fake"; chmod +x "$fake"
    git config --global --add "credential.https://github.com.helper" "!$fake"
    local got; got=$(_find_gcm_path) || true
    [ "$got" = "$fake" ] && pass "find: gitconfig helper 命中" || fail "find" "got=$got"
    teardown_env
}

test_find_excludes_template_dirs() {
    setup_env; src_git_auth
    # 只验证「模板目录名不被当作真实用户」的逻辑：若本机 /mnt/c/Users 下正好
    # 只有模板目录有 exe，不应返回它们。（本机有真实用户目录，故通常返回真实目录。）
    local got; got=$(_find_gcm_path) || true
    case "$got" in
        */Default/*|*/Public/*|*/All\ Users/*|*/Default\ User/*)
            fail "find" "命中模板目录: $got" ;;
        "") pass "find: 未命中任何 exe（含排除模板目录）" ;;
        *)  pass "find: 命中真实目录（模板目录已排除）" ;;
    esac
    teardown_env
}

# ---------- _gcm_status ----------
test_status_not_configured() {
    setup_env; src_git_auth
    [ "$(_gcm_status "")" = "not_configured" ] \
        && pass "status: 无 helper → not_configured" || fail "status" "$(_gcm_status "")"
    git config --global --add "credential.https://github.com.helper" '!gh auth git-credential'
    [ "$(_gcm_status "")" = "not_configured" ] \
        && pass "status: 仅 gh helper → not_configured" || fail "status" "$(_gcm_status "")"
    teardown_env
}

test_status_bad_path_or_ok() {
    setup_env; src_git_auth
    # helper 指向不存在路径。_find_gcm_path 可能 fallback 到真实 GCM（本机装了），
    # 此时 gcm_path 非空但 helper 值本身坏 → 新逻辑应返回 bad_path；
    # 若本机无 GCM → gcm_path 空 → 也 bad_path。两种都接受 bad_path。
    git config --global --add "credential.https://github.com.helper" "!/nonexistent/gcm.exe"
    local p=""; p=$(_find_gcm_path) || true
    local st; st=$(_gcm_status "$p")
    [ "$st" = "bad_path" ] && pass "status: 坏 helper 路径 → bad_path" \
        || fail "status" "期望 bad_path，实得 $st（本机可能另有可达 GCM，find=$p）"
    teardown_env
}

test_status_ok() {
    setup_env; src_git_auth
    local fake="$TEST_HOME/gcm.exe"; printf '#!/bin/bash\n' > "$fake"; chmod +x "$fake"
    git config --global --add "credential.https://github.com.helper" "!$fake"
    [ "$(_gcm_status "$fake")" = "ok" ] && pass "status: 可达 helper → ok" || fail "status" "$(_gcm_status "$fake")"
    teardown_env
}

# ---------- _pat_status ----------
test_pat_status_no_gh() {
    setup_env; src_git_auth
    if command -v gh >/dev/null 2>&1; then
        echo "  ⊘ SKIP pat: 本机有 gh（无法隔离）"
        teardown_env; return
    fi
    [ "$(_pat_status)" = "not_logged_in" ] && pass "pat: 无 gh → not_logged_in" || fail "pat" "$(_pat_status)"
    teardown_env
}

# ---------- 入口守卫 ----------
test_entry_guard() {
    setup_env
    # source 时 BASH_SOURCE != $0，不应执行 main。用子 shell 验证不产生副作用输出。
    local out; out=$( (source "$CCCONFIG_DIR/lib/git-auth.sh") 2>&1 )
    [ -z "$out" ] && pass "入口: source 不触发 main（无输出）" || fail "入口" "source 有输出: $out"
    teardown_env
}

echo ""
echo "git-auth.sh 单元测试"
echo "════════════════════"
echo ""

test_redact
test_find_from_gitconfig
test_find_excludes_template_dirs
test_status_not_configured
test_status_bad_path_or_ok
test_status_ok
test_pat_status_no_gh
test_entry_guard

echo ""
echo "────────────────────────────────────"
printf "  PASS: %d  FAIL: %d\n" "$PASS" "$FAIL"
echo "────────────────────────────────────"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
