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
    # dry-run 判定放最前：已安装时也要能 dry-run 出"本该做什么"，
    # 不能被 has_botmux 的 early-return 吃掉（否则 --dry-run 静默跑真实补链逻辑）。
    if _dry_run_enabled "$@"; then
        if has_botmux; then
            echo "would: keep botmux $(botmux_version)（已装）"
        else
            echo "would: npm install -g botmux"
        fi
        echo "would: link ~/.local/bin/botmux"
        return 0
    fi

    if has_botmux; then
        ok "已安装: $(botmux_version)"
    else
        # npm 官方分发：主包是纯分发壳，真正的 133MB 单文件二进制由平台子包
        # （botmux-linux-x64）提供，走 optionalDependencies。装包较大且较慢。
        info "npm install -g botmux（含 ~130MB 平台二进制，需 1-2 分钟）…"
        run npm install -g botmux --no-audit --no-fund || {
            err "npm 安装失败"
            info "备用: curl -fsSL https://raw.githubusercontent.com/deepcoldy/botmux/master/install.sh | sh"
            return 1
        }
        ok "安装完成: $(botmux_version)"
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
    # 装完即引导：不留「手动跑 setup」这道坎 —— 交互环境直接问要不要现在做完。
    _offer_setup_and_start
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

# ── 引导向导 ──────────────────────────────────────────────────────────
# 目标：把「装完 → 扫码建应用 → 启动 → 自启」一条龙走完，不让用户自己去拼命令。
# 关键约束（实测）：
#   · 非 TTY 下 botmux setup 直接退出、不产出二维码 → 必须真实终端，否则不给跑
#   · --allowed-users 是**必填**（owner 邮箱/手机号/on_xxx），botmux 不会交互询问
#     → 向导自己收集（本机 lark-cli 的 user token 已过期、且新建应用不认 ou_xxx，取不到就手输）
#   · 扫码链接 10 分钟有效、单人单次 → 提示要当场扫完

# 探测该 owner 是否已是 daemon 注入的当前 session owner（此路径返回成功）
# 拿不到就算了 —— botmux 也接受邮箱/手机号，手输更稳。

# 收集 owner（管理员）。返回 0 = 已取得并写入 _OWNER
_read_owner() {
    _OWNER=""
    # 有 lark-cli 授权时提示可用的 open_id（仅作参考，跨应用无效，故默认不自动填）
    local hint=""
    local lk_cfg="${LARKSUITE_CLI_CONFIG_DIR:-}"
    [ -z "$lk_cfg" ] && [ -f "$HOME/.lark-cli-account" ] && \
        lk_cfg="$(grep '^configDir=' "$HOME/.lark-cli-account" 2>/dev/null | cut -d= -f2)"
    if [ -n "$lk_cfg" ]; then
        local oid
        oid="$(LARKSUITE_CLI_CONFIG_DIR="$lk_cfg" lark-cli auth status --json 2>/dev/null \
            | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('identities',{}).get('user',{}).get('openId') or '')
except Exception: print('')" 2>/dev/null || true)"
        [ -n "$oid" ] && hint="$oid"
    fi

    echo -e "  ${GRAY}owner = 谁有权用这个 bot。填你飞书账号的完整邮箱或手机号最稳。${NC}" >&2
    echo -e "  ${GRAY}（新建应用时 ou_xxx open_id 无效——那是别的 app 签发的，跨应用不认）${NC}" >&2
    [ -n "$hint" ] && echo -e "  ${GRAY}（你当前 lark-cli 账号 open_id: $hint，仅供辨认，别填它）${NC}" >&2

    local v
    v="$(prompt '你的飞书邮箱或手机号（owner）' '')"
    v="$(printf '%s' "$v" | tr -d '[:space:]')"
    [ -z "$v" ] && { warn "未输入 owner —— 没有它建出来的 bot 拒绝任何人发消息"; return 1; }
    case "$v" in
        ou_*) warn "ou_ 开头是 open_id，新建应用不认；请改用完整邮箱或手机号"; return 1 ;;
    esac
    _OWNER="$v"
    return 0
}

# 判断 botmux setup add 的 JSON 结果（stdout 里最后一个 {"ok":…} 行）
# 返回 0 = ok:true；1 = 明确失败；2 = 未捕获到 JSON（可能被二维码/TUI 混流）
_setup_json_ok() {
    local out="$1"
    local line
    line="$(printf '%s\n' "$out" | grep -oE '\{"ok":(true|false)[^\n]*' | tail -1)"
    [ -z "$line" ] && return 2
    printf '%s' "$line" | grep -q '"ok":true' && return 0 || return 1
}

# 一条龙引导。返回 0 = 走到「已就绪」；非 0 = 中途停下（用户取消/失败）
do_guide() {
    section "botmux 引导：从零到能用"

    # 0) 前置：真终端才能扫码
    if ! has_tty; then
        err "非交互终端（无 /dev/tty）—— 扫码必须在真实终端里做"
        info "请在终端直接运行: bash init-option.sh botmux guide"
        return 1
    fi
    has_botmux || { err "botmux 未安装，先跑 --install"; return 1; }

    # 1) daemon/app 状态速览
    local bots; bots="$(bot_count)"
    if [ "$bots" != "0" ]; then
        ok "已有 $bots 个 bot 配置，跳过建应用"
        _guide_start_and_autostart && return 0
        return 1
    fi

    # 2) 收 owner
    echo ""
    echo -e "  ${BOLD}第 1 步 / 3：指定管理员（owner）${NC}"
    _read_owner || return 1
    ok "owner: $_OWNER"

    # 3) 扫码建应用（这一步要用户拿手机扫）
    echo ""
    echo -e "  ${BOLD}第 2 步 / 3：扫码创建飞书应用${NC}"
    echo -e "  ${GRAY}接下来终端会显示一个二维码 ——${NC}"
    echo -e "  ${YELLOW}  请用手机飞书 App 扫码${NC}，在手机上确认创建应用。"
    echo -e "  ${GRAY}  · 链接 10 分钟内有效、单人单次，请当场扫完${NC}"
    echo -e "  ${GRAY}  · 扫码后 botmux 会自动配齐权限、长连接事件、发版${NC}"
    echo -e "  ${GRAY}  · 新建的应用是**专用的**，不会和你 lark-cli 的 app 冲突${NC}"
    echo ""
    confirm "现在开始扫码建应用？" y || { info "已跳过（之后可跑: bash init-option.sh botmux guide）"; return 1; }

    echo ""
    local out rc
    # --create-app 走扫码；--allowed-users 必填；默认（不加 --no-open-platform-auto）
    # 会继续自动配权限/事件/发版。输出混着二维码，故整段捕获后再判 JSON。
    out="$(botmux setup add --create-app --allowed-users "$_OWNER" 2>&1)"; rc=$?
    printf '%s\n' "$out"

    echo ""
    if _setup_json_ok "$out"; then
        ok "应用创建成功"
    else
        local jrc=$?
        if [ $jrc -eq 1 ]; then
            err "建应用失败（上面 JSON 的 error 字段是原因）"
            _guide_failure_hints "$out"
            return 1
        fi
        # 未捕获 JSON：可能是部分完成/输出被 TUI 吃掉 —— 用 bot 数复核，别误判
        if [ "$(bot_count)" != "0" ]; then
            ok "已检测到新配置的 bot（JSON 未捕获但状态已变）"
        else
            warn "没抓到结果 JSON，且未检出 bot —— 可能中途取消"
            _guide_failure_hints "$out"
            return 1
        fi
    fi

    # 4) 启动 + 自启
    echo ""
    echo -e "  ${BOLD}第 3 步 / 3：启动 daemon${NC}"
    _guide_start_and_autostart || return 1

    echo ""
    ok "botmux 已就绪 —— 现在可以在飞书里私聊这个 bot 了"
    info "试试: 给它发一句「你好」，或拉它进群后 @ 它"
    info "会话列表: bash init-option.sh botmux sessions    Dashboard: bash init-option.sh botmux dashboard"
    return 0
}

# 启动 daemon + 询问开机自启
_guide_start_and_autostart() {
    if daemon_running; then
        ok "daemon 已在运行"
    else
        botmux start 2>&1 | sed 's/^/  /' || { err "daemon 启动失败，看日志: bash init-option.sh botmux logs"; return 1; }
        sleep 2
        daemon_running && ok "daemon 已启动" || warn "daemon 未确认在跑，稍后用 5G 复查"
    fi
    echo ""
    if botmux autostart status 2>/dev/null | grep -qiE "enabled|已启用|已开启|active"; then
        info "开机自启已开启"
    else
        if confirm "设置开机自启（systemd --user，无需 sudo）？" y; then
            botmux autostart enable 2>&1 | sed 's/^/  /' && ok "已设开机自启" || warn "自启设置失败（可手动: botmux autostart enable）"
        else
            info "已跳过自启（之后: botmux autostart enable）"
        fi
    fi
    return 0
}

# 失败时按输出给针对性提示
_guide_failure_hints() {
    local out="$1"
    echo ""
    echo -e "  ${BOLD}怎么排查${NC}"
    if printf '%s' "$out" | grep -qi "exit status\|network\|timeout\|未找到\|not found"; then
        info "疑似网络/CLI 缺失。先单独跑: botmux setup --no-open-platform-auto"
    fi
    if printf '%s' "$out" | grep -qi "invalid_param\|invalid param\|allowed-users"; then
        info "owner 格式问题 —— 用完整邮箱，如 name@company.com"
    fi
    info "重试整条引导: bash init-option.sh botmux guide"
    info "只要扫码那步（不自动配权限）: botmux setup add --create-app --allowed-users <你的邮箱> --no-open-platform-auto"
}

# 装完即问要不要现在做完整引导（交互环境才问）
_offer_setup_and_start() {
    local bots; bots="$(bot_count)"
    if [ "$bots" != "0" ]; then
        info "启动: bash init-option.sh botmux start    开机自启: botmux autostart enable"
        echo ""
        return 0
    fi
    if ! has_tty || [ "${NONINTERACTIVE:-false}" = "true" ]; then
        warn "尚未配置飞书应用"
        info "在终端跑一条龙引导: bash init-option.sh botmux guide"
        return 0
    fi
    if confirm "现在就配置飞书应用（扫码 → 启动 → 自启一次做完）？" y; then
        do_guide || true
    else
        info "之后可跑: bash init-option.sh botmux guide"
    fi
    echo ""
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
            "一条龙引导（建应用→启动→自启）" \
            "启动 daemon" \
            "重启 daemon" \
            "停止 daemon" \
            "运行状态" \
            "看日志" \
            "会话列表" \
            "Dashboard 登录链接" \
            "升级" \
            "重装/补链接" \
            "仅建应用（setup 原始命令）" \
            "退出")
        case "$cmd" in
            1)  do_guide;               pause_enter ;;
            2)  do_start;               pause_enter ;;
            3)  do_restart;             pause_enter ;;
            4)  do_stop;                pause_enter ;;
            5)  botmux status 2>&1 || true;  pause_enter ;;
            6)  do_logs --no-follow --lines 40; pause_enter ;;
            7)  do_sessions;             pause_enter ;;
            8)  do_dashboard;           pause_enter ;;
            9)  do_update;              pause_enter ;;
            10) do_install;             pause_enter ;;
            11) do_setup;               pause_enter ;;
            ""|0|12) return 0 ;;
        esac
    done
}

case "${1:-}" in
    --status|status)    shift 2>/dev/null || true; do_status ;;
    --install|-i|install)
                        shift 2>/dev/null || true; do_install "$@" ;;
    --update|-u|update) shift 2>/dev/null || true; do_update ;;
    guide|wizard|--guide) shift 2>/dev/null || true; do_guide "$@" ;;
    setup)              shift; do_setup "$@" ;;
    start|--start)      shift; do_start "$@" ;;
    stop|--stop)        shift; do_stop "$@" ;;
    restart|--restart)  shift; do_restart "$@" ;;
    logs|--logs)        shift; do_logs "$@" ;;
    sessions|list)      shift; do_sessions "$@" ;;
    dashboard)          shift; do_dashboard "$@" ;;
    menu|"")            do_menu ;;
    *)
        echo "用法: bash init.sh [--status|--install|--update|guide|setup|start|stop|restart|logs|sessions|dashboard|menu]"
        exit 1 ;;
esac