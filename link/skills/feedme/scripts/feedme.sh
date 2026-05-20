#!/bin/bash
# feedme.sh — Main interactive TUI for feedme skill
# Called by Claude when user says "feedme". Outputs structured signals for Claude to act on.

set -euo pipefail
BACKTITLE="feedme | 智能订餐助手"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONF_FILE="$HOME/.claude/projects/-home-francis-git/conf/feedme/feedme.json"

# Check whiptail
if ! command -v whiptail &>/dev/null; then
    echo "ERROR: whiptail not found. Install: sudo apt-get install whiptail"
    exit 1
fi

show_main_menu() {
    local choice
    choice=$(whiptail --clear --backtitle "$BACKTITLE" \
        --title "🍔 麦当劳订餐" \
        --ok-button "选择" --cancel-button "退出" \
        --menu "今天想吃点什么？" 17 62 6 \
        "1" "🔄  快速复购 — 历史订单再来一单" \
        "2" "📋  浏览菜单 — 查看今日可选餐品" \
        "3" "⭐  智能推荐 — 根据你的喜好推荐" \
        "4" "🎫  我的优惠券 — 查看和领取优惠券" \
        "5" "⚙️  设置 — 地址、偏好、积分查询" \
        "6" "🚪  退出" \
        3>&1 1>&2 2>&3)
    echo "$choice"
}

show_reorder_menu() {
    # Show recent orders for quick reorder
    local history_json recent
    history_json=$(python3 "$SKILL_DIR/scripts/prefs.py" get history 2>/dev/null || echo "[]")
    recent=$(echo "$history_json" | python3 -c "
import json, sys
h = json.load(sys.stdin)
if not h:
    print('[]')
    sys.exit(0)
tags = []
seen = set()
for entry in h:
    if entry.get('action') != 'order':
        continue
    items = ', '.join(i.get('name','?') for i in entry.get('items',[]))
    total = entry.get('total', 0)
    t = entry.get('time','')[:16]
    key = f'{items}|{total}|{t}'
    if key in seen:
        continue
    seen.add(key)
    tags.append(f'{len(tags)+1} {items} ¥{total} {t}')
args = []
for i, t in enumerate(tags):
    args.append(str(i+1))
    args.append(t)
    if i == 0:
        args.append('ON')
    else:
        args.append('OFF')
print(json.dumps(args))
" 2>/dev/null)

    if [ "$recent" = "[]" ] || [ -z "$recent" ]; then
        whiptail --backtitle "$BACKTITLE" --title "📋 历史订单" \
            --msgbox "还没有历史订单。\n\n试试浏览菜单或智能推荐！" 10 50
        echo "NO_HISTORY"
        return
    fi

    # Parse JSON array to bash args
    local -a args=()
    while IFS= read -r line; do
        args+=("$line")
    done < <(echo "$recent" | python3 -c "
import json, sys
a = json.load(sys.stdin)
for item in a:
    print(item)
")

    local selection
    selection=$(whiptail --backtitle "$BACKTITLE" \
        --title "🔄 快速复购" \
        --radiolist "选择历史订单重新下单：" 18 70 8 \
        "${args[@]}" \
        3>&1 1>&2 2>&3)
    echo "REORDER:$selection"
}

show_coupon_menu() {
    whiptail --backtitle "$BACKTITLE" \
        --title "🎫 我的优惠券" \
        --ok-button "确定" \
        --msgbox "优惠券数据由 Claude 通过 MCP 实时查询后显示。\n\n等待 Claude 获取数据..." 10 50
    echo "FETCH_COUPONS"
}

show_settings_menu() {
    local choice
    choice=$(whiptail --clear --backtitle "$BACKTITLE" \
        --title "⚙️ 设置" \
        --menu "选择设置项：" 15 55 5 \
        "addr" "📍  管理配送地址" \
        "taste" "👅  设置口味偏好" \
        "budget" "💰  设置预算上限" \
        "points" "⭐  查看积分" \
        "back" "↩️   返回主菜单" \
        3>&1 1>&2 2>&3)
    echo "SETTING:$choice"
}

show_address_list() {
    local addrs
    addrs=$(python3 "$SKILL_DIR/scripts/prefs.py" get addresses 2>/dev/null)
    if [ "$addrs" = "[]" ] || [ "$addrs" = "null" ] || [ -z "$addrs" ]; then
        whiptail --backtitle "$BACKTITLE" --title "📍 配送地址" \
            --msgbox "还没有保存地址。\n\n请在主菜单中选择「设置 → 管理配送地址」添加。" 10 55
        echo "NO_ADDRESS"
        return
    fi

    # Parse addresses into whiptail menu items
    local -a args=()
    local count=$(echo "$addrs" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    for i in $(seq 0 $((count - 1))); do
        local addr_info=$(echo "$addrs" | python3 -c "
import json,sys
a=json.load(sys.stdin)[$i]
print(f'{a[\"contactName\"]} {a[\"phone\"]} {a[\"address\"]}{a[\"addressDetail\"]}')
")
        args+=("$((i+1))" "$addr_info" "OFF")
    done
    args[2]="ON"  # First one default selected

    local sel
    sel=$(whiptail --backtitle "$BACKTITLE" \
        --title "📍 选择配送地址" \
        --radiolist "请选择配送地址：" 15 70 "$count" \
        "${args[@]}" \
        3>&1 1>&2 2>&3)
    echo "ADDR_SELECTED:$sel"
}

show_order_confirm() {
    local items="$1" total="${2:-?}" addr="${3:-未选择}"
    whiptail --backtitle "$BACKTITLE" \
        --title "✅ 确认下单" \
        --yes-button "确认下单" --no-button "取消" \
        --yesno "即将下单：\n\n$items\n\n💰 预估总价：¥$total\n📍 配送地址：$addr\n\n确认下单？" 14 60
    if [ $? -eq 0 ]; then
        echo "ORDER_CONFIRMED"
    else
        echo "ORDER_CANCELLED"
    fi
}

# Main
if [ $# -eq 0 ]; then
    # Interactive mode — show menu
    choice=$(show_main_menu)
    case "$choice" in
        1) show_reorder_menu ;;
        2) echo "BROWSE_MENU" ;;
        3) echo "SMART_RECOMMEND" ;;
        4) show_coupon_menu ;;
        5)
            sub=$(show_settings_menu)
            echo "$sub"
            ;;
        6) echo "EXIT" ;;
        *) echo "CANCELLED" ;;
    esac
else
    # Script mode — handle subcommand
    case "$1" in
        reorder) show_reorder_menu ;;
        menu) echo "BROWSE_MENU" ;;
        recommend) echo "SMART_RECOMMEND" ;;
        coupons) show_coupon_menu ;;
        settings) show_settings_menu ;;
        addresses) show_address_list ;;
        confirm)
            show_order_confirm "${2:-}" "${3:-}" "${4:-}"
            ;;
        *) echo "Unknown command: $1" >&2; exit 1 ;;
    esac
fi
