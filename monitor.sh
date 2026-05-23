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
WATCH_DIR="$HOME/git"

export PATH="$HOME/.local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

    rm -f "$repo_dir/.git/index.lock" 2>/dev/null

    local repo=$(repo_name "$repo_dir")
    local changed_files=$(git -C "$repo_dir" status --porcelain 2>/dev/null)
    [ -z "$changed_files" ] && return 0

    echo "" | tee -a "$LOG_FILE"
    info "[$repo] changes detected"
    echo "$changed_files" | while read line; do do_log "[$repo]   $line"; done

    if git -C "$repo_dir" ls-files -u 2>/dev/null | grep -q .; then
        error "[$repo] UNRESOLVED CONFLICTS — manual resolution needed"
        return 1
    fi

    git -C "$repo_dir" add -A 2>/dev/null || warn "[$repo] git add failed (nested .git?)"
    local commit_output

    if commit_output=$(git -C "$repo_dir" commit -m "Auto-sync: $(date '+%Y-%m-%d %H:%M:%S')" 2>&1); then
        local commit_hash=$(echo "$commit_output" | grep -o '[a-f0-9]\{7\}' | tail -1)
        log "[$repo] committed $commit_hash"

        local branch=$(git -C "$repo_dir" branch --show-current)
        local pull_output
        if pull_output=$(timeout 120 git -C "$repo_dir" pull --ff-only origin "$branch" 2>&1); then
            log "[$repo] pull OK"
            if [ -f "$repo_dir/setup-links.sh" ]; then
                bash "$repo_dir/setup-links.sh" >> "$LOG_FILE" 2>&1 && \
                    log "[$repo] links OK" || warn "[$repo] links failed"
            fi
            if [ -f "$repo_dir/init-skill.sh" ]; then
                bash "$repo_dir/init-skill.sh" sync >> "$LOG_FILE" 2>&1 && \
                    log "[$repo] skills sync OK" || warn "[$repo] skills sync failed"
            fi
            if timeout 60 git -C "$repo_dir" push origin "$branch" >> "$LOG_FILE" 2>&1; then
                log "[$repo] pushed → GitHub ($commit_hash)"
            else
                warn "[$repo] push failed — check network"
            fi
        else
            echo "$pull_output" >> "$LOG_FILE"
            if echo "$pull_output" | grep -qi "connection\|network\|kex_exchange\|could not read from remote\|gnutls"; then
                warn "[$repo] pull failed: network issue"
            elif echo "$pull_output" | grep -qi "fatal: refusing to merge unrelated histories\|fatal: have diverged\|Not possible to fast-forward"; then
                error "[$repo] pull failed: diverged — run: cd $repo_dir && git pull --ff"
            else
                error "[$repo] pull failed: $(echo "$pull_output" | head -1)"
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

# Scan all repos and sync any with changes
sync_all_repos() {
    local repos=$(list_repos)
    for repo_dir in $repos; do
        commit_and_push "$repo_dir"
    done
}

# ========== PM2 resurrect ==========
resurrect_pm2() {
    export PATH="$HOME/.local/bin:$PATH"
    local waited=0
    while ! pm2 ping &>/dev/null && [ $waited -lt 10 ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if pm2 ping &>/dev/null; then
        log "Resurrecting PM2..."
        pm2 resurrect 2>/dev/null || true
    fi
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

    : > "$LOG_FILE"
    QUIET_MODE=true

    # Single inotify watching ~/git/, accepting events from any tracked repo.
    # Debounce triggers a scan of ALL repos (sync_all_repos).
    local debounce=120
    local min_push_gap=60

    setsid inotifywait -m -r -q \
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
            date +%s > "$MONITOR_HOME/.monitor-sync.debounce"
        done &

    local event_pid=$!

    # Debounce loop → scan all repos
    {
        trap 'kill $event_pid 2>/dev/null; rm -f "$MONITOR_HOME/.monitor-sync.debounce"; exit' EXIT

        pending=0
        last_push_time=0
        debounce_file="$MONITOR_HOME/.monitor-sync.debounce"

        while kill -0 $event_pid 2>/dev/null; do
            sleep 2
            if [ ! -f "$debounce_file" ]; then
                continue
            fi
            evt_ts=$(cat "$debounce_file" 2>/dev/null)
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
                if [ "$last_push_time" -gt 0 ] && [ $gap -lt $min_push_gap ]; then
                    do_log "Skipped: <${min_push_gap}s since last push"
                    pending=0
                    rm -f "$debounce_file"
                    continue
                fi

                do_log "Debounce done, syncing all repos..."
                sync_all_repos
                pending=0
                last_push_time=$(date +%s)
                rm -f "$debounce_file"
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
    rm -f "$MONITOR_HOME/.monitor-sync.debounce"
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

    echo ""
    echo -e "${GRAY}Commands: start | stop | log | monitor | tail${NC}"
    echo ""
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

        if echo "$content" | grep -qE '^(Committed|Pulled|Push|Pushed|==)'; then
            echo -e "  ${GREEN}${ts:-??:??:??}${NC}  $content"
        elif echo "$content" | grep -qE '(detected|change|debounce)'; then
            echo -e "  ${CYAN}${ts:-??:??:??}${NC}  $content"
        elif echo "$content" | grep -qE '(FAILED|ERROR|UNRESOLVED)'; then
            echo -e "  ${RED}${ts:-??:??:??}${NC}  $content"
        elif echo "$content" | grep -qE '(WARN|Skipped|Nothing)'; then
            echo -e "  ${YELLOW}${ts:-??:??:??}${NC}  $content"
        else
            echo -e "  ${GRAY}${ts:-??:??:??}${NC}  $content"
        fi
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

    tail -f "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        local ts=$(echo "$line" | grep -oE '^\[[0-9:]+\]' | tr -d '[]')
        local content=$(echo "$line" | sed 's/^\[[0-9:]\+\] //')

        if echo "$content" | grep -qE '^(Committed|Pulled|Push|Pushed|==)'; then
            echo -e "  ${GREEN}${ts:-??:??:??}${NC}  $content"
        elif echo "$content" | grep -qE '(detected|change|debounce)'; then
            echo -e "  ${CYAN}${ts:-??:??:??}${NC}  $content"
        elif echo "$content" | grep -qE '(FAILED|ERROR|UNRESOLVED)'; then
            echo -e "  ${RED}${ts:-??:??:??}${NC}  $content"
        elif echo "$content" | grep -qE '(WARN|Skipped|Nothing)'; then
            echo -e "  ${YELLOW}${ts:-??:??:??}${NC}  $content"
        else
            echo -e "  ${GRAY}${ts:-??:??:??}${NC}  $content"
        fi
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
    echo "  Watch ~/git/ → 120s debounce → sync ALL repos"
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
