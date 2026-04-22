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
#   monitor-sync.sh tail       实时跟踪日志（显示推送结果）
#
# 依赖：inotifywait (Linux/WSL)
#       安装（免sudo）：下载 deb 提取二进制和库
#         mkdir -p ~/.local/lib && cd /tmp
#         curl -sLO http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools/inotify-tools_3.22.6.0-4_amd64.deb
#         dpkg-deb -x inotify-tools_*.deb . && cp usr/bin/inotify* ~/.local/bin/
#         curl -sLO http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools/libinotifytools0_3.22.6.0-4_amd64.deb
#         dpkg-deb -x libinotifytools0_*.deb . && cp usr/lib/x86_64-linux-gnu/libinotifytools.so.0 ~/.local/lib/
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

# 解决 inotifywait 对 libinotifytools.so.0 的依赖（免 sudo 安装方式）
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# 日志前缀
log() {
    local msg="[$(date '+%H:%M:%S')] $1"
    echo -e "${GREEN}[SYNC]${NC} $1"
    echo "$msg" >> "$LOG_FILE"
}
warn() {
    local msg="[$(date '+%H:%M:%S')] ⚠️ $1"
    echo -e "${YELLOW}[SYNC]${NC} ⚠️ $1"
    echo "$msg" >> "$LOG_FILE"
}
info() {
    local msg="[$(date '+%H:%M:%S')] $1"
    echo -e "${CYAN}[SYNC]${NC} $1"
    echo "$msg" >> "$LOG_FILE"
}
error() {
    local msg="[$(date '+%H:%M:%S')] ❌ $1"
    echo -e "${RED}[SYNC]${NC} ❌ $1" | tee -a "$LOG_FILE"
}

# ========== 检查依赖 ==========
check_deps() {
    if ! command -v inotifywait &>/dev/null; then
        error "缺少 inotifywait，请用免sudo方式安装（见脚本顶部注释）"
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
    local changed_files=$(git status --short 2>/dev/null)
    if [ -z "$changed_files" ]; then
        return 0
    fi

    echo "" | tee -a "$LOG_FILE"
    log "========== 检测到变化 =========="
    echo "$changed_files" | tee -a "$LOG_FILE"
    log "=================================="

    # 检查是否有未合并的冲突文件（git stash pop 产生冲突时会留下 unmerged 状态）
    # 冲突标记若被 commit 会破坏仓库，需要 abort
    if git ls-files -u 2>/dev/null | grep -q .; then
        echo "" | tee -a "$LOG_FILE"
        error "=========================================="
        error "⚠️  检测到未解决的 Git 合并冲突"
        error "    stash pop 或 merge 产生了冲突，请先手动解决"
        error "    不要 git add 或 git commit，直接手动处理"
        error "=========================================="
        echo "" | tee -a "$LOG_FILE"
        warn "手动解决后重新启动 monitor-sync"
        return 1
    fi

    # Stage 所有变化
    git add -A 2>/dev/null

    # 生成提交信息
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local commit_msg="自动同步: $timestamp"

    # 提交
    local commit_output
    if commit_output=$(git commit -m "$commit_msg" 2>&1); then
        echo "$commit_output" >> "$LOG_FILE"
        # 提取 commit hash
        local commit_hash=$(echo "$commit_output" | grep -o '[a-f0-9]\{7\}' | tail -1)
        log "✅ 已提交: $commit_hash"

        # 先 pull --ff，再 push
        log "正在 pull --ff ..."
        local pull_output
        if pull_output=$(git pull --ff origin main 2>&1); then
            echo "$pull_output" >> "$LOG_FILE"
            log "✅ pull 成功"

            # 推送
            if git push origin main >> "$LOG_FILE" 2>&1; then
                log "=========================================="
                log "✅ 已推送到 GitHub"
                log "=========================================="
                log "提交: $commit_hash"
                log "文件:"
                echo "$changed_files" | while read line; do
                    log "  $line"
                done
            else
                warn "推送失败，请手动检查网络或重试"
                warn "命令: cd $REPO_DIR && git push origin main"
            fi
        else
            # pull 失败（可能是两台机器同时有提交，出现冲突）
            echo "$pull_output" >> "$LOG_FILE"
            echo "" | tee -a "$LOG_FILE"
            error "=========================================="
            error "⚠️  pull 失败：远程有新提交，产生冲突"
            error "=========================================="
            echo "" | tee -a "$LOG_FILE"
            warn "解决方式（二选一）："
            echo "" | tee -a "$LOG_FILE"
            warn "方式A - 保留本地版本（你的修改优先）："
            echo "  cd $REPO_DIR" | tee -a "$LOG_FILE"
            echo "  git stash" | tee -a "$LOG_FILE"
            echo "  git pull origin main --ff" | tee -a "$LOG_FILE"
            echo "  git stash pop" | tee -a "$LOG_FILE"
            echo "  git push origin main" | tee -a "$LOG_FILE"
            echo "" | tee -a "$LOG_FILE"
            warn "方式B - 保留远程版本（对方的修改优先）："
            echo "  cd $REPO_DIR" | tee -a "$LOG_FILE"
            echo "  git fetch origin" | tee -a "$LOG_FILE"
            echo "  git reset --hard origin/main" | tee -a "$LOG_FILE"
            echo "" | tee -a "$LOG_FILE"
            warn "或使用 Git 工具手动合并后推送"
        fi
    else
        # 提交失败
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
    log "防抖: 120秒（合并连续变化后一次性推送）"
    log "排除: .git/, node_modules/, *.log, .monitor-sync.*, .auto-sync.*, *.swp"

    # 清空日志文件
    : > "$LOG_FILE"

    # 使用 setsid 完全脱离终端
    setsid inotifywait -m -r -q \
        --exclude '(\.git/|node_modules/|\.log$|\.monitor-sync\.|\.auto-sync\.|\.tmp$|\.swp$|\.tmp)' \
        -e modify,create,delete,move \
        "$REPO_DIR" \
        >> "$LOG_FILE" 2>&1 </dev/null &

    local notify_pid=$!
    echo $notify_pid > "$PID_FILE"
    log "监控已启动 (PID: $notify_pid)"
    log "使用 'tail' 命令查看实时推送结果"

    # 防抖参数
    local debounce=120
    local last_change=0
    local pending=false
    local last_push_time=0

    # 主循环
    while kill -0 $notify_pid 2>/dev/null; do
        sleep 1

        # 检查是否有新事件
        if [ -s "$LOG_FILE" ]; then
            local now=$(date +%s)
            local log_mtime=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo $now)

            if [ "$log_mtime" -gt "$last_change" ]; then
                if [ "$pending" = true ]; then
                    last_change=$now
                else
                    pending=true
                    last_change=$now
                    info "检测到文件变化，等待 120秒 防抖..."
                fi
            fi
        fi

        # 防抖计时器
        if [ "$pending" = true ]; then
            local time_diff=$(( $(date +%s) - last_change ))
            if [ $time_diff -ge $debounce ]; then
                # 检查距离上次推送是否太近（避免频繁推送）
                local time_since_push=$(( $(date +%s) - last_push_time ))
                if [ $last_push_time -gt 0 ] && [ $time_since_push -lt 60 ]; then
                    info "距离上次推送不足 60秒，跳过本次推送"
                    pending=false
                    continue
                fi

                info "防抖结束，开始提交推送..."
                last_change=$(date +%s)  # 防止 commit_and_push 写入日志触发误判
                commit_and_push
                pending=false
                last_push_time=$(date +%s)
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
    local lines="${1:-30}"
    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        echo "=== monitor-sync 日志 (最后 $lines 行) ==="
        tail -n "$lines" "$LOG_FILE"
    else
        echo "无日志记录"
    fi
}

# ========== 实时跟踪日志 ==========
tail_watch() {
    if [ -f "$LOG_FILE" ]; then
        echo "实时跟踪 monitor-sync 日志（显示推送结果，Ctrl+C 退出）..."
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
    echo "  实时显示文件变化"
    echo "  Ctrl+C 退出（后台监控继续运行）"
    echo "========================================"
    echo ""
    echo "提示：查看推送结果请用 'tail' 命令"
    echo ""

    : > "$LOG_FILE"

    # 前台运行 inotifywait
    inotifywait -m -r -q \
        --exclude '(\.git/|node_modules/|\.log$|\.monitor-sync\.|\.auto-sync\.|\.tmp$|\.swp$|\.tmp)' \
        -e modify,create,delete,move \
        "$REPO_DIR" 2>/dev/null | while read -r path action file; do
            echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${YELLOW}$action${NC} $path$file"
        done
}

# ========== 主程序 ==========
case "${1:-status}" in
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
        log_watch "$2"
        ;;
    monitor)
        run_monitor
        ;;
    tail)
        tail_watch
        ;;
    *)
        echo "用法: $0 {start|stop|status|log|monitor|tail}"
        echo ""
        echo "  start   - 后台启动监控（监控+推送）"
        echo "  stop    - 停止监控"
        echo "  status  - 查看状态"
        echo "  log [N] - 查看最近N行日志（默认30）"
        echo "  monitor - 前台实时查看文件变化（调试用）"
        echo "  tail    - 实时跟踪日志（显示推送结果）"
        exit 1
        ;;
esac

echo ""
exit 0
