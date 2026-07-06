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

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/.git" ]; then
    MONITOR_HOME="$SCRIPT_DIR"
else
    MONITOR_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
PID_FILE="$MONITOR_HOME/.monitor-sync.pid"
LOG_FILE="$MONITOR_HOME/.monitor-sync.log"
DEBOUNCE_FILE="$MONITOR_HOME/.monitor-sync.debounce"
CHANGED_REPOS_FILE="$MONITOR_HOME/.monitor-sync.changed-repos"
WATCH_DIR="$HOME/git"

export PATH="$HOME/.local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ORANGE='\033[38;5;208m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

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
error()  { do_log "ERROR: $1"; $QUIET_MODE && return; echo -e "${RED}[SYNC]${NC} $1" | tee -a "$LOG_FILE"; }

# ========== Git helpers ==========

# Given a file path, find the nearest parent with .git/
get_repo_root() {
    local dir="$1"
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
            if timeout 60 git -C "$repo_dir" push origin "$branch" >> "$LOG_FILE" 2>&1; then
                local latest_hash=$(git -C "$repo_dir" rev-parse --short HEAD)
                log "[$repo] OK pushed → GitHub ($latest_hash)"
            else
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

    # Skill sync: independent of pull/push, builds local symlinks for new skills in link/skills/.
    # Runs before commit so even "nothing to commit" still rebuilds links.
    if [ -f "$repo_dir/init-skill.sh" ]; then
        local skill_output skill_rc
        skill_output=$(bash "$repo_dir/init-skill.sh" sync 2>&1)
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
        local pull_output pull_rc
        set +e
        pull_output=$(timeout --kill-after=10 60 git -C "$repo_dir" pull --rebase origin "$branch" 2>&1)
        pull_rc=$?
        set -e
        local skip_push=false
        if [ $pull_rc -eq 0 ]; then
            if echo "$pull_output" | grep -q "is up to date\|up-to-date\|Already up to date"; then
                :  # no remote changes
            else
                log "[$repo] OK rebase"
            fi
        else
            echo "$pull_output" >> "$LOG_FILE"
            if [ $pull_rc -eq 124 ] || echo "$pull_output" | grep -qi "connection\|network\|kex_exchange\|could not read from remote\|gnutls\|Recv failure"; then
                warn "[$repo] pull failed (network), pushing directly"
            elif echo "$pull_output" | grep -qi "unrelated histories"; then
                error "[$repo] !! unrelated histories — skip push"
                skip_push=true
            elif echo "$pull_output" | grep -qi "CONFLICT\|conflict\|could not be applied"; then
                git -C "$repo_dir" rebase --abort 2>/dev/null || true
                warn "[$repo] !! rebase 冲突 — reset to origin/$branch"
                git -C "$repo_dir" reset --hard "origin/$branch" 2>&1 | head -1 >> "$LOG_FILE" || true
                git -C "$repo_dir" stash pop 2>/dev/null || true
                skip_push=true
            else
                warn "[$repo] pull failed: $(echo "$pull_output" | head -1)"
            fi
        fi

        if ! $skip_push; then
            if [ -f "$repo_dir/setup-links.sh" ]; then
                local links_output links_rc
                links_output=$(bash "$repo_dir/setup-links.sh" 2>&1)
                links_rc=$?
                echo "$links_output" | while IFS= read -r line; do do_log "[$repo] $line"; done
                if [ $links_rc -eq 0 ]; then
                    log "[$repo] OK links"
                else
                    warn "[$repo] links failed"
                fi
            fi
            if timeout 60 git -C "$repo_dir" push origin "$branch" >> "$LOG_FILE" 2>&1; then
                log "[$repo] OK pushed → GitHub ($commit_hash)"
            else
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
    pm2 ping &>/dev/null && { log "Resurrecting PM2..."; pm2 resurrect 2>/dev/null || true; }
}

# ========== Start monitoring ==========
start_watch() {
    check_deps || return 1

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        warn "Already running (PID: $(cat "$PID_FILE"))"
        return 1
    fi

    cd "$MONITOR_HOME"
    resurrect_pm2 &

    rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE"
    find "$WATCH_DIR" -maxdepth 2 -name '.monitor-sync.lock' -type d -exec rmdir {} \; 2>/dev/null || true
    QUIET_MODE=true

    # Single inotify watching ~/git/, accepting events from any tracked repo.
    # Debounce triggers sync_repos with only the changed repo list (L2 优化).
    local debounce=120
    local min_push_gap=60

    inotifywait -m -r -q \
        --exclude '(\.git/|_ext/|\.snapshots/|node_modules/)' \
        -e modify,create,delete,move \
        "$WATCH_DIR" 2>/dev/null | while IFS= read -r line; do
            # Skip sync-internal files
            case "$line" in
                *".monitor-sync"*) continue ;;
                *".tmp."*) continue ;;
                *".snapshots/"*) continue ;;
                *"_ext/"*) continue ;;
            esac
            # Check if file is under a tracked git repo
            local filepath=$(echo "$line" | awk '{print $1}')
            local repo_root
            repo_root=$(get_repo_root "$filepath" 2>/dev/null) || continue
            # Skip repos without remote
            git -C "$repo_root" remote get-url origin &>/dev/null 2>&1 || continue

            echo "[$(date '+%H:%M:%S')] $(repo_name "$repo_root"): $line" >> "$LOG_FILE"
            date +%s > "$DEBOUNCE_FILE"
            # 记录改动的 repo，debounce 后只 sync 这些（避免无关仓库 add+commit 噪音）
            echo "$repo_root" >> "$CHANGED_REPOS_FILE"
        done &

    local event_pid=$!

    # Debounce loop → sync only repos that had changes
    {
        trap 'kill $event_pid 2>/dev/null; pkill -P $event_pid 2>/dev/null; rm -f "$DEBOUNCE_FILE" "$CHANGED_REPOS_FILE" "$PID_FILE"; exit' EXIT

        pending=0
        last_push_time=0
        idle_ticks=0

        while kill -0 $event_pid 2>/dev/null; do
            sleep 2
            if [ ! -f "$DEBOUNCE_FILE" ]; then
                idle_ticks=$((idle_ticks + 1))
                # Periodic full sync every 30 min idle (900 ticks × 2s)
                if [ $idle_ticks -ge 900 ]; then
                    idle_ticks=0
                    now=$(date +%s)
                    gap=$((now - last_push_time))
                    if [ "$last_push_time" -eq 0 ] || [ "$gap" -ge "$min_push_gap" ]; then
                        do_log "Periodic sync (30min idle)"
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

    echo $monitor_pid > "$PID_FILE"
    echo -e "${GREEN}[SYNC]${NC} Started (monitor: $monitor_pid, events: $event_pid)"
    echo -e "${GRAY}Use: status | log | tail${NC}"
    echo -e "${GRAY}Watching: $WATCH_DIR → all git repos${NC}"
    echo -e "${GRAY}Repos: $(list_repos | xargs -I{} basename {} | tr '\n' ' ')${NC}"
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
    else
        echo -e "  ${RED}✗${NC} Not running"
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
    local service_file="$HOME/.config/systemd/user/claude-auto-sync.service"
    echo -n "  systemd 自启动 ... "
    if [ -f "$service_file" ]; then
        echo -e "${GREEN}✅${NC}"
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
        echo -e "${YELLOW}[SYNC]${NC} monitor-sync not running"
        return
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[monitor-sync] Tail (Ctrl+C to exit)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    {   tail -n 60 "$LOG_FILE" 2>/dev/null | grep -vE ' /home/' | tail -n 10
        echo "GFM_SEP"
        tail -f "$LOG_FILE" 2>/dev/null | grep -vE ' /home/'
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
        --exclude '\.git/|_ext/|\.snapshots/|node_modules/|\.log$|\.monitor-sync\.|\.tmp$|\.swp$' \
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
case "${1:-status}" in
    start)    start_watch ;;
    stop)     stop_watch ;;
    status)   status_watch ;;
    log)      log_watch "$2" ;;
    monitor)  run_monitor ;;
    tail)     tail_watch ;;
    pub|pushpub) push_public ;;
    help|--help|-h) show_help ;;
    *)        echo -e "${RED}Unknown: $1${NC}"; show_help; exit 1 ;;
esac
