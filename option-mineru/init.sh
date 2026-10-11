#!/bin/bash
# ccconfig/option-mineru/init.sh — MinerU 文档解析（MCP，自动分级省额度）
#
# 用途：PDF/图片/Office/网页 → Markdown。封装上游 mineru-open-mcp，按每份文件
#   的页数/体积自动选档：≤20页/≤10MB 走免费 Flash，超过才用 token 的 Precision，
#   避免小文件白烧每日额度。上游原生只看「有没有 token」，有 token 就全程付费。
#
# 组成：
#   1. mineru_mcp.py   分级包装层（本目录，走 uvx 拉 mineru-open-mcp + pymupdf 依赖）
#   2. token           conf/mineru.json（各用户私有 ccprivate，跨机同步）
#   3. MCP 注册        conf/mcp-servers.json 定义 → init-mcp.sh sync 注册
#
# 用法：
#   bash init.sh --status    状态检查
#   bash init.sh --install   安装（建 conf + 同步 MCP）
#   bash init.sh --update    更新（重同步）
#   bash init.sh key         交互填/更新 token（可留空＝只用免费 Flash）
#   bash init.sh menu        交互菜单

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_ROOT/lib/dry-run.sh"
source "$CCCONFIG_ROOT/lib/colors.sh"
source "$CCCONFIG_ROOT/lib/path-helper.sh"
source "$CCCONFIG_ROOT/lib/interact.sh"

WRAPPER="$SCRIPT_DIR/mineru_mcp.py"
CCPRIVATE="${CCPRIVATE_HOME:-${CCPRIVATE_DIR:-$HOME/git/ccprivate}}"
CONF="$CCPRIVATE/conf/mineru.json"
TEMPLATE="$CCCONFIG_ROOT/conf/mineru.json.example"

# ── token 读取（占位符视为未填）──
read_token() {
    [ -f "$CONF" ] || { echo ""; return; }
    python3 -c "
import json
try:
    t = (json.load(open('$CONF')).get('token') or '').strip()
except Exception:
    t = ''
import sys
ph = ('请填入', '请到', 'your key', 'placeholder', '<your-')
print('' if (not t or any(x in t for x in ph)) else t)
" 2>/dev/null || echo ""
}

has_uvx() { command -v uvx &>/dev/null; }

# ── 状态 ──
do_status() {
    local token; token="$(read_token)"
    local mcp_state="未注册"
    if command -v claude &>/dev/null && claude mcp list 2>/dev/null | grep -q "^mineru:"; then
        if claude mcp list 2>/dev/null | grep "^mineru:" | grep -q "✔"; then
            mcp_state="已连"
        else
            mcp_state="已注册(未连)"
        fi
    fi
    local flash="≤20页/≤10MB 免费 Flash"
    [ -z "$token" ] && flash="$flash（无 token：全程只走 Flash）"

    local rc=0
    if [ ! -f "$WRAPPER" ]; then rc=2; fi
    if [ ! -f "$CONF" ]; then rc=2; fi
    if ! has_uvx; then rc=2; fi
    if [ "$mcp_state" = "未注册" ]; then rc=1; fi

    if [ $rc -eq 0 ]; then
        echo "OK mineru 已就绪 (MCP:$mcp_state)"
    elif [ $rc -eq 1 ]; then
        echo "WARN mineru 已装未注册 (MCP:$mcp_state)"
    else
        echo "MISSING mineru 未安装 (MCP:$mcp_state)"
    fi
    echo "  包装层: $WRAPPER $([ -f "$WRAPPER" ] && echo ✓ || echo ✗)"
    echo "  配置:   $CONF $([ -f "$CONF" ] && echo ✓ || echo '✗（未建）')"
    echo "  token:  $([ -n "$token" ] && echo "已配置(尾4位:${token: -4})" || echo '未配置（只走免费 Flash）')"
    echo "  uvx:    $(has_uvx && echo ✓ || echo '✗ 未安装 uv')"
    echo "  分级:   $flash"
    return $rc
}

# ── 建 conf ──
ensure_conf() {
    if [ -f "$CONF" ]; then return 0; fi
    mkdir -p "$(dirname "$CONF")"
    if [ -f "$TEMPLATE" ]; then
        run cp "$TEMPLATE" "$CONF"
        ok "创建: $CONF（来自模板，token 占位）"
    else
        cat > "$CONF" <<'JSON'
{
  "description": "MinerU 文档解析 API 配置（mineru.net）",
  "api_base": "https://mineru.net/api/v4",
  "token": "",
  "flash_page_limit": 20,
  "flash_size_limit_mb": 10
}
JSON
        ok "创建: $CONF"
    fi
    info "token 存此处（私有 ccprivate，跨机同步，不入公开库）"
}

# ── 同步 MCP 注册 ──
sync_mcp() {
    bash "$CCCONFIG_ROOT/lib/init-mcp.sh" sync 2>&1 | sed 's/^/  /' || true
}

# ── 安装 ──
do_install() {
    section "安装 mineru"
    if ! has_uvx; then
        warn "未装 uv/uvx → 无法运行 MCP（uvx 会拉 mineru-open-mcp 依赖）"
        info "装 uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
    fi
    ensure_conf
    echo ""
    section "同步 MCP 注册"
    sync_mcp
    echo ""
    local token; token="$(read_token)"
    if [ -z "$token" ]; then
        warn "尚未配置 token → 全程免费 Flash 档（≤20页/10MB）"
        info "填 token（解锁 >20页 Precision）: bash init-option.sh mineru key"
    fi
    info "完成后重启 Claude session 使 MCP 生效"
    echo ""
}

# ── 更新 ──
do_update() {
    section "更新 mineru"
    ensure_conf
    sync_mcp
    info "包装层为源码：更新 ccconfig 即更新（git pull / maintain.sh self）"
    echo ""
}

# ── 交互填 Key ──
do_key() {
    section "配置 MinerU token"
    ensure_conf
    local cur; cur="$(read_token)"
    [ -n "$cur" ] && info "当前 token 尾4位: ${cur: -4}"
    info "获取: https://mineru.net/apiManage → API 管理 → 创建 token"
    info "留空直接回车 = 只用免费 Flash 档"
    local val; val="$(prompt 'MinerU API token' '')"
    if [ -z "$val" ]; then
        info "未输入 → 保持只走免费 Flash"
        return 0
    fi
    python3 - "$CONF" "$val" <<'PYEOF'
import json, os, sys
path, val = sys.argv[1], sys.argv[2]
with open(path) as f:
    d = json.load(f)
d['token'] = val
tmp = path + '.tmp'
with open(tmp, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False); f.write('\n')
os.replace(tmp, path)
PYEOF
    ok "token 已写入 $CONF"
    sync_mcp
    info "重启 Claude session 生效"
}

do_menu() {
    while true; do
        do_status || true
        echo ""
        local cmd; cmd=$(menu_select "MinerU" "状态" "安装" "更新" "配置 token" "退出")
        case "$cmd" in
            1) do_status || true; read -p "  回车继续..." _ </dev/tty || true ;;
            2) do_install; read -p "  回车继续..." _ </dev/tty || true ;;
            3) do_update; read -p "  回车继续..." _ </dev/tty || true ;;
            4) do_key; read -p "  回车继续..." _ </dev/tty || true ;;
            ""|0|5) return 0 ;;
        esac
    done
}

case "${1:-}" in
    --status|status) do_status ;;
    --install|-i|install|"") do_install ;;
    --update|-u|update) do_update ;;
    key|keys) do_key ;;
    menu) do_menu ;;
    *) echo "用法: bash init.sh [--status|--install|--update|key|menu]"; exit 1 ;;
esac
