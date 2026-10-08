#!/bin/bash
# option-getnote/init.sh — 得到大脑(Get笔记) CLI + Skill 集成引导
#
# 官方方案（2026-11 切换）：CLI(`@getnote/cli`) + 5个原子 Skill
#   凭证：OAuth 浏览器授权 → ~/.getnote/config.json（或 API Key 方式）
#   不用 MCP server、不用 ccprivate/conf/getnote-accounts.json 多账号
#
# 使用：
#   bash init.sh                    # 交互菜单
#   bash init.sh --status           # 状态检查（init-option.sh 消费首行 OK/MISSING）
#   bash init.sh install            # 装 CLI + 5 Skills + OAuth 授权
#   bash init.sh auth               # OAuth 授权（浏览器确认）
#   bash init.sh doctor             # 诊断（getnote doctor -o json）
#   bash init.sh update             # 升级 CLI + 同步 Skills

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_DIR/lib/path-helper.sh"
source "$CCCONFIG_DIR/lib/dry-run.sh"
source "$CCCONFIG_DIR/lib/colors.sh"
source "$CCCONFIG_DIR/lib/interact.sh"

NPM_GLOBAL_BIN="$(npm prefix -g 2>/dev/null)/bin" || NPM_GLOBAL_BIN=""
LOCAL_BIN="$HOME/.local/bin"

# ── CLI 是否可执行 ──
cli_exists() { command -v getnote >/dev/null 2>&1; }

# ── 确保 getnote 进 PATH（npm 全局 bin 不在 PATH 时的处理） ──
ensure_path() {
    if cli_exists; then return 0; fi
    local src="$NPM_GLOBAL_BIN/getnote"
    if [ -f "$src" ] && [ -d "$LOCAL_BIN" ]; then
        ln -sf "$src" "$LOCAL_BIN/getnote"
        ln -sf "$NPM_GLOBAL_BIN/gnote" "$LOCAL_BIN/gnote" 2>/dev/null || true
        info "已在 $LOCAL_BIN 建 getnote 链接"
        export PATH="$LOCAL_BIN:$PATH"
    fi
    cli_exists
}

# ── 授权状态：读 getnote auth status ──
auth_status() {
    if ! ensure_path; then echo "NO_CLI"; return 1; fi
    local s
    s=$(getnote auth status 2>/dev/null)
    if echo "$s" | grep -q "Authenticated"; then
        echo "AUTHED"
    elif echo "$s" | grep -q "Not authenticated"; then
        echo "NOAUTH"
    else
        echo "UNKNOWN($s)"
    fi
}

# ── 状态检查（首行契约: OK/WARN/MISSING <描述>） ──
do_status() {
    if ! ensure_path; then
        echo "MISSING getnote CLI 未安装 → bash ccconfig/option-getnote/init.sh install"
        return 0
    fi
    local as; as=$(auth_status)
    case "$as" in
        AUTHED)
            if getnote doctor -o json 2>/dev/null | grep -q '"ready": *true'; then
                echo "OK getnote CLI 已装且已授权（doctor ready）"
            else
                echo "WARN getnote 已授权但 doctor 有问题 → bash init.sh doctor"
            fi
            ;;
        NOAUTH)
            echo "MISSING getnote CLI 已装但未授权 → bash init.sh auth"
            ;;
        NO_CLI)
            echo "MISSING getnote CLI 未安装 → bash init.sh install"
            ;;
        *)
            echo "MISSING getnote 状态未知($as) → bash init.sh doctor"
            ;;
    esac
}

# ── 安装：CLI + Skills + 授权 ──
do_install() {
    echo ""
    echo -e "${CYAN}── 安装得到大脑 CLI + Skill ──${NC}"
    echo ""
    if cli_exists; then
        local v; v=$(getnote version 2>/dev/null | head -1)
        ok "CLI 已安装: $v"
    else
        info "安装 @getnote/cli（需 Node.js 18+）..."
        if $DRY_RUN; then
            info "DRY-RUN: npm install -g @getnote/cli@latest"
        else
            npm install -g @getnote/cli@latest 2>&1 | sed 's/^/  /'
        fi
        ensure_path
        cli_exists && ok "CLI 安装完成" || { err "CLI 安装失败，检查 npm 输出"; return 1; }
    fi

    # 5 个原子 Skill + OAuth 授权（getnote setup 一体化）
    info "安装 5 个原子 Skill 并授权..."
    if $DRY_RUN; then
        info "DRY-RUN: getnote setup && getnote auth login"
    else
        getnote setup 2>&1 | sed 's/^/  /'
        echo ""
        info "开始 OAuth 授权（浏览器确认）..."
        getnote auth login
    fi

    echo ""
    getnote doctor -o json 2>/dev/null | grep -q '"ready": *true' \
        && ok "得到大脑连接完成（doctor ready）" \
        || warn "doctor 未全绿 → bash init.sh doctor 排查"
    echo ""
}

# ── 授权（OAuth 浏览器） ──
do_auth() {
    if ! ensure_path; then
        err "CLI 未安装，先: bash init.sh install"
        return 1
    fi
    echo ""
    info "打开浏览器完成得到大脑授权..."
    if $DRY_RUN; then
        info "DRY-RUN: getnote auth login"
    else
        getnote auth login
    fi
    getnote auth status 2>/dev/null | head -1
}

# ── 诊断 ──
do_doctor() {
    if ! ensure_path; then
        err "CLI 未安装，先: bash init.sh install"
        return 1
    fi
    getnote doctor -o json 2>&1 | sed 's/^/  /'
}

# ── 升级 CLI + 同步 Skills ──
do_update() {
    if ! ensure_path; then
        err "CLI 未安装，先: bash init.sh install"
        return 1
    fi
    info "升级 getnote（CLI + Skills + doctor 验证）..."
    if $DRY_RUN; then
        info "DRY-RUN: getnote update"
    else
        getnote update
    fi
}

# ── 主入口 ──
case "${1:-}" in
    --status|-s)  do_status ;;
    install|i)    do_install ;;
    auth|a)       do_auth ;;
    doctor|d)     do_doctor ;;
    update|u)     do_update ;;
    ""|menu)
        while true; do
            c=$(menu_select "得到大脑 getnote" \
                "安装/重装 (CLI+Skill+授权)" \
                "授权 (OAuth 浏览器)" \
                "诊断 (doctor)" \
                "升级 (CLI+Skill)" \
                "状态")
            [[ -z "$c" || "$c" == "0" ]] && exit 0
            case "$c" in
                1) do_install ;;
                2) do_auth ;;
                3) do_doctor ;;
                4) do_update ;;
                5) do_status; echo "" ;;
                *) warn "无效选项" ;;
            esac
        done
        ;;
    *) err "用法: bash init.sh [--status|install|auth|doctor|update]"; exit 1 ;;
esac