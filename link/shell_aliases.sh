#!/bin/bash
# shell_aliases.sh — 跨终端同步的 shell 别名/函数
# 由 ccconfig/setup-links.sh 链接到 ~/.claude/shell_aliases.sh
# ~/.bashrc 自动 source 此文件

CCCONFIG_HOME="${CCCONFIG_HOME:-$HOME/git/ccconfig}"

# auto-sync monitor 自启动（WSL/systemd user bus 不可用时 fallback）
# 通过 PID 文件避免重复启动
if [ -f "$CCCONFIG_HOME/lib/monitor.sh" ]; then
    _monitor_pid_file="$CCCONFIG_HOME/.monitor-sync.pid"
    if [ ! -f "$_monitor_pid_file" ] || ! kill -0 "$(cat "$_monitor_pid_file")" 2>/dev/null; then
        bash "$CCCONFIG_HOME/lib/monitor.sh" start 2>/dev/null &
    fi
    unset _monitor_pid_file
fi

# claude-mini: 切换到 MiniMax LLM 后启动 Claude
claude-mini() {
    bash "$CCCONFIG_HOME/init-llm.sh" minimax && claude "$@"
}

# claude-ds: 切换到 DeepSeek LLM 后启动 Claude
claude-ds() {
    bash "$CCCONFIG_HOME/init-llm.sh" deepseek && claude "$@"
}

# bat: cat 替代
if command -v batcat &>/dev/null; then
    alias cat=batcat
elif command -v bat &>/dev/null; then
    alias cat=bat
fi
