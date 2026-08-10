#!/bin/bash
# interact.sh — 统一交互菜单/选择/输入/表格/进度库
#
# 依赖: colors.sh（已 source）
# 可选: gum 命令（自动检测，降级为纯 sh 实现）
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
#   spinner        [msg] [cmd...]      等待动画
#   menu_multi     [title] [items...]  多选 checklist

# ========== 检测外部工具 ==========
_has_gum() { command -v gum &>/dev/null; }

# ========== 确认 (y/n) ==========
confirm() {
    local msg="${1:-确定？}"
    local default="${2:-n}"

    if _has_gum; then
        gum confirm "$msg" 2>/dev/null && return 0 || return 1
    fi

    local prompt_str
    case "$default" in
        y|Y) prompt_str="[Y/n]" ;;
        *)   prompt_str="[y/N]" ;;
    esac
    local ans
    read -p "  $msg $prompt_str: " ans
    case "$ans" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        "") [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1 ;;
        *) return 1 ;;
    esac
}

# ========== 单选菜单 ==========
menu_select() {
    local title="${1:-选择}"; shift
    local items=("$@")
    [[ ${#items[@]} -eq 0 ]] && { warn "menu_select: items 为空"; return 1; }

    if _has_gum; then
        gum choose --header "$title" "${items[@]}" 2>/dev/null
        return $?
    fi

    echo ""; section "$title"
    local i sel
    for i in "${!items[@]}"; do
        printf "  %2d) %s\n" $((i+1)) "${items[$i]}"
    done; echo ""
    read -p "  选择 [1-${#items[@]}]: " sel
    sel=$(menu_num "$sel")
    [[ -z "$sel" ]] || (( sel < 1 || sel > ${#items[@]} )) && return 1
    echo "${items[$((sel-1))]}"
}

# ========== 文本输入 ==========
prompt() {
    local msg="${1:-输入}"
    local default="${2:-}"

    if _has_gum; then
        gum input --placeholder "$msg" --value "$default" 2>/dev/null
        return $?
    fi

    local ans
    if [[ -n "$default" ]]; then
        read -p "  $msg [$default]: " ans
        echo "${ans:-$default}"
    else
        read -p "  $msg: " ans; echo "$ans"
    fi
}

# ========== 密码输入 ==========
prompt_password() {
    local msg="${1:-输入密码}"
    if _has_gum; then
        gum input --password --placeholder "$msg" 2>/dev/null
        return $?
    fi
    local ans
    read -s -p "  $msg: "; echo; echo "$ans"
}

# ========== 表格 ==========
table() {
    local title="${1:-}"; shift
    local header_csv="${1:-}"; shift
    local rows=("$@")
    local min_col_width=10

    if _has_gum; then
        local data="$header_csv"
        local row; for row in "${rows[@]}"; do data+="\n$row"; done
        echo -e "$data" | gum table --separator "," 2>/dev/null && return 0 || true
    fi

    # 纯 sh fallback
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

    if _has_gum; then
        gum spin --title "$msg" -- "$@" 2>/dev/null
        return $?
    fi

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

    if _has_gum; then
        gum choose --no-limit --header "$title" "${items[@]}" 2>/dev/null | tr '\n' ' '
        return $?
    fi

    echo ""; section "$title（输入序号切换，回车确认）"
    local selected=() i choice
    for i in "${!items[@]}"; do printf "  %2d) [ ] %s\n" $((i+1)) "${items[$i]}"; done
    echo ""
    while true; do
        read -p "  输入序号（留空确认）: " choice
        [[ -z "$choice" ]] && break
        choice=$(menu_num "$choice")
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