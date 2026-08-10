#!/bin/bash
# interact.sh — 统一交互菜单/选择/输入/表格函数库
#
# 纯 sh 实现，零外部依赖。只调用 section/warn/ok 等颜色函数（colors.sh），不依赖 menu_num。
# 菜单显示全部走 stderr，避开 `c=$(menu_select ...)` 把 stdout 截走后菜单不显示的问题。
# read -p 自动从 /dev/tty 读，避开 stdin 被管道/重定向导致的 read 阻塞/失败。
#
# 来源:
#   source "$SCRIPT_DIR/lib/interact.sh"
#   source "$SCRIPT_DIR/colors.sh"  # 必须先 source
#
# ========== API ==========
#
# confirm [msg] [default]
#   询问 y/n。default=n 默认拒绝，default=y 默认接受。
#   用法:
#     confirm "继续？" && echo yes || echo no
#     confirm "删除？" n && rm file
#
# menu_select [title] [item1] [item2] ... [itemN]
#   单选菜单。items 必须是纯文本（不带数字前缀），菜单自动加 "1) 2) 3)"。
#   返回选中项的**序号字符串**（"5"），选中最后一项返回 "${#items[@]}"。
#   0 表示「返回/取消」（用户输入空、非法、越界，或末项是"返回"被选中）。
#   菜单显示走 stderr，返回值走 stdout（`c=$(menu_select ...)` 接）。
#   用法:
#     c=$(menu_select "ccconfig 运维" "状态" "Monitor" "更新" "返回")
#     case "$c" in
#         1) bash status.sh ;;
#         2) bash monitor.sh ;;
#         3) bash update.sh ;;
#         4) return 0 ;;  # 末项"返回"
#         *) return 0 ;;  # 0 或越界
#     esac
#   **坑**: bash case pattern 不支持动态表达式，"返回"项序号需硬算：
#     case "$c" in
#         $((${#names[@]} + 3))) return 0 ;;   # 末项
#         ...
#     esac
#
# prompt [msg] [default]
#   文本输入。default 可选，留空时无默认值。
#   用法:
#     name=$(prompt "输入名字" "default")
#
# prompt_password [msg]
#   密码输入（不回显）。用法:
#     pwd=$(prompt_password "Token")
#
# table [title] [header_csv] [row_csv] ...
#   ASCII 表格。header 是 "Col1,Col2,Col3"，每行 row 是 "v1,v2,v3"。
#   用法:
#     table "MCP 状态" "name,status,ver" "tavily,✅,1.0" "getnote,✅,2.1"
#
# menu_multi [title] [item1] [item2] ... [itemN]
#   多选 checklist。返回空格分隔的多个 items（不带数字）。
#   用法:
#     sel=$(menu_multi "选择 MCP" "tavily" "getnote" "exa")
#     for s in $sel; do echo "选了 $s"; done
#
# spinner [msg] [cmd] [args...]
#   跑命令时显示 spinner，完成后打 ✓。用法:
#     spinner "装包中..." npm install
#
# ========== 已知踩坑 ==========
#   1. menu_select 显示走 stderr — 不要 `>` 重定向整个函数输出（会丢菜单）
#   2. read 走 /dev/tty — 非 tty 环境（管道/CI）会 fallback，EOF 时返空字符串
#   3. while+case 不能 continue 重入菜单 — 每次都重新打印列表，状态丢失

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
    if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then
        read -p "  $msg $prompt_str: " ans < /dev/tty || true
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
# 返回: 选中项的序号字符串（如 "5"）；0 表示「返回/取消」（用户输入空、非法、越界）。
# 用法: c=$(menu_select "title" "item1" "item2" "返回"); case "$c" in 1) ... ;; 0) return ;; esac
menu_select() {
    local title="${1:-选择}"; shift
    local items=("$@")
    [[ ${#items[@]} -eq 0 ]] && { warn "menu_select: items 为空"; return 1; }

    # 菜单输出走 stderr — 避开 `c=$(...)` 把 stdout 截走后菜单列表不显示
    printf '\n' >&2
    section "$title" >&2
    local i sel
    for i in "${!items[@]}"; do
        printf '  %2d) %s\n' "$((i+1))" "${items[$i]}" >&2
    done
    printf '\n' >&2
    # 从 /dev/tty 读，避开 stdin 被管道/重定向导致的 read 阻塞/失败
    if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then
        read -p "  选择 [1-${#items[@]}]: " sel < /dev/tty || true
    else
        read -p "  选择 [1-${#items[@]}]: " sel
    fi
    [[ "$sel" =~ ^[0-9]+$ ]] || { printf '0\n'; return 0; }
    (( sel < 1 || sel > ${#items[@]} )) && { printf '0\n'; return 0; }
    printf '%s\n' "$sel"
}

# ========== 文本输入 ==========
prompt() {
    local msg="${1:-输入}"
    local default="${2:-}"

    local ans
    if [[ -n "$default" ]]; then
        if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then
            read -p "  $msg [$default]: " ans < /dev/tty || true
        else
            read -p "  $msg [$default]: " ans
        fi
        echo "${ans:-$default}"
    else
        if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then
            read -p "  $msg: " ans < /dev/tty || true
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
    if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then
        read -s -p "  $msg: " ans < /dev/tty || ans=""
    else
        read -s -p "  $msg: " ans || ans=""
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