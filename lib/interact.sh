#!/bin/bash
# interact.sh — 统一交互菜单/选择/输入/表格函数库
#
# 纯 sh 实现，零外部依赖。只调用 section/warn/ok 等颜色函数（colors.sh），不依赖 menu_num。
#
# 来源:
#   source "$SCRIPT_DIR/lib/interact.sh"
#
# 函数:
#   confirm        [msg] [default=n]  确认提示 (y/n)
#   menu_select    [title] [items...]  单选菜单
#   prompt         [msg] [default]     文本输入
#   prompt_password [msg]              密码输入
#   table          [title] [header_csv] [rows_csv...]  表格
#   menu_multi     [title] [items...]  多选 checklist

# ========== 确认 (y/n) ==========
confirm() {
    local msg="${1:-确定？}"
    local default="${2:-n}"

    local prompt_str
    case "$default" in
        y|Y) prompt_str="[Y/n]" ;;
        *)   prompt_str="[y/N]" ;;
    esac
    local ans
    if [[ -r /dev/tty ]]; then
        read -p "  $msg $prompt_str: " ans < /dev/tty
    else
        read -p "  $msg $prompt_str: " ans
    fi
    case "$ans" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        "") [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1 ;;
        *) return 1 ;;
    esac
}

# ========== 单选菜单 ==========
# 调用方传纯文本 items（不带数字前缀），本函数自动加 "1) 2) 3)" 序号。
# 返回: 选中项的序号字符串（如 "5"），0 表示返回/取消（非选中任何项）。
# 用法: c=$(menu_select "title" "item1" "item2" ...); case "$c" in 1) ... ;; 0) return ;; esac
menu_select() {
    local title="${1:-选择}"; shift
    local items=("$@")
    [[ ${#items[@]} -eq 0 ]] && { warn "menu_select: items 为空"; return 1; }

    printf '\n'; section "$title"
    local i sel
    for i in "${!items[@]}"; do
        printf '  %2d) %s\n' "$((i+1))" "${items[$i]}"
    done
    printf '\n'
    # 从 /dev/tty 读，避开 stdin 被管道/重定向导致的 read 阻塞/失败
    if [[ -r /dev/tty ]]; then
        read -p "  选择 [1-${#items[@]}, 0=返回]: " sel < /dev/tty
    else
        read -p "  选择 [1-${#items[@]}, 0=返回]: " sel
    fi
    [[ "$sel" =~ ^[0-9]+$ ]] || { printf '0\n'; return 0; }
    (( sel < 0 || sel > ${#items[@]} )) && { printf '0\n'; return 0; }
    printf '%s\n' "$sel"
}

# ========== 文本输入 ==========
prompt() {
    local msg="${1:-输入}"
    local default="${2:-}"

    local ans
    if [[ -n "$default" ]]; then
        if [[ -r /dev/tty ]]; then
            read -p "  $msg [$default]: " ans < /dev/tty
        else
            read -p "  $msg [$default]: " ans
        fi
        echo "${ans:-$default}"
    else
        if [[ -r /dev/tty ]]; then
            read -p "  $msg: " ans < /dev/tty
        else
            read -p "  $msg: " ans
        fi
        echo "$ans"
    fi
}

# ========== 密码输入 ==========
prompt_password() {
    local msg="${1:-输入密码}"
    local ans
    if [[ -r /dev/tty ]]; then
        read -s -p "  $msg: " ans < /dev/tty
    else
        read -s -p "  $msg: " ans
    fi
    printf '\n'
    echo "$ans"
}

# ========== 表格 ==========
table() {
    local title="${1:-}"; shift
    local header_csv="${1:-}"; shift
    local rows=("$@")
    local min_col_width=10
    local cols; IFS=',' read -ra cols <<< "$header_csv"
    local col_count=${#cols[@]} widths=() i val

    for i in "${!cols[@]}"; do
        local max=${#cols[$i]}; (( max < min_col_width )) && max=$min_col_width
        for row in "${rows[@]}"; do
            IFS=',' read -ra vals <<< "$row"
            val="${vals[$i]:-}"; local len=${#val}
            (( len > max )) && max=$len
        done; widths+=($(( max + 2 )))
    done

    [[ -n "$title" ]] && echo -e "  ${BOLD}${title}${NC}"
    for i in "${!cols[@]}"; do printf "  %-${widths[$i]}s" "${cols[$i]}"; done; echo ""
    for w in "${widths[@]}"; do printf "  %-${w}s" "$(printf '─%.0s' $(seq 1 $((w-2))))"; done; echo ""
    for row in "${rows[@]}"; do
        IFS=',' read -ra vals <<< "$row"
        for i in "${!cols[@]}"; do printf "  %-${widths[$i]}s" "${vals[$i]:-}"; done; echo ""
    done; echo ""
}

# ========== 等待动画 ==========
spinner() {
    local msg="${1:-处理中...}"; shift
    [[ $# -eq 0 ]] && { warn "spinner: 无命令"; return 1; }

    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    ( "$@" & local pid=$! i=0
      while kill -0 $pid 2>/dev/null; do
        printf "\r  ${GRAY}%s %s${NC}" "${frames[$i]}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} )); sleep 0.1
      done
      wait $pid; printf "\r  ${GREEN}✓${NC} %s\n" "$msg" )
}

# ========== 多选 checklist ==========
menu_multi() {
    local title="${1:-选择}"; shift
    local items=("$@")
    [[ ${#items[@]} -eq 0 ]] && { warn "menu_multi: items 为空"; return 1; }

    echo ""; section "$title（输入序号切换，回车确认）"
    local selected=() i choice
    for i in "${!items[@]}"; do printf "  %2d) [ ] %s\n" $((i+1)) "${items[$i]}"; done
    echo ""
    while true; do
        read -p "  输入序号（留空确认）: " choice
        [[ -z "$choice" ]] && break
        [[ "$choice" =~ ^[0-9]+$ ]] || choice=""
        if [[ -n "$choice" ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
            local idx=$((choice-1))
            if [[ " ${selected[*]} " == *" $idx "* ]]; then
                local new=()
                for s in "${selected[@]}"; do [[ "$s" != "$idx" ]] && new+=("$s"); done
                selected=("${new[@]}")
                printf "\033[1A\033[2K  %2d) [ ] %s\n" "$choice" "${items[$idx]}"
            else
                selected+=("$idx")
                printf "\033[1A\033[2K  %2d) [\e[32m✓\e[0m] %s\n" "$choice" "${items[$idx]}"
            fi
        fi
    done
    local result=""
    for idx in "${selected[@]}"; do result+="${items[$idx]} "; done
    echo "$result"
}