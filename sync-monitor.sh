#!/bin/bash
# Claude Config - File monitoring & auto-sync script (Linux/WSL)
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
    REPO_DIR="$SCRIPT_DIR"
else
    REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
PID_FILE="$REPO_DIR/.monitor-sync.pid"
LOG_FILE="$REPO_DIR/.monitor-sync.log"

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

# ========== Check deps ==========
check_deps() {
    if ! command -v inotifywait &>/dev/null; then
        error "Missing inotifywait (see header for install instructions)"
        return 1
    fi
}

# ========== Commit and push ==========
commit_and_push() {
    cd "$REPO_DIR"
    rm -f "$REPO_DIR/.git/index.lock" 2>/dev/null

    # Check for changes
    if ! git status --porcelain 2>/dev/null | grep -q .; then
        return 0
    fi

    local changed_files=$(git status --short 2>/dev/null)
    [ -z "$changed_files" ] && return 0

    echo "" | tee -a "$LOG_FILE"
    log "== Detected changes =="
    echo "$changed_files" | tee -a "$LOG_FILE"
    log "======================"

    # Check for unmerged conflicts
    if git ls-files -u 2>/dev/null | grep -q .; then
        echo "" | tee -a "$LOG_FILE"
        error "=========================================="
        error "UNRESOLVED GIT CONFLICTS detected"
        error "Do NOT git add/commit - resolve manually first"
        error "Then restart monitor-sync"
        error "=========================================="
        echo "" | tee -a "$LOG_FILE"
        return 1
    fi

    git add -A 2>/dev/null
    local commit_msg="Auto-sync: $(date '+%Y-%m-%d %H:%M:%S')"
    local commit_output

    if commit_output=$(git commit -m "$commit_msg" 2>&1); then
        local commit_hash=$(echo "$commit_output" | grep -o '[a-f0-9]\{7\}' | tail -1)
        log "Committed: $commit_hash"

        log "Pulling --ff..."
        local pull_output
        if pull_output=$(timeout 120 git pull --ff origin main 2>&1); then
            log "Pull OK"
            if timeout 60 git push origin main >> "$LOG_FILE" 2>&1; then
                log "== Pushed to GitHub =="
                log "Commit: $commit_hash"
                echo "$changed_files" | while read line; do
                    log "  $line"
                done
            else
                warn "Push failed - check network"
            fi
        else
            echo "$pull_output" >> "$LOG_FILE"
            echo "" | tee -a "$LOG_FILE"
            error "=========================================="
            error "PULL FAILED: remote has new commits"
            error "=========================================="
            echo "" | tee -a "$LOG_FILE"
            warn "Solution A - Keep local (your changes first):"
            echo "  cd $REPO_DIR && git stash && git pull --ff && git stash pop && git push" | tee -a "$LOG_FILE"
            echo "" | tee -a "$LOG_FILE"
            warn "Solution B - Keep remote (their changes first):"
            echo "  cd $REPO_DIR && git fetch && git reset --hard origin/main" | tee -a "$LOG_FILE"
        fi
    else
        echo "$commit_output" >> "$LOG_FILE"
        if echo "$commit_output" | grep -q "nothing to commit"; then
            log "Nothing to commit"
        else
            warn "Commit failed: $(echo "$commit_output" | head -1)"
        fi
    fi
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

    cd "$REPO_DIR"
    resurrect_pm2

    : > "$LOG_FILE"
    QUIET_MODE=true

    # Single-process pipeline: inotify → log → debounce → commit.
    # Everything runs inside the pipe's while loop so it can't silently die
    # while inotifywait keeps running (the original bug).
    #
    # NOTE: WSL2 inotify is unstable when watching a repo directory directly
    # with --exclude. Watching the parent ~/git works reliably, so we watch
    # the parent and filter events to only care about files under REPO_DIR.
    local watch_dir="$HOME/git"
    local debounce=120
    local min_push_gap=60

    setsid inotifywait -m -r -q \
        --exclude '(\.git/|\.snapshots/)' \
        -e modify,create,delete,move \
        "$watch_dir" 2>/dev/null | while IFS= read -r line; do
            # Skip events not under REPO_DIR
            case "$line" in
                "$REPO_DIR"*) ;;
                *) continue ;;
            esac
            # Skip sync-internal files to avoid feedback loop
            case "$line" in
                *".monitor-sync.log"*|*".monitor-sync.debounce"*|*".monitor-sync.pid"*) continue ;;
            esac
            # Skip transient temp files (editor atomic writes: write .tmp → rename)
            case "$line" in
                *".tmp."*) continue ;;
            esac
            # Skip snapshot files (init-update.sh pre/post versions, gitignored)
            case "$line" in
                *".snapshots/"*) continue ;;
            esac

            echo "[$(date '+%H:%M:%S')] $line" >> "$LOG_FILE"
            date +%s > "$REPO_DIR/.monitor-sync.debounce"
        done &

    local event_pid=$!

    # Debounce loop: checks the timestamp file, triggers commit after quiet period.
    # Runs in a separate background subshell — must NOT use 'local' inside it.
    {
        trap 'kill $event_pid 2>/dev/null; rm -f "$REPO_DIR/.monitor-sync.debounce"; exit' EXIT

        pending=0
        last_push_time=0
        debounce_file="$REPO_DIR/.monitor-sync.debounce"

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
                do_log "File change detected, waiting ${debounce}s debounce..."
            fi

            if [ "$pending" -eq 1 ] && [ $elapsed -ge $debounce ]; then
                gap=$((now - last_push_time))
                if [ "$last_push_time" -gt 0 ] && [ $gap -lt $min_push_gap ]; then
                    do_log "Skipped: <${min_push_gap}s since last push"
                    pending=0
                    rm -f "$debounce_file"
                    continue
                fi

                do_log "Debounce done, pushing..."
                commit_and_push
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
    echo -e "${GRAY}Watching: $watch_dir (filtered to $REPO_DIR)${NC}"
}

# ========== Stop monitoring ==========
stop_watch() {
    # Kill any stale inotifywait processes
    pkill -f "inotifywait.*ccconfig" 2>/dev/null || true

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
    rm -f "$REPO_DIR/.monitor-sync.debounce"
}

# ========== Status ==========
status_watch() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[monitor-sync] Status${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        local mon_pid=$(cat "$PID_FILE")
        echo -e "  ${GREEN}✓${NC} Monitor loop (PID: $mon_pid)"

        # Check inotifywait
        local evt_pid=$(pgrep -f "inotifywait.*/home/francis/git" 2>/dev/null)
        if [ -n "$evt_pid" ]; then
            echo -e "  ${GREEN}✓${NC} inotifywait (PID: $evt_pid)"
        else
            echo -e "  ${RED}✗${NC} inotifywait (dead — restart needed)"
        fi

        # Health: check if log has recent events
        if [ -f "$LOG_FILE" ]; then
            local first_log=$(head -1 "$LOG_FILE" 2>/dev/null | grep -oE '^\[[0-9:]+\]' | tr -d '[]')
            [ -n "$first_log" ] && echo -e "  ${GRAY}Started: $first_log${NC}"

            if [ -s "$LOG_FILE" ]; then
                local last_line=$(tail -1 "$LOG_FILE" 2>/dev/null | sed 's/^\[[0-9:]\+\] //')
                [ -n "$last_line" ] && echo -e "  ${GRAY}Last: $last_line${NC}"
            fi
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

    cd "$REPO_DIR"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[monitor-sync] Frontend Mode${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Live file changes (Ctrl+C to exit)"
    echo ""
    echo -e "${GRAY}Use 'tail' for push results${NC}"
    echo ""

    inotifywait -m -r -q \
        --exclude '\.git/|\.snapshots/|node_modules/|\.log$|\.monitor-sync\.|\.auto-sync\.|\.tmp$|\.swp$|\.tmp' \
        -e modify,create,delete,move \
        "$REPO_DIR" 2>/dev/null | while read -r path action file; do
            echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${YELLOW}$action${NC} $path$file"
        done
}

# ========== Help ==========
show_help() {
    echo ""
    echo -e "${CYAN}monitor-sync.sh${NC} - File monitoring & auto-sync"
    echo ""
    echo -e "${GREEN}Commands:${NC}"
    echo "  start              Start in background (silent)"
    echo "  stop               Stop monitoring"
    echo "  status             Show status"
    echo "  log [N]            Show last N log lines"
    echo "  monitor            Frontend: file changes"
    echo "  tail               Frontend: push results"
    echo ""
    echo -e "${GREEN}Flow:${NC}"
    echo "  Watch → 120s debounce → commit → pull --ff → push"
    echo ""
}

# ========== Main ==========
case "${1:-status}" in
    start)    start_watch ;;
    stop)     stop_watch ;;
    status)   status_watch ;;
    log)      log_watch "$2" ;;
    monitor)  run_monitor ;;
    tail)     tail_watch ;;
    help|--help|-h) show_help ;;
    *)        echo -e "${RED}Unknown: $1${NC}"; show_help; exit 1 ;;
esac
