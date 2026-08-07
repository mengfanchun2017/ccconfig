#!/bin/bash
# ccconfig/option-usage/init.sh — Token 用量组件管理
#
# 功能：
#   - 初始化归档目录 ccprivate/usage/
#   - 配置 token-usage.json (feishu_url + timer 开关 + 启动时间)
#   - 装/卸 systemd timer
#   - 查看状态
#
# 用法（也通过 maintain.sh 10 号菜单调用）：
#   bash ccconfig/option-usage/init.sh                # 初始化（建目录）
#   bash ccconfig/option-usage/init.sh install        # 装 systemd timer
#   bash ccconfig/option-usage/init.sh uninstall      # 卸 timer
#   bash ccconfig/option-usage/init.sh config         # 交互式配置 token-usage.json
#   bash ccconfig/option-usage/init.sh status         # 查状态（timer/归档/配置）
#   bash ccconfig/option-usage/init.sh set-feishu <url>   # 单独设 feishu_url
#   bash ccconfig/option-usage/init.sh set-time <HH:MM:SS> # 单独设启动时间

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CCPRIVATE="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
SERVICE="ccconfig-token-usage.service"
TIMER="ccconfig-token-usage.timer"
CONFIG="$CCPRIVATE/conf/token-usage.json"
EXAMPLE_CONFIG="$CCCONFIG_DIR/conf/token-usage.json.example"

source "$CCCONFIG_DIR/lib/colors.sh" 2>/dev/null || {
    ok()   { echo "  ✅ $1"; }
    warn() { echo "  ⚠  $1"; }
    err()  { echo "  ❌ $1"; }
    info() { echo "  ℹ  $1"; }
}

# ============ 初始化 ============
setup_archive() {
    info "归档目录: $CCPRIVATE/usage/"
    mkdir -p "$CCPRIVATE/usage"

    local gitignore="$CCPRIVATE/.gitignore"
    if ! grep -qE '^/usage/?$|^/usage/' "$gitignore" 2>/dev/null; then
        echo "" >> "$gitignore"
        echo "# Token usage archive (local stat only; remove this line to sync to remote)" >> "$gitignore"
        echo "/usage/" >> "$gitignore"
        ok ".gitignore 加 /usage/ 排除"
    fi
    ok "归档目录就绪"

    # 确保 token-usage.json 存在（复制 example）
    if [[ ! -f "$CONFIG" && -f "$EXAMPLE_CONFIG" ]]; then
        cp "$EXAMPLE_CONFIG" "$CONFIG"
        ok "已创建 $CONFIG（默认配置）"
        info "编辑 conf/token-usage.json 修改 feishu_url 和 schedule"
    elif [[ -f "$CONFIG" ]]; then
        info "配置已存在: $CONFIG"
    else
        warn "未找到 $EXAMPLE_CONFIG，请手动创建 $CONFIG"
    fi
}

# ============ systemd timer 装/卸 ============
enable_timer() {
    local service_file="$SCRIPT_DIR/$SERVICE"
    local timer_file="$SCRIPT_DIR/$TIMER"
    [[ ! -f "$service_file" ]] && { err "找不到 $service_file"; return 1; }
    [[ ! -f "$timer_file" ]] && { err "找不到 $timer_file"; return 1; }

    # 从 config 读启动时间，生成定制 timer
    local schedule="12:01:00"
    if [[ -f "$CONFIG" ]]; then
        local cfg_schedule
        cfg_schedule=$(python3 -c "import json;d=json.load(open('$CONFIG'));print(d.get('schedule','12:01:00'))" 2>/dev/null)
        [[ -n "$cfg_schedule" ]] && schedule="$cfg_schedule"
    fi

    # 生成最终 timer 文件（替换 OnCalendar）
    local tmp_timer tmp_service
    tmp_timer=$(mktemp)
    tmp_service=$(mktemp)
    sed "s|OnCalendar=.*|OnCalendar=*-*-* $schedule|" "$timer_file" > "$tmp_timer"
    # 替换 service 模板占位符
    sed -e "s|<USER>|$(whoami)|g" \
        -e "s|<GROUP>|$(id -gn)|g" \
        -e "s|<HOME>|$HOME|g" \
        "$service_file" > "$tmp_service"
    info "timer 启动时间: $schedule"

    sudo cp "$tmp_service" /etc/systemd/system/$SERVICE
    sudo cp "$tmp_timer" /etc/systemd/system/$TIMER
    rm -f "$tmp_timer" "$tmp_service"
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$TIMER"
    ok "timer 已启用"
    info "查状态: systemctl status $TIMER"
}

disable_timer() {
    sudo systemctl disable --now "$TIMER" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$SERVICE" "/etc/systemd/system/$TIMER"
    sudo systemctl daemon-reload
    ok "timer 已禁用"
}

# ============ 状态 ============
status() {
    # 首行供 init-option 解析：OK/WARN/MISSING（无 ANSI）
    local has_conf=false has_timer=false
    [[ -f "$CONFIG" ]] && has_conf=true
    systemctl is-active "$TIMER" 2>/dev/null | grep -q "active" && has_timer=true

    if $has_conf && $has_timer; then
        echo "OK usage — token 用量组件：timer 运行中"
    elif $has_conf && ! $has_timer; then
        echo "WARN usage — 已配置，timer 未启用（bash init-option.sh usage 或 init.sh install）"
    else
        echo "MISSING usage — 未配置（bash init-option.sh usage）"
    fi

    echo "── 配置 ──"
    if $has_conf; then
        python3 -c "
import json
d = json.load(open('$CONFIG'))
print(f'  feishu_url:      {d.get(\"feishu_url\",\"(未设)\")}')
print(f'  enabled:         {d.get(\"enabled\", True)}')
print(f'  schedule:        {d.get(\"schedule\",\"12:01:00\")}')
print(f'  include_today:   {d.get(\"include_today\", False)}')
" 2>/dev/null || echo "  配置解析失败"
    else
        warn "  配置不存在: $CONFIG"
        info "  运行 init.sh config 创建"
    fi

    echo ""
    echo "── systemd timer ──"
    if $has_timer; then
        ok "$TIMER 运行中"
        systemctl status "$TIMER" --no-pager -l 2>/dev/null | head -5
        echo ""
        echo "── 上次执行 ──"
        systemctl status "$SERVICE" --no-pager -l 2>/dev/null | head -5
    else
        warn "$TIMER 未启用"
        info "运行 init.sh install 启用"
    fi

    echo ""
    echo "── 归档 ──"
    info "$CCPRIVATE/usage/"
    ls -1 "$CCPRIVATE/usage/" 2>/dev/null | head -10 || warn "  空"
    local total
    total=$(ls "$CCPRIVATE/usage/"*.csv 2>/dev/null | wc -l)
    info "总 CSV 文件: $total"
}

# ============ 配置交互 ============
config_interactive() {
    [[ ! -f "$CONFIG" ]] && setup_archive

    local current_url current_schedule current_today
    current_url=$(python3 -c "import json;d=json.load(open('$CONFIG'));print(d.get('feishu_url',''))" 2>/dev/null)
    current_schedule=$(python3 -c "import json;d=json.load(open('$CONFIG'));print(d.get('schedule','12:01:00'))" 2>/dev/null)
    current_today=$(python3 -c "import json;d=json.load(open('$CONFIG'));print(d.get('include_today',False))" 2>/dev/null)

    echo ""
    echo "── 当前 token-usage.json 配置 ──"
    echo "  feishu_url:     $current_url"
    echo "  schedule:       $current_schedule"
    echo "  include_today:  $current_today"
    echo ""
    echo "  1) 设置 feishu_url"
    echo "  2) 设置 schedule (启动时间 HH:MM:SS)"
    echo "  3) 设置 include_today (true/false)"
    echo "  0) 返回"

    read -p "  选择 [0-3]: " opt
    case "$opt" in
        1) read -p "  feishu_url: " v; set_feishu "$v" ;;
        2) read -p "  schedule (HH:MM:SS): " v; set_schedule "$v" ;;
        3) read -p "  include_today (true/false): " v; set_include_today "$v" ;;
        0) ;;
    esac
}

set_feishu() {
    local v="$1"
    python3 - "$CONFIG" "$v" << 'PYEOF'
import json, sys
p, v = sys.argv[1:3]
d = json.load(open(p))
d["feishu_url"] = v
json.dump(d, open(p, "w"), indent=4, ensure_ascii=False)
PYEOF
    ok "feishu_url 已更新: $v"
}

set_schedule() {
    local v="$1"
    python3 - "$CONFIG" "$v" << 'PYEOF'
import json, sys
p, v = sys.argv[1:3]
d = json.load(open(p))
d["schedule"] = v
json.dump(d, open(p, "w"), indent=4, ensure_ascii=False)
PYEOF
    ok "schedule 已更新: $v"
    info "重新装 timer 才生效：bash init.sh install"
}

set_include_today() {
    local v="$1"
    v=$(echo "$v" | tr '[:upper:]' '[:lower:]')
    local b="false"
    [[ "$v" == "true" || "$v" == "1" || "$v" == "yes" ]] && b="true"
    python3 - "$CONFIG" "$b" << 'PYEOF'
import json, sys
p, v = sys.argv[1:3]
d = json.load(open(p))
d["include_today"] = (v == "true")
json.dump(d, open(p, "w"), indent=4, ensure_ascii=False)
PYEOF
    ok "include_today 已更新: $b"
}

# ============ 入口分发 ============
case "${1:-}" in
    install|setup|enable)
        setup_archive
        enable_timer
        ;;
    uninstall|disable|remove|untimer)
        disable_timer
        ;;
    config|configure)
        config_interactive
        ;;
    status|--status)
        status
        ;;
    run|trigger)
        bash "$SCRIPT_DIR/token-usage.sh" --by-day --incremental --auto-backfill
        ;;
    set-feishu)
        shift
        set_feishu "${1:-}"
        ;;
    set-time|set-schedule)
        shift
        set_schedule "${1:-}"
        ;;
    set-today|set-include-today)
        shift
        set_include_today "${1:-}"
        ;;
    "")
        setup_archive
        status
        ;;
    *)
        echo "用法: $0 [install|uninstall|config|status|run|set-feishu <url>|set-time <HH:MM:SS>|set-today <t/f>]"
        exit 1
        ;;
esac