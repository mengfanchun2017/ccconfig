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
# Install inotifywait (no sudo):
#   mkdir -p ~/.local/lib && cd /tmp
#   curl -sLO http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools/inotify-tools_3.22.6.0-4_amd64.deb
#   dpkg-deb -x inotify-tools_*.deb . && cp usr/bin/inotify* ~/.local/bin/
#   curl -sLO http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools/libinotifytools0_3.22.6.0-4_amd64.deb
#   dpkg-deb -x libinotifytools0_*.deb . && cp usr/lib/x86_64-linux-gnu/libinotifytools.so.0 ~/.local/lib/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/dry-run.sh"
if [ -d "$SCRIPT_DIR/.git" ]; then
    MONITOR_HOME="$SCRIPT_DIR"
else
    MONITOR_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
PID_FILE="${MONITOR_PID_FILE:-$MONITOR_HOME/.monitor-sync.pid}"
LOG_FILE="$MONITOR_HOME/.monitor-sync.log"
DEBOUNCE_FILE="$MONITOR_HOME/.monitor-sync.debounce"
CHANGED_REPOS_FILE="$MONITOR_HOME/.monitor-sync.changed-repos"
WATCH_DIR="$HOME/git"

export PATH="$HOME/.local/bin:$PATH"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$HOME/.local/lib:$LD_LIBRARY_PATH}"

# Colors
source "$SCRIPT_DIR/colors.sh"

# Quiet mode for start command
QUIET_MODE=false

# Log to file (always)
do_log() {
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
}

# Log to terminal + file
log()    { do_log "$1"; $QUIET_MODE && return; echo -e "${GREEN}[SYNC]${NC} $1"; }
warn()   { do_log "WARN: $1"; $QUIET_MODE && return; echo -e "${YELLOW}[SYNC]${NC} $1"; }
info()   { do_log "$1"; $QUIET_MODE && return; echo -e "${CYAN}[SYNC]${NC} $1"; }
error()  { do_log "ERROR: $1"; $QUIET_MODE && return; echo -e "${RED}[SYNC]${NC} $1"; }

# ========== PAT 过期检查 ==========
# 三个触发点：monitor start / commit_and_push 末尾 / git_push auth error
# 缓存 6h 避免每次 commit 都 curl（auth error 时强制刷新）
PAT_CACHE_FILE="$HOME/.local/share/ccconfig/pat-status"
PAT_WARN_FILE="$HOME/.local/share/ccconfig/pat-warn"
PAT_CACHE_TTL=21600  # 6h

check_pat_status() {
    local force="${1:-false}"

    # 缓存检查（force=true 跳过）
    if [[ "$force" != "true" ]] && [[ -f "$PAT_CACHE_FILE" ]]; then
        local cache_mtime=$(stat -c %Y "$PAT_CACHE_FILE" 2>/dev/null || echo 0)
        local now=$(date +%s)
        [[ $((now - cache_mtime)) -lt $PAT_CACHE_TTL ]] && return 0
    fi

    # gh 未登录 → 跳过（让其他 check 报告）
    local token=$(gh auth token 2>/dev/null) || return 0

    # curl 拿 expiration header（5s timeout，不阻塞 monitor）
    local exp=$(curl -s --max-time 5 -H "Authorization: Bearer $token" \
        -D - https://api.github.com/user -o /dev/null 2>/dev/null | \
        grep -i 'github-authentication-token-expiration:' | \
        awk '{print $2}' | tr -d '\r')
    [[ -z "$exp" ]] && { rm -f "$PAT_CACHE_FILE" "$PAT_WARN_FILE"; return 0; }

    local exp_epoch=$(date -d "$exp UTC" +%s 2>/dev/null) || return 0
    local now=$(date +%s)
    local days_left=$(( (exp_epoch - now) / 86400 ))

    mkdir -p "$(dirname "$PAT_CACHE_FILE")"
    echo "${days_left}|${exp}" > "$PAT_CACHE_FILE"
    chmod 600 "$PAT_CACHE_FILE"

    # 根据剩余天数告警
    if [[ $days_left -lt 10 ]]; then
        log_pat_warn "$days_left" "$exp" "critical"
    elif [[ $days_left -lt 30 ]]; then
        log_pat_warn "$days_left" "$exp" "warn"
    else
        # 健康：清除旧 warn flag
        rm -f "$PAT_WARN_FILE"
    fi
}

log_pat_warn() {
    local days="$1" exp="$2" level="$3"
    local sym="⚠ "
    [[ "$level" == "critical" ]] && sym="❌"

    do_log ""
    do_log "═══════════════════════════════════════════════════════════════"
    do_log "${sym} GitHub PAT 即将过期（剩余 ${days} 天，过期 ${exp} UTC）"
    do_log "───────────────────────────────────────────────────────────────"
    do_log "续期（30 秒）："
    do_log "  1. 打开 https://github.com/settings/tokens"
    do_log "  2. 找到 ccconfig-push，点 Regenerate token"
    do_log "  3. 复制新 token，然后跑："
    do_log ""
    do_log "       bash ~/git/ccconfig/bin/refresh-gh-auth.sh"
    do_log ""
    do_log "  或手动："
    do_log "       gh auth login --with-token <<< \"<new-token>\""
    do_log "       gh auth setup-git"
    do_log "═══════════════════════════════════════════════════════════════"
    do_log ""

    # 写 flag 文件给 status.sh / SessionStart hook 读
    mkdir -p "$(dirname "$PAT_WARN_FILE")"
    echo "${days}|${exp}|${level}" > "$PAT_WARN_FILE"
    chmod 600 "$PAT_WARN_FILE"
}

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

check_deps() {
    if ! command -v inotifywait &>/dev/null; then
        error "Missing inotifywait (see header for install instructions)"
        return 1
    fi
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

# Push with retry (network intermittent on WSL)
git_push() {
    local repo_dir="$1" branch="$2"
    local attempt=1 max_attempts=3
    local output rc
    while [ $attempt -le $max_attempts ]; do
        set +e
        output=$(timeout 30 git -C "$repo_dir" push origin "$branch" 2>&1)
        rc=$?
        set -e
        if [ $rc -eq 0 ]; then
            echo "$output"
            return 0
        fi
        if echo "$output" | grep -qiE "bad credentials|401|token.*expired|invalid_token|authentication failed|unauthorized"; then
            # Auth error → 强制检查 PAT 状态 + 写醒目 warn（不重试，续期后才能 push）
            check_pat_status "true"
            echo "$output" >&2
            return $rc
        elif echo "$output" | grep -qi "connection\|network\|Recv failure\|reset by peer\|timeout\|Could not resolve"; then
            if [ $attempt -lt $max_attempts ]; then
                log "[$(repo_name "$repo_dir")] push attempt $attempt failed, retry in 10s..."
                sleep 10
            fi
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
    if ! mkdir "$lock_dir" 2>/dev/null; then
        do_log "[$repo] skip — sync already in progress"
        return 0
    fi
    trap "rmdir '$lock_dir' 2>/dev/null" RETURN

    rm -f "$repo_dir/.git/index.lock" 2>/dev/null

    local changed_files=$(git -C "$repo_dir" status --porcelain 2>/dev/null)
    if [ -z "$changed_files" ]; then
        local branch=$(git -C "$repo_dir" branch --show-current)
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
                warn "[$repo] !! push failed — check network"
            fi
        else
            log "[$repo] already up to date"
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

    local commit_output

    if commit_output=$(git -C "$repo_dir" commit -m "Auto-sync: $(date '+%Y-%m-%d %H:%M:%S')" 2>&1); then
        local commit_hash=$(echo "$commit_output" | grep -o '[a-f0-9]\{7\}' | tail -1)
        log "[$repo] OK committed $commit_hash"

        local branch=$(git -C "$repo_dir" branch --show-current)
        local skip_push=false

        # Proxy health check: if proxy is configured but down, skip pull (avoids hang)
        if [ -n "${HTTPS_PROXY}${https_proxy}${HTTP_PROXY}${http_proxy}" ] && ! check_proxy; then
            do_log "[$repo] proxy not reachable, skipping pull (push directly)"
        else
            local pull_attempt=1 pull_max=2
            local pull_ok=false
            while [ $pull_attempt -le $pull_max ]; do
                local pull_output pull_rc
                set +e
                pull_output=$(timeout --kill-after=5 30 git -C "$repo_dir" pull --rebase origin "$branch" 2>&1)
                pull_rc=$?
                set -e
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
                warn "[$repo] !! push failed — check network"
            fi
        fi
    else
        if echo "$commit_output" | grep -q "nothing to commit"; then
            :  # not an error
        else
            warn "[$repo] commit failed: $(echo "$commit_output" | head -1)"
        fi
    fi

    # 每次 commit_and_push 完后检查 PAT（cache 6h，不频繁）
    check_pat_status
}

# Sync a list of repos (one per line). Empty arg = sync all.
# 默认全量（旧终端 / pub 路径），debounce 路径传改动列表
sync_repos() {
    local repos_arg="$1"
    local repos
    if [ -n "$repos_arg" ]; then
        repos="$repos_arg"
    else
        repos=$(list_repos)
    fi
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
start_watch() {
    check_deps || return 1

    # PIDFile 检查：活的 + 是 monitor.sh 自身 → service 已在跑，exit 0
    # 防止 systemd Type=forking 看到 exit 1 → enable --now 失败
    # 幂等：任一 PIDFile 指向存活 monitor → 已有实例，直接返回
    # systemd 实例写 /run/...，手动实例写默认路径，两个都查，避免重复 start 互不知情
    local pid_candidate=""
    for pf in "$PID_FILE" /run/claude-auto-sync/monitor.pid; do
        if [ -f "$pf" ] && kill -0 "$(cat "$pf" 2>/dev/null)" 2>/dev/null; then
            local existing_cmd
            existing_cmd=$(cat "/proc/$(cat "$pf" 2>/dev/null)/cmdline" 2>/dev/null | tr '\0' ' ')
            if [[ "$existing_cmd" == *"monitor.sh"* ]]; then
                pid_candidate="$(cat "$pf" 2>/dev/null)"
                break
            fi
        fi
    done
    if [ -n "$pid_candidate" ]; then
        do_log "Already running (PID: $pid_candidate) — keep alive"
        return 0
    fi
    # PIDFile 残留（指向无关进程或死进程），清理后重启
    for pf in "$PID_FILE" /run/claude-auto-sync/monitor.pid; do
        [ -f "$pf" ] && rm -f "$pf"
    done

    cd "$MONITOR_HOME"
    QUIET_MODE=true
    resurrect_pm2 &
    # PAT 过期检查：后台异步跑一次，6h 内 cache，不阻塞 monitor 启动
    check_pat_status &

    # 清理上次崩溃残留的僵尸 inotifywait：只杀孤儿（PPID=1），不误杀运行中实例
    # pkill -f 匹配太宽，会杀掉同目录所有 inotifywait（含健康实例）→ 触发 restart 风暴
    for p in $(pgrep -f "inotifywait.*$WATCH_DIR" 2>/dev/null); do
        [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "1" ] && kill "$p" 2>/dev/null || true
    done
    sleep 1

    rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE"
    find "$WATCH_DIR" -maxdepth 2 -name '.monitor-sync.lock' -type d -exec rmdir {} \; 2>/dev/null || true

    # Single inotify watching ~/git/, accepting events from any tracked repo.
    # Debounce triggers sync_repos with only the changed repo list (L2 优化).
    local debounce=60
    local min_push_gap=60

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
            local filepath=$(echo "$line" | awk '{print $1}')
            local repo_root
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
        trap 'kill $event_pid 2>/dev/null; pkill -P $event_pid 2>/dev/null; rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE" "$PID_FILE"; exit' EXIT
        # systemd stop / Ctrl+C：快速干净退出，避免 stop-sigterm 90s 超时被 KILL
        trap 'exit 0' TERM INT
        # sync 里 git 命令偶发非零，不能 let set -e 终止整个 loop → systemd 疯狂 restart
        set +e

        pending=0
        last_push_time=0
        idle_ticks=0
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
                inotify_restarts=$((inotify_restarts + 1))
                if [ $inotify_restarts -gt $inotify_max_restarts ]; then
                    do_log "inotifywait died $inotify_max_restarts times, giving up"
                    echo "failed" > "$STATUS_FILE"
                    break
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
            if [ ! -f "$DEBOUNCE_FILE" ]; then
                idle_ticks=$((idle_ticks + 1))
                # Periodic full sync every 12h idle (21600 ticks × 2s)
                if [ $idle_ticks -ge 21600 ]; then
                    idle_ticks=0
                    now=$(date +%s)
                    gap=$((now - last_push_time))
                    if [ "$last_push_time" -eq 0 ] || [ "$gap" -ge "$min_push_gap" ]; then
                        do_log "Periodic sync (12h idle)"
                        sync_repos
                        last_push_time=$(date +%s)
                    fi
                fi
                continue
            fi
            idle_ticks=0
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
                    do_log "Skipped: <${min_push_gap}s since last push"
                    pending=0
                    rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE"
                    continue
                fi

                # 去重改动 repo 列表，sync_repos 不传 = 全量（fallback 行为）
                changed=$(sort -u "$CHANGED_REPOS_FILE" 2>/dev/null | grep -v '^$' || true)
                if [ -z "$changed" ]; then
                    do_log "Debounce done, no changed repos recorded — syncing all (fallback)"
                    sync_repos
                else
                    do_log "Debounce done, syncing $(echo "$changed" | wc -l) changed repo(s)..."
                    sync_repos "$changed"
                fi
                pending=0
                last_push_time=$(date +%s)
                rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE"
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
    (
        sleep 30
        do_log "Initial scan for pending changes..."
        sync_repos
    ) &
}

# ========== Stop monitoring ==========
stop_watch() {
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

# ========== Status ==========
status_watch() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[monitor-sync] Status${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        local mon_pid=$(cat "$PID_FILE")
        echo -e "  ${GREEN}✓${NC} Monitor loop (PID: $mon_pid)"
    elif [ -f /run/claude-auto-sync/monitor.pid ] && kill -0 "$(cat /run/claude-auto-sync/monitor.pid)" 2>/dev/null; then
        # systemd 启动时把 PID 写到 /run/claude-auto-sync/monitor.pid
        local mon_pid=$(cat /run/claude-auto-sync/monitor.pid)
        echo -e "  ${GREEN}✓${NC} Monitor loop (PID: $mon_pid, via systemd PIDFile)"
    elif pgrep -f 'monitor.sh start' &>/dev/null; then
        # 最后兜底：直接 pgrep
        local mon_pid=$(pgrep -f 'monitor.sh start' | head -1)
        echo -e "  ${GREEN}✓${NC} Monitor loop (PID: $mon_pid, pgrep fallback)"
    else
        echo -e "  ${RED}✗${NC} Not running"
        return
    fi

    local evt_pid=$(pgrep -f "inotifywait.*$WATCH_DIR" 2>/dev/null)
    if [ -n "$evt_pid" ]; then
        echo -e "  ${GREEN}✓${NC} inotifywait (PID: $evt_pid)"
    else
        echo -e "  ${RED}✗${NC} inotifywait (dead — restart needed)"
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

    # LLM Gateway
    echo -n "  LLM Gateway ... "
    local llm_pid_file="$HOME/.cache/llmswitch.pid"
    if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then
        local proxy_health=$(curl -s --max-time 2 http://127.0.0.1:8899/health 2>/dev/null || echo '{}')
        local llm_mode=$(echo "$proxy_health" | python3 -c "import json,sys; print(json.load(sys.stdin).get('mode','?'))" 2>/dev/null)
        local llm_peak=$(echo "$proxy_health" | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak',False))" 2>/dev/null)
        local llm_route=$(echo "$proxy_health" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_route','?'))" 2>/dev/null)
        if [ "$llm_mode" = "auto" ] && [ "$llm_peak" = "True" ]; then
            echo -e "${YELLOW}●${NC} auto → ${YELLOW}${llm_route}${NC} (peak)"
        elif [ "$llm_mode" = "manual" ]; then
            echo -e "${GREEN}●${NC} manual → ${llm_route}"
        elif [ "$llm_mode" = "off" ]; then
            echo -e "${GRAY}●${NC} off"
        else
            echo -e "${GREEN}●${NC} auto → ${llm_route}"
        fi
    else
        echo -e "${GRAY}－${NC} not running"
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

    # SUCCESS (green) — "OK" prefix, key milestones
    if echo "$content" | grep -qE '(OK pushed|OK committed|OK pull|OK links|OK skills|Started|Stopped|Resurrecting)'; then
        echo -e "  ${GREEN}${ts}${NC}  $content"
        return
    fi

    # LLMSWITCH (orange) — gateway route/start/stop/mode events
    if echo "$content" | grep -qE '^llmswitch'; then
        echo -e "  ${ORANGE}${ts}${NC}  $content"
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
    echo "  Watch ~/git/ → 120s debounce → sync only repos with changes"
    echo ""
}

# ========== Push public ==========
push_public() {
    if [ ! -f "$SCRIPT_DIR/pushpub.sh" ]; then
        echo -e "${RED}[SYNC]${NC} pushpub.sh not found"
        return 1
    fi
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[SYNC] Export to ccconfig-public${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    bash "$SCRIPT_DIR/pushpub.sh"
}

# ========== Main ==========
case "${1}" in
    start)    start_watch ;;
    stop)     stop_watch ;;
    status)   status_watch ;;
    log)      log_watch "${2:-}" ;;
    monitor)  run_monitor ;;
    ""|start) start_watch ;;
    tail)     tail_watch ;;
    pub|pushpub) push_public ;;
    help|--help|-h) show_help ;;
    *)        echo -e "${RED}Unknown: $1${NC}"; show_help; exit 1 ;;
esac
