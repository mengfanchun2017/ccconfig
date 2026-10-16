#!/bin/bash
# shell_init.sh — 终端初始化：auto-sync 自启动、memory symlink、别名/函数
# 由 ccconfig/lib/setup-links.sh 链接到 ~/.claude/shell_init.sh
# ~/.bashrc 自动 source 此文件

CCCONFIG_HOME="${CCCONFIG_HOME:-$HOME/git/ccconfig}"

# ccconfig 脚本直接可执行（maintain.sh / init-base.sh / init-* 等）
case ":$PATH:" in
    *":$CCCONFIG_HOME:"*) ;;
    *) export PATH="$CCCONFIG_HOME:$PATH" ;;
esac

# ========== project memory symlink ==========
# 检测 ~/git/*/ 下各项目是否有 .claude/memory/ 目录
# 有则建 symlink 让 Claude Code 把 memory 写到项目 repo 中
for _repo in "$HOME/git"/*/; do
    [ -d "${_repo}.claude/memory" ] || continue
    _project_id="$(echo "${_repo%/}" | tr '/' '-')"
    _central="$HOME/.claude/projects/$_project_id/memory"
    [ -L "$_central" ] && continue
    [ -d "$_central" ] && cp -a "$_central"/* "${_repo}.claude/memory/" 2>/dev/null
    rm -rf "$_central"
    mkdir -p "$(dirname "$_central")"
    ln -sf "${_repo}.claude/memory" "$_central"
done
unset _repo _project_id _central

# auto-sync monitor 自启动（WSL/systemd user bus 不可用时 fallback）
# 通过 PID 文件避免重复启动
if [ -f "$CCCONFIG_HOME/lib/monitor.sh" ]; then
    _monitor_pid_file="$CCCONFIG_HOME/.monitor-sync.pid"
    if [ ! -f "$_monitor_pid_file" ] || ! kill -0 "$(cat "$_monitor_pid_file")" 2>/dev/null; then
        bash "$CCCONFIG_HOME/lib/monitor.sh" start >/dev/null 2>&1 & disown
    fi
    unset _monitor_pid_file
fi

# claude-mini: 切换到 MiniMax3.1 LLM 后启动 Claude
claude-mini() {
    bash "$CCCONFIG_HOME/lib/init-llm.sh" minimax31 && claude "$@"
}

# claude-ds: 切换到 DeepSeek LLM 后启动 Claude
claude-ds() {
    bash "$CCCONFIG_HOME/lib/init-llm.sh" deepseek && claude "$@"
}

# claudeby: 直进 FleetView（agent view），并把 bypassPermissions 设为派发 session 的默认模式
# `--dangerously-skip-permissions` 在 `claude agents` 下即 `--permission-mode bypassPermissions`
# 的作用域是「派发 session 的默认模式」（见 `claude agents --help`），不是 agent view 自己。
# why bypass 而非 auto：auto 每条命令要调分类器模型，外部 LLM + 慢网关场景必然超时 →
# fail-closed 拦命令（见 ADR 0018 附节）。bypass 直接 allow，完全不碰分类器。
# ⚠️ 别名改后老 shell 不重载，必须开新终端或 source ~/.bashrc（检查: ./maintain.sh 1C）
alias claudeby='claude agents --dangerously-skip-permissions'

# claudebys: 直接开一个 bypassPermissions 会话（不经 FleetView）
# 用途：单会话高权限场景；FleetView 不可用 / 只想开一个 bypass 终端时用
# 与 claudeby 的区别：claudeby 进多会话管理界面并把 bypass 作为派发默认值；
# claudebys 就地起一个 bypass 会话，输入即执行，无中间界面
alias claudebys='claude --dangerously-skip-permissions'

# lark-cli: 从 ~/.lark-cli-account 读上次切换的账号（lark-switch.sh 写入）
# 跨机器持久化靠 ccprivate/link/.lark-default-account symlink（auto-sync 上推）
if [ -f "$HOME/.lark-cli-account" ]; then
    _lark_dir=$(grep '^configDir=' "$HOME/.lark-cli-account" 2>/dev/null | cut -d'=' -f2)
    if [ -n "$_lark_dir" ] && [ -d "$_lark_dir" ]; then
        export LARKSUITE_CLI_CONFIG_DIR="$_lark_dir"
    fi
    unset _lark_dir
fi

# bat: cat 替代
if command -v batcat &>/dev/null; then
    alias cat=batcat
elif command -v bat &>/dev/null; then
    alias cat=bat
fi
