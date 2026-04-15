#!/bin/bash
# Claude Config - 文件监控与自动同步脚本 (Linux/WSL)
#
# 功能：监控文件变化 → 防抖 120s → commit → pull --ff → push
#       pull --ff 解决多机同时 push 的冲突
# 使用：
#   monitor-sync.sh start      后台启动监控
#   monitor-sync.sh stop       停止监控
#   monitor-sync.sh status     查看状态
#   monitor-sync.sh log [N]    查看最近N行日志（默认20）
#   monitor-sync.sh monitor    前台持续监控（手动查看用）
#
# 依赖：inotifywait (Linux/WSL)
#       安装：sudo apt-get install inotify-tools
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/.git" ]; then
    REPO_DIR="$SCRIPT_DIR"
else
    REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
PID_FILE="$REPO_DIR/.monitor-sync.pid"
LOG_FILE="$REPO_DIR/.monitor-sync.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local msg="[$(date '+%H:%M:%S')] $1"
    echo -e "${GREEN}[monitor]${NC} $1"
    echo "$msg" >> "$LOG_FILE"
}
warn() {
    local msg="[$(date '+%H:%M:%S')] $1"
    echo -e "${YELLOW}[monitor]${NC} $1"
    echo "$msg" >> "$LOG_FILE"
}
info() {
    echo -e "${CYAN}[monitor]${NC} $1"
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
}
error() { echo -e "${RED}[monitor]${NC} $1" | tee -a "$LOG_FILE"; }

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

    # 清理可能的陈旧锁文件（git crash 后遗留）
    rm -f "$REPO_DIR/.git/index.lock" 2>/dev/null

    # 检查是否有变化（包括 untracked files）
    if ! git status --porcelain 2>/dev/null | grep -q .; then
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

    # 提交（检查返回值，因为 pipe 可能掩盖失败）
    local commit_output
    if commit_output=$(git commit -m "$commit_msg" 2>&1); then
        echo "$commit_output" >> "$LOG_FILE"
        log "已提交"

        # 先 pull --ff，再 push（解决多机冲突）
        log "正在 pull --ff ..."
        local pull_output
        if pull_output=$(git pull --ff origin main 2>&1); then
            echo "$pull_output" >> "$LOG_FILE"
            log "pull 成功"
        else
            # pull 失败（可能是两台机器同时有提交）
            echo "$pull_output" >> "$LOG_FILE"
            warn "pull 失败（对方有新提交）: $(echo "$pull_output" | grep -v "^Merge" | grep -v "^ " | head -1)"
            warn "请手动处理: cd $REPO_DIR && git pull --ff origin main"
        fi

        # 推送
        if git push origin main >> "$LOG_FILE" 2>&1; then
            log "已推送到 GitHub"
        else
            warn "推送失败，可能有冲突"
        fi
    else
        # 提交失败（可能是 lock 或无变化）
        echo "$commit_output" >> "$LOG_FILE"
        if echo "$commit_output" | grep -q "nothing to commit"; then
            log "无变化可提交"
        else
            warn "提交失败: $(echo "$commit_output" | head -1)"
        fi
    fi
}

# ========== PM2 进程复活 ==========
resurrect_pm2() {
    export PATH="$HOME/.local/bin:$PATH"

    # 等待 PM2 daemon 就绪（最多 10 秒）
    local waited=0
    while ! pm2 ping &>/dev/null && [ $waited -lt 10 ]; do
        sleep 1
        waited=$((waited + 1))
    done

    if pm2 ping &>/dev/null; then
        log "复活 PM2 进程..."
        pm2 resurrect 2>/dev/null || true
    else
        warn "PM2 daemon 未就绪，跳过 resurrect"
    fi
}

# ========== 启动监控 ==========
start_watch() {
    check_deps || return 1

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        warn "已经在运行中 (PID: $(cat "$PID_FILE"))，使用 monitor 查看前台实时输出"
        return 1
    fi

    cd "$REPO_DIR"

    # 复活 PM2 进程（ccbot 等）
    resurrect_pm2

    log "启动文件监控..."
    log "监控目录: $REPO_DIR"
    log "排除: .git/, node_modules/, *.log, .monitor-sync.*, .auto-sync.*, *.swp"

    # 清空日志文件
    : > "$LOG_FILE"

    # 使用 setsid 完全脱离终端，避免 Claude Code PTY 中后台进程仍输出到终端
    # setsid 创建新会话，inotifywait 不再属于当前 session 的前台进程组
    setsid inotifywait -m -r -q \
        --exclude '(\.git/|node_modules/|\.log$|\.monitor-sync\.|\.auto-sync\.|\.tmp$|\.swp$|\.tmp)' \
        -e modify,create,delete,move \
        "$REPO_DIR" \
        >> "$LOG_FILE" 2>&1 </dev/null &

    local notify_pid=$!
    echo $notify_pid > "$PID_FILE"
    log "监控已启动 (PID: $notify_pid)"

    # 防抖参数（秒）：等待变化稳定后再提交，避免频繁变化时反复提交
    local debounce=120
    local last_change=0
    local pending=false

    # 主循环：每秒检查一次
    while kill -0 $notify_pid 2>/dev/null; do
        sleep 1

        # 检查是否有新事件（LOG_FILE 有内容）
        if [ -s "$LOG_FILE" ]; then
            local now=$(date +%s)

            if [ "$pending" = true ]; then
                # 已在防抖中，更新 last_change（新变化重置计时器）
                last_change=$now
            else
                # 首次检测到事件，开始防抖
                pending=true
                last_change=$now
            fi

            # 清空日志（避免重复检测）
            : > "$LOG_FILE"
        fi

        # 防抖计时器：只有在 pending=true 且超过 debounce 秒后才提交
        if [ "$pending" = true ]; then
            local time_diff=$(( $(date +%s) - last_change ))
            if [ $time_diff -ge $debounce ]; then
                commit_and_push
                pending=false
            fi
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

# ========== 查看日志 ==========
log_watch() {
    local lines="${1:-20}"
    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        echo "=== 最近 monitor-sync 活动 (最后 $lines 行) ==="
        tail -n "$lines" "$LOG_FILE"
    else
        echo "无日志记录"
    fi
}

# ========== 实时跟踪 ==========
tail_watch() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "实时跟踪 monitor-sync（Ctrl+C 退出）..."
        tail -f "$LOG_FILE"
    else
        echo "monitor-sync 未运行"
    fi
}

# ========== 前台持续监控模式 ==========
run_monitor() {
    check_deps || return 1

    cd "$REPO_DIR"

    echo ""
    echo "========================================"
    echo "  monitor-sync 前台模式"
    echo "  实时显示文件变化和同步活动"
    echo "  Ctrl+C 退出（后台监控继续运行）"
    echo "========================================"
    echo ""

    info "启动前台监控..."
    info "监控目录: $REPO_DIR"

    : > "$LOG_FILE"

    # 前台运行 inotifywait（不 setsid，不 &，直接在终端显示）
    inotifywait -m -r -q \
        --exclude '(\.git/|node_modules/|\.log$|\.monitor-sync\.|\.auto-sync\.|\.tmp$|\.swp$|\.tmp)' \
        -e modify,create,delete,move \
        "$REPO_DIR" 2>/dev/null | while read -r path action file; do
            echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${YELLOW}$action${NC} $path$file"
            echo "[$(date '+%H:%M:%S')] $action $path$file" >> "$LOG_FILE"
        done
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
    log)
        log_watch "${2:-20}"
        ;;
    tail)
        tail_watch
        ;;
    monitor|run)
        # 前台模式：直接运行 inotifywait，持续输出
        run_monitor
        ;;
    *)
        echo "用法: $0 {start|stop|status|log|tail|monitor}"
        echo ""
        echo "  start   - 后台启动监控（推荐开机后运行一次）"
        echo "  stop    - 停止后台监控"
        echo "  status  - 查看运行状态"
        echo "  log [N] - 查看最近N行日志（默认20）"
        echo "  tail    - 实时跟踪日志（后台监控的日志）"
        echo "  monitor - 前台持续监控（手动查看文件变化用）"
        echo ""
        echo "首次使用: $0 start   启动后台监控"
        echo "调试查看: $0 monitor 前台实时查看变化"
        exit 1
        ;;
esac
