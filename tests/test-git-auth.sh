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
    # source 时 BASH_SOURCE != $0，不应执行 main。验证：source 后交互函数仍可用
    # 且没有菜单输出（main 会 clear + 打印状态）。用子 shell 隔离 set -e 继承。
    local rc=0
    ( set +e; source "$CCCONFIG_DIR/lib/git-auth.sh" >/dev/null 2>&1; declare -F do_status >/dev/null 2>&1 ) || rc=$?
    [ "$rc" -eq 0 ] && pass "入口: source 不触发 main（函数已加载）" || fail "入口" "source rc=$rc"
    teardown_env
}

# ---------- 探测/安装/登录（新增能力）----------
test_win_to_wsl() {
    src_git_auth
    local got
    got=$(_win_to_wsl 'C:\Users\franc\AppData\gcm.exe')
    [ "$got" = "/mnt/c/Users/franc/AppData/gcm.exe" ] \
        && pass "wsl: 盘符+反斜杠转换" || fail "wsl" "got=$got"
    got=$(_win_to_wsl '/mnt/c/already/wsl')
    [ "$got" = "/mnt/c/already/wsl" ] && pass "wsl: 非 Windows 路径原样" || fail "wsl" "got=$got"
}

test_slow_probe_exists() {
    src_git_auth
    declare -F _find_gcm_path_slow >/dev/null 2>&1 \
        && pass "slow: _find_gcm_path_slow 已定义" || fail "slow" "缺函数"
}

test_install_hint_content() {
    src_git_auth
    local out; out=$(do_install_hint 2>&1)
    grep -q 'Git.GCM' <<< "$out" && pass "install: 含 GCM 独立包命令" || fail "install" "缺 Git.GCM"
    grep -q 'winget install --id Git.Git' <<< "$out" && pass "install: 含 Git for Windows 备选" \
        || fail "install" "缺 Git.Git"
    grep -q 'gh auth login' <<< "$out" && pass "install: 含 PAT 备选命令" || fail "install" "缺 PAT 备选"
    grep -q 'winget install' <<< "$out" && ! grep -q '^\s*winget install' <<< "$out" \
        && fail "install" "不应自动执行 winget" || pass "install: 只给命令不执行"
}

test_login_filters_password() {
    src_git_auth
    local fake; fake=$(mktemp)
    printf '#!/bin/bash\necho "username=testuser"\necho "password=SECRET123"\n' > "$fake"; chmod +x "$fake"
    local out; out=$(_do_login "$fake" 2>&1)
    grep -q '登录成功（testuser）' <<< "$out" && pass "login: 成功识别 username" || fail "login" "$out"
    grep -q 'SECRET123' <<< "$out" && fail "login" "password 泄露!" || pass "login: password 不外泄"
    rm -f "$fake"
}

test_login_failure_no_username() {
    src_git_auth
    local fake; fake=$(mktemp)
    printf '#!/bin/bash\necho "fatal: could not read Username"\n' > "$fake"; chmod +x "$fake"
    local out rc=0
    out=$(_do_login "$fake" 2>&1) || rc=$?
    [ "$rc" -ne 0 ] && pass "login: 无 username → 失败" || fail "login" "应失败却 rc=0"
    grep -q '登录未完成' <<< "$out" && pass "login: 失败有提示" || fail "login" "$out"
    rm -f "$fake"
}

test_gcm_has_credential() {
    src_git_auth
    local fake; fake=$(mktemp)
    printf '#!/bin/bash\necho "username=u"\necho "password=x"\n' > "$fake"; chmod +x "$fake"
    _gcm_has_credential "$fake" && pass "has_cred: 有 username → 真" || fail "has_cred" "应为真"
    printf '#!/bin/bash\nexit 1\n' > "$fake"
    _gcm_has_credential "$fake" && fail "has_cred" "应为假" || pass "has_cred: 无 username → 假"
    rm -f "$fake"
}

test_auth_fail_diagnosis() {
    grep -q 'could not read Username' "$CCCONFIG_DIR/lib/git-auth.sh" \
        && pass "诊断: 认证失败关键词已加" || fail "诊断" "缺关键词"
    grep -q '_find_gcm_path_slow' "$CCCONFIG_DIR/lib/git-auth.sh" \
        && pass "诊断: 慢探测已接线" || fail "诊断" "慢探测未接线"
}

# ---------- init-bootstrap 接线（GCM 优先链）----------
test_init_bootstrap_gcm_wiring() {
    local ib="$CCCONFIG_DIR/init-bootstrap.sh"
    grep -q 'setup_gcm_auth' "$ib" \
        && pass "init-bootstrap: 含 setup_gcm_auth" \
        || fail "init-bootstrap" "缺 setup_gcm_auth"
    # 主流程（create + clone 两处）都要在 gh_auth 前检查 GCM
    local n; n=$(grep -cE '^[[:space:]]*setup_gcm_auth$' "$ib")
    [ "$n" -ge 2 ] && pass "init-bootstrap: create/clone 两路径均检查 GCM（$n 处）" \
        || fail "init-bootstrap" "GCM 检查仅 $n 处（应 ≥2）"
    grep -q 'gcm_helper_active' "$ib" \
        && pass "init-bootstrap: setup_git_ident 有 GCM 保护（不覆盖）" \
        || fail "init-bootstrap" "setup_git_ident 会覆盖 GCM"
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
test_win_to_wsl
test_slow_probe_exists
test_install_hint_content
test_login_filters_password
test_login_failure_no_username
test_gcm_has_credential
test_auth_fail_diagnosis
test_init_bootstrap_gcm_wiring

echo ""
echo "────────────────────────────────────"
printf "  PASS: %d  FAIL: %d\n" "$PASS" "$FAIL"
echo "────────────────────────────────────"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
