#!/bin/bash
# Git Monitor - Multi-repo file monitoring & auto-sync (Linux/WSL)
#
# Watches ~/git/ for changes in ALL git repos, auto-commits and pushes.
#
# Usage:
#   start              Start monitoring in background (silent)
#   stop               Stop monitoring
#   status             Show status
#   log [N]            Show last N log lines (default: 30)
#   monitor            Frontend: show file changes live
#   tail               Frontend: follow push results
#
# Install inotifywait: bash lib/install-inotify.sh（apt 优先 → 免 sudo deb 提取 + wrapper）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/dry-run.sh"
if [ -d "$SCRIPT_DIR/.git" ]; then
    MONITOR_HOME="$SCRIPT_DIR"
else
    MONITOR_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
PID_FILE="${MONITOR_PID_FILE:-$MONITOR_HOME/.monitor-sync.pid}"
# systemd 实例写的 PIDFile（unit 里 MONITOR_PID_FILE=/run/claude-auto-sync/monitor.pid）。
# 可覆盖：测试要隔离「两个 PIDFile 都不存在 → 只能靠 pgrep 兜底」这条路径，
# 硬编码路径会让开发机上真实存在的那份永远命中，测不出兜底。
SYSTEMD_PID_FILE="${MONITOR_SYSTEMD_PID_FILE:-/run/claude-auto-sync/monitor.pid}"
LOG_FILE="$MONITOR_HOME/.monitor-sync.log"
DEBOUNCE_FILE="$MONITOR_HOME/.monitor-sync.debounce"
CHANGED_REPOS_FILE="$MONITOR_HOME/.monitor-sync.changed-repos"
WATCH_DIR="$HOME/git"

export PATH="$HOME/.local/bin:$PATH"
# 展开必须把 ~/.local/lib 无条件放进去：写成 ${VAR:+$HOME/.local/lib:$VAR} 时
# VAR 未设 → 整个展开为空，库路径根本没加（免 sudo 装的 libinotifytools.so.0 找不到）
export LD_LIBRARY_PATH="$HOME/.local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Colors
source "$SCRIPT_DIR/colors.sh"

# Quiet mode for start command
QUIET_MODE=false

# Log to file (always). 子进程输出（init-skill/setup-links/git）non-tty 仍带色，统一剥掉存纯文本
strip_ansi() { sed -r 's/\x1B\[[0-9;]*[mK]//g'; }

do_log() {
    { echo "[$(date '+%H:%M:%S')] $1"; } | strip_ansi >> "$LOG_FILE"
}

# Log to terminal + file
log()    { do_log "$1"; $QUIET_MODE && return; echo -e "${GREEN}[SYNC]${NC} $1"; }
# 仅写日志文件、不刷终端：常规无变化用。心跳（每 5min × 每仓）会把
# "already up to date" 刷成噪音，但它仍是排查时的时间锚点，故不删只降级。
logq()   { do_log "$1"; }
warn()   { do_log "WARN: $1"; $QUIET_MODE && return; echo -e "${YELLOW}[SYNC]${NC} $1"; }
info()   { do_log "$1"; $QUIET_MODE && return; echo -e "${CYAN}[SYNC]${NC} $1"; }
error()  { do_log "ERROR: $1"; $QUIET_MODE && return; echo -e "${RED}[SYNC]${NC} $1"; }

# PAT 失效检测改为 on-failure-only：git_push auth error 时提示续期，不再周期巡检过期天数

# ========== Git helpers ==========

# Given a file path, find the nearest parent with .git/
get_repo_root() {
    local dir="${1%/}"  # strip trailing slash
    while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ] && [ "$dir" != "." ]; do
        if [ -d "$dir/.git" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# List all git repos under WATCH_DIR (with remotes)
list_repos() {
    for d in "$WATCH_DIR"/*/; do
        [ -d "${d}.git" ] || continue
        # Skip repos without remotes
        git -C "$d" remote get-url origin &>/dev/null 2>&1 || continue
        echo "$d"
    done
}

# Get repo name from path
repo_name() {
    basename "$1"
}

# inotifywait 是否"真能跑"：command -v 只看得见文件，库缺失时二进制在、
# 一执行就 "error while loading shared libraries"（免 sudo 装的库在 ~/.local/lib）。
inotify_usable() {
    command -v inotifywait &>/dev/null || return 1
    local probe
    probe=$(inotifywait --help 2>&1 || true)
    [[ "$probe" != *"error while loading shared libraries"* &&
       "$probe" != *"cannot open shared object file"* ]]
}

# 自动修复（免 sudo 安装）。必须子 shell 里 source：install-inotify.sh 会 source
# colors.sh，它的 error()/warn() 会顶掉本文件的同名日志函数（那些还要写 LOG_FILE）
repair_inotify() {
    ( source "$SCRIPT_DIR/install-inotify.sh"; install_inotify ) >>"$LOG_FILE" 2>&1 || true
    export PATH="$HOME/.local/bin:$PATH"
    inotify_usable
}

check_deps() {
    inotify_usable && return 0
    if ! command -v inotifywait &>/dev/null; then
        error "缺少 inotifywait — 修复: bash ~/git/ccconfig/maintain.sh fix"
    else
        error "inotifywait 无法加载共享库（libinotifytools.so.0）— 修复: bash ~/git/ccconfig/maintain.sh fix"
    fi
    return 1
}

# Check if HTTPS_PROXY is alive (2s timeout). Returns 0 if reachable or no proxy configured.
check_proxy() {
    local proxy="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy}}}}"
    [ -z "$proxy" ] && return 0
    local hostport=$(echo "$proxy" | sed 's|^https\?://||;s|/$||')
    [ -z "$hostport" ] && return 0
    local host="${hostport%:*}" port="${hostport##*:}"
    if command -v nc &>/dev/null; then
        timeout 2 nc -z "$host" "$port" 2>/dev/null
    else
        return 0  # no nc, assume reachable (don't false-skip pull)
    fi
}

# 是否配置了代理（任一 proxy env 非空）
proxy_configured() {
    [ -n "${HTTPS_PROXY:-}${https_proxy:-}${HTTP_PROXY:-}${http_proxy:-}" ]
}

# 代理可用 = 未配置（直连）或 配置了且可达
proxy_usable() {
    ! proxy_configured || check_proxy
}

# Push 失败原因，别再一律 "check network"（分叉/认证也会走到失败分支）
push_fail_reason() {
    local r
    r=$(printf '%s' "$1" | grep -oiE "non-fast-forward|fetch first|rejected|bad credentials|token.*expired|connection|timed out|could not resolve|could not connect|reset by peer" | head -1)
    printf '%s' "${r:-unknown}"
}

# pull --rebase --autostash，与 git_push 对称：代理死了剥 env 直连。
# 抽成独立函数是因为 git_push 遇到 non-fast-forward 时也要调它做自愈。
git_pull_rebase() {
    local repo_dir="$1" branch="$2"
    local penv=()
    proxy_usable || penv=(env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy)
    local had_e=0; case $- in *e*) had_e=1 ;; esac
    set +e
    local out
    out=$(timeout --kill-after=5 30 "${penv[@]}" git -C "$repo_dir" pull --rebase --autostash origin "$branch" 2>&1)
    local rc=$?
    if [ "$had_e" = 1 ]; then set -e; fi
    printf '%s' "$out"
    return $rc
}

# Push with retry (network intermittent on WSL)
git_push() {
    local repo_dir="$1" branch="$2"
    local attempt=1 max_attempts=3
    local output rc
    # 记住调用方的 errexit 状态。loop 里是刻意 set +e 的（见 start_watch 注释），
    # 取完 rc 若无脑 set -e 会把外层"故意关掉"重新打开 —— 之后任意一条非零命令
    # 就终止 loop 子 shell，systemd 随即 restart（实测每 ~20min 一次，全在 push 之后）
    local had_e=0; case $- in *e*) had_e=1 ;; esac
    # 代理死了就剥掉 proxy env 直连。systemd unit 硬编码 HTTPS_PROXY，Clash 退出后
    # 那个端口无人监听 → git 走它 0ms connection refused，push 永远失败（日志还会
    # 假称 "push directly"）。剥离后直连 github.com 正常。
    local penv=()
    proxy_usable || penv=(env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy)
    while [ $attempt -le $max_attempts ]; do
        set +e
        output=$(timeout 30 "${penv[@]}" git -C "$repo_dir" push origin "$branch" 2>&1)
        rc=$?
        if [ "$had_e" = 1 ]; then set -e; fi
        if [ $rc -eq 0 ]; then
            echo "$output"
            return 0
        fi
        if echo "$output" | grep -qiE "bad credentials|401|token.*expired|invalid_token|authentication failed|unauthorized"; then
            # Auth error → PAT 失效/过期，不重试，提示续期后才能 push
            do_log ""
            do_log "❌ GitHub PAT 失效（401/auth error）— 续期后才能 push"
            do_log "   bash ~/git/ccconfig/bin/refresh-gh-auth.sh"
            echo "$output" >&2
            return $rc
        elif echo "$output" | grep -qi "connection\|network\|Recv failure\|reset by peer\|timeout\|Could not resolve"; then
            if [ $attempt -lt $max_attempts ]; then
                log "[$(repo_name "$repo_dir")] push attempt $attempt failed, retry in 10s..."
                sleep 10
            fi
        elif echo "$output" | grep -qiE "non-fast-forward|fetch first|updates were rejected"; then
            # 分叉（远程有新提交）→ 非快进被拒。此前只报 "check network"，分叉永远不自愈。
            # pull --rebase --autostash 后重推；冲突交回调用方（skip_push 语义）由 pull 分支兜底。
            log "[$(repo_name "$repo_dir")] non-fast-forward → rebase onto origin/$branch"
            local rebase_out rebase_rc
            set +e
            rebase_out=$(git_pull_rebase "$repo_dir" "$branch" 2>&1)
            rebase_rc=$?
            if [ "$had_e" = 1 ]; then set -e; fi
            if [ -f "$repo_dir/.git/rebase-merge" ] || [ -f "$repo_dir/.git/rebase-apply" ]; then
                git -C "$repo_dir" rebase --abort 2>/dev/null || true
                echo "rebase conflict — local conflict state aborted" >&2
                printf '%s' "$rebase_out" >&2
                return 1
            fi
            if [ $rebase_rc -eq 0 ]; then
                log "[$(repo_name "$repo_dir")] OK rebase"
                set +e
                output=$(timeout 30 "${penv[@]}" git -C "$repo_dir" push origin "$branch" 2>&1)
                rc=$?
                if [ "$had_e" = 1 ]; then set -e; fi
                if [ $rc -eq 0 ]; then
                    echo "$output"
                    return 0
                fi
                echo "$output" >&2
                return $rc
            fi
            printf '%s' "$rebase_out" >&2
            return $rebase_rc
        else
            # Non-network error (conflict, etc.) — don't retry
            echo "$output" >&2
            return $rc
        fi
        attempt=$((attempt + 1))
    done
    echo "$output" >&2
    return $rc
}

# ========== Commit and push for one repo ==========
commit_and_push() {
    local repo_dir="$1"

    local repo=$(repo_name "$repo_dir")
    local lock_dir="$repo_dir/.monitor-sync.lock"
    local stale_lock=90
    if ! mkdir "$lock_dir" 2>/dev/null; then
        # 陈旧锁自愈：进程被 kill 时 trap RETURN 不执行 → 锁永久残留 → 后续全 skip。
        # 锁只是互斥目录，正常 commit+push 几十秒内释放；超 stale_lock 秒还在 = 持有者已退场。
        if [ -d "$lock_dir" ] && [ "$(stat -c %Y "$lock_dir" 2>/dev/null)" -lt "$(( $(date +%s) - stale_lock ))" ]; then
            rmdir "$lock_dir" 2>/dev/null
            if mkdir "$lock_dir" 2>/dev/null; then
                do_log "[$repo] cleared stale lock, retrying sync"
            else
                do_log "[$repo] skip — sync already in progress"
                return 0
            fi
        else
            do_log "[$repo] skip — sync already in progress"
            return 0
        fi
    fi
    trap "rmdir '$lock_dir' 2>/dev/null" RETURN

    if pgrep -x git >/dev/null 2>&1; then
        do_log "[$repo] warn — 检测到活跃 git 进程，跳过清理 index.lock"
    else
        rm -f "$repo_dir/.git/index.lock" 2>/dev/null
    fi

    local changed_files=$(git -C "$repo_dir" status --porcelain 2>/dev/null)
    if [ -z "$changed_files" ]; then
        local branch=$(git -C "$repo_dir" branch --show-current)
        # 先把远程状态拉下来：不做这步时，多终端场景下"对端推了新提交、本机无改动"
        # 会走进 else 打 already up to date —— 本机永远看不见对端进展（心跳也只是
        # 更频繁地重复这句），收敛根本不成立。这里走 git_pull_rebase（autostash 保底），
        # 与有改动路径同一条整合逻辑：工作区本就干净，快进就是纯"取回对端改动"。
        # 注意 errexit：Git Bash 的 set -e 会与 wait 的 SIGCHLD 交互，fetch 成功也会让
        # 子 shell 立刻退出（实测：心跳触发后 11s 主 loop 就重启，NRestarts+1）。
        # 沿用 git_push 的 had_e 手法只保护本段，不把外层刻意关掉的 errexit 重新打开。
        local had_e=0; case $- in *e*) had_e=1 ;; esac
        # 1) 显式 fetch。必须先 fetch 才算得出落后量：origin/$branch 是上次 fetch 的
        #    缓存，不 fetch 就永远是 0（实测纯远程领先时报 already up to date）。
        #    多终端场景下这里是"本机能否看见对端"的唯一入口。
        local fetch_out fetch_rc
        local fetch_attempt=1 fetch_max=2
        # git_push 早有 3× 重试，fetch 此前一次失败就放弃 —— 代理链路的 TLS
        # handshake / HTTP2 framing 抖动是**瞬时**的（实测同一分钟内 5 个仓库
        # 里 2 个失败、下一轮心跳全成功），不重试等于白白丢掉一轮对端可见性。
        # 取 2 次而非 3 次：fetch 在一轮里要跑 N 个仓库，失败多是代理整体抖动，
        # 每个仓库都重试 3 次会把"代理宕了"放大成 3 倍等待；2 次已能吃掉瞬时抖动。
        while [ $fetch_attempt -le $fetch_max ]; do
            set +e
            if proxy_usable; then
                fetch_out=$(timeout 30 git -C "$repo_dir" fetch origin "$branch" 2>&1)
            else
                fetch_out=$(timeout 30 env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy git -C "$repo_dir" fetch origin "$branch" 2>&1)
            fi
            fetch_rc=$?
            if [ "$had_e" = 1 ]; then set -e; fi
            [ $fetch_rc -eq 0 ] && break
            # 只对网络类错误重试；认证/仓库不存在等重试无意义，重试只是拖慢
            if ! printf '%s' "$fetch_out" | grep -qiE "connection|network|GnuTLS|handshake|framing|reset by peer|timeout|Could not resolve"; then
                break
            fi
            if [ $fetch_attempt -lt $fetch_max ]; then
                do_log "[$repo] fetch attempt $fetch_attempt failed, retry in 5s..."
                sleep 5
            fi
            fetch_attempt=$((fetch_attempt + 1))
        done

        local behind=0
        local just_integrated=0   # 本轮是否已整合过（抑制紧随其后的重复 "already up to date"）
        if [ $fetch_rc -eq 0 ]; then
            behind=$(git -C "$repo_dir" rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo 0)
        else
            warn "[$repo] !! fetch 失败（rc=$fetch_rc）— 无法判断对端进展"
            do_log "[$repo]   fetch err: $(printf '%s' "$fetch_out" | head -2 | tr '\n' ' ')"
        fi

        # 2) 确有对端新提交才整合（跳过时不产生第二次网络往返）。
        #    工作区干净 → autostash 不生效，快进即"纯取回对端改动"。
        if [ "${behind:-0}" -gt 0 ]; then
            local pull_out pull_rc
            set +e
            pull_out=$(git_pull_rebase "$repo_dir" "$branch" 2>&1)
            pull_rc=$?
            if [ "$had_e" = 1 ]; then set -e; fi
            if [ "$pull_rc" -eq 0 ]; then
                log "[$repo] 整合其他终端 ${behind} 个提交（pull --rebase）"
                just_integrated=1
                behind=0
            else
                warn "[$repo] !! 整合对端改动失败（rc=$pull_rc, 仍落后 ${behind}）"
                do_log "[$repo]   pull err: $(printf '%s' "$pull_out" | head -3 | tr '\n' ' ')"
            fi
        fi
        local unpushed=$(git -C "$repo_dir" log origin/"$branch".."$branch" --oneline 2>/dev/null)
        if [ -n "$unpushed" ]; then
            local count=$(echo "$unpushed" | wc -l)
            log "[$repo] no local changes, pushing $count unpushed commit(s)"
            local push_output push_rc
            push_output=$(git_push "$repo_dir" "$branch" 2>&1)
            push_rc=$?
            if [ $push_rc -eq 0 ]; then
                local latest_hash=$(git -C "$repo_dir" rev-parse --short HEAD)
                log "[$repo] OK pushed → GitHub ($latest_hash)"
            else
                echo "$push_output" | while IFS= read -r errline; do do_log "[$repo] $errline"; done
                warn "[$repo] !! push failed — $(push_fail_reason "$push_output")"
            fi
        else
            # 区分"真同步了"与"本机落后远程"：只打同一句会让心跳在真正落后时
            # 也显得一切正常（用户实测就是看不出双端有没有收敛）。
            # 刚整合过就不再补一句 already up to date —— 同一次调用里说两遍
            # 同一件事纯属冗余（曾出现 "整合其他终端 1 个提交" + "already up to date"）。
            if [ "${behind:-0}" -gt 0 ]; then
                log "[$repo] up to date locally, but ${behind} commit(s) behind remote — 未整合其他终端的改动"
            elif [ "${just_integrated:-0}" -eq 0 ]; then
                logq "[$repo] already up to date"
            fi
        fi
        return 0
    fi

    echo "" | tee -a "$LOG_FILE"
    info "[$repo] * changes detected"
    echo "$changed_files" | while read line; do do_log "[$repo]   $line"; done

    if git -C "$repo_dir" ls-files -u 2>/dev/null | grep -q .; then
        error "[$repo] !! UNRESOLVED CONFLICTS — manual resolution needed"
        return 1
    fi

    git -C "$repo_dir" add -A -- ':!.monitor-sync.*' 2>/dev/null || warn "[$repo] git add failed (nested .git?)"

    # Skill sync: independent of pull/push, builds local symlinks for new skills in templates/skills/.
    # Runs before commit so even "nothing to commit" still rebuilds links.
    if [ -f "$repo_dir/lib/init-skill.sh" ]; then
        local skill_output skill_rc
        skill_output=$(bash "$repo_dir/lib/init-skill.sh" sync 2>&1)
        skill_rc=$?
        echo "$skill_output" | while IFS= read -r line; do do_log "[$repo] $line"; done
        if [ $skill_rc -eq 0 ]; then
            log "[$repo] OK skills sync"
        else
            warn "[$repo] skills sync failed"
        fi
    fi

    # 提交信息带改动摘要。session 已不再自己 commit（见 CLAUDE.md 约束），
    # 这里写什么就是历史里仅有的信息——只留时间戳等于把"改了什么"全丢掉。
    local staged_files staged_count commit_subject commit_msg
    staged_files=$(git -C "$repo_dir" diff --cached --name-only 2>/dev/null || true)
    staged_count=$(printf '%s' "$staged_files" | awk 'NF{n++} END{print n+0}')
    if [ "$staged_count" -gt 0 ]; then
        commit_subject="Auto-sync: $repo $staged_count 文件"
        commit_msg=$(printf '%s\n\n%s' "$commit_subject" \
            "$(printf '%s\n' "$staged_files" | head -12 | sed 's/^/  /')")
        [ "$staged_count" -gt 12 ] && commit_msg="$commit_msg
  …还有 $((staged_count - 12)) 个"
    else
        commit_msg="Auto-sync: $repo $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    unset staged_files staged_count commit_subject

    local commit_output

    if commit_output=$(git -C "$repo_dir" commit -m "$commit_msg" 2>&1); then
        local commit_hash=$(echo "$commit_output" | grep -o '[a-f0-9]\{7\}' | tail -1)
        log "[$repo] OK committed $commit_hash"

        local branch=$(git -C "$repo_dir" branch --show-current)
        local skip_push=false

        # 永远尝试 pull：与 git_push 对称，代理死了就剥 env 直连（git_pull_rebase 内处理）。
        # 旧版在代理不可达时直接 skip pull → 远程领先时永不 rebase → 永久分叉 → 每次 push
        # 非快进被拒（还误报 "check network"）。代理健康与否都不该跳过整合远程改动。
        local pull_attempt=1 pull_max=2
        local pull_ok=false
        while [ $pull_attempt -le $pull_max ]; do
            local pull_output pull_rc
            pull_output=$(git_pull_rebase "$repo_dir" "$branch" 2>&1)
            pull_rc=$?
            if [ $pull_rc -eq 0 ]; then
                if echo "$pull_output" | grep -q "is up to date\|up-to-date\|Already up to date"; then
                    :  # no remote changes
                else
                    log "[$repo] OK rebase"
                fi
                pull_ok=true
                break
            fi
            # Network/timeout error -> retry; non-network error -> don't retry
            if [ $pull_rc -eq 124 ] || echo "$pull_output" | grep -qi "connection\|network\|kex_exchange\|could not read from remote\|gnutls\|Recv failure"; then
                if [ $pull_attempt -lt $pull_max ]; then
                    log "[$repo] pull attempt $pull_attempt failed, retry in 10s..."
                    # 必须落真实报错：此前网络类分支只打上面那句通用消息，
                    # pull_output 被丢弃 → 事后无法判定是超时/代理/DNS/协议。
                    # 全历史约 50 次 pull failed 全是这样丢证据的（rc=$pull_rc）。
                    do_log "[$repo]   pull rc=$pull_rc err: $(printf '%s' "$pull_output" | head -3 | tr '\n' ' ')"
                    sleep 10
                fi
            else
                echo "$pull_output" | while IFS= read -r errline; do do_log "[$repo] $errline"; done
                if echo "$pull_output" | grep -qi "unrelated histories"; then
                    error "[$repo] !! unrelated histories — skip push"
                    skip_push=true
                elif echo "$pull_output" | grep -qi "CONFLICT\|conflict\|could not be applied"; then
                    # 兜底：reset --hard 前先把本地工作存到 stash，万一 stash pop 失败也能恢复
                    local safety_stash="ccconfig-monitor-safety-$(date +%s)"
                    git -C "$repo_dir" stash push -m "$safety_stash" 2>/dev/null || true
                    git -C "$repo_dir" rebase --abort 2>/dev/null || true
                    warn "[$repo] !! rebase 冲突 — reset to origin/$branch (本地工作存到 $safety_stash)"
                    git -C "$repo_dir" reset --hard "origin/$branch" 2>&1 | head -1 >> "$LOG_FILE" || true
                    # 只在 stash 真的有内容时才 pop
                    if git -C "$repo_dir" stash list | grep -q "$safety_stash"; then
                        git -C "$repo_dir" stash pop 2>/dev/null || warn "[$repo] stash pop 失败，存于 $safety_stash（手动恢复）"
                    fi
                    skip_push=true
                else
                    warn "[$repo] pull failed: $(echo "$pull_output" | head -1)"
                fi
                break  # non-network error, don't retry
            fi
            pull_attempt=$((pull_attempt + 1))
        done
        if ! $pull_ok && ! $skip_push; then
            warn "[$repo] pull failed after $pull_max attempts, pushing directly"
        fi

        if ! $skip_push; then
            if [ -f "$repo_dir/lib/setup-links.sh" ]; then
                local links_output links_rc
                links_output=$(bash "$repo_dir/lib/setup-links.sh" 2>&1)
                links_rc=$?
                echo "$links_output" | while IFS= read -r line; do do_log "[$repo] $line"; done
                if [ $links_rc -eq 0 ]; then
                    log "[$repo] OK links"
                else
                    warn "[$repo] links failed"
                fi
            fi
            local push_output push_rc
            push_output=$(git_push "$repo_dir" "$branch" 2>&1)
            push_rc=$?
            if [ $push_rc -eq 0 ]; then
                log "[$repo] OK pushed → GitHub ($commit_hash)"
                # 已迁移：aiagt deploy → fsyncdoc skill，不再 auto-sync 触发
            else
                echo "$push_output" | while IFS= read -r errline; do do_log "[$repo] $errline"; done
                warn "[$repo] !! push failed — $(push_fail_reason "$push_output")"
            fi
        else
            # skip_push 走到这里 = unrelated histories 或 rebase 冲突兜底。
            # 此前静默返回 → 本地已提交但未推送的 commit 无限期搁浅，无人知晓。
            # 显式报出未推送数量，把"静默搁浅"变成"可见告警"。
            local _unpushed
            _unpushed=$(git -C "$repo_dir" rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)
            if [ "${_unpushed:-0}" -gt 0 ]; then
                error "[$repo] !! 跳过推送 — ${_unpushed} 个 commit 未推送（远程领先或冲突未解）。查看: git -C $repo_dir log origin/$branch..HEAD"
            else
                warn "[$repo] !! 跳过推送（无未推送 commit，仅本地改动未落盘）"
            fi
        fi
    else
        if echo "$commit_output" | grep -q "nothing to commit"; then
            :  # not an error
        else
            warn "[$repo] commit failed: $(echo "$commit_output" | head -1)"
        fi
    fi
}

# Sync a list of repos (one per line). Empty arg = sync all.
# 默认全量（旧终端 / pub 路径），debounce 路径传改动列表
sync_repos() {
    # ${1:-} 不能写成 "$1"：文件级 set -u 在循环的 set +e 下**依然生效**
    # （set +e 只关 errexit，不关 nounset）。裸 "$1" 会让无参调用当场
    # "$1: unbound variable" 退出 rc=1 —— 而"无参 = 全量"是官方语义
    # （help 与 initial scan 都用它）。实测：这就是 monitor loop 在每次
    # 全量同步后 11 秒内死掉、systemd 每 ~5min 重启一次的根因。
    local repos_arg="${1:-}"
    local repos
    if [ -n "$repos_arg" ]; then
        repos="$repos_arg"
    else
        repos=$(list_repos)
    fi
    local repo_dir
    for repo_dir in $repos; do
        [ -d "$repo_dir" ] || continue
        commit_and_push "$repo_dir"
    done
}

# ========== PM2 resurrect ==========
resurrect_pm2() {
    export PATH="$HOME/.local/bin:$PATH"
    command -v pm2 &>/dev/null || return 0
    pm2 ping &>/dev/null && pm2 list 2>/dev/null | grep -q "│ [0-9]" && { log "Resurrecting PM2..."; pm2 resurrect >/dev/null 2>&1 || true; }
}

# ========== Start monitoring ==========
# 找出存活 monitor loop 的 PID；无则回空。start_watch / status_watch 共用。
#
# 难点：daemon 与「一次性调用」的 cmdline 无法用子串区分。
#   - daemon 的父 bash 与它 fork 的 loop 子 shell，cmdline 都是
#     `/bin/bash /path/to/monitor.sh start`
#   - 而 `timeout 25 bash monitor.sh start`、`sudo systemctl ...`、
#     `bash -c '... monitor.sh start ...'`、`monitor.sh status|tail|log` 这些
#     一次性调用，cmdline 里【同样】含 "monitor.sh"，甚至含 "monitor.sh start"
#
# 实测事故（2026-10-30，两次都踩在这上面）：
#   ① 一条诊断命令 `bash -c '... monitor.sh start ...'` 把自己认成实例
#      → start_watch 提前 return 【不写 PIDFile】→ systemd Type=forking 报
#      "Can't open PID file after start: No such file or directory" → Result=protocol
#      → 每 10s 重启的死循环（服务彻底起不来）。
#   ② 改用「必须有子进程」当 daemon 特征后，`timeout bash monitor.sh start` 又因
#      它是包装器、有子进程而被误判，同样复发。
#
# 因此判据改成【整条 cmdline 锚定匹配】：只认 cmdline 恰好是
#   `bash <path>/monitor.sh start`（前后无其它参数/命令）的进程。
# 包装器（timeout/sudo/env/nice/setsid/bash -c/系统 shell-snapshot 包装）的 cmdline
# 都不是这个形状，一次性子命令（status/tail/log）也不是 → 一并排除。
# 另排除 $$ 与 $PPID（自身 + 直接调用者），双保险。
#
# 宁漏不误判：漏判的代价是 systemd 多起一个实例（旧 loop 会在下个周期被拒启后收敛），
# 误判的代价是【服务起不来】。方向必须偏向前者。
_monitor_cmdline_is_daemon() {
    local cmd
    cmd=$(cat "/proc/$1/cmdline" 2>/dev/null | tr '\0' ' ')
    cmd="${cmd%"${cmd##*[![:space:]]}"}"   # 去掉 tr 留下的尾随空格
    # 按词判等，而不是正则：cmdline 必须**恰好**是 `<bash> <脚本路径> start` 三个词。
    # 不用 `[[ =~ ]]` 的理由有两条 —— 一是 `[^ ]` 里的字面空格会直接打断 `[[ ]]` 的
    # 正则解析（实测报 `syntax error in conditional expression`）；二是正则的 `.*`
    # 会把 `bash -c 'sleep 5; /path/monitor.sh start'` 这种包装器一并认成 daemon
    # （它同样以 `bash ` 开头、以 `monitor.sh start` 结尾）。词数恰好为 3 天然排除
    # 一切包装器（-c / timeout / sudo / 系统 shell-snapshot 包装都会多出词）。
    local -a parts
    read -r -a parts <<< "$cmd"
    [ "${#parts[@]}" -eq 3 ] || return 1
    [[ "${parts[0]}" == "bash" || "${parts[0]}" == "/bin/bash" ]] || return 1
    [[ "${parts[1]}" == *monitor.sh ]] || return 1
    [[ "${parts[2]}" == "start" ]] || return 1
    return 0
}

find_live_monitor_pid() {
    local pf pid cmd
    # 1) PIDFile：权威且低成本，依次校验手动那份与 systemd 那份
    for pf in "$PID_FILE" "$SYSTEMD_PID_FILE"; do
        [ -f "$pf" ] || continue
        pid=$(cat "$pf" 2>/dev/null) || continue
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || continue
        if _monitor_cmdline_is_daemon "$pid"; then
            echo "$pid"
            return 0
        fi
    done
    # 2) pgrep 兜底：PIDFile 已被 loop 退出 trap 删掉的情形（实测会发生）
    local cand
    while read -r cand; do
        [ -n "$cand" ] || continue
        # ⚠️ BASHPID 必须一起排除，只排 $$ 不够（2026-10-30 第三次踩坑）：
        # 调用处是 `pid_candidate=$(find_live_monitor_pid)` —— 命令替换会 fork 一个
        # 子 shell，而这个子 shell 的 cmdline **恰好就是** `bash <path>/monitor.sh start`
        # （3 词、与真 daemon 无法区分）。`$$` 在子 shell 里取的是**父** PID，所以
        # `[ "$cand" = "$$" ]` 排不掉它 → 函数返回自己的子 shell PID → start_watch
        # 认为"已在运行" → 永不启动（systemd 场景即 Result=protocol 死循环）。
        # $BASHPID 才是「当前这个 shell 的真实 PID」，子 shell 里它≠$$，正好排掉。
        [ "$cand" = "$$" ] && continue
        [ "$cand" = "$BASHPID" ] && continue
        [ "$cand" = "$PPID" ] && continue
        if _monitor_cmdline_is_daemon "$cand"; then
            echo "$cand"
            return 0
        fi
    done < <(pgrep -f 'monitor\.sh start' 2>/dev/null)
    return 1
}

start_watch() {
    if ! check_deps; then
        # 依赖坏了先自愈：升级/换机后常见"二进制在、库丢了"，直接 return 1 会
        # 让 systemd Type=forking 起不来，也让人工 start 变成无解
        warn "inotifywait 不可用，尝试自动修复..."
        if repair_inotify; then
            log "inotifywait 已修复: $(command -v inotifywait)"
        else
            return 1
        fi
    fi

    # `|| true` 不可省：find_live_monitor_pid 在【无实例】时按约定返回 1，而裸的
    # 赋值 `x=$(...)` 会把子命令的退出码当作自身退出码，`set -e`（本文件顶部）随即
    # 终止 start_watch —— 表现为"start 退出码 1、零输出、什么都不起"。
    # 这个坑此前被掩盖：那时函数有 bug 永远返回 0，反而"跑得下去"。
    local pid_candidate
    pid_candidate=$(find_live_monitor_pid || true)

    if [ -n "$pid_candidate" ]; then
        do_log "Already running (PID: $pid_candidate) — keep alive"
        # 幂等返回不等于"没事"：loop 活着但 inotifywait 坏了，此前静默 return 0，
        # 菜单里选"启动监控"看着像没反应
        $QUIET_MODE || echo -e "${YELLOW}[SYNC]${NC} monitor 已在运行 (PID: $pid_candidate) — 未重启"
        # ⚠️ Type=forking 契约：即便判定"已在运行"，也必须确保 PIDFile 存在且内容正确。
        # 这条路径此前直接 return，不写 PIDFile；而 PIDFile 可能已被 loop 退出 trap
        # 删除（或本来就缺失）→ systemd 报
        #   "Can't open PID file ... (yet?) after start: No such file or directory"
        # → Result=protocol → 每 10s 重启一次的死循环（2026-10-30 实测事故，根因是
        # 上面 find_live_monitor_pid 曾把调用者误认成实例，但契约缺失本身是独立的坑：
        # 只要 PIDFile 丢了，哪怕认对了实例也同样起不来）。
        # 补写 PIDFile，让 systemd 始终能取到 MainPID。
        # 只写 $PID_FILE，不要顺手也写 $SYSTEMD_PID_FILE：后者默认就是
        # /run/claude-auto-sync/monitor.pid，而 unit 里 RuntimeDirectoryMode=1777
        # 让该目录全局可写 —— 手动运行一次就会把 francis 拥有的 pid 文件塞进 systemd
        # 的运行时目录，systemd 随即拒绝："PID file is owned by 1000 (must be owned by 0)"。
        # systemd 模式下 unit 已设 MONITOR_PID_FILE=/run/...，$PID_FILE 本就是那个路径，
        # 写它即可满足 Type=forking；手动模式下写 $MONITOR_HOME 那份，二者互不污染。
        if [ -n "$PID_FILE" ]; then
            mkdir -p "$(dirname "$PID_FILE")" 2>/dev/null || true
            [ "$(cat "$PID_FILE" 2>/dev/null)" = "$pid_candidate" ] \
                || echo "$pid_candidate" > "$PID_FILE" 2>/dev/null || true
        fi
        if ! inotify_usable; then
            $QUIET_MODE || echo -e "${RED}[SYNC]${NC} 但 inotifywait 不可用（共享库缺失?）— 修复: bash maintain.sh fix"
        elif ! pgrep -f "inotifywait.*$WATCH_DIR" &>/dev/null; then
            $QUIET_MODE || echo -e "${YELLOW}[SYNC]${NC} inotifywait 未在跑 — loop 下个周期会自愈；强制重启: sudo systemctl restart claude-auto-sync"
        fi
        return 0
    fi
    # PIDFile 残留（指向无关进程或死进程），清理后重启
    for pf in "$PID_FILE" "$SYSTEMD_PID_FILE"; do
        [ -f "$pf" ] && rm -f "$pf"
    done

    cd "$MONITOR_HOME"
    QUIET_MODE=true
    resurrect_pm2 &

    # 清理上次崩溃残留的僵尸 inotifywait：只杀孤儿（PPID=1），不误杀运行中实例
    # pkill -f 匹配太宽，会杀掉同目录所有 inotifywait（含健康实例）→ 触发 restart 风暴
    for p in $(pgrep -f "inotifywait.*$WATCH_DIR" 2>/dev/null); do
        [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "1" ] && kill "$p" 2>/dev/null || true
    done
    sleep 1

    # 清掉上一个 loop 的残留 status（degraded/failed 会误导 status_watch），新 loop 再自写
    rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE" "$MONITOR_HOME/.monitor-sync.status"
    find "$WATCH_DIR" -maxdepth 2 -name '.monitor-sync.lock' -type d -exec rmdir {} \; 2>/dev/null || true

    # Single inotify watching ~/git/, accepting events from any tracked repo.
    # Debounce triggers sync_repos with only the changed repo list (L2 优化).
    # 30s：session 已不再自己 commit（见 CLAUDE.md 约束），改完要尽快落盘，
    #   太长会让连续编辑攒成一坨。
    local debounce=30
    # min_push_gap 是纯节流，不承担"合并编辑"职责（那是 debounce 的活）。
    # 与 debounce 同值 30s 会让"30s debounce 后再判 30s gap"二次等待，
    # 连续操作时每一拍都被 Defer 一轮。独立取 10s 只防同步风暴。
    local min_push_gap=10
    # 心跳周期（秒）。它替代了原来的 12h 空闲兜底，是"对端提交本机可见"的唯一
    # 兜底通道 —— 所以按 wall-clock 计，不能按"暂无文件事件"计（见循环内注释）。
    local heartbeat_secs=300

    inotifywait -m -r -q \
        --exclude '(\.git/|_ext/|\.snapshots/|node_modules/|\.tmp\.)' \
        -e modify,create,delete,move \
        "$WATCH_DIR" 2> >(tr -d '\000' >> "$LOG_FILE") | while IFS= read -r line; do
            # Skip sync-internal files
            case "$line" in
                *".monitor-sync"*) continue ;;
                *".snapshots/"*) continue ;;
                *"_ext/"*) continue ;;
            esac
            # Check if file is under a tracked git repo
            local filepath repo_root
            filepath=$(echo "$line" | awk '{print $1}')
            repo_root=$(get_repo_root "$filepath" 2>/dev/null) || continue
            # Skip repos without remote
            git -C "$repo_root" remote get-url origin &>/dev/null 2>&1 || continue

            echo "[$(date '+%H:%M:%S')] $(repo_name "$repo_root"): $line" | tr -d '\000' >> "$LOG_FILE"
            date +%s > "$DEBOUNCE_FILE"
            # 记录改动的 repo，debounce 后只 sync 这些（避免无关仓库 add+commit 噪音）
            echo "$repo_root" >> "$CHANGED_REPOS_FILE"
        done &

    local event_pid=$!

    # Debounce loop → sync only repos that had changes
    # Auto-restart inotifywait with exponential backoff (WSL can drop watches)
    # 退避序列: 2s → 4s → 8s → 16s → 32s → ... → 300s (5min cap)
    # 连续 8 次失败 (累计 ~10min) 后放弃，避免 panic loop
    {
        trap 'do_log "Monitor loop EXIT trap (PID $$, last cmd rc=$?)"; kill $event_pid 2>/dev/null; pkill -P $event_pid 2>/dev/null; rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE" "$PID_FILE"; exit' EXIT
        # systemd stop / Ctrl+C：快速干净退出，避免 stop-sigterm 90s 超时被 KILL
        # 留痕：此前这个 trap 静默吞掉 TERM，loop 每 ~5min 被杀一次却查不到死因
        # （systemd 只报 Result=success，因为 exit 0）。记一行才能定位谁在发 TERM。
        trap 'do_log "Monitor loop received TERM/INT — exiting (PID $$)"; exit 0' TERM INT
        # sync 里 git 命令偶发非零，不能 let set -e 终止整个 loop → systemd 疯狂 restart
        set +e

        pending=0
        last_push_time=0
        heartbeat_ts=0   # 心跳上次触发时刻（epoch）；0 = 尚未起跳
        local inotify_restarts=0
        local inotify_backoff=2  # 初始退避秒数
        local inotify_max_restarts=8
        local inotify_max_backoff=300
        local confirm_after=0    # restart 后存活确认时间戳（epoch）

        # 健康状态文件：status.sh 可读
        local STATUS_FILE="$MONITOR_HOME/.monitor-sync.status"
        echo "ok" > "$STATUS_FILE"

        while true; do
            if ! kill -0 $event_pid 2>/dev/null; then
                # 二进制本身不可用（库丢了）时重拉多少次都白搭——先修；
                # 修不好走长冷却，别再刷 8 次退避把 30 分钟耗在注定失败的 restart 上
                if ! inotify_usable; then
                    do_log "inotifywait 不可用（共享库缺失?）— 尝试自动修复"
                    echo "degraded:repairing" > "$STATUS_FILE"
                    repair_inotify || true
                    if ! inotify_usable; then
                        do_log "自动修复失败，冷却 300s 后重试（手动: bash maintain.sh fix）"
                        echo "degraded:inotify-unusable" > "$STATUS_FILE"
                        sleep 300
                        continue
                    fi
                    do_log "inotifywait 修复成功，重新拉起"
                    inotify_restarts=0
                    inotify_backoff=2
                fi
                inotify_restarts=$((inotify_restarts + 1))
                if [ $inotify_restarts -gt $inotify_max_restarts ]; then
                    # 超限不停摆：进入 5min 冷却后回 loop 顶重试，WSL inotify 偶发持续崩也能自愈
                    do_log "inotifywait died $inotify_max_restarts times, cooling down 300s then retry"
                    echo "degraded:cooldown" > "$STATUS_FILE"
                    sleep 300
                    inotify_restarts=0
                    inotify_backoff=2
                    continue
                fi
                do_log "inotifywait died, restarting (attempt $inotify_restarts/$inotify_max_restarts) after ${inotify_backoff}s backoff..."
                echo "degraded:restart=$inotify_restarts/$inotify_max_restarts,backoff=${inotify_backoff}s" > "$STATUS_FILE"
                sleep "$inotify_backoff"
                # 下次退避翻倍，封顶 5min
                inotify_backoff=$((inotify_backoff * 2))
                [ "$inotify_backoff" -gt "$inotify_max_backoff" ] && inotify_backoff=$inotify_max_backoff
                inotifywait -m -r -q                     --exclude '(\.git/|_ext/|\.snapshots/|node_modules/|\.tmp\.)'                     -e modify,create,delete,move                     "$WATCH_DIR" 2> >(tr -d '\000' >> "$LOG_FILE") | while IFS= read -r line; do
                        case "$line" in
                            *".monitor-sync"*) continue ;;
                            *".snapshots/"*) continue ;;
                            *"_ext/"*) continue ;;
                        esac
                        local filepath=$(echo "$line" | awk '{print $1}')
                        local repo_root
                        repo_root=$(get_repo_root "$filepath" 2>/dev/null) || continue
                        git -C "$repo_root" remote get-url origin &>/dev/null 2>&1 || continue
                        echo "[$(date '+%H:%M:%S')] $(repo_name "$repo_root"): $line" | tr -d '\000' >> "$LOG_FILE"
                        date +%s > "$DEBOUNCE_FILE"
                        echo "$repo_root" >> "$CHANGED_REPOS_FILE"
                    done &
                event_pid=$!
                # 启动成功 → 30s 后确认存活再重置 backoff 计数
                # （原 subshell 写法改不到父 loop 的变量，计数永不重置 → 8 次后 giving up）
                confirm_after=$(( $(date +%s) + 30 ))
            fi
            sleep 2
            # restart 后 inotifywait 存活满 30s → 确认真活下来，重置退避计数
            if [ "$confirm_after" -gt 0 ] && [ "$(date +%s)" -ge "$confirm_after" ] && kill -0 $event_pid 2>/dev/null; then
                confirm_after=0
                inotify_restarts=0
                inotify_backoff=2
                echo "ok" > "$STATUS_FILE"
            fi
            # 心跳：按 wall-clock 计，且必须在 DEBOUNCE 判断之外。
            # 两个"必须在外面"的理由：
            #   1) 原实现用"无事件 tick 计数"（只在 DEBOUNCE_FILE 不存在时递增、
            #      一有事件即清零）→ 语义其实是"本地空闲 5min 才收敛"。而收敛需求
            #      跟本机是否空闲毫无关系：两端都在高频编辑时恰恰最需要对端提交可见，
            #      心跳却永不触发（实测 8 分钟零收敛动作）。
            #   2) 即便改成 wall-clock，只要仍留在 `if [ ! -f "$DEBOUNCE_FILE" ]` 内，
            #      持续编辑会让该文件一直存在 → 整段被跳过，心跳同样永不触发。
            # 心跳自带 last_push_time 门控，与 debounce 路径互不干扰。
            now=$(date +%s)
            if [ "$heartbeat_ts" -eq 0 ]; then
                heartbeat_ts=$now
            elif [ $((now - heartbeat_ts)) -ge "$heartbeat_secs" ]; then
                gap=$((now - last_push_time))
                if [ "$last_push_time" -eq 0 ] || [ "$gap" -ge "$min_push_gap" ]; then
                    heartbeat_ts=$now
                    do_log "Heartbeat sync (${heartbeat_secs}s wall-clock) — 收敛其他终端的改动"
                    sync_repos
                    last_push_time=$(date +%s)
                fi
            fi

            if [ ! -f "$DEBOUNCE_FILE" ]; then
                continue
            fi
            evt_ts=$(cat "$DEBOUNCE_FILE" 2>/dev/null)
            if [ -z "$evt_ts" ]; then
                continue
            fi
            now=$(date +%s)
            elapsed=$((now - evt_ts))

            if [ "$pending" -eq 0 ]; then
                pending=1
                do_log "Change detected, waiting ${debounce}s debounce..."
            fi

            if [ "$pending" -eq 1 ] && [ $elapsed -ge $debounce ]; then
                gap=$((now - last_push_time))
                if [ "$last_push_time" -gt 0 ] && [ "$gap" -lt "$min_push_gap" ]; then
                    # 不丢触发：原来这里 rm 掉 DEBOUNCE_FILE 就相当于把这次改动忘了 ——
                    # 紧接上次 push 写入的文件会一直脏着，要等下一个无关事件才被带走
                    # （实测：08:51:58 push → 08:52:00 写入 → 08:52:25 判 skip → 文件
                    # 持续未提交）。保留 DEBOUNCE_FILE 与 pending，下一 tick 重算 gap，
                    # 够了就同步 —— 语义从"丢弃"变"延后"。
                    do_log "Deferred: <${min_push_gap}s since last push — 待 gap 满足后同步"
                    continue
                fi

                # 去重改动 repo 列表，sync_repos 不传 = 全量（fallback 行为）
                changed=$(sort -u "$CHANGED_REPOS_FILE" 2>/dev/null | grep -v '^$' || true)
                # 先清触发文件再同步：sync_repos 要跑 4~24s，期间 inotify 若重建
                # DEBOUNCE_FILE（用户正在编辑），它之前会被下面那行 rm 抹掉 ——
                # 那次改动要等下一个无关文件事件才被带走（实测复现：写于 sync 窗口内的
                # 文件持续 200s+ 保持未提交）。改成先清 → 期间的新事件重新武装 debounce，
                # 语义从"丢事件"变成"延后一轮"。
                rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE"
                pending=0
                if [ -z "$changed" ]; then
                    do_log "Debounce done, no changed repos recorded — syncing all (fallback)"
                    sync_repos
                else
                    do_log "Debounce done, syncing $(echo "$changed" | wc -l) changed repo(s)..."
                    sync_repos "$changed"
                fi
                last_push_time=$(date +%s)
            fi
        done
    } &
    local monitor_pid=$!
    disown $monitor_pid 2>/dev/null || true
    disown $event_pid 2>/dev/null || true

    echo $monitor_pid > "$PID_FILE"
    do_log "Monitor started (monitor: $monitor_pid, events: $event_pid)"
    $QUIET_MODE || echo -e "${GREEN}[SYNC]${NC} Started (monitor: $monitor_pid, events: $event_pid)"
    $QUIET_MODE || echo -e "${GRAY}Use: status | log | tail${NC}"
    $QUIET_MODE || echo -e "${GRAY}Watching: $WATCH_DIR → all git repos${NC}"
    $QUIET_MODE || echo -e "${GRAY}Repos: $(list_repos | xargs -I{} basename {} | tr '\n' ' ')${NC}"

    # 启动后 30s 扫描已有改动（不等 debounce）
    # 为什么显式传 list_repos 结果 + 打仓库数：旧版这里 sync_repos 无参空转，
    # 日志只留一行 "Initial scan..."，事后完全看不出是"没有改动"还是"没扫到仓库"。
    # 实测重启后待提交改动会一直躺着，直到下一次文件事件才被提交。
    (
        sleep 30
        local _init_repos
        _init_repos=$(list_repos)
        local _init_n
        _init_n=$(printf '%s' "$_init_repos" | awk 'NF{c++} END{print c+0}')
        do_log "Initial scan: ${_init_n} 个仓库待查"
        if [ "$_init_n" -eq 0 ]; then
            do_log "Initial scan: list_repos 返回空（WATCH_DIR=$WATCH_DIR），跳过一次"
        else
            sync_repos "$_init_repos"
            do_log "Initial scan done"
        fi
    ) &
}

# systemd 托管时 monitor loop PID 写在 /run/claude-auto-sync/monitor.pid，
# 不能 kill（systemd Restart=always 立即拉起，start_watch 又被 Already running 挡）。
# 非 systemd 场景再走裸 stop_watch 旧逻辑。
is_systemd_managed() {
    local pf="$SYSTEMD_PID_FILE"
    [ -f "$pf" ] || return 1
    local pid; pid=$(cat "$pf" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
    local cmd; cmd=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
    [[ "$cmd" == *"monitor.sh"* ]]
}

# ========== Stop monitoring ==========
stop_watch() {
    if is_systemd_managed; then
        # 剥 inotify 让 systemd loop 自愈（它的 debounce 会自动重启），
        # 不动 monitor loop（杀也白杀，systemd 拉起 + start_watch 拒启）
        pkill -f "inotifywait.*$WATCH_DIR" 2>/dev/null || true
        rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE"
        echo -e "${YELLOW}[SYNC]${NC} systemd 托管（inotifywait 已剥，loop 会自愈）"
        echo -e "${GRAY}  完全重启: sudo systemctl restart claude-auto-sync${NC}"
        return 0
    fi

    pkill -f "inotifywait.*$WATCH_DIR" 2>/dev/null || true

    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null && echo -e "${GREEN}[SYNC]${NC} Stopped" || echo -e "${RED}[SYNC]${NC} Stop failed"
        else
            echo -e "${YELLOW}[SYNC]${NC} Process not found"
        fi
        rm -f "$PID_FILE"
    else
        echo -e "${YELLOW}[SYNC]${NC} Not running"
    fi
    rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE"
}

# ========== Restart ==========
restart_watch() {
    if is_systemd_managed; then
        echo -e "${YELLOW}[SYNC]${NC} systemd 托管，重启请走 systemctl:"
        echo -e "${GRAY}  sudo systemctl restart claude-auto-sync${NC}"
        return 0
    fi
    stop_watch
    sleep 1
    start_watch
}

# ========== Status ==========
status_watch() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[monitor-sync] Status${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local mon_pid
    if mon_pid=$(find_live_monitor_pid); then
        echo -e "  ${GREEN}✓${NC} Monitor loop (PID: $mon_pid)"
    else
        echo -e "  ${RED}✗${NC} Not running"
        return
    fi

    local evt_pid=$(pgrep -f "inotifywait.*$WATCH_DIR" 2>/dev/null)
    if [ -n "$evt_pid" ]; then
        echo -e "  ${GREEN}✓${NC} inotifywait (PID: $evt_pid)"
    elif ! command -v inotifywait &>/dev/null; then
        echo -e "  ${RED}✗${NC} inotifywait 未安装 — 修复: bash maintain.sh fix"
    elif ! inotify_usable; then
        # 二进制在但库丢了：只说 dead 会让人反复 restart，restart 治不了这个
        echo -e "  ${RED}✗${NC} inotifywait 无法加载共享库（libinotifytools.so.0）— 修复: bash maintain.sh fix"
    else
        echo -e "  ${RED}✗${NC} inotifywait (dead — restart needed)"
    fi

    # 降级状态：loop 会写 degraded:restart=N/M,backoff=Ns 或 failed，
    # 此前只写不读，inotify 反复崩到放弃后这里看不出来
    local status_file="$MONITOR_HOME/.monitor-sync.status"
    if [ -f "$status_file" ]; then
        local st; st=$(cat "$status_file" 2>/dev/null || true)
        case "$st" in
            ok) : ;;
            failed)
                echo -e "  ${RED}✗${NC} inotify 反复崩溃已放弃（status: failed）— 重启: bash lib/monitor.sh restart" ;;
            degraded*)
                echo -e "  ${YELLOW}⚠${NC}  inotify 降级中（${st#degraded:}）" ;;
            "") : ;;
            *) echo -e "  ${GRAY}status: $st${NC}" ;;
        esac
    fi

    echo ""
    echo -e "  ${GRAY}Tracked repos:${NC}"
    for repo_dir in $(list_repos); do
        local name=$(repo_name "$repo_dir")
        local branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null)
        local status=$(git -C "$repo_dir" status --porcelain 2>/dev/null | wc -l)
        if [ "$status" -gt 0 ]; then
            echo -e "    ${YELLOW}$name${NC} ($branch) — $status file(s) pending"
        else
            echo -e "    ${GREEN}$name${NC} ($branch) — clean"
        fi
    done

    if [ -f "$LOG_FILE" ]; then
        local last_line=$(tail -1 "$LOG_FILE" 2>/dev/null | sed 's/^\[[0-9:]\+\] //')
        [ -n "$last_line" ] && echo -e "\n  ${GRAY}Last: $last_line${NC}"
    fi

    # 飞书账号
    echo -n "  飞书账号 ... "
    local lark_name="" lark_dir=""
    if [ -f "$HOME/.lark-cli-account" ]; then
        lark_name=$(grep '^name=' "$HOME/.lark-cli-account" 2>/dev/null | cut -d'=' -f2)
        lark_dir=$(grep '^configDir=' "$HOME/.lark-cli-account" 2>/dev/null | cut -d'=' -f2)
    fi
    lark_dir="${lark_dir:-${LARKSUITE_CLI_CONFIG_DIR:-$HOME/.lark-cli}}"
    if [ -n "$lark_name" ]; then
        echo -e "${GREEN}${lark_name}${NC} ${GRAY}(${lark_dir})${NC}"
    else
        echo -e "${YELLOW}未配置${NC}"
    fi

    # Bridge — 端口用 BRIDGE_PORT（mirrored 多发行版并存时各发行版不同，见 ensure-bridge.sh）
    local bport="${BRIDGE_PORT:-8898}"
    if grep -q "127.0.0.1:${bport}" "$HOME/.claude/settings.json" 2>/dev/null; then
        echo -n "  Bridge (${bport}) ... "
        if curl -s --max-time 2 "http://127.0.0.1:${bport}/health" >/dev/null 2>&1; then
            local up=$(curl -s --max-time 1 "http://127.0.0.1:${bport}/health" 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('upstream_model','?'))" 2>/dev/null || echo "?")
            echo -e "${GREEN}✅${NC} → $up"
        else
            echo -e "${RED}❌${NC} — bash init-llm.sh heal"
        fi
    fi

    # systemd 自启动
    local user_svc="$HOME/.config/systemd/user/claude-auto-sync.service"
    local sys_svc="/etc/systemd/system/claude-auto-sync.service"
    echo -n "  systemd 自启动 ... "
    if [ -f "$sys_svc" ]; then
        if systemctl is-active --quiet claude-auto-sync.service 2>/dev/null || pgrep -f 'monitor.sh start' &>/dev/null; then
            # WSL2 systemd 偶发 is-active 报 deactivating，但 monitor 进程实际在跑
            if systemctl is-active --quiet claude-auto-sync.service 2>/dev/null; then
                echo -e "${GREEN}✅${NC} (system-level)"
            else
                echo -e "${GREEN}✅${NC} (system-level, process active via pgrep)"
            fi
        else
            echo -e "${YELLOW}⚠ ${NC}system service 存在但未运行 → sudo systemctl enable --now claude-auto-sync"
        fi
    elif [ -f "$user_svc" ]; then
        if systemctl --user status claude-auto-sync.service &>/dev/null 2>&1; then
            echo -e "${GREEN}✅${NC} (user-level)"
        else
            echo -e "${YELLOW}⚠ ${NC}user service 存在，但 systemd user bus 不可用（WSL 常见）"
            echo -e "  ${GRAY}替代: bash ccconfig/lib/monitor.sh start${NC}"
            echo -e "  ${GRAY}推荐: 安装 system-level service → sudo cp ccconfig/lib/claude-auto-sync.service /etc/systemd/system/ && sudo systemctl enable --now claude-auto-sync${NC}"
        fi
    else
        echo -e "${RED}❌${NC} 未配置"
    fi

    echo ""
    echo -e "${GRAY}Commands: start | stop | log | monitor | tail${NC}"
    echo ""
}

# ========== Log line colorizer ==========
colorize_line() {
    local ts="$1" content="$2"

    # 剥内嵌色：log 历史含旧 escape（do_log 已剥，但历史行还在），剥后规则才能匹配
    content=$(echo "$content" | strip_ansi)
    # 空行/仅 repo 前缀行丢弃，减少噪声（init-skill/链接脚本输出大量空行）
    if echo "$content" | grep -qE '^[[:space:]]*$|^\[[a-z_-]+\][[:space:]]*$'; then return; fi

    # ERROR (red) — "!!" prefix, failures that need attention
    if echo "$content" | grep -qE '(\!\!|ERROR|UNRESOLVED|aborting)'; then
        echo -e "  ${RED}${ts}${NC}  $content"
        return
    fi

    # WARNING (yellow) — skipped, nothing to commit, warn prefix
    if echo "$content" | grep -qE '(WARN|Skipped|nothing to commit)'; then
        echo -e "  ${YELLOW}${ts}${NC}  $content"
        return
    fi

    # SUCCESS (green) — OK prefix / ✅ 完成 / key milestones
    if echo "$content" | grep -qE '(OK pushed|OK committed|OK pull|OK links|OK skills|OK rebase|✅|Started|Stopped|Resurrecting)'; then
        echo -e "  ${GREEN}${ts}${NC}  $content"
        return
    fi

    # ACTIVITY (cyan) — changes, debounce, sync progress
    if echo "$content" | grep -qE '(\* changes detected|Change detected|Debounce done|syncing |MOVED_TO|DELETED|CREATED|MODIFY)'; then
        echo -e "  ${CYAN}${ts}${NC}  $content"
        return
    fi

    # DEFAULT (gray) — file listings, misc
    echo -e "  ${GRAY}${ts}${NC}  $content"
}

# ========== Log viewer (formatted) ==========
log_watch() {
    local lines="${1:-30}"

    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}[SYNC]${NC} No log file"
        return
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[monitor-sync] Log (last $lines lines)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    tail -n "$lines" "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        local ts=$(echo "$line" | grep -oE '^\[[0-9:]+\]' | tr -d '[]')
        local content=$(echo "$line" | sed 's/^\[[0-9:]\+\] //')
        colorize_line "${ts:-??:??:??}" "$content"
    done

    echo ""
}

# ========== Tail (formatted) ==========
tail_watch() {
    if [ ! -f "$LOG_FILE" ]; then
        # Log 文件未创建 = 从未启动过
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo -e "${GREEN}[SYNC]${NC} Running (PID: $(cat "$PID_FILE")) — no file changes yet"
        else
            echo -e "${YELLOW}[SYNC]${NC} monitor-sync not running"
        fi
        return
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[monitor-sync] Tail (Ctrl+C to exit)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    {   tail -n 60 "$LOG_FILE" 2>/dev/null | grep -a -vE ' /home/' | tail -n 10
        echo "GFM_SEP"
        tail -f "$LOG_FILE" 2>/dev/null | grep -a --line-buffered -vE ' /home/'
    } | while IFS= read -r line; do
        if [ "$line" = "GFM_SEP" ]; then
            echo -e "${GRAY}─── following ───${NC}"
            continue
        fi
        local ts=$(echo "$line" | grep -oE '^\[[0-9:]+\]' | tr -d '[]')
        local content=$(echo "$line" | sed 's/^\[[0-9:]\+\] //')
        colorize_line "${ts:-??:??:??}" "$content"
    done
}

# ========== Frontend monitor ==========
run_monitor() {
    check_deps || return 1

    cd "$MONITOR_HOME"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[monitor-sync] Frontend Mode${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Live file changes (Ctrl+C to exit)"
    echo ""
    echo -e "${GRAY}Use 'tail' for push results${NC}"
    echo ""

    inotifywait -m -r -q \
        --exclude '\.git/|_ext/|\.snapshots/|node_modules/|\.log$|\.monitor-sync\.|\.tmp$|\.tmp\.|\.swp$' \
        -e modify,create,delete,move \
        "$WATCH_DIR" 2>/dev/null | while read -r path action file; do
            local full_path="${path}${file}"
            local repo_root
            repo_root=$(get_repo_root "$full_path" 2>/dev/null) || continue
            echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${YELLOW}$action${NC} [$(repo_name "$repo_root")] $path$file"
        done
}

# ========== Help ==========
show_help() {
    echo ""
    echo -e "${CYAN}monitor-sync.sh${NC} — Multi-repo file monitoring & auto-sync"
    echo ""
    echo -e "${GREEN}Commands:${NC}"
    echo "  start              Start in background (silent)"
    echo "  stop               Stop monitoring"
    echo "  status             Show status + tracked repos"
    echo "  log [N]            Show last N log lines"
    echo "  monitor            Frontend: file changes"
    echo "  tail               Frontend: push results"
    echo ""
    echo -e "${GREEN}Flow:${NC}"
    echo "  Watch ~/git/ → 30s debounce → sync only repos with changes"
    echo "  Push 前先 pull --rebase（多终端安全）+ 心跳每 5min 收敛对端提交"
    echo "  ${GRAY}查看双端收敛状态: bash maintain.sh status${NC}"
    echo ""
}

# ========== Push public ==========
# ========== Main ==========
case "${1:-}" in
    start)    start_watch ;;
    stop)     stop_watch ;;
    status)   status_watch ;;
    restart)  restart_watch ;;
    log)      log_watch "${2:-}" ;;
    monitor)  run_monitor ;;
    "")   start_watch ;;
    tail)     tail_watch ;;
    help|--help|-h) show_help ;;
    *)        echo -e "${RED}Unknown: $1${NC}"; show_help; exit 1 ;;
esac
