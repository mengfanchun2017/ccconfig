#!/bin/bash
# ==============================================
# lock.sh — 统一锁助手
#
# 功能：
#   - acquire_lock <name> [timeout_sec]  非阻塞拿锁
#   - release_lock <name>                释放锁
#   - with_lock <name> <cmd...>          RAII 风格：拿锁跑命令，自动释放
#   - 锁目录：$CCC_LOCK_DIR 或 $HOME/.cache/ccconfig-locks/
#
# 用法：
#   source "$LIB_DIR/lock.sh"
#   if acquire_lock monitor 5; then
#       # 临界区
#       release_lock monitor
#   else
#       echo "另一个实例在跑"
#   fi
#
#   # 或 RAII 风格
#   with_lock monitor sleep 10
#
# 特性：
#   - flock 跨进程、跨平台（Linux/WSL/macOS）
#   - 持锁进程死后自动释放（原子）
#   - 拿不到锁立即返回（不阻塞）
#   - 持锁者写入 PID 到 .pid 侧文件，便于诊断
# ==============================================

: "${CCC_LOCK_DIR:=$HOME/.cache/ccconfig-locks}"
mkdir -p "$CCC_LOCK_DIR" 2>/dev/null || true

_lock_path() {
    printf '%s/%s.lock' "$CCC_LOCK_DIR" "$1"
}

_lock_pid_path() {
    printf '%s/%s.pid' "$CCC_LOCK_DIR" "$1"
}

# 非阻塞拿锁
# 返回: 0=拿到, 1=已被他人持有
acquire_lock() {
    local name="$1"
    local timeout="${2:-0}"
    local lock_file
    lock_file=$(_lock_path "$name")

    exec 9>"$lock_file" 2>/dev/null || return 1
    if flock -n 9 2>/dev/null; then
        printf '%s\n' "$$" >&9
        printf '%s\n' "$$" > "$(_lock_pid_path "$name")"
        return 0
    fi

    if [[ "$timeout" -gt 0 ]]; then
        if flock -w "$timeout" 9 2>/dev/null; then
            printf '%s\n' "$$" >&9
            printf '%s\n' "$$" > "$(_lock_pid_path "$name")"
            return 0
        fi
    fi

    exec 9>&-
    return 1
}

# 释放锁
release_lock() {
    local name="$1"
    local lock_file
    lock_file=$(_lock_path "$name")

    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
    rm -f "$(_lock_pid_path "$name")" 2>/dev/null || true
}

# RAII 风格：拿锁 → 跑命令 → 释放
with_lock() {
    local name="$1"
    shift
    if ! acquire_lock "$name" 0; then
        echo "[lock] $name 已被持锁（pid=$(cat "$(_lock_pid_path "$name")" 2>/dev/null || echo ?))" >&2
        return 1
    fi
    local rc=0
    "$@" || rc=$?
    release_lock "$name"
    return $rc
}

# 自检：列出当前持锁者
lock_status() {
    local name="$1"
    if [ -f "$(_lock_pid_path "$name")" ]; then
        local pid
        pid=$(cat "$(_lock_pid_path "$name")")
        if kill -0 "$pid" 2>/dev/null; then
            echo "[lock] $name 持有者: PID $pid (live)"
            return 0
        fi
        echo "[lock] $name 持有者: PID $pid (dead — stale)"
        return 1
    fi
    echo "[lock] $name 未持锁"
    return 1
}
