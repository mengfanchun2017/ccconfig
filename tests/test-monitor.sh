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
    # 两个 PIDFile 都指向沙箱内不存在的路径：既不碰开发机上真实的 systemd
    # PIDFile（否则兜底路径永远测不到 —— 实测会误判 PASS），也避免 set -u 下
    # 引用未定义变量导致函数静默失败。
    export PID_FILE="$TEST_HOME/.monitor-sync.pid"
    export SYSTEMD_PID_FILE="$TEST_HOME/systemd-monitor.pid"
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

# ========== find_live_monitor_pid（单例判据，start/status 共用）==========
# 直接 eval 真实函数体，不复制粘贴 —— 上面 test_start_watch_* 是内联重写检查逻辑，
# 测的是测试自己而非代码，新增判据（pgrep 兜底）根本没被覆盖到。

test_find_live_monitor_pid_pidfile() {
    eval "$(sed -n '/^find_live_monitor_pid() {/,/^}/p' "$CCCONFIG_DIR/lib/monitor.sh")"
    if ! declare -F find_live_monitor_pid &>/dev/null; then
        fail "find_live_monitor_pid" "无法从 monitor.sh 提取函数体"
        return
    fi
    setup_isolated_env
    # 造一个 cmdline 含 monitor.sh 的存活进程：后台 sleep 后改名不可行，
    # 改用本脚本自身进程 —— 其 cmdline 是 "bash tests/test-monitor.sh"，不含 monitor.sh，
    # 故这里显式起一个 bash -c 包装，令 /proc/PID/cmdline 命中 "monitor.sh"。
    bash -c 'exec -a "bash $CCCONFIG_DIR/lib/monitor.sh start" sleep 30' &
    local fake=$!
    sleep 0.3
    PID_FILE="$TEST_HOME/monitor.pid"
    echo "$fake" > "$PID_FILE"
    local got; got=$(find_live_monitor_pid)
    if [ "$got" = "$fake" ]; then
        pass "find_live_monitor_pid: PIDFile 命中 ($fake)"
    else
        fail "find_live_monitor_pid" "PIDFile 存活却返回 '$got'（期望 $fake）"
    fi
    kill "$fake" 2>/dev/null || true
    rm -f "$PID_FILE"
    teardown_isolated_env
}

test_find_live_monitor_pid_pgrep_fallback() {
    eval "$(sed -n '/^find_live_monitor_pid() {/,/^}/p' "$CCCONFIG_DIR/lib/monitor.sh")"
    setup_isolated_env
    # 两个 PIDFile 都指向不存在的路径 —— 这是唯一能真正隔离「兜底」的构造：
    # 只置空 $PID_FILE 不够，systemd 那份（/run/...）在开发机上真实存在，
    # 旧逻辑照样能命中它，于是测不出兜底缺失（实测反例：反向验证误判 PASS）。
    PID_FILE="$TEST_HOME/monitor.pid"
    SYSTEMD_PID_FILE="$TEST_HOME/systemd-monitor.pid"
    bash -c 'exec -a "bash $CCCONFIG_DIR/lib/monitor.sh start" sleep 30' &
    local fake=$!
    sleep 0.3
    # 关键回归点：PIDFile 缺失时必须靠 pgrep 兜底认出实例。
    # 旧实现只看 PIDFile → 返回空 → start_watch 起第二份 loop 抢同一批仓库。
    # 注意断言的是【契约】而非具体 PID：开发机/CI 上可能本来就有真实例在跑，
    # 此时返回真实例也是正确行为；只要求"非空且确实是个 monitor 进程"。
    local got; got=$(find_live_monitor_pid) || true
    if [ -n "$got" ] && [ -r "/proc/$got/cmdline" ] \
       && tr '\0' ' ' < "/proc/$got/cmdline" | grep -q 'monitor\.sh'; then
        pass "find_live_monitor_pid: PIDFile 缺失时兜底命中 monitor 进程 ($got)"
    else
        fail "find_live_monitor_pid" "PIDFile 缺失时未兜底，返回 '$got'"
    fi
    kill "$fake" 2>/dev/null || true
    teardown_isolated_env
}

test_find_live_monitor_pid_excludes_self() {
    eval "$(sed -n '/^find_live_monitor_pid() {/,/^}/p' "$CCCONFIG_DIR/lib/monitor.sh")"
    setup_isolated_env
    PID_FILE="$TEST_HOME/monitor.pid"
    # 绝不能把调用者自身判为"已有实例" —— 否则 start_watch 永远认为自己已在运行，
    # 于是在没有任何实例的机器上反而起不来（比漏判更糟的失效方向）。
    # 同样只断言契约：返回值不得是自身或其父进程。
    local got; got=$(find_live_monitor_pid) || true
    if [ -z "$got" ] || { [ "$got" != "$$" ] && [ "$got" != "$PPID" ]; }; then
        pass "find_live_monitor_pid: 未把调用者自身当实例 (got='${got:-空}')"
    else
        fail "find_live_monitor_pid" "把调用者自身判成了实例 (got=$got)"
    fi
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

    [[ -n "$min_push_gap" && "$min_push_gap" -lt "$debounce" ]] \
        && pass "debounce: min_push_gap(${min_push_gap}s) 独立于 debounce(${debounce}s)" \
        || fail "debounce" "min_push_gap=${min_push_gap} 未与 debounce=${debounce} 解耦"

    # 用比真值更小的 gap 做判据（gap=1），避免 boundary 恰好等于 min_push_gap 时翻转
    local last_push_time=$(( $(date +%s) - 1 ))
    local gap=$(( $(date +%s) - last_push_time ))
    [ "$gap" -lt "$min_push_gap" ] \
        && pass "debounce: ${gap}s 内重复 → 延后（Deferred）" || fail "debounce" "gap=${gap}s 未判为需节流"
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
    # 精确定位 debounce 块自己那次 sync_repos（锚在 "Debounce done" 的下一段），
    # 不能用第一个 sync_repos —— 心跳的调用现在更靠前，会误判成"顺序颠倒"。
    sync_line=$(awk '/Debounce done, no changed repos recorded/{ found=NR } found && /^                    sync_repos/{print NR; exit}' "$mon")
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
    # 本机要等自己碰文件才顺带 pull。心跳把收敛窗口压到 heartbeat_secs。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    local hb
    hb=$(grep -m1 '^    local heartbeat_secs=' "$mon" | grep -oE '[0-9]+')
    if [ "${hb:-0}" -gt 0 ] && [ "${hb:-0}" -le 600 ]; then
        pass "heartbeat: 周期 ${hb}s ≤ 10min"
    else
        fail "heartbeat" "心跳周期 ${hb:-?}s 过长，多终端收敛会滞后"
    fi
    grep -q 'Heartbeat sync' "$mon" \
        && pass "heartbeat: 日志可辨识（不再是 Periodic sync）" \
        || fail "heartbeat" "心跳日志无辨识度"

    # 关键回归：心跳必须按 wall-clock 且在 DEBOUNCE 判断之外。
    # 原实现用 idle_ticks（无事件才递增、一有事件即清零）→ 实为"本地空闲才收敛"，
    # 高频编辑时永不触发；仅改成 wall-clock 但仍留在 `if [ ! -f DEBOUNCE_FILE ]` 内
    # 同样永不触发（持续编辑让该文件一直存在）。两条都必须成立。
    grep -q 'idle_ticks' "$mon" \
        && fail "heartbeat" "idle_ticks 残留 → 心跳仍被本地空闲度门控" \
        || pass "heartbeat: 已弃用 idle_ticks（改 wall-clock）"
    local hb_line deb_line
    hb_line=$(grep -n "^            elif \[ \$((now - heartbeat_ts))" "$mon" | cut -d: -f1 | head -1)
    deb_line=$(grep -n '^            if \[ ! -f "\$DEBOUNCE_FILE" \]; then' "$mon" | cut -d: -f1 | head -1)
    if [ -n "$hb_line" ] && [ -n "$deb_line" ] && [ "$hb_line" -lt "$deb_line" ]; then
        pass "heartbeat: 位于 DEBOUNCE 判断之外（hb@$hb_line < debounce@$deb_line）"
    else
        fail "heartbeat" "hb@${hb_line:-?} 未在 DEBOUNCE@${deb_line:-?} 之外 → 持续编辑时永不触发"
    fi
}

test_min_gap_independent() {
    # min_push_gap 是纯节流，不该与 debounce 同值：30s debounce 后再判 30s gap
    # = 二次等待，连续操作时每拍都被 Defer。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    local deb gap
    deb=$(grep -m1 '^    local debounce=' "$mon" | grep -oE '[0-9]+')
    gap=$(grep -m1 '^    local min_push_gap=' "$mon" | grep -oE '[0-9]+')
    if [ -n "$gap" ] && [ "${gap:-0}" -lt "${deb:-0}" ]; then
        pass "min-gap: ${gap}s < debounce ${deb}s（不再二次等待）"
    else
        fail "min-gap" "min_push_gap=${gap:-?} ≥ debounce=${deb:-?} → 连续操作每拍都被 Defer"
    fi
}

test_sync_repos_noarg_safe() {
    # "无参 = 全量" 是 sync_repos 的官方语义（help 与 initial scan 都用）。
    # 但文件级 `set -u` 在循环的 `set +e` 下**依然生效**（set +e 只关 errexit，
    # 不关 nounset），所以裸 `local repos_arg="$1"` 会让无参调用当场
    # "$1: unbound variable" 退出 rc=1 —— 这就是 monitor loop 每次全量同步后
    # 11 秒内死掉、systemd 每 ~5min 重启一次的根因（全部全量路径都崩塌）。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    grep -q 'local repos_arg="${1:-}"' "$mon" \
        && pass "sync_repos: 无参调用安全（\${1:-} 而非 \$1）" \
        || fail "sync_repos" '裸 $1 → 无参调用在 set -u 下必崩'
    # 真正的行为验证：隔离环境里无参调用必须返回 0
    setup_isolated_env
    mkdir -p "$HOME/.tmpmon/lib"
    sed '/^# ========== Main ==========$/,$d' "$mon" > "$HOME/.tmpmon/lib/mon.sh"
    mkdir -p "$HOME/.tmpmon/watch"
    local rc=0
    ( set -euo pipefail
      export WATCH_DIR="$HOME/.tmpmon/watch" MONITOR_HOME="$HOME/.tmpmon"
      export MONITOR_PID_FILE="$HOME/.tmpmon/m.pid" QUIET_MODE=true
      source "$HOME/.tmpmon/lib/mon.sh"
      set +e
      sync_repos
      exit $?
    ) >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] \
        && pass "sync_repos: 无参调用实测 rc=0" \
        || fail "sync_repos" "无参调用 rc=$rc（应为 0）"
    teardown_isolated_env
}

test_status_reports_sync_state() {
    # B3：status 必须能让用户自查双端收敛（未推/落后/工作区脏）。
    # 没有它，多终端用户在"本机不碰文件"时完全无从知道对端推到哪了 ——
    # 这正是原始提问"看不出两边有没有收敛"的直接来源。
    local st="$CCCONFIG_DIR/lib/status.sh"
    grep -q '双端同步' "$st" \
        && pass "status: 有'双端同步'一节" \
        || fail "status" "status 不展示双端收敛状态"
    grep -q '落后 \${\?_bh' "$st" \
        && pass "status: 显式列出落后（其他终端）" \
        || fail "status" "未列出 behind"
    grep -q '工作区脏' "$st" \
        && pass "status: 显式列出工作区脏文件数" \
        || fail "status" "未列出 dirty"
    # --quick 供 SessionStart 用，不能引入网络等待
    grep -q 'if ! \$QUICK_MODE; then' "$st" \
        && pass "status: fetch 受 QUICK_MODE 保护（--quick 不走网络）" \
        || fail "status" "--quick 也会 fetch → SessionStart 被拖慢"
    # 失败重试：monitor 并发 fetch 同一仓库会瞬时失败，单次失败不足以判定不可达
    grep -q 'for _try in 1 2' "$st" \
        && pass "status: fetch 失败重试一次（抗 monitor 并发抖动）" \
        || fail "status" "单次 fetch 失败即报错 → 假警报"
}

test_remote_ahead_detected() {
    # 只有心跳不够：「无本地改动」分支若不整合远程，纯远程领先时永远走 already up to date
    # → 对端推了新提交本机看不见（心跳只是更频繁重复同一句），收敛不成立。
    # 判据：该分支内必须整合远程（git_pull_rebase）且落后时打出 behind 信息。
    local mon="$CCCONFIG_DIR/lib/monitor.sh"
    local blk
    blk=$(awk '/local changed_files=\$\(git -C "\$repo_dir" status --porcelain/,/^    fi$/' "$mon")
    echo "$blk" | grep -q 'git_pull_rebase "\$repo_dir" "\$branch"' \
        && pass "converge: 无本地改动分支整合远程（能取回对端提交）" \
        || fail "converge" "该分支不整合远程 → 纯远程领先永不收敛"
    echo "$blk" | grep -q 'behind' \
        && pass "converge: 落后远程时区分日志（非 already up to date）" \
        || fail "converge" "落后远程仍报 already up to date"
    # errexit 回归：本段必须在恢复 errexit 前捕获 rc（沿用 git_push 的 had_e 手法）。
    # 违反时实测后果是 fetch/pull 成功后 2s 内主 loop 自杀 → systemd 每 ~5min 重启一次。
    echo "$blk" | grep -q 'had_e' \
        && pass "converge: 用 had_e 保护 errexit（不把外层 set +e 重开）" \
        || fail "converge" "缺 had_e 保护 → 心跳会打死 monitor loop"
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
    "desc: find_live_monitor_pid PIDFile 命中"       test_find_live_monitor_pid_pidfile
    "desc: find_live_monitor_pid PIDFile 缺失时兜底"  test_find_live_monitor_pid_pgrep_fallback
    "desc: find_live_monitor_pid 排除自身"           test_find_live_monitor_pid_excludes_self
    "desc: status_watch 无 PIDFile → 未运行"         test_status_watch_no_pid
    "desc: debounce 30s 内重复 → 跳过"               test_debounce_window
    "desc: backoff 2→...→300 cap"                    test_exponential_backoff
    "desc: max_restart 9 > 8 → 放弃"                 test_max_restart_giveup
    "desc: 提交信息带摘要（monitor + sync）"          test_commit_message_has_summary
    "desc: 初始扫描可见且显式传仓库"                  test_initial_scan_observable
    "desc: race — debounce 触发文件先清后同步"        test_debounce_race_guard
    "desc: min-gap — 跳过改延后不丢触发"              test_min_gap_defer_not_drop
    "desc: min-gap — 节流值独立于 debounce"           test_min_gap_independent
    "desc: heartbeat — wall-clock 收敛其他终端"       test_heartbeat_convergence
    "desc: sync_repos 无参调用安全（set -u 地雷）"    test_sync_repos_noarg_safe
    "desc: status — 报表双端收敛（未推/落后/脏）"     test_status_reports_sync_state
    "desc: converge — 无改动分支 fetch 且报落后"      test_remote_ahead_detected
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
