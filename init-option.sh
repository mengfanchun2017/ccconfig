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

source "$SCRIPT_DIR/lib/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; DIM='\033[2m'; NC='\033[0m'
    ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
    err()   { echo -e "  ${RED}❌ $1${NC}"; }
    warn()  { echo -e "  ${YELLOW}⚠  $1${NC}"; }
    info()  { echo -e "  ${GRAY}$1${NC}"; }
    section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
}

# ── 分组定义 ──
# 每个组：组标题 + 组内菜单项列表
# 每一项: "name" 选项名
# "---" 分隔行（仅展示，不可选）

# 内置 CLI 描述
declare -A CLI_DESC
CLI_DESC["bat"]="bat 是 cat 替代，语法高亮+行号"
CLI_DESC["glow"]="终端 Markdown 渲染阅读"
CLI_DESC["nano"]="终端文本编辑器，简单直观"

# Option 描述

# ── 分组列表 ──
# 格式: "group_title|item1 item2 ..."
MENU_GROUPS=(
    "--os--|bat glow nano"
    "--claude--|mcp skill"
    "--lark--|larkcli larkbridge"
    "--other--|officecli remote cloudflare usage"
    "--key--|feishu_key"
)

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
        bat)
            if command -v batcat &>/dev/null || command -v bat &>/dev/null; then
                local ver=$(bat --version 2>/dev/null | head -1 || batcat --version 2>/dev/null | head -1 || echo "")
                echo "ok|OK|bat 已安装${ver:+ ($ver)}"
            else
                echo "miss|MISSING|bat 未安装"
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
    echo ""
    echo -e "${CYAN}可选组件状态${NC}"
    echo ""

    local idx=1
    local -a all_names

    # 确保 mcp 在 group 中可被检测（作为内置选项，无 option-mcp 目录）
    mcp_status() {
        local conf="$CCPRIVATE_HOME/conf/claude.json"
        if [ -f "$conf" ]; then
            local count=$(python3 -c "import json; d=json.load(open('$conf')); print(len(d.get('mcp_servers',[])))" 2>/dev/null || echo "0")
            if [ "$count" -gt 0 ]; then
                echo "ok|OK|$count 个 MCP 服务器已注册"
            else
                echo "miss|MISSING|MCP 未配置（bash lib/init-mcp.sh sync）"
            fi
        else
            echo "miss|MISSING|claude.json 未找到"
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
                bat|glow|nano) ;;
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
            render_status "$status"
            echo ""
            idx=$((idx + 1))
        done
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
            read -p "  添加新 app? [Y/n]: " confirm
            confirm="${confirm:-y}"
            [[ "$confirm" =~ ^[Yy]$ ]] || return 0
            _feishu_add_app "$conf"
            continue
        fi

        echo -e "  当前 apps:  ${GRAY}(当前活跃: ${current_name:-无})${NC}"
        echo ""
        local i=1
        names=()
        for app_json in "${apps_json[@]}"; do
            local name=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
            local appid=$(echo "$app_json" | python3 -c "import json,sys; a=json.load(sys.stdin)['appId']; print(a[:12]+'...' if len(a)>12 else a)")
            local lcen=$(echo "$app_json" | python3 -c "import json,sys; print('Y' if json.load(sys.stdin).get('larkCli',{}).get('enabled') else '.')")
            local ccen="."
            local lben=$(echo "$app_json" | python3 -c "import json,sys; d=json.load(sys.stdin).get('larkBridge',{}); print('Y' if d.get('enabled') else ('.' if d else ''))")
            local lb_suffix=""
            [ -n "$lben" ] && lb_suffix=" B=${lben}"
            local desc=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))")
            local marker_str=""
            [ "$name" = "$current_name" ] && marker_str=" ${GREEN}← 当前${NC}"
            if [ -n "$marker_str" ]; then
                echo -e "    ${i}) ${name}${GRAY}${NC} appId=${appid}  L=${lcen} C=${ccen} ${marker_str}"
            else
                printf "    %d) %-12s appId=%s  L=%s C=%s%s\n" "$i" "$name" "$appid" "$lcen" "$ccen" "$lb_suffix"
            fi
            [ -n "$desc" ] && echo -e "       ${GRAY}${desc}${NC}"
            names+=("$name")
            i=$((i + 1))
        done
        echo "    a) 添加新 app"
        echo "    0) 返回主菜单"
        echo ""

        read -p "  选择 [0-${#apps_json[@]}/a]: " sel

        case "$sel" in
            0|q) return 0 ;;
            a|A) _feishu_add_app "$conf" ;;
        esac

        if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#apps_json[@]} ]; then
            continue
        fi

        local target_name="${names[$((sel - 1))]}"
        echo ""

        # app 二级菜单
        echo -e "${CYAN}── 应用: ${target_name}${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} 编辑 App ID / Secret"
        echo -e "  ${YELLOW}2)${NC} 切换到此账号 (lark-cli)"
        echo -e "  ${CYAN}3)${NC} OAuth 授权 (lark-cli auth login)"
        echo -e "  ${GRAY}4)${NC} 查看当前授权状态"
        if [ "$target_name" != "$current_name" ]; then
            echo -e "     ${DIM}(当前活跃: ${current_name:-无})${NC}"
        fi
        echo ""
        printf "  ${DIM}d) 删除  0) 返回${NC}"
        echo ""
        read -p "  选择 [0-4/d]: " sub

        case "$sub" in
            0) break ;;
            1) _feishu_edit_key "$conf" "$target_name" ;;
            2)
                echo ""
                bash "$SCRIPT_DIR/option-larkcli/lark-switch.sh" "$target_name"
                # 切换后自动检测 auth
                local cd="$HOME/.lark-cli-${target_name}"
                if [ -f "${cd}/config.json" ]; then
                    if ! LARKSUITE_CLI_CONFIG_DIR="$cd" lark-cli auth status 2>/dev/null | grep -q "tokenStatus.*valid"; then
                        echo ""
                        warn "  该账号尚未 OAuth 授权，自动拉起授权..."
                        LARKSUITE_CLI_CONFIG_DIR="$cd" bash "$SCRIPT_DIR/option-larkcli/init.sh" --auth-login "$target_name" 2>&1
                    else
                        info "  授权状态正常"
                    fi
                fi
                ;;
            3)
                echo ""
                local cd="$HOME/.lark-cli-${target_name}"
                if [ -f "${cd}/config.json" ]; then
                    LARKSUITE_CLI_CONFIG_DIR="$cd" bash "$SCRIPT_DIR/option-larkcli/init.sh" --auth-login "$target_name" 2>&1
                else
                    warn "先选 1 编辑 App ID/Secret"
                fi
                ;;
            4)
                echo ""
                local cd="$HOME/.lark-cli-${target_name}"
                if [ -f "${cd}/config.json" ]; then
                    LARKSUITE_CLI_CONFIG_DIR="$cd" lark-cli auth status 2>&1 | grep -v "^\[lark-cli\]" | sed 's/^/  /'
                else
                    warn "初始化中，暂无授权状态"
                fi
                ;;
            d|D)
                _feishu_delete_app "$conf" "$target_name"
                ;;
        esac
        echo ""
    done
}

# ── 安装单个 option ──
install_option() {
    local name="$1"
    shift

    if _dry_run_enabled "$@"; then
        printf 'would: bash option-%s/init.sh\n' "$name"
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
          echo "  ─ usage 管理 ─"
          echo "    1) 安装 timer (每天 12:01 自动归档+推飞书)"
          echo "    2) 卸载 timer"
          echo "    3) 配置 (feishu_url / schedule / include_today)"
          echo "    4) 查看状态"
          echo "    5) 手动触发归档+推飞书（按配置跑，不含今天）"
          echo "    0) 返回"
          read -p "  选择 [0-5]: " sub
          case "$sub" in
            1) bash "$SCRIPT_DIR/option-usage/init.sh" install ;;
            2) bash "$SCRIPT_DIR/option-usage/init.sh" uninstall ;;
            3) bash "$SCRIPT_DIR/option-usage/init.sh" config ;;
            4) bash "$SCRIPT_DIR/option-usage/init.sh" status ;;
            5) bash "$SCRIPT_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;;
            0) break ;;
          esac
          echo ""
          read -p "  按回车继续..." dummy
        done
      fi
      return 0
    fi

    if _dry_run_enabled "$@"; then
        printf 'would: bash option-%s/init.sh\n' "$name"
        return 0
    fi

    # option-* 目录
    if has_init_script "$name"; then
        section "安装 $name"
        local args=("$@")
        if [ "$name" = "larkbridge" ] && [ ${#args[@]} -eq 0 ]; then
            args=("--run")
        fi
        bash "$SCRIPT_DIR/option-$name/init.sh" "${args[@]}"
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
        bat)   install_bat ;;
        glow)  install_glow ;;
        nano)  install_nano ;;
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
                sudo dpkg -i /tmp/bat.deb 2>/dev/null || sudo apt-get install -f -y
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
        ok "glow 已安装: $(glow --version 2>/dev/null | head -1)"
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
            sudo dpkg -i /tmp/glow.deb 2>/dev/null || sudo apt-get install -f -y
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

install_nano() {
    section "nano 文本编辑器"

    if command -v nano &>/dev/null; then
        ok "nano 已安装: $(nano --version 2>/dev/null | head -1)"
        return 0
    fi

    info "安装 nano..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y nano
    else
        err "无法安装 nano（非 apt 系统）"
        return 1
    fi

    if command -v nano &>/dev/null; then
        ok "nano 已安装"
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
                    bat|glow|nano) all_names+=("$name") ;;
                    *) has_init_script "$name" && all_names+=("$name") ;;
                esac
            done
        done

        local max_idx=${#all_names[@]}
        read -p "选择安装 (1-${max_idx}, a 全部, 0 退出): " choice

        case "$choice" in
            0|q|exit) echo ""; exit 0 ;;
            a|all)
                for n in "${all_names[@]}"; do
                    if [ "$n" = "feishu_key" ]; then
                        feishu_key_wizard
                    else
                        install_option "$n"
                    fi
                done
                echo ""
                ok "全部安装完成"
                ;;
            *)
                local any_valid=false
                for token in $choice; do
                    if [[ "$token" =~ ^[0-9]+$ ]] && [ "$token" -ge 1 ] && [ "$token" -le $max_idx ]; then
                        local selected="${all_names[$((token - 1))]}"
                        if [ "$selected" = "feishu_key" ]; then
                            feishu_key_wizard
                        else
                            install_option "$selected"
                        fi
                        any_valid=true
                    fi
                done
                if ! $any_valid; then
                    warn "无效选择"
                fi
                ;;
        esac

        echo ""
        read -p "操作完成，按回车继续..." dummy
    done
}

# ── 飞书 app 辅助函数（被 feishu_key_wizard 调用） ──
_feishu_add_app() {
    local conf="$1"
    echo ""
    read -p "  新 app 名称 (如 personal): " new_name
    [ -z "$new_name" ] && { err "名称不能为空"; return 1; }
    read -p "  App ID: " new_appid
    read -p "  App Secret: " new_secret
    read -p "  workDir (回车=~/git): " new_workdir
    new_workdir="${new_workdir:-/home/$USER/git}"
    python3 - "$conf" "$new_name" "$new_appid" "$new_secret" "$new_workdir" << 'PYEOF'
import json, sys
conf, name, appid, secret, workdir = sys.argv[1:6]
with open(conf) as f: d = json.load(f)
d.setdefault('apps', []).append({
    'name': name,
    'appId': appid,
    'appSecret': secret,
    'description': '',
    'brand': 'feishu',
    'workDir': workdir,
    'claudeConfigDir': '/home/' + __import__('os').environ.get('USER','user') + '/.claude',
    'larkCli': {'enabled': True, 'configDir': f'~/.lark-cli-{name}'},
})
with open(conf, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
print(f'✅ 已添加 {name}')
PYEOF
}

_feishu_edit_key() {
    local conf="$1" name="$2"
    echo ""
    read -p "  新 App ID (回车跳过): " new_appid
    read -p "  新 App Secret (回车跳过): " new_secret
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
    read -p "  确认删除 app「${name}」? [y/N]: " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        info "已取消"
        return 0
    fi
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

# ── 入口 ──
case "${1:-menu}" in
    --status|status|-s)
        list_all
        ;;
    -l|list)
        for group_entry in "${MENU_GROUPS[@]}"; do
            local group_title="${group_entry%%|*}"
            local group_items="${group_entry#*|}"
            echo "$group_title"
            for n in $group_items; do
                case "$n" in
                    mcp) echo "  mcp" ;;
                    bat|glow|nano) echo "  $n" ;;
                    *) has_init_script "$n" && echo "  $n" ;;
                esac
            done
        done
        ;;
    all|--all|-a)
        shift 2>/dev/null || true
        for group_entry in "${MENU_GROUPS[@]}"; do
            local group_items="${group_entry#*|}"
            for n in $group_items; do
                case "$n" in
                    mcp) install_option "mcp" --batch ;;
                    bat|glow|nano) install_option "$n" --batch ;;
                    usage) install_option "$n" --batch --yes ;;
                    *) has_init_script "$n" && install_option "$n" --batch ;;
                esac
            done
        done
        echo ""
        ok "全部可选组件安装完成"
        ;;
    menu|--menu|"")
        interactive_menu
        ;;
    *)
        install_option "$@"
        ;;
esac
