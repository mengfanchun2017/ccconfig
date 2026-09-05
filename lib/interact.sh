#!/bin/bash
# shellcheck disable=SC2162,SC2059,SC2034  # read -r not needed interactively; printf color vars intentional; unused vars by design
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
#   返回选中项的**序号字符串**（如 "5"）。末项返回其序号 ${#items[@]}。
#   "0" = 取消哨值：用户输入空/非法/越界/EOF/显式输入 0，stdout 输出 "0"。
#   调用方判取消：[[ -z "$c" || "$c" = "0" ]]（-z 为兼容兜底，新契约下恒为 "0"）。
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

    # 非交互旁路：CI/脚本化环境返回默认值，不阻塞 read
    if [[ "${NONINTERACTIVE:-false}" == "true" ]]; then
        [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1
    fi

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

    # 非交互旁路：返回 "0"（取消哨值），caller 走默认/返回分支
    if [[ "${NONINTERACTIVE:-false}" == "true" ]]; then
        printf '0\n'; return 0
    fi

    # 菜单输出走 stderr — 避开 `c=$(...)` 把 stdout 截走后菜单列表不显示
    printf '\n' >&2
    echo -e "  ${BOLD_GRAY}--${title}--${NC}" >&2
    local i sel=""
    for i in "${!items[@]}"; do
        printf "  ${BOLD_GREEN}%d)${NC}  %s\n" "$((i+1))" "${items[$i]}" >&2
    done
    printf '\n' >&2
    # 从 /dev/tty 读，避开 stdin 被管道/重定向导致的 read 阻塞/失败
    # 两分支都加 || true：EOF/管道断开时 read 返回非零，set -e 下会中断子 shell
    if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then
        printf "  ${BOLD_GREEN}选择 [1-${#items[@]}] (0=返回): ${NC}" >&2; read -r sel < /dev/tty || true
    else
        printf "  ${BOLD_GREEN}选择 [1-${#items[@]}] (0=返回): ${NC}" >&2; read -r sel || true
    fi
    # 取消哨值统一 "0"：空/非法/越界/EOF/输入 0 均返回 "0"
    # 调用方用 [[ -z "$c" || "$c" = "0" ]] 判取消（-z 是旧契约的兼容兜底）
    [[ "$sel" =~ ^[0-9]+$ ]] || { printf '0\n'; return 0; }
    (( sel < 1 || sel > ${#items[@]} )) && { printf '0\n'; return 0; }
    printf '%s\n' "$sel"
}

# ========== 文本输入 ==========
prompt() {
    local msg="${1:-输入}"
    local default="${2:-}"

    # 非交互旁路：直接返回默认值
    if [[ "${NONINTERACTIVE:-false}" == "true" ]]; then
        echo "$default"; return 0
    fi

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

    # 非交互旁路：返回空（CI 环境无法输入密码）
    if [[ "${NONINTERACTIVE:-false}" == "true" ]]; then
        echo ""; return 0
    fi

    local ans
    if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then
        read -s -p "  $msg: " ans < /dev/tty || ans=""
    else
        read -s -p "  $msg: " ans || ans=""
    fi
    printf '\n'
    echo "$ans"
}

# ========== Key 输入（不回显 + 末 4 位确认粘贴）==========
prompt_key() {
    local msg="${1:-输入 Key}"

    if [[ "${NONINTERACTIVE:-false}" == "true" ]]; then
        echo ""; return 0
    fi

    local ans
    if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then
        read -s -p "  $msg: " ans < /dev/tty || ans=""
    else
        read -s -p "  $msg: " ans || ans=""
    fi
    printf '\n'
    [[ -n "$ans" ]] && printf '  ↳ 已输入（末 4 位: %s）\n' "${ans: -4}" >&2
    echo "$ans"
}

# ========== Key 输入（明文 + 已有 key 检查）==========
# 用法: key=$(prompt_key_plain "DeepSeek API Key" "$existing_key")
# - existing 为空/占位符 → 明文输入新 key
# - existing 有效 → 提示尾号 4 位，回车保持 / 粘贴新 key 替换
prompt_key_plain() {
    local msg="${1:-输入 Key}"
    local existing="${2:-}"

    if [[ "${NONINTERACTIVE:-false}" == "true" ]]; then
        echo "$existing"; return 0
    fi

    # 占位符检测
    local _is_ph=0
    [[ -z "$existing" ]] && _is_ph=1
    [[ "$_is_ph" -eq 0 ]] && case "$existing" in *请填入*|*请替换*|*your.key*|*placeholder*|*changeme*) _is_ph=1 ;; esac

    local ans
    if [[ $_is_ph -eq 0 ]]; then
        local hint="已配置 尾号 ${existing: -4}，回车保持 / 粘贴新 key 替换"
        if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then
            read -p "  $msg [$hint]: " ans < /dev/tty || ans=""
        else
            read -p "  $msg [$hint]: " ans || ans=""
        fi
        echo "${ans:-$existing}"
    else
        if [[ -t 2 && -e /dev/tty && -r /dev/tty ]]; then
            read -p "  $msg: " ans < /dev/tty || ans=""
        else
            read -p "  $msg: " ans || ans=""
        fi
        echo "$ans"
    fi
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
      while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${GRAY}%s %s${NC}" "${frames[$i]}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} )); sleep 0.1
      done
      wait "$pid"; printf "\r  ${GREEN}✓${NC} %s\n" "$msg" )
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

# ========== trim 去除字段首尾空白 ==========
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

# ========== 数据驱动菜单系统 ==========
# 数据 schema:
#   declare -a MENU_ENTRIES=(
#       "cat|letter|title|desc|action|submenu"
#       ...
#   )
#   declare -A CAT_NAME=([1]="状态" [2]="auto-sync" ...)
#
# cat    : 全局分类 ID（不重置，1-N，唯一）
# letter : 分类内字母（A-Z）
# title  : 显示标题（建议 ≤ 22 字符）
# desc   : 灰色说明（建议 ≤ 30 字符）
# action : 主动作（bash 命令或函数名）。空=分组标记
# submenu: 可选。menu:xxx = 调用 _submenu_xxx；空=无
#
# 系统快捷键（与数据无关，常驻可用）:
#   s=1A(状态总览)  t=2C(tail)  r=刷新  q/0=退出  ?=帮助

# 渲染菜单（按 cat 分组，分类标题 --name--）
menu_render() {
    [[ -z "${MENU_ENTRIES+x}" ]] && { warn "menu_render: MENU_ENTRIES 未定义"; return 1; }

    local current_cat="" entry cat letter title desc action submenu
    for entry in "${MENU_ENTRIES[@]}"; do
        IFS='|' read -r cat letter title desc action submenu <<< "$entry"
        cat=$(trim "$cat"); letter=$(trim "$letter")
        title=$(trim "$title"); desc=$(trim "$desc")

        # 分类标题（cat 切换时打印）
        if [[ "$cat" != "$current_cat" ]]; then
            local cat_label="${CAT_NAME[$cat]:-}"
            if [[ -n "$cat_label" && "$cat" != "0" ]]; then
                printf "  ${BOLD_GRAY}--%s--${NC}\n" "$cat_label"
            elif [[ "$cat" == "0" ]]; then
                printf "  ${BOLD_GRAY}--退出--${NC}\n"
            fi
            current_cat="$cat"
        fi

        # 菜单项: <cat><letter>  title        desc
        local key="${cat}${letter}"
        printf "  ${BOLD_GREEN}%s${letter:+%s}${NC}  %-20s ${DIM}%s${NC}\n" \
               "$cat" ${letter:+"$letter"} "$title" "$desc"
    done
}

# 帮助
menu_help() {
    cat <<'EOF' | sed 's/^/  /'
输入规则:
  <cat><letter>  直接执行（如 2C = monitor tail）
  <letter>       跨分类首字母匹配（首个匹配项）
  <cat>          进入该分类首个动作
  s              状态总览  (= 1A)
  t              tail 追踪 (= 2C)
  r              刷新
  q / 0          退出
  ?              显示帮助
EOF
}

# 内部：执行指定 cat+letter
_exec_entry() {
    local target_cat="$1"
    local target_letter="$2"
    local entry cat letter title desc action submenu

    for entry in "${MENU_ENTRIES[@]}"; do
        IFS='|' read -r cat letter title desc action submenu <<< "$entry"
        cat=$(trim "$cat"); letter=$(trim "$letter")
        if [[ "$cat" == "$target_cat" && "$letter" == "$target_letter" ]]; then
            # 子菜单
            if [[ -n "$submenu" && "$submenu" =~ ^menu: ]]; then
                local sub="${submenu#menu:}"
                if declare -F "_submenu_$sub" > /dev/null; then
                    "_submenu_$sub"
                    return 3  # 子菜单返回 3 → menu_loop 跳过暂停
                else
                    warn "子菜单不存在: _submenu_$sub"
                    return 3
                fi
            fi
            # 主动作
            if [[ -n "$action" ]]; then
                eval "$action" || { warn "执行失败: $action"; return 3; }
                return 0
            fi
            warn "无动作: ${target_cat}${target_letter} ($title)"
            return 3
        fi
    done
    warn "未找到 ${target_cat}${target_letter}"
    return 3
}

# 内部：找 cat 内首个 letter
_exec_cat_first() {
    local target_cat="$1"
    local entry cat letter action
    for entry in "${MENU_ENTRIES[@]}"; do
        IFS='|' read -r cat letter _ _ action _ <<< "$entry"
        cat=$(trim "$cat"); letter=$(trim "$letter")
        if [[ "$cat" == "$target_cat" && -n "$action" ]]; then
            _exec_entry "$target_cat" "$letter"
            return $?
        fi
    done
    return 3
}

# 内部：跨分类首个 letter 匹配
_exec_letter_first() {
    local target_letter="$1"
    local entry cat letter action
    for entry in "${MENU_ENTRIES[@]}"; do
        IFS='|' read -r cat letter _ _ action _ <<< "$entry"
        cat=$(trim "$cat"); letter=$(trim "$letter")
        if [[ "$letter" == "$target_letter" && -n "$action" ]]; then
            _exec_entry "$cat" "$letter"
            return $?
        fi
    done
    return 3
}

# 解析用户输入
# 返回码:
#   0 = 已处理动作
#   1 = 刷新请求（重渲染）
#   2 = 退出请求
#   3 = 无效输入
menu_parse() {
    local input="$1"
    [[ -z "$input" ]] && return 0

    # 系统快捷键
    case "$input" in
        q|Q|0|exit|quit) return 2 ;;
        s|S)               _exec_entry 1 A; return $? ;;
        t|T)               _exec_entry 2 C; return $? ;;
        r|R|fs|fresh)      return 1 ;;
        \?|h|H|help|HELP)  menu_help; return 0 ;;
    esac

    # cat + letter 组合（如 1A, 2C, 15D）
    if [[ "$input" =~ ^([0-9]+)([A-Za-z])$ ]]; then
        local cat="${BASH_REMATCH[1]}"
        local letter="${BASH_REMATCH[2]^^}"
        _exec_entry "$cat" "$letter"
        return $?
    fi

    # 单字母 → 跨分类首字母匹配
    if [[ "$input" =~ ^[A-Za-z]$ ]]; then
        local letter="${input^^}"
        _exec_letter_first "$letter"
        return $?
    fi

    # 单数字 → 该分类首个动作
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        _exec_cat_first "$input"
        return $?
    fi

    warn "无效输入: $input (输入 ? 看帮助)"
    return 3
}

# 标准主循环：渲染 + read + parse + 按回车继续
# 调用方需已定义 MENU_ENTRIES / CAT_NAME
# 用法:
#   menu_loop "标题"
menu_loop() {
    local title="${1:-菜单}"
    local skip_pause=0
    while true; do
        clear 2>/dev/null || true
        banner "$title"
        menu_render
        echo ""
        printf "  ${BOLD_GREEN}选择: ${NC}"; read -r choice < /dev/tty || choice=""
        echo ""
        menu_parse "$choice"
        local rc=$?
        [[ $rc -eq 2 ]] && return 0
        [[ $rc -eq 1 ]] && continue
        # 子菜单返回 3 跳过暂停
        if [[ $rc -ne 3 ]]; then
            echo ""
            printf "  按回车继续..."; read -r dummy < /dev/tty || true
        fi
    done
}