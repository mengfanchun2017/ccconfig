#!/bin/bash
# lib/bridge-service.sh — bridge 的 systemd user 服务管理
#
# 用法: bridge-service.sh {available|installed|active|install|enable|start|stop|restart|sync|status|uninstall}
#
# 为什么需要它：bridge 此前只有 shell watchdog 守护，而 watchdog 自己是 setsid 起的
# 孤儿进程 —— 系统/WSL 重启后它与 bridge 一起消失，只能等下一个 Claude session 的
# SessionStart hook 补。中间这段没有自愈（实测现象：切完当时好用，重启后 API error）。
# 交给 systemd user 服务守护后：开机自拉起、挂了自动重启、代码更新被 Restart 覆盖。
#
# 回退：systemd 不可用（WSL1 / 无 systemd / 无 user bus）时，本脚本的 install/start
# 返回非 0，调用方退回 shell watchdog（bridge-supervisor.sh via setsid）。两条路复用
# 同一个 supervisor 脚本，不存在第二份巡检循环。
#
# 注意：只依赖 lib/colors.sh（info/warn/ok/error），与 ensure-bridge.sh 一致。

CCCONFIG_ROOT="${CCCONFIG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SVC_NAME="claude-bridge"
SVC_TEMPLATE="$CCCONFIG_ROOT/lib/claude-bridge.service"
USER_UNIT_DIR="$HOME/.config/systemd/user"
USER_UNIT_FILE="$USER_UNIT_DIR/$SVC_NAME.service"

# systemd user 实例是否可用（WSL1/无 systemd 时为否）
bridge_service_available() {
    command -v systemctl &>/dev/null || return 1
    systemctl --user is-system-running &>/dev/null || \
        systemctl --user status &>/dev/null || return 1
    return 0
}

bridge_service_installed() { [[ -f "$USER_UNIT_FILE" ]]; }
bridge_service_active()    { systemctl --user is-active --quiet "$SVC_NAME" 2>/dev/null; }
bridge_service_enabled()   { systemctl --user is-enabled --quiet "$SVC_NAME" 2>/dev/null; }

# 安装（或刷新）unit 文件。幂等：内容一致时不做无谓的 daemon-reload。
# 输出 0=已安装/已是最新  1=不可用或失败
bridge_service_install() {
    bridge_service_available || return 1
    [[ -f "$SVC_TEMPLATE" ]] || { warn "  bridge 服务模板缺失: $SVC_TEMPLATE"; return 1; }
    mkdir -p "$USER_UNIT_DIR"
    local rendered
    rendered="$(sed -e "s|<HOME>|$HOME|g" -e "s|<CCCONFIG_ROOT>|$CCCONFIG_ROOT|g" "$SVC_TEMPLATE")"
    if [[ -f "$USER_UNIT_FILE" ]] && [[ "$rendered" == "$(cat "$USER_UNIT_FILE")" ]]; then
        return 0
    fi
    printf '%s\n' "$rendered" > "$USER_UNIT_FILE"
    systemctl --user daemon-reload 2>/dev/null || true
    return 0
}

# 开机自启需要 linger（否则用户未登录时 user manager 不跑）。
# 需要 polkit 权限，失败不算致命 —— 至少登录会话内可用。
_bridge_service_try_linger() {
    loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes' && return 0
    loginctl enable-linger "$USER" &>/dev/null || true
}

bridge_service_enable() {
    bridge_service_install || return 1
    systemctl --user enable "$SVC_NAME" &>/dev/null || return 1
    _bridge_service_try_linger
    return 0
}

bridge_service_start() {
    bridge_service_install || return 1
    systemctl --user start "$SVC_NAME" &>/dev/null || return 1
    return 0
}

bridge_service_stop() {
    bridge_service_installed || return 0
    systemctl --user stop "$SVC_NAME" &>/dev/null || true
    return 0
}

bridge_service_restart() {
    bridge_service_installed || return 1
    systemctl --user restart "$SVC_NAME" &>/dev/null || return 1
    return 0
}

bridge_service_disable() {
    bridge_service_installed || return 0
    systemctl --user disable --now "$SVC_NAME" &>/dev/null || true
    return 0
}

bridge_service_uninstall() {
    bridge_service_disable
    rm -f "$USER_UNIT_FILE" 2>/dev/null || true
    rm -f "$USER_UNIT_DIR/default.target.wants/$SVC_NAME.service" 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
    return 0
}

# 幂等确保「已安装 + 已启用 + 正在跑」。切到需 bridge 的 preset / init / 一键修复都调它。
# 输出 0=服务在跑  1=systemd 不可用（调用方退回 shell watchdog）
bridge_service_sync() {
    bridge_service_available || return 1
    bridge_service_install  || return 1
    bridge_service_enabled  || systemctl --user enable "$SVC_NAME" &>/dev/null || true
    _bridge_service_try_linger
    bridge_service_active   || bridge_service_start || true
    # Restart=on-failure：若 supervisor 因「当前 preset 直连」退出过，需显式 start
    bridge_service_active || bridge_service_start || return 1
    return 0
}

bridge_service_status() {
    if ! bridge_service_available; then
        echo "  服务: systemd user 不可用 → 退回 shell watchdog"
        return 1
    fi
    if ! bridge_service_installed; then
        echo "  服务: ${YELLOW}未安装${NC} → bash lib/bridge-service.sh sync"
        return 1
    fi
    local active enabled
    bridge_service_active  && active="${GREEN}active${NC}"   || active="${YELLOW}inactive${NC}"
    bridge_service_enabled && enabled="enabled"             || enabled="disabled"
    echo -e "  服务: $active ($enabled)"
    systemctl --user status "$SVC_NAME" --no-pager -n 3 2>/dev/null | sed 's/^/    /'
    return 0
}

# 命令行入口：被 source 时不执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _sd="$(dirname "${BASH_SOURCE[0]}")"
    # colors.sh 提供 info/warn/ok/error；缺失时降级为 echo
    [[ -f "$_sd/colors.sh" ]] && source "$_sd/colors.sh"
    case "${1:-status}" in
        available) bridge_service_available && echo yes || echo no ;;
        installed) bridge_service_installed && echo yes || echo no ;;
        active)    bridge_service_active    && echo yes || echo no ;;
        install)   bridge_service_install ;;
        enable)    bridge_service_enable ;;
        start)     bridge_service_start ;;
        stop)      bridge_service_stop ;;
        restart)   bridge_service_restart ;;
        sync)      bridge_service_sync ;;
        disable)   bridge_service_disable ;;
        uninstall) bridge_service_uninstall ;;
        status)    bridge_service_status ;;
        *) echo "用法: $0 {available|installed|active|install|enable|start|stop|restart|sync|disable|uninstall|status}"; exit 2 ;;
    esac
fi