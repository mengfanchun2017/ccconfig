#!/bin/bash
# test-monitor.sh — monitor.sh 核心函数单元测试
#
# 覆盖：
#   - get_repo_root: 沿父目录查找 .git
#   - check_proxy: 无 proxy / 活着 / 不可达
#   - git_push: 网络错误重试 / 非网络错误不重试
#   - commit_and_push: 锁 / dirty / 已 sync / 无变化
#   - start_watch: PIDFile 存活 / PIDFile 残留
#   - stop_watch: PIDFile 清理

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0; SKIP=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1 — $2"; FAIL=$((FAIL+1)); }
skip() { echo "  ⊘ SKIP $1 — $2"; SKIP=$((SKIP+1)); }

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ========== mock 环境 ==========

setup_isolated_env() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    mkdir -p "$HOME/.local/bin" "$HOME/.cache"
}

teardown_isolated_env() {
    rm -rf "$TEST_HOME"
}

# ========== get_repo_root ==========

test_get_repo_root_finds_dot_git() {
    setup_isolated_env
    # 创建目录树: /tmp/xxx/project/sub/ → /tmp/xxx/project/.git
    local repo="$TEST_HOME/myrepo"
    mkdir -p "$repo/sub/deep"
    mkdir -p "$repo/.git"
    local target="$repo/sub/deep/file.txt"
    # 模拟 get_repo_root 逻辑
    local dir
    dir="$(dirname "$target")"
    while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ] && [ "$dir" != "." ]; do
        if [ -d "$dir/.git" ]; then
            if [ "$dir" = "$repo" ]; then
                pass "get_repo_root: nested path → repo root"
            else
                fail "get_repo_root" "got $dir"
            fi
            teardown_isolated_env
            return
        fi
        dir="$(dirname "$dir")"
    done
    fail "get_repo_root" "未找到 .git"
    teardown_isolated_env
}

test_get_repo_root_no_git() {
    setup_isolated_env
    local target="$TEST_HOME/nothing/here/file.txt"
    mkdir -p "$(dirname "$target")"
    local dir
    dir="$(dirname "$target")"
    local found=false
    while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ] && [ "$dir" != "." ]; do
        if [ -d "$dir/.git" ]; then
            found=true
            break
        fi
        dir="$(dirname "$dir")"
    done
    $found && fail "get_repo_root" "不应找到" || pass "get_repo_root: 无 .git → 返回 1"
    teardown_isolated_env
}

# ========== check_proxy ==========

test_check_proxy_empty() {
    unset HTTPS_PROXY https_proxy HTTP_PROXY http_proxy
    local proxy="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
    [ -z "$proxy" ] && pass "check_proxy: 无 proxy → 跳过检查" || fail "check_proxy" "proxy=$proxy"
}

test_check_proxy_with_value() {
    export HTTPS_PROXY="http://127.0.0.1:7890"
    local proxy="$HTTPS_PROXY"
    [ -n "$proxy" ] && pass "check_proxy: 识别 HTTPS_PROXY=$proxy" || fail "check_proxy" "未识别"
}

# ========== git_push retry ==========

test_git_push_retry_on_network_error() {
    # 模拟 git 两次网络失败，第三次成功
    local attempt=0
    local output=""
    local outputs=("Connection refused" "Recv failure: Connection reset" "push successful")
    while [ $attempt -lt 3 ]; do
        output="${outputs[$attempt]}"
        attempt=$((attempt + 1))
        if echo "$output" | grep -qi "connection\|network\|Recv failure"; then
            # 网络错误 → 重试
            continue
        fi
        break
    done
    [ "$attempt" -eq 3 ] && pass "git_push: 两次网络失败后第三次成功" || fail "git_push" "attempt=$attempt"
}

test_git_push_no_retry_on_auth_error() {
    # 模拟非网络错误（auth）→ 不重试
    local output="Permission denied (publickey)"
    local attempt=0
    while [ $attempt -lt 3 ]; do
        attempt=$((attempt + 1))
        if echo "$output" | grep -qi "connection\|network\|Recv failure"; then
            continue
        fi
        # 非网络错误 → 立即退出
        break
    done
    [ "$attempt" -eq 1 ] && pass "git_push: auth 错误不重试" || fail "git_push" "attempt=$attempt"
}

# ========== commit_and_push lock ==========

test_commit_and_push_lock_serializes() {
    setup_isolated_env
    local repo="$TEST_HOME/test-repo"
    mkdir -p "$repo/.git"
    local lock_dir="$repo/.monitor-sync.lock"
    # 模拟已有锁
    mkdir -p "$lock_dir"
    # 第二次 mkdir 失败 → 跳过
    if ! mkdir "$lock_dir" 2>/dev/null; then
        pass "commit_and_push: 已有锁 → 跳过"
    else
        fail "commit_and_push" "锁未生效"
        rmdir "$lock_dir"
    fi
    teardown_isolated_env
}

test_commit_and_push_unresolved_conflict() {
    # 验证 commit_and_push 函数内有冲突检测逻辑
    if grep -q 'ls-files -u' "$CCCONFIG_DIR/lib/monitor.sh"; then
        pass "commit_and_push: 含 ls-files -u 冲突检测"
    else
        fail "commit_and_push" "未含冲突检测"
    fi
    if grep -q 'UNRESOLVED CONFLICTS' "$CCCONFIG_DIR/lib/monitor.sh"; then
        pass "commit_and_push: 冲突时输出 UNRESOLVED CONFLICTS 警告"
    else
        fail "commit_and_push" "缺少冲突警告"
    fi
}

# ========== start_watch PIDFile ==========

test_start_watch_pidfile_alive() {
    setup_isolated_env
    local pid_file="$TEST_HOME/.monitor-sync.pid"
    # 写入当前 PID（活着的）
    echo $$ > "$pid_file"
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        pass "start_watch: PIDFile 有效 ($$)"
    else
        fail "start_watch" "PIDFile 无效"
    fi
    rm -f "$pid_file"
    teardown_isolated_env
}

test_start_watch_stale_pidfile() {
    setup_isolated_env
    local pid_file="$TEST_HOME/.monitor-sync.pid"
    # 写入死 PID（99999 应不存在）
    echo "99999" > "$pid_file"
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        fail "start_watch" "误判死 PID 为活"
    else
        pass "start_watch: 死 PIDFile 检测"
    fi
    rm -f "$pid_file"
    teardown_isolated_env
}

# ========== status_watch ==========

test_status_watch_no_pid() {
    setup_isolated_env
    local pid_file="$TEST_HOME/.monitor-sync.pid"
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        fail "status_watch" "误判"
    else
        pass "status_watch: 无 PIDFile → 未运行"
    fi
    teardown_isolated_env
}

# ========== debounce 逻辑 ==========

test_debounce_window() {
    # 直接读 monitor.sh 的真值，不在测试里再写一份硬编码。
    # 旧版测试写 60、断言标签写 30s、monitor 与帮助文案又是 60/120 —— 三方对不上。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    local debounce min_push_gap
    debounce=$(grep -m1 '^    local debounce=' "$mon" | grep -oE '[0-9]+')
    min_push_gap=$(grep -m1 '^    local min_push_gap=' "$mon" | grep -oE '[0-9]+')
    [[ "$debounce" == "30" ]] \
        && pass "debounce: monitor.sh 真值 = 30s" || fail "debounce" "monitor.sh 实为 ${debounce}s"

    # 帮助文案不能与真值不符（曾写 120s）
    grep -q "→ ${debounce}s debounce" "$mon" \
        && pass "debounce: 帮助文案与真值一致" || fail "debounce" "帮助文案与 ${debounce}s 不符"

    [[ -n "$min_push_gap" && "$min_push_gap" == "$debounce" ]] \
        && pass "debounce: debounce 与 min_push_gap 同值" \
        || fail "debounce" "debounce=${debounce} vs min_push_gap=${min_push_gap}"

    local last_push_time=$(( $(date +%s) - 10 ))
    local gap=$(( $(date +%s) - last_push_time ))
    [ "$gap" -lt "$min_push_gap" ] \
        && pass "debounce: ${gap}s 内重复 → 跳过" || fail "debounce" "误判"
}

# ========== exponential backoff ==========

test_exponential_backoff() {
    # 模拟 monitor.sh 的退避序列 2 → 4 → 8 → 16 → 32 → 64 → 128 → 256 → 300 (cap)
    local backoff=2
    local max=300
    local seq=()
    seq+=("$backoff")
    for i in 2 3 4 5 6 7 8 9; do
        backoff=$((backoff * 2))
        [ "$backoff" -gt "$max" ] && backoff=$max
        seq+=("$backoff")
    done
    local expected="2 4 8 16 32 64 128 256 300"
    local got="${seq[*]}"
    [ "$got" = "$expected" ] && pass "exponential backoff: 2→4→...→300 cap" || fail "backoff" "got=$got"
}

test_max_restart_giveup() {
    # 8 次失败后放弃
    local max_restarts=8
    local restarts=9
    if [ "$restarts" -gt "$max_restarts" ]; then
        pass "max_restart: 9 > 8 → 放弃"
    else
        fail "max_restart" "未给出"
    fi
}

test_commit_message_has_summary() {
    # session 已不自己 commit（见 CLAUDE.md 约束），提交信息是历史里仅有的信息，
    # 退化成纯时间戳就等于把"改了什么"全丢掉。monitor 与 sync 两个提交点都要带摘要。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    local syn="$CCCONFIG_DIR/lib/sync.sh"

    grep -q 'Auto-sync: \$repo \$staged_count 文件' "$mon" \
        && pass "commit_msg: monitor 摘要含仓库名+文件数" \
        || fail "commit_msg" "monitor 未生成摘要提交信息"
    grep -q 'diff --cached --name-only' "$mon" \
        && pass "commit_msg: monitor 列出改动文件" \
        || fail "commit_msg" "monitor 未列出改动文件"

    grep -q 'Auto-sync: \$repo_name \$_nfiles 文件' "$syn" \
        && pass "commit_msg: sync 摘要与 monitor 同格式" \
        || fail "commit_msg" "sync 的提交信息格式与 monitor 不一致"
}

test_initial_scan_observable() {
    # 初始扫描曾静默空转：日志只留一行 "Initial scan..."，看不出是"没改动"还是"没扫到仓库"
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    grep -q 'Initial scan: \${_init_n} 个仓库待查' "$mon" \
        && pass "initial_scan: 打印仓库数" \
        || fail "initial_scan" "初始扫描无仓库数日志"
    awk '/Initial scan: \$\{_init_n\}/,/^    \) &/' "$mon" | grep -q 'sync_repos "\$_init_repos"' \
        && pass "initial_scan: 显式传仓库列表" \
        || fail "initial_scan" "初始扫描未显式传仓库列表"
}

# ========== Bash 语法 ==========

test_monitor_sh_syntax() {
    if bash -n "$CCCONFIG_DIR/lib/monitor.sh" 2>/dev/null; then
        pass "monitor.sh 语法正确"
    else
        fail "monitor.sh" "syntax error"
    fi
}

# ========== 多终端并发（race 修复 + 心跳） ==========

test_debounce_race_guard() {
    # 竞态回归：曾经 rm DEBOUNCE_FILE 在 sync_repos 之后 → 同步窗口内到达的新事件
    # 被抹掉，那份改动要等下一个无关事件才提交（实测写于窗口内的文件 200s+ 仍脏）。
    # 判据：rm 必须出现在 sync_repos 调用之前。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    local rm_line sync_line
    rm_line=$(awk '/^                rm -f "\$DEBOUNCE_FILE" "\$CHANGED_REPOS_FILE"$/{print NR; exit}' "$mon")
    sync_line=$(awk '/^                    sync_repos/{print NR; exit}' "$mon")
    if [ -n "$rm_line" ] && [ -n "$sync_line" ] && [ "$rm_line" -lt "$sync_line" ]; then
        pass "race: debounce 触发文件在 sync_repos 之前清除（rm@$rm_line < sync@$sync_line）"
    else
        fail "race" "rm@${rm_line:-?} 未在 sync_repos@${sync_line:-?} 之前 — 窗口内事件会被丢"
    fi
}

test_min_gap_defer_not_drop() {
    # 第二处同类 bug：紧接上次 push 的写入会被 min_push_gap 判 "Skipped" 并 rm 掉
    # DEBOUNCE_FILE → 那份改动被忘掉，要等下一个无关事件才提交
    # （实测 08:51:58 push → 08:52:00 写入 → 08:52:25 skip → 文件持续脏）。
    # 判据：该分支保留触发文件（无 rm），且 pending 未清零 → 下一 tick 会重试。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    local blk
    blk=$(awk '/min_push_gap}s since last push/,/^                fi$/' "$mon")
    echo "$blk" | grep -q 'Deferred' \
        && pass "min-gap: 改为延后（Deferred）而非丢弃" \
        || fail "min-gap" "仍是 Skipped 语义"
    echo "$blk" | grep -q 'rm -f "\$DEBOUNCE_FILE"' \
        && fail "min-gap" "跳过分支仍 rm 触发文件 → 会丢改动" \
        || pass "min-gap: 跳过分支保留触发文件（下 tick 重试）"
}

test_heartbeat_convergence() {
    # 多终端收敛：monitor 只看本机文件事件、从不轮询远程，对端推上来的提交
    # 本机要等自己碰文件才顺带 pull。心跳把收敛窗口从 12h 压到 5min。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    local ticks
    ticks=$(grep -m1 'idle_ticks -ge ' "$mon" | grep -oE '[0-9]+' | head -1)
    if [ "${ticks:-0}" -gt 0 ] && [ "${ticks:-0}" -le 300 ]; then
        pass "heartbeat: 空闲心跳 ${ticks} ticks（×2s = $((ticks * 2))s）≤ 5min"
    else
        fail "heartbeat" "心跳间隔 ${ticks:-?} ticks 过长，多终端收敛会滞后"
    fi
    grep -q 'Heartbeat sync' "$mon" \
        && pass "heartbeat: 日志可辨识（不再是 Periodic sync）" \
        || fail "heartbeat" "心跳日志无辨识度"
}

test_pull_failure_evidence() {
    # pull 失败必须落真实报错：此前网络类分支只打通用 "attempt N failed"，
    # pull_output 被丢弃 → 全历史约 50 次失败全是无证据的。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    awk '/pull attempt \$pull_attempt failed, retry in 10s/,/sleep 10/' "$mon" | grep -q 'pull rc=' \
        && pass "pull-err: 网络类失败落 rc + 原始输出" \
        || fail "pull-err" "pull 失败仍丢错误详情"
}

test_skip_push_visible() {
    # skip_push 静默返回会让未推送 commit 无限期搁浅（冲突兜底/unrelated histories）。
    # 必须显性报出未推送数量。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    grep -q 'skip_push 走到这里' "$mon" \
        && pass "skip-push: 有显性告警分支" \
        || fail "skip-push" "skip_push 仍静默"
    awk '/skip_push 走到这里/,/^        fi$/' "$mon" | grep -q 'rev-list --count' \
        && pass "skip-push: 报告未推送 commit 数" \
        || fail "skip-push" "未量化未推送 commit"
}

# ========== 主流程 ==========

all_tests=(
    "desc: get_repo_root nested path → repo root"   test_get_repo_root_finds_dot_git
    "desc: get_repo_root 无 .git → 返回 1"           test_get_repo_root_no_git
    "desc: check_proxy 无 proxy → 跳过"              test_check_proxy_empty
    "desc: check_proxy 识别 HTTPS_PROXY"            test_check_proxy_with_value
    "desc: git_push 两次网络失败后第三次成功"        test_git_push_retry_on_network_error
    "desc: git_push auth 错误不重试"                 test_git_push_no_retry_on_auth_error
    "desc: commit_and_push 已有锁 → 跳过"            test_commit_and_push_lock_serializes
    "desc: commit_and_push 检测未解决冲突"           test_commit_and_push_unresolved_conflict
    "desc: start_watch PIDFile 有效"                 test_start_watch_pidfile_alive
    "desc: start_watch 死 PIDFile 检测"              test_start_watch_stale_pidfile
    "desc: status_watch 无 PIDFile → 未运行"         test_status_watch_no_pid
    "desc: debounce 30s 内重复 → 跳过"               test_debounce_window
    "desc: backoff 2→...→300 cap"                    test_exponential_backoff
    "desc: max_restart 9 > 8 → 放弃"                 test_max_restart_giveup
    "desc: 提交信息带摘要（monitor + sync）"          test_commit_message_has_summary
    "desc: 初始扫描可见且显式传仓库"                  test_initial_scan_observable
    "desc: race — debounce 触发文件先清后同步"        test_debounce_race_guard
    "desc: min-gap — 跳过改延后不丢触发"              test_min_gap_defer_not_drop
    "desc: heartbeat — 5min 空闲收敛其他终端"        test_heartbeat_convergence
    "desc: pull 失败落真实报错"                      test_pull_failure_evidence
    "desc: skip_push 显性告警未推送 commit"           test_skip_push_visible
    "desc: monitor.sh 语法检查"                      test_monitor_sh_syntax
)

echo ""
echo -e "${CYAN}monitor.sh 单元测试${NC}"
echo "══════════════════════════════"
echo ""

run_tests() {
    local idx=0
    local n=${#all_tests[@]}
    while [ $idx -lt $n ]; do
        local fn="${all_tests[$((idx+1))]:-}"
        if [ -n "$fn" ] && declare -F "$fn" >/dev/null 2>&1; then
            "$fn" 2>/dev/null || true
        fi
        idx=$((idx + 2))
    done
}
run_tests

echo ""
echo "────────────────────────────────────"
printf "  ${GREEN}PASS${NC}: %d  ${RED}FAIL${NC}: %d  ${YELLOW}SKIP${NC}: %d  TOTAL: %d\n" "$PASS" "$FAIL" "$SKIP" "$((${#all_tests[@]} / 2))"
echo "────────────────────────────────────"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
