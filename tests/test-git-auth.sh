#!/bin/bash
# test-git-auth.sh — lib/git-auth.sh 纯逻辑单元测试
#
# 覆盖认证状态机的可 mock 部分（不联网、不改真实 gitconfig）：
#   - _redact_user      : Windows 用户名脱敏
#   - _find_gcm_path    : gitconfig helper 优先 / 多用户目录排除模板目录
#   - _gcm_status       : ok / not_configured / bad_path 三态
#   - _pat_status       : 无 gh / gh 未登录 → not_logged_in
#
# 手法：GIT_CONFIG_GLOBAL 指向沙箱文件，用假 helper 控制输入。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1 — $2"; FAIL=$((FAIL+1)); }

TEST_HOME=""
setup_env() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig"
    : > "$GIT_CONFIG_GLOBAL"
    unset GIT_CONFIG_NOSYSTEM 2>/dev/null || true
}
teardown_env() { [ -n "$TEST_HOME" ] && rm -rf "$TEST_HOME"; }

# 只 source 函数定义，不触发 main（git-auth.sh 末行有 BASH_SOURCE 守卫）
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
    # 造 Default/Public 两个模板目录，各放一个可达 exe；真实用户目录没有
    for ud in "Default" "Public" "All Users"; do
        local d="/mnt/c/Users/$ud/AppData/Local/Programs/MinGit/ucrt64/bin"
        mkdir -p "$d" 2>/dev/null || true
        printf '#!/bin/bash\n' > "$d/git-credential-manager.exe" 2>/dev/null || true
        chmod +x "$d/git-credential-manager.exe" 2>/dev/null || true
    done
    # /mnt/c 在 WSL 上不可写时此用例无意义 → 跳过
    if [ ! -w /mnt/c/Users ] 2>/dev/null && [ ! -d /mnt/c/Users/Default ]; then
        skip=1
    fi
    local got; got=$(_find_gcm_path) || true
    # 期望：不返回模板目录下的 exe
    case "$got" in
        */Default/*|*/Public/*|*/All\ Users/*) fail "find" "命中模板目录: $got" ;;
        "") pass "find: 跳过模板目录（无可返回）" ;;
        *) pass "find: 跳过模板目录（命中真实目录 $got）" ;;
    esac
    teardown_env
}

# ---------- _gcm_status ----------
test_status_not_configured() {
    setup_env; src_git_auth
    # 无任何 helper
    [ "$(_gcm_status "")" = "not_configured" ] && pass "status: 无 helper → not_configured" || fail "status" "$(_gcm_status "")"
    # 只有 gh helper（非 GCM）
    git config --global --add "credential.https://github.com.helper" '!gh auth git-credential'
    [ "$(_gcm_status "")" = "not_configured" ] && pass "status: 仅 gh helper → not_configured" || fail "status" "$(_gcm_status "")"
    teardown_env
}

test_status_bad_path() {
    setup_env; src_git_auth
    # helper 指向不存在的路径，且系统里没有别的可达 GCM → bad_path
    git config --global --add "credential.https://github.com.helper" "!/nonexistent/gcm.exe"
    local p=""; p=$(_find_gcm_path) || true
    [ "$(_gcm_status "$p")" = "bad_path" ] && pass "status: helper 坏路径 → bad_path" || fail "status" "$(_gcm_status "$p")"
    teardown_env
}

test_status_ok() {
    setup_env; src_git_auth
    local fake="$TEST_HOME/gcm.exe"; printf '#!/bin/bash\n' > "$fake"; chmod +x "$fake"
    git config --global --add "credential.https://github.com.helper" "!$fake"
    local p="$fake"
    [ "$(_gcm_status "$p")" = "ok" ] && pass "status: 可达 helper → ok" || fail "status" "$(_gcm_status "$p")"
    teardown_env
}

# ---------- _pat_status ----------
test_pat_status_no_gh() {
    setup_env; src_git_auth
    # PATH 里没有 gh → not_logged_in
    PATH="$TEST_HOME:/usr/bin:/bin"
    command -v gh >/dev/null 2>&1 && { echo "  ⊘ SKIP pat: 本机有 gh"; teardown_env; return; }
    [ "$(_pat_status)" = "not_logged_in" ] && pass "pat: 无 gh → not_logged_in" || fail "pat" "$(_pat_status)"
    teardown_env
}

# ---------- 入口契约（不执行交互） ----------
test_entry_guard() {
    # source 时不应执行 main（BASH_SOURCE 守卫）
    setup_env
    ( source "$CCCONFIG_DIR/lib/git-auth.sh" ) && pass "入口: source 不触发 main" || fail "入口" "source 触发了 main"
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
test_status_bad_path
test_status_ok
test_pat_status_no_gh
test_entry_guard

echo ""
echo "────────────────────────────────────"
printf "  PASS: %d  FAIL: %d\n" "$PASS" "$FAIL"
echo "────────────────────────────────────"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
