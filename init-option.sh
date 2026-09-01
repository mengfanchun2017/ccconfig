#!/bin/bash
# init-option.sh — 可选组件统一安装入口
#
# 用法：
#   bash init-option.sh                  # 交互式菜单
#   bash init-option.sh --status         # 列出所有 option 及安装状态
#   bash init-option.sh <name>           # 安装指定 option
#   bash init-option.sh all              # 安装所有 option
#
# 状态规范: 每个 option 的 init.sh --status 第一行必须是
#   OK <name> ...   |   WARN <name> ...   |   MISSING <name> ...
# （无 ANSI，供 init-option 解析；后续行可含 ANSI 供详情展示）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/dry-run.sh"
source "$SCRIPT_DIR/lib/path-helper.sh" 2>/dev/null || true

source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/interact.sh"

# ── 分组定义 ──
# 每个组：组标题 + 组内菜单项列表
# 每一项: "name" 选项名
# "---" 分隔行（仅展示，不可选）

# 内置 CLI 描述
declare -A CLI_DESC
CLI_DESC["batcat"]="cat 替代，语法高亮+行号"
CLI_DESC["glow"]="终端 Markdown 渲染阅读"
# nano: Ubuntu 26 自带，仅展示提示不出现在安装列表

# Option 描述

# ── 分组列表 ──
# 格式: "group_title|item1 item2 ..."
MENU_GROUPS=(
    "--os--|batcat glow"
    "--claude--|mcp skill"
    "--lark--|larkcli"
    "--other--|officecli remote cloudflare usage"
    "--auto--|llmswitch"
    "--key--|feishu_key"
)

# 自动管理的项：状态展示但不可 toggle
declare -A AUTO_MANAGED
AUTO_MANAGED["llmswitch"]="由 init-llm 自动启停（按 provider 切换）|bash init-llm.sh|bash maintain.sh llmswitch {start,stop,status,restart}"

# ── 检测 option-* 目录 ──
list_option_dirs() {
    local dirs=()
    for d in "$SCRIPT_DIR"/option-*/; do
        [ -d "$d" ] || continue
        dirs+=("$(basename "$d")")
    done
    echo "${dirs[@]}"
}

has_init_script() {
    [ -f "$SCRIPT_DIR/option-$1/init.sh" ]
}

# ── 解析 ANSI 转义并清理 ──
_strip_ansi() {
    sed -r 's/\x1b\[[0-9;]*[mK]//g'
}

# ── 状态行解析：返回 "ICON|STATE|DETAIL"
#   ICON: ok|warn|miss|running|stopped
#   STATE: OK|WARN|MISSING|<raw>
#   DETAIL: 描述文本（已 strip ANSI）
parse_status_line() {
    local raw="$1"
    local line
    line=$(echo -e "$raw" | _strip_ansi | head -1)
    line=$(echo "$line" | sed 's/^[[:space:]]*//')

    if [[ "$line" =~ ^OK[[:space:]]+(.+)$ ]]; then
        echo "ok|OK|${BASH_REMATCH[1]}"
        return
    fi
    if [[ "$line" =~ ^WARN[[:space:]]+(.+)$ ]]; then
        echo "warn|WARN|${BASH_REMATCH[1]}"
        return
    fi
    if [[ "$line" =~ ^MISSING[[:space:]]+(.+)$ ]] || [[ "$line" =~ ^FAIL[[:space:]]+(.+)$ ]]; then
        echo "miss|MISSING|${BASH_REMATCH[1]}"
        return
    fi
    # 退化：视为状态描述
    echo "?|$line|$line"
}

# ── 检测二进制是否安装（用于 CLI 工具 + option-*） ──
option_status() {
    local name="$1"

    # 内置 CLI
    case "$name" in
        batcat|bat)
            if command -v batcat &>/dev/null || command -v bat &>/dev/null; then
                local bcmd="bat"; command -v bat &>/dev/null || bcmd="batcat"
                local ver=$($bcmd --version 2>/dev/null | head -1)
                echo "ok|OK|batcat 已安装${ver:+ ($ver)}"
            else
                echo "miss|MISSING|batcat 未安装"
            fi
            return
            ;;
        glow)
            if command -v glow &>/dev/null; then
                local ver=$(glow --version 2>/dev/null | head -1)
                echo "ok|OK|glow 已安装${ver:+ ($ver)}"
            else
                echo "miss|MISSING|glow 未安装"
            fi
            return
            ;;
        nano)
            if command -v nano &>/dev/null; then
                local ver=$(nano --version 2>/dev/null | head -1)
                echo "ok|OK|nano 已安装${ver:+ ($ver)}"
            else
                echo "miss|MISSING|nano 未安装"
            fi
            return
            ;;
    esac

    # option-* 目录（取 --status 首行）
    if has_init_script "$name"; then
        local out
        out=$(bash "$SCRIPT_DIR/option-$name/init.sh" --status 2>&1 | _strip_ansi | head -1)
        if [ -z "$out" ]; then
            echo "miss|MISSING|$name 无 status 输出"
        else
            parse_status_line "$out"
        fi
        return
    fi

    echo "miss|MISSING|未知选项: $name"
}

# ── 渲染状态图标 + 详情 ──
render_status() {
    local icon_state_detail="$1"
    local icon="${icon_state_detail%%|*}"
    local rest="${icon_state_detail#*|}"
    local detail="${rest#*|}"

    case "$icon" in
        ok)       printf "  ${GREEN}✓${NC} %s" "$detail" ;;
        warn)     printf "  ${YELLOW}!${NC} %s" "$detail" ;;
        running)  printf "  ${GREEN}●${NC} %s" "$detail" ;;
        stopped)  printf "  ${YELLOW}○${NC} %s" "$detail" ;;
        miss)     printf "  ${GRAY}✗${NC} ${GRAY}%s${NC}" "$detail" ;;
        *)        printf "  ${GRAY}?${NC} %s" "$detail" ;;
    esac
}

# ── 检测 feishu key 状态：是否含占位符 ──
check_feishu_key() {
    local conf
    conf="$(resolve_conf feishu.json 2>/dev/null)" || { echo "no_conf|ccprivate/conf/feishu.json 不存在"; return; }
    python3 - "$conf" << 'PYEOF' 2>/dev/null
import json, sys
PLACEHOLDER = ['请填入','请到','请替换','your key','your_key','placeholder','changeme','<your-','your-app-name']
def is_ph(v):
    if not v or not isinstance(v, str): return True
    return any(p in v.lower() for p in PLACEHOLDER)
with open(sys.argv[1]) as f: d = json.load(f)
apps = d.get('apps', [])
ph_lc = [a['name'] for a in apps if a.get('larkCli',{}).get('enabled') and (is_ph(a.get('appId','')) or is_ph(a.get('appSecret','')))]
ph_unfilled = [a['name'] for a in apps if not a.get('appId') or not a.get('appSecret')]
if ph_lc:
    out = ["larkcli:" + ",".join(ph_lc)]
    print("placeholder|" + ";".join(out))
elif ph_unfilled:
    print("empty|" + ",".join(ph_unfilled))
else:
    print("ok|所有 appId/appSecret 已配置")
PYEOF
}

# ── 列出所有 option（分组格式） ──
list_all() {
    echo -e "${CYAN}可选组件状态${NC}"
    echo ""

    local idx=1
    local -a all_names

    # 确保 mcp 在 group 中可被检测（作为内置选项，无 option-mcp 目录）
    mcp_status() {
        local conf="$CCPRIVATE_HOME/conf/mcp-servers.json"
        if [ -f "$conf" ]; then
            local count=$(python3 -c "import json; d=json.load(open('$conf')); print(len(d.get('mcp_servers',[])))" 2>/dev/null || echo "0")
            if [ "$count" -gt 0 ]; then
                echo "ok|OK|$count 个 MCP 服务器已注册"
            else
                echo "miss|MISSING|MCP 未配置（bash lib/init-mcp.sh sync）"
            fi
        else
            echo "miss|MISSING|mcp-servers.json 未找到"
        fi
    }

    for group_entry in "${MENU_GROUPS[@]}"; do
        local group_title="${group_entry%%|*}"
        local group_items="${group_entry#*|}"

        echo -e "  ${BOLD}${group_title}${NC}"

        for name in $group_items; do
            # 检查是否存在
            case "$name" in
                mcp|feishu_key) ;;
                batcat|glow) ;;
                usage) ;;
                *) has_init_script "$name" || continue ;;
            esac

            all_names+=("$name")
            local status
            if [ "$name" = "mcp" ]; then
                status=$(mcp_status)
            elif [ "$name" = "feishu_key" ]; then
                status=$(check_feishu_key 2>/dev/null || echo "no_conf|ccprivate 未初始化")
            elif [ "$name" = "usage" ]; then
                local ccpriv_conf="${CCPRIVATE_HOME:-$HOME/git/ccprivate}/conf/token-usage.json"
                if [ -f "$ccpriv_conf" ]; then
                    if systemctl is-active ccconfig-token-usage.timer 2>/dev/null | grep -q "active"; then
                        status="ok|OK|timer 运行中"
                    else
                        status="ok|OK|已配置，timer 未启用"
                    fi
                else
                    status="miss|MISSING|未配置（bash option-usage/init.sh）"
                fi
            else
                status=$(option_status "$name")
            fi

            printf "  %2d) %-12s " "$idx" "$name"
            # 自动管理的项：加 [auto] 标签，可观测但不可 toggle
            if [ -n "${AUTO_MANAGED[$name]:-}" ]; then
                printf "${GRAY}[auto]${NC} "
            fi
            render_status "$status"
            # 内置 CLI 描述
            local desc="${CLI_DESC[$name]:-}"
            [ -n "$desc" ] && printf "  ${DIM}- ${desc}${NC}"
            echo ""
            idx=$((idx + 1))
        done

        # nano: Ubuntu 26 自带，仅提示
        if [ "$group_title" = "--os--" ]; then
            if command -v nano &>/dev/null; then
                local nano_ver=$(nano --version 2>/dev/null | head -1)
                echo -e "     ${GRAY}• nano         Ubuntu 26 已自带${nano_ver:+ ($nano_ver)} - 终端文本编辑器，简单直观${NC}"
            fi
        fi
    done

    echo ""
    echo -e "  ${DIM}a) 全部安装  0) 返回${NC}"
    echo ""
}

# ── 飞书 key 配置向导 ──
feishu_key_wizard() {
    section "飞书 key 配置向导"

    local conf
    if ! conf="$(resolve_conf feishu.json)"; then
        err "ccprivate/conf/feishu.json 不存在"
        info "先运行: bash ccconfig/init-ccprivate-repo.sh"
        return 1
    fi

    info "配置文件: $conf"
    echo ""

    while true; do
        # 读取当前活跃账号
        local current_name=""
        local marker="$HOME/.lark-cli-account"
        [ -f "$marker" ] && current_name=$(grep '^name=' "$marker" | cut -d'=' -f2)

        # 列出所有 apps
        local -a apps_json names
        while IFS= read -r line; do
            [ -n "$line" ] && apps_json+=("$line")
        done < <(python3 - "$conf" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for a in d.get('apps', []):
    print(json.dumps(a, ensure_ascii=False))
PYEOF
        )

        if [ ${#apps_json[@]} -eq 0 ]; then
            err "feishu.json 中没有 apps 配置"
            echo ""
            confirm "添加新 app？" y || return 0
            _feishu_add_app "$conf"
            continue
        fi

        echo -e "  当前 apps:  ${GRAY}(当前活跃: ${current_name:-无})${NC}"
        echo -e "  ${GRAY}cli=lark-cli 命令行账号   bridge=飞书↔Claude 机器人（决定是否出现在 larkbridge 选单）${NC}"
        echo ""
        local i=1
        names=()
        for app_json in "${apps_json[@]}"; do
            local name appid desc lc lb
            IFS=$'\t' read -r name appid desc lc lb < <(echo "$app_json" | python3 -c "
import json, sys
a = json.load(sys.stdin)
i = a.get('appId','')
# larkbridge 历史上写过 larkBridge 驼峰，两种都认
lb = a.get('larkbridge') or a.get('larkBridge') or {}
print('\t'.join([
    a.get('name','?'),
    (i[:12] + '…') if len(i) > 12 else i,
    a.get('description',''),
    'Y' if a.get('larkCli',{}).get('enabled') else 'N',
    'Y' if lb.get('enabled') else 'N',
]))")
            local lc_disp="${GRAY}✗ cli${NC}"; [ "$lc" = "Y" ] && lc_disp="${GREEN}✓ cli${NC}"
            local lb_disp="${GRAY}✗ bridge${NC}"; [ "$lb" = "Y" ] && lb_disp="${GREEN}✓ bridge${NC}"
            local marker_str=""
            [ "$name" = "$current_name" ] && marker_str="  ${GREEN}← 当前${NC}"
            printf "    %d) %-12s appId=%-14s %b  %b%b\n" "$i" "$name" "$appid" "$lc_disp" "$lb_disp" "$marker_str"
            [ -n "$desc" ] && echo -e "       ${GRAY}${desc}${NC}"
            names+=("$name")
            i=$((i + 1))
        done
        local sel; sel=$(menu_select "选择 app" "${names[@]}" "添加新 app" "返回")
        [[ -z "$sel" ]] && continue
        local names_count=${#names[@]}
        if [[ "$sel" == "$((names_count + 2))" ]]; then  # 返回
            return 0
        elif [[ "$sel" == "$((names_count + 1))" ]]; then  # 添加新 app
            _feishu_add_app "$conf"; continue
        fi

        local target_name=""
        [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "$names_count" ]] && target_name="${names[$((sel-1))]}"
        [[ -z "$target_name" ]] && continue

        # app 二级菜单（纯文本，menu_select 自动编号）
        local sub; sub=$(menu_select "应用: $target_name" \
            "编辑 App ID/Secret" \
            "切换账号" \
            "OAuth 授权" \
            "查看授权" \
            "删除" \
            "返回")
        [[ -z "$sub" ]] && continue

        case "$sub" in
            "1") _feishu_edit_key "$conf" "$target_name" ;;
            "2")
                echo ""
                bash "$SCRIPT_DIR/option-larkcli/lark-switch.sh" "$target_name"
                local cfg_dir="$HOME/.lark-cli-${target_name}"
                if [ -f "${cfg_dir}/config.json" ]; then
                    if ! LARKSUITE_CLI_CONFIG_DIR="$cfg_dir" lark-cli auth status 2>/dev/null | grep -q "tokenStatus.*valid"; then
                        echo ""; warn "未授权，自动拉起..."
                        LARKSUITE_CLI_CONFIG_DIR="$cfg_dir" bash "$SCRIPT_DIR/option-larkcli/init.sh" --auth-login "$target_name" 2>&1
                    else
                        info "授权状态正常"
                    fi
                fi
                ;;
            "3")
                local cfg_dir="$HOME/.lark-cli-${target_name}"
                [ -f "${cfg_dir}/config.json" ] && LARKSUITE_CLI_CONFIG_DIR="$cfg_dir" bash "$SCRIPT_DIR/option-larkcli/init.sh" --auth-login "$target_name" 2>&1 || warn "先编辑 App ID/Secret"
                ;;
            "4")
                local cfg_dir="$HOME/.lark-cli-${target_name}"
                [ -f "${cfg_dir}/config.json" ] && LARKSUITE_CLI_CONFIG_DIR="$cfg_dir" lark-cli auth status 2>&1 | grep -v "^\[lark-cli\]" | sed 's/^/  /' || warn "config.json 不存在"
                ;;
            "5") _feishu_delete_app "$conf" "$target_name" ;;
            *) break ;;
        esac
        echo ""
    done
}

# ── 安装单个 option ──
install_option() {
    local name="$1"
    shift

    if _dry_run_enabled "$@"; then
        printf 'would: install %s\n' "$name"
        return 0
    fi

    # usage 特殊处理：先于 has_init_script 拦截
    if [ "$name" = "usage" ]; then
      local is_batch=false
      for a in "$@"; do [[ "$a" == "--batch" || "$a" == "--yes" || "$a" == "-y" ]] && is_batch=true; done
      if $is_batch; then
        section "安装 usage → timer"
        bash "$SCRIPT_DIR/option-usage/init.sh" 2>&1 | sed 's/^/  /'
        bash "$SCRIPT_DIR/option-usage/init.sh" install 2>&1 | sed 's/^/  /'
      else
        while true; do
          local sub; sub=$(menu_select "usage 管理" \
            "安装 timer (每天 12:01 归档+推飞书)" "卸载 timer" \
            "配置 (feishu_url/schedule/include_today)" "状态" "手动触发" "返回")
          case "$sub" in
            "1") bash "$SCRIPT_DIR/option-usage/init.sh" install ;;
            "2") bash "$SCRIPT_DIR/option-usage/init.sh" uninstall ;;
            "3") bash "$SCRIPT_DIR/option-usage/init.sh" config ;;
            "4") bash "$SCRIPT_DIR/option-usage/init.sh" status ;;
            "5") bash "$SCRIPT_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;;
            *) break ;;
          esac
          echo ""
          read -p "按回车继续..." dummy < /dev/tty || true
        done
      fi
      return 0
    fi

    # option-* 目录 + ccbridge 兼容
    if [ "$name" = "larkbridge" ]; then
        local ccbridge_init="${CCBRIDGE_HOME:-$HOME/git/ccbridge}/init.sh"
        if [ ! -f "$ccbridge_init" ]; then
            warn "ccbridge 未安装（git clone ~/git/ccbridge）"
            return 1
        fi
        if [ ${#@} -eq 0 ]; then
            echo ""
            bash "$ccbridge_init" --status 2>&1 | grep -v '^$'
            echo ""
            local lb_sub; lb_sub=$(menu_select "larkbridge" \
                "前台启动" "后台启动" "停止" "看日志" "返回")
            [[ -z "$lb_sub" ]] && return 0
            case "$lb_sub" in
                "1") bash "$ccbridge_init" --run ;;
                "2") bash "$ccbridge_init" --bg ;;
                "3") bash "$ccbridge_init" --stop ;;
                "4") bash "$ccbridge_init" --logs ;;
                *) return 0 ;;
            esac
            return $?
        fi
        bash "$ccbridge_init" "$@"
        return $?
    fi

    if has_init_script "$name"; then
        # remote: 无参数默认执行 --run（一键安装）
        if [ "$name" = "remote" ] && [ ${#@} -eq 0 ]; then
            section "安装 remote"
            bash "$SCRIPT_DIR/option-$name/init.sh" --run
            return $?
        fi
        section "安装 $name"
        bash "$SCRIPT_DIR/option-$name/init.sh" "$@"
        return $?
    fi

    # MCP
    if [ "$name" = "mcp" ]; then
        section "MCP 服务器"
        bash "$SCRIPT_DIR/lib/init-mcp.sh" sync
        echo ""
        echo -e "  ${GRAY}Key 配置/管理: bash maintain.sh mcp config${NC}"
        return $?
    fi

    # 内置 CLI / option 选项
    case "$name" in
        batcat|bat)   install_bat ;;
        glow)  install_glow ;;
        *) err "未知选项: $name" ; return 1 ;;
    esac
}

# ── CLI 工具安装函数 ──
install_bat() {
    section "bat 安装 + alias cat=bat"

    if command -v batcat &>/dev/null || command -v bat &>/dev/null; then
        ok "bat 已安装"
    else
        info "安装 bat..."
        if command -v sudo &>/dev/null; then
            sudo apt-get install -y bat 2>/dev/null || {
                warn "apt 安装失败，尝试下载二进制..."
                local bv
                bv=$(curl -fsSL "https://api.github.com/repos/sharkdp/bat/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4 | tr -d 'v')
                bv="${bv:-0.24.0}"
                curl -fsSL "https://github.com/sharkdp/bat/releases/download/v${bv}/bat_${bv}_amd64.deb" -o /tmp/bat.deb
                sudo apt-get install -y /tmp/bat.deb 2>/dev/null || sudo apt-get install -f -y
                rm -f /tmp/bat.deb
            }
        else
            err "需要 sudo 才能安装 bat"
            return 1
        fi
    fi

    # alias cat=bat
    local alias_file="$HOME/.claude/shell_init.sh"
    if [ -f "$alias_file" ] && ! grep -q "alias cat=bat" "$alias_file" 2>/dev/null; then
        echo -e "\n# bat: cat 替代\nif command -v batcat &>/dev/null; then\n    alias cat=batcat\nelif command -v bat &>/dev/null; then\n    alias cat=bat\nfi" >> "$alias_file"
        ok "alias cat=bat 已写入 shell_init.sh"
    elif grep -q "alias cat=bat" "$alias_file" 2>/dev/null; then
        ok "alias cat=bat 已存在"
    fi

    ok "bat 就绪"
}

install_glow() {
    section "glow Markdown 阅读器"

    if command -v glow &>/dev/null; then
        local gver=$(glow --version 2>/dev/null | head -1); gver=${gver:-glow}
        ok "glow 已安装 ($gver)"
        return 0
    fi

    info "安装 glow..."
    if command -v sudo &>/dev/null; then
        sudo apt-get install -y glow 2>/dev/null || {
            warn "apt 无 glow 包，下载二进制..."
            local gv
            gv=$(curl -fsSL "https://api.github.com/repos/charmbracelet/glow/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4 | tr -d 'v')
            gv="${gv:-2.1.0}"
            curl -fsSL "https://github.com/charmbracelet/glow/releases/download/v${gv}/glow_${gv}_linux_amd64.deb" -o /tmp/glow.deb
            sudo apt-get install -y /tmp/glow.deb 2>/dev/null || sudo apt-get install -f -y
            rm -f /tmp/glow.deb
        }
    else
        err "需要 sudo 才能安装 glow"
        return 1
    fi

    if command -v glow &>/dev/null; then
        ok "glow 已安装: $(glow --version 2>/dev/null | head -1)"
    else
        err "glow 安装失败"
    fi
}


# ── 交互菜单 ──
interactive_menu() {
    echo -e "${CYAN}Claude Code 可选组件安装${NC}"

    while true; do
        list_all

        # 运行时收集 all_names（与 list_all 一致）
        local -a all_names
        for group_entry in "${MENU_GROUPS[@]}"; do
            local group_items="${group_entry#*|}"
            for name in $group_items; do
                case "$name" in
                    mcp|feishu_key|usage) all_names+=("$name") ;;
                    batcat|glow) all_names+=("$name") ;;
                    *) has_init_script "$name" && all_names+=("$name") ;;
                esac
            done
        done

        # menu_select 自动编号，传入纯文本
        local menu_items=()
        for n in "${all_names[@]}"; do
            local desc=""
            case "$n" in
                mcp) desc="MCP 服务" ;;
                feishu_key) desc="飞书 Key" ;;
                usage) desc="Token 用量" ;;
                batcat|glow) ;;
                *) [ -n "${AUTO_MANAGED[$n]:-}" ] && desc="[auto]" ;;
            esac
            menu_items+=("$n${desc:+ ($desc)}")
        done
        menu_items+=("全部安装")
        menu_items+=("退出")

        local total_items=${#menu_items[@]}          # = all_names + 2
        local all_idx=$((total_items - 1))            # 全部安装序号
        local exit_idx=$total_items                   # 退出序号

        local choice; choice=$(menu_select "可选组件" "${menu_items[@]}")
        [[ -z "$choice" || "$choice" == "0" || "$choice" == "$exit_idx" ]] && break

        if [[ "$choice" == "$all_idx" ]]; then
            for n in "${all_names[@]}"; do
                if [ "$n" = "feishu_key" ]; then
                    feishu_key_wizard
                else
                    install_option "$n"
                fi
            done
            ok "全部安装完成"
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#all_names[@]} ]]; then
            local selected="${all_names[$((choice-1))]}"
            if [ "$selected" = "feishu_key" ]; then
                feishu_key_wizard
            else
                install_option "$selected"
            fi
        else
            warn "无效选择"
        fi

        echo ""; read -p "按回车继续..." dummy < /dev/tty || true
    done
}

# ── 飞书 app 辅助函数（被 feishu_key_wizard 调用） ──
_feishu_add_app() {
    local conf="$1"
    echo ""
    local new_name; new_name=$(prompt "新 app 名称 (如 personal)")
    [ -z "$new_name" ] && { err "名称不能为空"; return 1; }
    local new_appid; new_appid=$(prompt "App ID")
    local new_secret; new_secret=$(prompt "App Secret")
    local new_desc; new_desc=$(prompt "描述")
    local new_workdir; new_workdir=$(prompt "workDir" "$HOME/git")
    local new_lb; if confirm "启用 larkbridge？" y; then new_lb=true; else new_lb=false; fi
    python3 - "$conf" "$new_name" "$new_appid" "$new_secret" "$new_workdir" "$new_desc" "$new_lb" << 'PYEOF'
import json, os, sys
conf, name, appid, secret, workdir, desc, lb = sys.argv[1:8]
with open(conf) as f: d = json.load(f)
d.setdefault('apps', []).append({
    'name': name,
    'appId': appid,
    'appSecret': secret,
    'description': desc,
    'brand': 'feishu',
    'workDir': workdir,
    'claudeConfigDir': os.path.expanduser('~/.claude'),
    'larkCli': {'enabled': True, 'configDir': f'~/.lark-cli-{name}'},
    'larkbridge': {'enabled': lb == 'true', 'adminOpenIds': []},
})
with open(conf, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
print(f'✅ 已添加 {name}（larkbridge={"开" if lb == "true" else "关"}）')
PYEOF
    if [ "$new_lb" = true ]; then
        echo ""
        info "  下一步建 bridge profile: bash ~/git/ccbridge/init.sh --run"
        info "  （选单的「ccprivate 配置」段会出现 ${new_name}，选它即自动建 profile）"
    fi
}

_feishu_edit_key() {
    local conf="$1" name="$2"
    echo ""
    local new_appid; new_appid=$(prompt "新 App ID")
    local new_secret; new_secret=$(prompt "新 App Secret")
    if [ -z "$new_appid" ] && [ -z "$new_secret" ]; then
        info "未修改"
        return 0
    fi
    python3 - "$conf" "$name" "${new_appid:-__KEEP__}" "${new_secret:-__KEEP__}" << 'PYEOF'
import json, sys
conf, n, appid, secret = sys.argv[1:5]
with open(conf) as f: d = json.load(f)
for a in d.get('apps', []):
    if a['name'] == n:
        if appid != '__KEEP__': a['appId'] = appid
        if secret != '__KEEP__': a['appSecret'] = secret
        with open(conf, 'w') as f:
            json.dump(d, f, indent=4, ensure_ascii=False)
        print(f'✅ {n} 已更新 (appId={"✓" if appid!="__KEEP__" else "·"}, secret={"✓" if secret!="__KEEP__" else "·"})')
        sys.exit(0)
print(f'❌ 未找到 app: {n}')
sys.exit(1)
PYEOF
}

_feishu_delete_app() {
    local conf="$1" name="$2"
    echo ""
    if ! confirm "确认删除 app「${name}」？" n; then info "已取消"; return 0; fi
    python3 - "$conf" "$name" << 'PYEOF'
import json, sys
conf, n = sys.argv[1:3]
with open(conf) as f: d = json.load(f)
before = len(d.get('apps', []))
d['apps'] = [a for a in d.get('apps', []) if a['name'] != n]
after = len(d['apps'])
if before == after:
    print(f'❌ 未找到 app: {n}')
    sys.exit(1)
with open(conf, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
print(f'✅ 已删除 {n}')
PYEOF
}

list_names_compact() {
    for group_entry in "${MENU_GROUPS[@]}"; do
        local group_title="${group_entry%%|*}"
        local group_items="${group_entry#*|}"
        echo "$group_title"
        for n in $group_items; do
            case "$n" in
                mcp|feishu_key) echo "  $n" ;;
                batcat|glow) echo "  $n" ;;
                *) if [ -n "${AUTO_MANAGED[$n]:-}" ] || has_init_script "$n"; then echo "  $n"; fi ;;
            esac
        done
    done
}

install_all() {
    for group_entry in "${MENU_GROUPS[@]}"; do
        local group_items="${group_entry#*|}"
        for n in $group_items; do
            # 自动管理的项：批量跳过（init-llm 按需拉起）
            [ -n "${AUTO_MANAGED[$n]:-}" ] && continue
            case "$n" in
                mcp) install_option "mcp" --batch ;;
                batcat|glow) install_option "$n" --batch ;;
                usage) install_option "$n" --batch --yes ;;
                *) has_init_script "$n" && install_option "$n" --batch ;;
            esac
        done
    done
    echo ""
    ok "全部可选组件安装完成"
}

# ── 入口 ──
# 解析全局 --dry-run：从参数中剥离并设置环境变量
_DRY_RUN_GLOBAL=false
case "${1:-}" in
    --dry-run|--preview|--what)
        _DRY_RUN_GLOBAL=true
        export CCC_DRY_RUN=1
        shift
        ;;
esac

case "${1:-menu}" in
    --status|status|-s)
        list_all
        ;;
    -l|list)
        list_names_compact
        ;;
    all|--all|-a)
        shift 2>/dev/null || true
        install_all
        ;;
    menu|--menu|"")
        interactive_menu
        ;;
    *)
        install_option "$@"
        ;;
esac
