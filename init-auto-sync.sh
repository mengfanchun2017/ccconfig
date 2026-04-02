#!/bin/bash
# Claude Config - 自动同步脚本 (Linux/WSL)
#
# 功能：监控文件变化，自动提交并推送到 GitHub
# 使用：./auto-sync.sh [start|stop|status]
#
# 依赖：inotifywait (Linux/WSL)
#       安装：sudo apt-get install inotify-tools
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 如果脚本在 claude-config/ 目录下，REPO_DIR 就是 SCRIPT_DIR
# 如果脚本在上一级（传统方式），REPO_DIR 就是 SCRIPT_DIR/..
if [ -d "$SCRIPT_DIR/.git" ]; then
    REPO_DIR="$SCRIPT_DIR"
else
    REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
PID_FILE="$REPO_DIR/.auto-sync.pid"
LOG_FILE="$REPO_DIR/.auto-sync.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[auto-sync]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[auto-sync]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[auto-sync]${NC} $1" | tee -a "$LOG_FILE"; }

# ========== 检查依赖 ==========
check_deps() {
    if ! command -v inotifywait &>/dev/null; then
        error "缺少 inotifywait，请安装：sudo apt-get install inotify-tools"
        return 1
    fi
}

# ========== 提交并推送 ==========
commit_and_push() {
    cd "$REPO_DIR"

    # 检查是否有变化（包括 untracked files）
    if git status --porcelain 2>/dev/null | grep -q .; then
        :  # 有变化，继续
    else
        return 0  # 没有变化
    fi

    # 获取变化文件列表
    local changed=$(git status --short 2>/dev/null | head -5 | sed 's/^/  /')
    if [ -z "$changed" ]; then
        return 0
    fi
    log "检测到变化："
    echo "$changed" | tee -a "$LOG_FILE"

    # Stage 所有变化
    git add -A 2>/dev/null

    # 生成提交信息
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local commit_msg="自动同步: $timestamp"

    # 提交
    if git commit -m "$commit_msg" 2>&1 | tee -a "$LOG_FILE"; then
        log "已提交"

        # 推送
        if git push origin main 2>&1 | tee -a "$LOG_FILE"; then
            log "已推送到 GitHub"
        else
            warn "推送失败，可能有冲突"
        fi
    fi
}

# ========== 启动监控 ==========
start_watch() {
    check_deps || return 1

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        warn "已经在运行中 (PID: $(cat "$PID_FILE"))"
        return 1
    fi

    cd "$REPO_DIR"

    log "启动文件监控..."
    log "监控目录: $REPO_DIR"
    log "排除: .git/, node_modules/, *.log, .auto-sync.*"

    # 清空日志文件
    : > "$LOG_FILE"

    # 后台运行 inotifywait
    inotifywait -m -r -q \
        --exclude '(\.git/|node_modules/|\.log$|\.auto-sync\.|\.tmp$)' \
        -e modify,create,delete,move \
        "$REPO_DIR" \
        >> "$LOG_FILE" 2>&1 &

    local notify_pid=$!
    echo $notify_pid > "$PID_FILE"
    log "监控已启动 (PID: $notify_pid)"

    # 防抖参数
    local debounce=3
    local last_change=0
    local pending=false

    # 主循环：每秒检查一次
    while kill -0 $notify_pid 2>/dev/null; do
        sleep 1

        # 检查是否有新事件（LOG_FILE 有内容）
        if [ -s "$LOG_FILE" ]; then
            local now=$(date +%s)
            local time_diff=$((now - last_change))

            if [ "$pending" = true ] && [ $time_diff -ge $debounce ]; then
                # 等待足够久，执行提交
                commit_and_push
                pending=false
                last_change=$now
            elif [ "$pending" = false ]; then
                # 首次检测到事件
                pending=true
                last_change=$now
            else
                # 还在 debounce 期间
                : # pending 保持 true
            fi

            # 清空日志（避免重复检测）
            : > "$LOG_FILE"
        fi
    done &
}

# ========== 停止监控 ==========
stop_watch() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null && log "已停止监控" || error "停止失败"
        else
            warn "进程不存在"
        fi
        rm -f "$PID_FILE"
    else
        warn "未运行"
    fi
}

# ========== 查看状态 ==========
status_watch() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        log "运行中 (PID: $(cat "$PID_FILE"))"
    else
        log "未运行"
    fi
}

# ========== 主程序 ==========
case "${1:-start}" in
    start)
        start_watch
        ;;
    stop)
        stop_watch
        ;;
    status)
        status_watch
        ;;
    *)
        echo "用法: $0 {start|stop|status}"
        exit 1
        ;;
esac
