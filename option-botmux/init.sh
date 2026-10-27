#!/bin/bash
# ccconfig/option-botmux/init.sh — botmux 飞书 ↔ AI 编程 CLI 桥接
#
# botmux = 飞书消息 → 本机 AI 编程 CLI（Claude Code / Codex / …）双向桥。
# 一条消息启动一个会话，每个会话独立 CLI 进程，输出实时流式回传成飞书卡片；
# 会话可用 `/adopt` / `/relay` 接管搬运，记录可查（dashboard + 会话落盘）。
#
# 与 ccbridge 的关系：ccbridge 已弃用（上游 lark-coding-agent-bridge 停更 2 月、
#   272 open issues），本 option 是其替代。ccbridge 仅作参考保留，不再接线。
#
# 上游形态：自包含单文件二进制（内嵌 PTY，运行不依赖本机 Node），npm 仅作分发。
#   curl -fsSL .../install.sh | sh   或   npm install -g botmux
#
# 用法：
#   bash init.sh --status     状态检查（首行 OK/WARN/MISSING，供 init-option 解析）
#   bash init.sh --install    安装（npm -g botmux + 建 ~/.local/bin 链接）
#   bash init.sh --update     升级（botmux upgrade）
#   bash init.sh setup        扫码建飞书应用 + 配权限 + 发版（交互）
#   bash init.sh start        启动 daemon（可加 autostart enable 开机自启）
#   bash init.sh status       运行状态（daemon + 会话）
#   bash init.sh logs         看日志
#   bash init.sh menu         交互菜单

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_ROOT/lib/dry-run.sh"
source "$CCCONFIG_ROOT/lib/colors.sh"
source "$CCCONFIG_ROOT/lib/path-helper.sh" 2>/dev/null || true
source "$CCCONFIG_ROOT/lib/interact.sh"

BOTMUX_HOME="$HOME/.botmux"
NPM_PREFIX="$(npm config get prefix 2>/dev/null || echo "")"
NODE_BIN="$(find_node_bin 2>/dev/null || true)"
export PATH="$HOME/.local/bin${NODE_BIN:+:$NODE_BIN}:$PATH"

has_botmux() { command -v botmux &>/dev/null; }

botmux_version() {
    has_botmux || { echo ""; return; }
    botmux --version 2>/dev/null | head -1 | tr -d '\n' || echo ""
}

# daemon 是否在跑（botmux status 输出含"运行中"；未跑时明确说"未在运行"）
daemon_running() {
    has_botmux || return 1
    local out; out="$(botmux status 2>&1 || true)"
    printf '%s' "$out" | grep -qv "未在运行" && printf '%s' "$out" | grep -qE "运行中|running|pid"
}

# 已配置的 bot 数（依赖 setup list --json）
bot_count() {
    has_botmux || { echo "0"; return; }
    local raw
    raw="$(botmux setup list --json 2>/dev/null || true)"
    [ -z "$raw" ] && { echo "0"; return; }
    printf '%s' "$raw" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(0); sys.exit(0)
bots = d.get('bots') if isinstance(d, dict) else d
print(len(bots) if isinstance(bots, list) else 0)
" 2>/dev/null || echo "0"
}

# ── 状态 ──
do_status() {
    local ver; ver="$(botmux_version)"
    local bots; bots="$(bot_count)"
    local running="no"
    daemon_running && running="yes"

    local rc=0
    if [ -z "$ver" ]; then
        rc=2                    # 未装
    elif [ "$bots" = "0" ]; then
        rc=1                    # 装了但没配 bot（未扫码建应用）
    elif [ "$running" != "yes" ]; then
        rc=1                    # 配了但 daemon 没跑
    fi

    case $rc in
        0) echo "OK botmux 运行中 ($ver, $bots bot)" ;;
        1) echo "WARN botmux 已装未就绪 ($ver, ${bots} bot, daemon:$running)" ;;
        *) echo "MISSING botmux 未安装" ;;
    esac

    echo "  版本:   ${ver:-未安装}"
    echo "  位置:   $(command -v botmux 2>/dev/null || echo '未在 PATH')"
    echo "  配置:   $BOTMUX_HOME $([ -d "$BOTMUX_HOME" ] && echo ✓ || echo '✗（未建）')"
    echo "  Bot:    $bots 个$([ "$bots" = "0" ] && echo '（未配置，跑 setup 扫码建应用）' || echo '')"
    echo "  daemon: $([ "$running" = "yes" ] && echo '运行中' || echo '未运行')"
    echo "  自启:   $(botmux autostart status 2>/dev/null | head -1 || echo '未知')"
    return $rc
}

# ── 安装 ──
do_install() {
    # section 标题由调用方（init-option.sh）打印，此处不再重复
    if has_botmux; then
        ok "已安装: $(botmux_version)"
    else
        # npm 官方分发：主包是纯分发壳，真正的 133MB 单文件二进制由平台子包
        # （botmux-linux-x64）提供，走 optionalDependencies。装包较大且较慢。
        if _dry_run_enabled "$@"; then
            echo "would: npm install -g botmux"
        else
            info "npm install -g botmux（含 ~130MB 平台二进制，需 1-2 分钟）…"
            run npm install -g botmux --no-audit --no-fund || {
                err "npm 安装失败"
                info "备用: curl -fsSL https://raw.githubusercontent.com/deepcoldy/botmux/master/install.sh | sh"
                return 1
            }
            ok "安装完成: $(botmux_version)"
        fi
    fi

    # npm prefix bin 不一定在 PATH（ccconfig 约定 ~/.local/bin），补链接
    if has_botmux && [ -n "$NPM_PREFIX" ] && [ -x "$NPM_PREFIX/bin/botmux" ]; then
        mkdir -p "$HOME/.local/bin"
        if [ ! -e "$HOME/.local/bin/botmux" ]; then
            ln -sf "$NPM_PREFIX/bin/botmux" "$HOME/.local/bin/botmux"
            ok "链接: ~/.local/bin/botmux → $NPM_PREFIX/bin/botmux"
        fi
    fi

    echo ""
    local bots; bots="$(bot_count)"
    if [ "$bots" = "0" ]; then
        warn "尚未配置飞书应用 → bash init-option.sh botmux setup（扫码建应用+配权限+发版）"
    fi
    info "启动: bash init-option.sh botmux start    开机自启: botmux autostart enable"
    echo ""
}

# ── 更新 ──
do_update() {
    section "更新 botmux"
    has_botmux || { err "botmux 未安装"; return 1; }
    info "当前: $(botmux_version)"
    run botmux upgrade || { err "升级失败（可试 npm install -g botmux --force）"; return 1; }
    ok "更新后: $(botmux_version)"
    echo ""
}

# ── setup（扫码建应用）──
do_setup() {
    section "botmux 配置（扫码建飞书应用）"
    has_botmux || { err "botmux 未安装"; return 1; }
    info "默认走内置 Web QR 登录，自动导入权限/redirect 并发版；"
    info "如需跳过平台自动化: botmux setup --no-open-platform-auto"
    echo ""
    botmux setup "$@"
}

# ── 运行管理 ──
do_start() {
    section "启动 botmux daemon"
    has_botmux || { err "botmux 未安装"; return 1; }
    local bots; bots="$(bot_count)"
    if [ "$bots" = "0" ]; then
        warn "没有已配置的 bot，先跑 setup 扫码建应用"
        return 1
    fi
    botmux start "$@"
    echo ""
    info "开机自启: botmux autostart enable"
}

do_stop() {
    section "停止 botmux daemon"
    has_botmux || { err "botmux 未安装"; return 1; }
    botmux stop "$@"
}

do_restart() {
    section "重启 botmux daemon"
    has_botmux || { err "botmux 未安装"; return 1; }
    botmux restart "$@"
}

do_logs() {
    has_botmux || { err "botmux 未安装"; return 1; }
    botmux logs "$@"
}

do_sessions() {
    has_botmux || { err "botmux 未安装"; return 1; }
    # list 在非交互下需要 --plain 才不打 TUI
    if has_tty; then
        botmux list "$@"
    else
        botmux list --plain "$@"
    fi
}

do_dashboard() {
    has_botmux || { err "botmux 未安装"; return 1; }
    botmux dashboard current "$@"
}

# ── 交互菜单 ──
do_menu() {
    while true; do
        do_status || true
        echo ""
        local cmd
        cmd=$(menu_select "botmux" \
            "配置（扫码建应用 setup）" \
            "启动 daemon" \
            "重启 daemon" \
            "停止 daemon" \
            "运行状态" \
            "看日志" \
            "会话列表" \
            "Dashboard 登录链接" \
            "升级" \
            "重装/补链接" \
            "退出")
        case "$cmd" in
            1)  do_setup;               pause_enter ;;
            2)  do_start;               pause_enter ;;
            3)  do_restart;             pause_enter ;;
            4)  do_stop;                pause_enter ;;
            5)  botmux status 2>&1 || true;  pause_enter ;;
            6)  do_logs --no-follow --lines 40; pause_enter ;;
            7)  do_sessions;             pause_enter ;;
            8)  do_dashboard;           pause_enter ;;
            9)  do_update;              pause_enter ;;
            10) do_install;             pause_enter ;;
            ""|0|11) return 0 ;;
        esac
    done
}

case "${1:-}" in
    --status|status)    shift 2>/dev/null || true; do_status ;;
    --install|-i|install)
                        shift 2>/dev/null || true; do_install "$@" ;;
    --update|-u|update) shift 2>/dev/null || true; do_update ;;
    setup)              shift; do_setup "$@" ;;
    start|--start)      shift; do_start "$@" ;;
    stop|--stop)        shift; do_stop "$@" ;;
    restart|--restart)  shift; do_restart "$@" ;;
    logs|--logs)        shift; do_logs "$@" ;;
    sessions|list)      shift; do_sessions "$@" ;;
    dashboard)          shift; do_dashboard "$@" ;;
    menu|"")            do_menu ;;
    *)
        echo "用法: bash init.sh [--status|--install|--update|setup|start|stop|restart|logs|sessions|dashboard|menu]"
        exit 1 ;;
esac