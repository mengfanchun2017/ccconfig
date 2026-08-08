#!/bin/bash
# maintain.sh — ccconfig 运维入口（默认菜单）
#
# 用法：
#   bash maintain.sh                    # 交互菜单（推荐）
#   bash maintain.sh setup              # 一键收尾（首次安装/修复）
#   bash maintain.sh status [--quick]   # 状态检查（--quick 跳过慢检查）
#   bash maintain.sh self [cc|skill|all]  # 自我更新
#   bash maintain.sh upgrade [comp]     # 升级组件
#   bash maintain.sh sync [--pull|--push] [repo]  # Git 同步
#   bash maintain.sh monitor [start|stop|status|tail]
#   bash maintain.sh deps               # 依赖检查
#   bash maintain.sh llmswitch [start|stop|restart|status]   # LLM 网关代理
#   bash maintain.sh fix                # 自动修复（= setup）
#
# 暗号：
#   hookstatus → bash maintain.sh status
#   pullff     → bash maintain.sh sync --pull

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CCCONFIG_DIR="$SCRIPT_DIR"

source "$LIB_DIR/dry-run.sh"
source "$LIB_DIR/path-helper.sh" 2>/dev/null || true
export PATH="$HOME/.local/bin:$(find_node_bin 2>/dev/null || echo ""):$PATH"
source "$LIB_DIR/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; DIM='\033[2m'; NC='\033[0m'
    ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
    err()   { echo -e "  ${RED}❌ $1${NC}"; }
    warn()  { echo -e "  ${YELLOW}⚠  $1${NC}"; }
    info()  { echo -e "  ${GRAY}$1${NC}"; }
    section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
}

# ── Step 5: 收尾 ──
do_finalize() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ccconfig 收尾 — 链接修复 + 状态检查 + 服务启动${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    # 1. 修复符号链接（ccprivate/setup.sh 统一处理公私链接）
    section "1. 修复符号链接"
    local ccprivate_setup="$ccpriv/setup.sh"
    if [[ -x "$ccprivate_setup" ]]; then
        bash "$ccprivate_setup" 2>/dev/null && ok "符号链接已修复" || warn "符号链接部分失败"
    else
        bash "$LIB_DIR/setup-links.sh"
        info "ccprivate/setup.sh 不可用，仅修复了公开链接"
    fi

    # 1b. 补齐 ccprivate 缺失目录（空目录 git 不跟踪，clone 后不存在）
    local expected_dirs=("skill-config" "rules" "agents" "commands" "bin")
    local created=false
    for d in "${expected_dirs[@]}"; do
        if [[ ! -d "$ccpriv/$d" ]]; then
            mkdir -p "$ccpriv/$d"
            touch "$ccpriv/$d/.gitkeep"
            created=true
        fi
    done
    if $created; then
        ok "缺失 ccprivate 目录已补齐"
    fi

    # 2. auto-sync 服务
    section "2. 启动 auto-sync"
    if bash "$LIB_DIR/init-autostart.sh" enable; then
        ok "auto-sync 已启动"
    else
        warn "auto-sync 启动失败（可手动: bash $LIB_DIR/monitor.sh start）"
    fi

    # 3. Example 模板自动同步（静默，只复制新增/更新，不覆盖用户编辑过的）
    if [ -x "$LIB_DIR/example-sync.sh" ]; then
        section "3. Example 模板同步"
        bash "$LIB_DIR/example-sync.sh" sync 2>/dev/null && ok "模板已同步" || warn "模板同步跳过"
    fi

    # 4. 状态检查
    section "4. 状态总览"
    bash "$LIB_DIR/status.sh" --quick

    # 5. 输出汇总
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ccconfig 就绪 🎉${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}日常命令:${NC}"
    echo ""
    echo -e "  ${CYAN}bash maintain.sh${NC}             # 交互菜单（推荐）"
    echo -e "  ${CYAN}bash maintain.sh status --quick${NC}  # 快速状态"
    echo -e "  ${CYAN}bash maintain.sh status${NC}         # 全量状态"
    echo -e "  ${CYAN}bash maintain.sh self all${NC}       # 更新 ccconfig + skill"
    echo -e "  ${CYAN}bash maintain.sh upgrade all${NC}     # 升级系统组件"
    echo ""
}

# ── 自我更新（ccconfig + skill）──
do_self() {
    local target="${1:-all}"
    case "$target" in
        cc|ccconfig)
            echo -e "${CYAN}── ccconfig 自更新 ──${NC}"
            git -C "$SCRIPT_DIR" fetch origin main 2>/dev/null || { warn "无法连接远程"; return 1; }
            local local_commit=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null)
            git -C "$SCRIPT_DIR" pull --ff-only origin main 2>/dev/null && {
                local after=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
                [ "$local_commit" != "$after" ] && ok "ccconfig: $local_commit → $after" || ok "ccconfig 已是最新: $local_commit"
            } || { warn "ccconfig 拉取失败（有本地改动？）"; return 1; }
            echo ""
            bash "$LIB_DIR/setup-links.sh"
            ;;
        skill)
            echo -e "${CYAN}── Skill 同步 ──${NC}"
            bash "$LIB_DIR/init-skill.sh" sync
            ;;
        all|"")
            do_self cc
            echo ""
            do_self skill
            ;;
        *)
            err "未知 self 目标: $target（可用: cc, skill, all）"
            return 1
            ;;
    esac
}

# ── 交互菜单 ──
show_menu() {
    echo ""
    echo -e "${CYAN}━━━ ccconfig 运维中心 ━━━${NC}"
    echo ""
    echo "  1) 状态检查         ─ 全量状态（链接/依赖/同步/Git/飞书/Playwright/MCP）"
    echo "  2) Monitor 管理     ─ 启停/状态/日志/实时监控"
    echo "  3) 自我更新         ─ 拉取 ccconfig + skill 最新"
    echo "  4) Git 同步         ─ 多仓库菜单式同步"
    echo "  5) 组件升级         ─ Node.js / Claude / gh / uv / lark-cli / lark-channel-bridge ..."
    echo "  6) 依赖检查         ─ 必需/核心/功能/可选依赖"
    echo "  7) 一键修复         ─ 重建链接 + 启用 auto-sync（= setup）"
    echo "  8) 模板同步         ─ 默认正向（template → ccprivate），反向仅仓库所有者可用"
    echo "  9) ccprivate 升级    ─ 检测并修复 ccprivate 结构"
    echo "  10) Bill & Token     ─ 模型单价配置 + Claude Code 用量聚合（CSV / 飞书）"
	echo "  11) MCP 管理         ─ 注册/启停/状态/Key/项目配置"
    echo "  12) llmswitch        ─ LLM 网关代理（init-llm 自动管理，手动可看下面板）"
    echo "  13) 飞书管理         ─ 账号 / lark-cli / larkbridge（多账号多机器人）"
    echo "  14) 回归测试         ─ WSL 新建 distro + bootstrap 全流程（CI/自动化）"
    echo ""
    echo "  0) 退出"
    echo ""
    read -p "选择 [0-14]: " c
    c=$(menu_num "$c")

    case "$c" in
        1) bash "$LIB_DIR/status.sh" "$@" ;;
        2) submenu_monitor ;;
        3) do_self all ;;
        4) bash "$LIB_DIR/sync.sh" ;;
        5) bash "$LIB_DIR/update.sh" menu ;;
        6) bash "$LIB_DIR/deps-check.sh" ;;
        7) do_finalize ;;
        8) bash "$LIB_DIR/example-sync.sh" status
           echo ""
           echo "  d) 查看差异   f) 正向同步（默认）   r) 反向同步（需 push 权限）   0) 返回"
           read -p "选择 [d/f/r/0]: " choice
           case "$choice" in
             d) bash "$LIB_DIR/example-sync.sh" diff ;;
             f) bash "$LIB_DIR/example-sync.sh" promote ;;
             r) bash "$LIB_DIR/example-sync.sh" reverse ;;
             0) ;;
             *) ;;
           esac ;;
        9) bash "$LIB_DIR/ccprivate-upgrade.sh"
           echo ""
           read -p "按回车返回菜单..." dummy
           show_menu ;;
        11) bash "$LIB_DIR/mcp-manager.sh" config
            read -p "按回车返回菜单..." dummy
            show_menu ;;
        12) submenu_llmswitch
            read -p "按回车返回菜单..." dummy
            show_menu ;;
        13) submenu_feishu
            read -p "按回车返回菜单..." dummy
            show_menu ;;
        14) bash "$CCCONFIG_DIR/bin/test-bootstrap.sh" "$@"
            read -p "按回车返回菜单..." dummy
            show_menu ;;
        10) while true; do
           echo ""
           echo "  ─ Bill & Token ─"
           echo "  1) Bill (配置模型 token 单价)"
           echo "  2) 用量统计 (总览)"
           echo "  3) 按日报告"
           echo "  4) 按天归档 (增量 → ccprivate/usage/)"
           echo "  5) 推飞书 (用配置 URL，弹提示输可临时覆盖)"
           echo "  6) timer 管理 (装/卸/状态/配置)"
           echo "  7) 手动触发归档+推飞书 (按配置跑，不含今天)"
           echo "  0) 返回"
           read -p "  选择 [0-7]: " choice
           choice=$(menu_num "$choice")
           case "$choice" in
             1) bash "$LIB_DIR/init-llm.sh" bill ;;
             2) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --stats ;;
             3) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --report ;;
             4) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ;;
             5)
                read -p "  飞书 URL (回车 = 用 config 默认): " url
                if [[ -n "$url" ]]; then
                   bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --feishu "$url"
                else
                   bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental
                fi
                ;;
             6) bash "$CCCONFIG_DIR/option-usage/init.sh" status
                echo ""
                echo "  ─ 操作 ─"
                echo "    i) 装 systemd timer"
                echo "    u) 卸 systemd timer"
                echo "    c) 配置 feishu_url / schedule / include_today"
                echo "    b) 返回"
                read -p "  选择 [i/u/c/b]: " sub
                case "$sub" in
                  i) bash "$CCCONFIG_DIR/option-usage/init.sh" install ;;
                  u) bash "$CCCONFIG_DIR/option-usage/init.sh" uninstall ;;
                  c) bash "$CCCONFIG_DIR/option-usage/init.sh" config ;;
                esac
                ;;
             7) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;;
             0) break ;;
             *) ;;
           esac
           echo ""
           echo "  按回车继续..."
           read -r dummy
           done ;;
        0) echo ""; exit 0 ;;
        *) show_menu ;;
    esac

    echo ""
    read -p "按回车返回菜单..." dummy
    show_menu
}

submenu_monitor() {
    echo ""
    echo -e "${CYAN}── Monitor 管理 ──${NC}"
    echo ""
    echo "  1) 启动             ─ 后台启动文件监控 + 自动提交推送"
    echo "  2) 停止             ─ 停止监控进程"
    echo "  3) 看状态           ─ 进程状态 + 各仓库待提交文件数"
    echo "  4) 实时追踪 (tail)  ─ 持续输出推送结果（Ctrl+C 退出）"
    echo "  5) 文件变更 (mon)   ─ 实时显示文件变更事件（Ctrl+C 退出）"
    echo ""
    echo "  0) 返回"
    echo ""
    read -p "选择 [0-5]: " c
    c=$(menu_num "$c")
    case "$c" in
        1) bash "$LIB_DIR/monitor.sh" start ;;
        2) bash "$LIB_DIR/monitor.sh" stop ;;
        3) bash "$LIB_DIR/monitor.sh" status ;;
        4) bash "$LIB_DIR/monitor.sh" tail ;;
        5) bash "$LIB_DIR/monitor.sh" monitor ;;
        0) return ;;
        *) submenu_monitor ;;
    esac
}

submenu_llmswitch() {
    echo ""
    echo -e "${CYAN}── llmswitch 网关代理 ──${NC}"
    echo -e "${GRAY}  由 init-llm 自动管理（按 provider 自动启/停）${NC}"
    echo ""
    echo "  1) 启动代理        ─ bash option-llmswitch/init.sh --start"
    echo "  2) 停止代理        ─ bash option-llmswitch/init.sh --stop"
    echo "  3) 重启代理        ─ bash option-llmswitch/init.sh --restart"
    echo "  4) 查看状态        ─ bash option-llmswitch/init.sh --status"
    echo "  5) 切换 LLM (推荐) ─ 自动按 provider 启/停（gate/minimax/...）"
    echo ""
    echo "  0) 返回"
    echo ""
    read -p "选择 [0-5]: " c
    c=$(menu_num "$c")
    case "$c" in
        1) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --start ;;
        2) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --stop ;;
        3) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --restart ;;
        4) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --status ;;
        5) bash "$LIB_DIR/init-llm.sh" ;;
        0) return ;;
        *) submenu_llmswitch ;;
    esac
}

# 读取 feishu.json 账号列表（一行一 JSON）
_feishu_list_apps() {
    local conf
    conf="$(resolve_conf feishu.json 2>/dev/null)" || true
    if [ -z "$conf" ] || [ ! -f "$conf" ]; then
        echo ""
        return 0
    fi
    python3 - "$conf" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for a in d.get('apps', []):
    print(json.dumps(a, ensure_ascii=False))
PYEOF
}

_feishu_current_account() {
    local marker="$HOME/.lark-cli-account"
    [ -f "$marker" ] && grep '^name=' "$marker" | cut -d'=' -f2
}

_feishu_current_profile() {
    [ -f "$HOME/.lark-channel/config.json" ] \
        && python3 -c "import json; print(json.load(open('$HOME/.lark-channel/config.json')).get('activeProfile',''))" 2>/dev/null
}

# larkbridge 必备权限清单 + 一键申请 URL（共享自 lib/feishu-perms.sh）
source "$LIB_DIR/feishu-perms.sh" 2>/dev/null || true

_feishu_perms_menu() {
    local apps; apps="$(_feishu_list_apps)"
    local i=1
    local labels=()
    echo ""
    echo -e "${CYAN}── 申请 larkbridge 权限 ──${NC}"
    echo ""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local n lb
        n=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        lb=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('larkbridge',{}).get('enabled',False))" 2>/dev/null)
        if [ "$lb" = "True" ]; then
            echo "  $i) $n"
            labels+=("$n")
            i=$((i+1))
        fi
    done < <(echo "$apps")
    if [ ${#labels[@]} -eq 0 ]; then
        warn "没有启用 larkbridge 的 app"
        return 0
    fi
    echo "  0) 返回"
    read -p "  选择 app [0-${#labels[@]}]: " c
    c=$(menu_num "$c")
    [ "$c" = "0" ] && return 0
    if [ -n "$c" ] && [ "$c" -ge 1 ] && [ "$c" -le "${#labels[@]}" ] 2>/dev/null; then
        _feishu_open_perms_for_app "${labels[$((c-1))]}"
    fi
    read -p "  按回车返回飞书菜单..." dummy
}

submenu_feishu() {
    local feishu_lb="$CCCONFIG_DIR/option-larkbridge/init.sh"
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"

    while true; do
        local lcb_ver; lcb_ver=$(lark-channel-bridge --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        local lcc_ver; lcc_ver=$(lark-cli --version 2>/dev/null | head -1 | sed 's/^[^0-9]*//' || echo "?")
        local cur_acct; cur_acct="$(_feishu_current_account)"
        local cur_prof; cur_prof="$(_feishu_current_profile)"

        echo ""
        echo -e "${CYAN}── 飞书统一管理 ──${NC}"
        echo ""
        echo -e "  ${GRAY}lark-cli: v${lcc_ver}    活跃账号: ${cur_acct:-无}${NC}"
        echo -e "  ${GRAY}lark-channel-bridge: v${lcb_ver}    活跃 profile: ${cur_prof:-无}${NC}"
        echo ""
        echo "  1) 飞书账号          ─ feishu.json apps 列表 + 切换 lark-cli 活跃账号"
        echo "  2) lark-cli          ─ OAuth 授权 / 看授权状态"
        echo "  3) larkbridge        ─ profile 列表 / 启停 / 日志 / 新增 / 删除"
        echo "  4) 发测试消息        ─ 给活跃 profile 的允许用户发 text"
        echo "  5) lark-cli 装包/升级    ─ 没装就装，已装就升 npm latest"
        echo "  6) larkbridge 装包/升级  ─ 没装就装，已装就升 npm latest"
        echo "  7) 申请权限         ─ 一键跳转飞书开放平台，开通 larkbridge 必备权限"
        echo ""
        echo "  0) 返回主菜单"
        echo ""
        read -p "选择 [0-7]: " c
        c=$(menu_num "$c")

        case "$c" in
            1) submenu_feishu_accounts ;;
            2) submenu_feishu_larkcli ;;
            3) submenu_feishu_larkbridge ;;
            4) _feishu_send_test_message ;;
            5)
                echo ""
                if ! command -v lark-cli &>/dev/null; then
                    info "lark-cli 未安装，正在装..."
                    bash "$CCCONFIG_DIR/option-larkcli/init.sh"
                else
                    bash "$LIB_DIR/update.sh" lark
                fi
                read -p "  按回车返回飞书菜单..." dummy
                ;;
            6)
                echo ""
                if ! command -v lark-channel-bridge &>/dev/null; then
                    info "lark-channel-bridge 未安装，正在装..."
                    bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --run 2>&1 | head -5 || true
                    info "（前台命令已退出，转后台请走 3) larkbridge）"
                else
                    bash "$LIB_DIR/update.sh" larkbridge
                fi
                read -p "  按回车返回飞书菜单..." dummy
                ;;
            7) _feishu_perms_menu ;;
            0) return 0 ;;
            *) continue ;;
        esac
    done
}

submenu_feishu_larkcli() {
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"

    while true; do
        echo ""
        echo -e "${CYAN}── lark-cli ──${NC}"
        bash "$feishu_lc" --status
        echo ""
        echo "  a) 重置全部账号配置 (re-run init)"
        echo "  k) 看当前账号的 OAuth 状态"
        echo "  l) 列出全部账号"
        echo "  0) 返回飞书菜单"
        read -p "  选择 [a/k/l/0]: " sub
        case "$sub" in
            a|A) bash "$feishu_lc" ;;
            k|K) bash "$feishu_switch" ;;
            l|L) bash "$feishu_switch" --list ;;
            0) return 0 ;;
            *) continue ;;
        esac
    done
}

submenu_feishu_larkbridge() {
    local feishu_lb="$CCCONFIG_DIR/option-larkbridge/init.sh"

    while true; do
        echo ""
        bash "$feishu_lb" --status
        echo ""
        echo "  ─ 操作 ─"
        echo "    s) 启停/重启 profile  ─ select"
        echo "    n) 新增 profile       ─ add（ccprivate 配置 or 扫码）"
        echo "    r) 删除 profile       ─ remove"
        echo "    l) 实时日志           ─ logs <profile>"
        echo "    d) 设为默认           ─ default"
        echo "    0) 返回飞书菜单"
        read -p "  选择 [s/n/r/l/d/0]: " sub
        case "$sub" in
            s|S) bash "$feishu_lb" --start ;;
            n|N) bash "$feishu_lb" --profile add ;;
            r|R) bash "$feishu_lb" --profile remove ;;
            l|L) bash "$feishu_lb" --logs ;;
            d|D) bash "$feishu_lb" --profile default ;;
            0) return 0 ;;
            *) continue ;;
        esac
    done
}

# 从活跃 profile 读第一个允许用户的 open_id 作为默认收件人
_feishu_default_openid() {
    local prof; prof="$(_feishu_current_profile)"
    [ -z "$prof" ] && return 0
    local root_cfg="$HOME/.lark-channel/config.json"
    [ -f "$root_cfg" ] || return 0
    python3 - "$root_cfg" "$prof" << 'PYEOF' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
prof = d.get('profiles', {}).get(sys.argv[2], {})
users = prof.get('access', {}).get('allowedUsers', [])
if users: print(users[0])
PYEOF
}

# 测试消息路径：allowedUsers 空时让用户输一次 open_id，自动 patch 进 ~/.lark-channel/config.json
# 同时回写 feishu.json 的 apps[].larkBridge.adminOpenIds 防止下次新建 profile 再问
# 注意：所有 info/warn/good 必须走 stderr，否则被 $(...) 当 oid 捕获
_feishu_resolve_recipient() {
    local target="$1"
    local oid; oid="$(_feishu_default_openid)"
    [ -n "$oid" ] && { echo "$oid"; return 0; }

    {
      warn "  活跃 profile 没有 allowedUsers，没法自动选收件人"
      echo ""
      info "  这个 open_id 是你自己飞书的 ID（bot 会拒绝其他人发消息，所以必须配）"
      info "  怎么找：飞书打开 bot → 给 bot 发任意消息 → 看 ~/.lark-channel/profiles/<active>/logs/*.jsonl 里 receive_id 字段"
      echo ""
    } >&2
    read -p "  输入你的 open_id (回车跳过): " input_oid
    [ -z "$input_oid" ] && { warn "  跳过" >&2; return 1; }

    local root_cfg="$HOME/.lark-channel/config.json"
    local prof; prof="$(_feishu_current_profile)"
    python3 - "$root_cfg" "$prof" "$input_oid" << 'PYEOF' 2>/dev/null
import json, sys
p, prof, oid = sys.argv[1], sys.argv[2], sys.argv[3]
with open(p) as f: d = json.load(f)
pr = d.setdefault('profiles', {}).setdefault(prof, {})
acc = pr.setdefault('access', {})
users = acc.setdefault('allowedUsers', [])
if oid not in users: users.append(oid)
with open(p,'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
    good "  ✓ 已写入 $root_cfg profiles.${prof}.access.allowedUsers" >&2

    # 同步到 feishu.json larkBridge.adminOpenIds（如果 target 在 apps 里）
    local feishu_conf; feishu_conf="$(resolve_conf feishu.json 2>/dev/null)" || true
    if [ -n "$feishu_conf" ] && [ -f "$feishu_conf" ]; then
        python3 - "$feishu_conf" "$target" "$input_oid" << 'PYEOF' 2>/dev/null
import json, sys
p, name, oid = sys.argv[1], sys.argv[2], sys.argv[3]
with open(p) as f: d = json.load(f)
for a in d.get('apps', []):
    if a.get('name') == name:
        lb = a.setdefault('larkbridge', {})
        ids = lb.setdefault('adminOpenIds', [])
        if oid not in ids: ids.append(oid)
        break
with open(p,'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
        good "  ✓ 已回写 $feishu_conf apps[${target}].larkBridge.adminOpenIds" >&2
    fi

    echo "$input_oid"
}

# 选 app，直接用活跃 profile 的 allowedUsers[0] 作为收件人
# （用户多次反馈「ailab 已经有了自己的 open_id」，不再让用户输入）
_feishu_send_test_message() {
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || { warn "找不到 feishu.json"; return 0; }
    [ -f "$conf" ] || { warn "feishu.json 不存在"; return 0; }

    local -a names
    local i=1
    echo ""
    echo -e "${CYAN}── 发测试消息 ──${NC}"
    echo ""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local n; n=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        [ -z "$n" ] && continue
        printf "  ${YELLOW}%d)${NC} %s\n" "$i" "$n"
        names+=("$n")
        i=$((i + 1))
    done < <(_feishu_list_apps)

    if [ ${#names[@]} -eq 0 ]; then
        warn "feishu.json 中无 app 配置"
        return 0
    fi
    echo "  0) 返回"
    read -p "  选择 app [0-${#names[@]}]: " sel
    [[ "$sel" =~ ^[0-9]+$ ]] || return 0
    [ "$sel" -ge 1 ] && [ "$sel" -le ${#names[@]} ] || return 0
    local target="${names[$((sel - 1))]}"

    local app_json
    app_json=$(python3 - "$conf" "$target" << 'PYEOF' 2>/dev/null
import json, sys
p, name = sys.argv[1], sys.argv[2]
with open(p) as f: d = json.load(f)
for a in d.get('apps', []):
    if a.get('name') == name:
        print(json.dumps(a, ensure_ascii=False))
        break
PYEOF
)
    [ -z "$app_json" ] && { bad "找不到 app: $target"; return 0; }
    local app_id; app_id=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['appId'])" 2>/dev/null)
    local app_secret; app_secret=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['appSecret'])" 2>/dev/null)

    if [[ "$app_id" == *"请填入"* ]] || [[ "$app_secret" == *"请填入"* ]] || [ -z "$app_id" ] || [ -z "$app_secret" ]; then
        warn "appId/appSecret 未配置，先去选项 1 编辑"
        return 0
    fi

    # 直接读默认收件人，没有就引导用户输一次后自动注入
    local oid; oid="$(_feishu_resolve_recipient "$target")"
    [ -n "$oid" ] || return 0

    local msg_text="ccconfig 飞书测试消息 ✅ from $target"
    {
      echo ""
      info "  → 目标 app: $target"
      info "  → 收件人 (profile 默认): $oid"
      info "  → 内容: $msg_text"
      echo ""
    } >&2
    read -p "  发送? [Y/n]: " cf
    [[ "$cf" =~ ^[Nn]$ ]] && { info "  取消" >&2; return 0; }

    info "  拿 tenant_access_token..." >&2
    local token
    token=$(curl -s --connect-timeout 5 --max-time 10 -X POST \
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
        -H "Content-Type: application/json" \
        -d "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
    [ -z "$token" ] && { bad "  拿 access_token 失败（appId/appSecret 不对？）" >&2; return 0; }

    info "  发消息..." >&2
    local body
    body=$(python3 -c "
import json, sys
print(json.dumps({'receive_id': sys.argv[1], 'msg_type':'text', 'content': json.dumps({'text': sys.argv[2]})}, ensure_ascii=False))
" "$oid" "$msg_text")
    local resp
    resp=$(curl -s --connect-timeout 5 --max-time 15 -X POST \
        "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=open_id" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null)
    local code msg_id
    code=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code',-1))" 2>/dev/null)
    msg_id=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('message_id',''))" 2>/dev/null)
    if [ "$code" = "0" ]; then
        good "  ✅ 已发送（message_id: ${msg_id:-?}）" >&2
        info "  在飞书查收" >&2
    else
        warn "  发送失败 (code=$code):" >&2
        echo "$resp" | python3 -m json.tool 2>/dev/null | sed 's/^/    /' >&2 || echo "$resp" >&2
    fi
}

submenu_feishu_accounts() {
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"
    local conf
    conf="$(resolve_conf feishu.json 2>/dev/null)" || { warn "找不到 feishu.json"; return 0; }

    while true; do
        local cur_acct; cur_acct="$(_feishu_current_account)"
        local -a lines names
        while IFS= read -r line; do
            [ -n "$line" ] && lines+=("$line")
        done < <(_feishu_list_apps)

        echo ""
        echo -e "${CYAN}── 飞书账号 (feishu.json apps[]) ──${NC}"
        echo -e "  ${GRAY}活跃账号: ${cur_acct:-无}    配置文件: ${conf}${NC}"
        echo ""

        if [ ${#lines[@]} -eq 0 ]; then
            warn "feishu.json 中无 app 配置"
            echo "  a) 添加新 app"
            echo "  0) 返回飞书菜单"
            read -p "  选择 [a/0]: " sel
            case "$sel" in
                a|A) bash "$feishu_lc" ;;
                0) return 0 ;;
            esac
            continue
        fi

        local i=1
        names=()
        for line in "${lines[@]}"; do
            local name; name=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
            local appid; appid=$(echo "$line" | python3 -c "import json,sys; a=json.load(sys.stdin)['appId']; print((a[:14]+'...') if len(a)>14 else a)" 2>/dev/null)
            local desc; desc=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" 2>/dev/null)
            local lc_on; lc_on=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print('Y' if d.get('larkCli',{}).get('enabled') else 'N')" 2>/dev/null)
            local lb_on; lb_on=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print('Y' if d.get('larkBridge',{}).get('enabled') else 'N')" 2>/dev/null)
            local marker="  "
            [ "$name" = "$cur_acct" ] && marker="${GREEN}← 活跃${NC}"
            local lc_disp="${GRAY}✗ lark-cli${NC}"; [ "$lc_on" = "Y" ] && lc_disp="${GREEN}✓ lark-cli${NC}"
            local lb_disp="${GRAY}✗ larkbridge${NC}"; [ "$lb_on" = "Y" ] && lb_disp="${GREEN}✓ larkbridge${NC}"
            printf "  ${YELLOW}%d)${NC} %-14s appId=${GRAY}%-18s${NC} %b  %b  ${marker}\n" "$i" "$name" "$appid" "$lc_disp" "$lb_disp"
            [ -n "$desc" ] && printf "       ${GRAY}%s${NC}\n" "$desc"
            names+=("$name")
            i=$((i + 1))
        done
        echo ""
        echo "  a) 添加新 app"
        echo "  d) 删除 app"
        echo "  0) 返回飞书菜单"
        echo ""
        read -p "  选择 [0-${#lines[@]}/a/d]: " sel

        case "$sel" in
            0|q) return 0 ;;
            a|A) bash "$feishu_lc" ;;
            d|D)
                if [ ${#names[@]} -eq 0 ]; then continue; fi
                read -p "  输入要删除的 app 名: " dn
                local found=0
                for n in "${names[@]}"; do [ "$n" = "$dn" ] && found=1 && break; done
                [ "$found" -eq 1 ] && {
                    read -p "  确认从 feishu.json 删 '${dn}'? [y/N] " cf
                    if [[ "$cf" =~ ^[Yy]$ ]]; then
                        python3 - "$conf" "$dn" << 'PYEOF'
import json, sys
p, name = sys.argv[1], sys.argv[2]
with open(p) as f: d = json.load(f)
d['apps'] = [a for a in d.get('apps',[]) if a.get('name') != name]
with open(p,'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
                        info "已删除"
                    fi
                } || warn "未找到: $dn"
                continue
                ;;
        esac

        if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#lines[@]} ]; then
            continue
        fi

        local target="${names[$((sel - 1))]}"
        echo ""
        echo -e "${CYAN}── 应用: ${target} ──${NC}"
        echo ""
        echo "  1) 切到此账号 (lark-cli 活跃)"
        echo "  2) OAuth 授权 (lark-cli auth login)"
        echo "  3) 看授权状态"
        echo "  4) 编辑 App ID / Secret"
        echo "  5) 发测试消息 (到此 app)"
        echo "  0) 返回账号列表"
        read -p "  选择 [0-5]: " sub
        case "$sub" in
            1) bash "$feishu_switch" "$target" ;;
            2)
                local cd="$HOME/.lark-cli-${target}"
                if [ -f "${cd}/config.json" ]; then
                    LARKSUITE_CLI_CONFIG_DIR="$cd" bash "$feishu_lc" --auth-login "$target"
                else
                    warn "先选 4 编辑 App ID/Secret，再走 lark-cli init"
                fi
                ;;
            3)
                local cd="$HOME/.lark-cli-${target}"
                if [ -f "${cd}/config.json" ]; then
                    LARKSUITE_CLI_CONFIG_DIR="$cd" lark-cli auth status 2>&1 \
                        | grep -v '^\[lark-cli\]' | sed 's/^/  /'
                else
                    warn "config.json 不存在"
                fi
                ;;
            4) warn "手动编辑: vim $conf" ;;
            5) _feishu_send_test_message_for "$target" ;;
            0) ;;
            *) ;;
        esac
    done
}

# 单 app 发测试消息（账号子菜单调用）：跳过选 app，直接发
_feishu_send_test_message_for() {
    local target="$1"
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || return 0
    local app_json
    app_json=$(python3 - "$conf" "$target" << 'PYEOF' 2>/dev/null
import json, sys
p, name = sys.argv[1], sys.argv[2]
with open(p) as f: d = json.load(f)
for a in d.get('apps', []):
    if a.get('name') == name:
        print(json.dumps(a, ensure_ascii=False))
        break
PYEOF
)
    [ -z "$app_json" ] && { bad "找不到 app: $target"; return 0; }
    local app_id; app_id=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['appId'])" 2>/dev/null)
    local app_secret; app_secret=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['appSecret'])" 2>/dev/null)

    if [[ "$app_id" == *"请填入"* ]] || [[ "$app_secret" == *"请填入"* ]] || [ -z "$app_id" ] || [ -z "$app_secret" ]; then
        warn "appId/appSecret 未配置"
        return 0
    fi

    local oid; oid="$(_feishu_resolve_recipient "$target")"
    [ -n "$oid" ] || return 0

    local msg_text="ccconfig 飞书测试消息 ✅ from $target"
    {
        echo ""
        info "  → 目标 app: $target"
        info "  → 收件人 (profile 默认): $oid"
        info "  → 内容: $msg_text"
        read -p "  发送? [Y/n]: " cf
        [[ "$cf" =~ ^[Nn]$ ]] && { info "  取消"; return 0; }

        info "  拿 tenant_access_token..."
        local token
        token=$(curl -s --connect-timeout 5 --max-time 10 -X POST \
            "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
            -H "Content-Type: application/json" \
            -d "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}" \
            | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
        [ -z "$token" ] && { bad "  拿 access_token 失败（appId/appSecret 不对？）"; return 0; }

        info "  发消息..."
        local body
        body=$(python3 -c "
import json, sys
print(json.dumps({'receive_id': sys.argv[1], 'msg_type':'text', 'content': json.dumps({'text': sys.argv[2]})}, ensure_ascii=False))
" "$oid" "$msg_text")
        local resp
        resp=$(curl -s --connect-timeout 5 --max-time 15 -X POST \
            "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=open_id" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$body" 2>/dev/null)
        local code msg_id
        code=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code',-1))" 2>/dev/null)
        msg_id=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('message_id',''))" 2>/dev/null)
        if [ "$code" = "0" ]; then
            good "  ✅ 已发送（message_id: ${msg_id:-?}）"
            info "  在飞书查收"
        else
            warn "  发送失败 (code=$code):"
            echo "$resp" | python3 -m json.tool 2>/dev/null | sed 's/^/    /' || echo "$resp"
            if [ "$code" = "99991672" ]; then
                echo ""
                warn "  → 应用未开通 im:message:send / send_as_bot 权限"
                info "  → 走飞书子菜单 7) 申请权限 一键跳转开通（要发布版本才生效）"
            fi
        fi
    } >&2
}

# ── 入口 ──
case "${1:-menu}" in
    menu|"")   show_menu ;;
    setup|finalize|first|init)  do_finalize ;;
    status)    shift; bash "$LIB_DIR/status.sh" "$@" ;;
    self)      shift; do_self "${1:-all}" ;;
    upgrade)   shift; bash "$LIB_DIR/update.sh" "$@" ;;
    update)    shift; bash "$LIB_DIR/update.sh" "$@" ;;        # alias（旧名保留）
    sync)      shift; bash "$LIB_DIR/sync.sh" "$@" ;;
    monitor)   shift; bash "$LIB_DIR/monitor.sh" "${1:-}" ;;
    deps)      bash "$LIB_DIR/deps-check.sh" ;;
    fix)       do_finalize ;;
    example)   shift; bash "$LIB_DIR/example-sync.sh" "$@" ;;
    upgrade-ccprivate|upgrade-ccpriv|ccpriv-upgrade)
        shift; bash "$LIB_DIR/ccprivate-upgrade.sh" "$@" ;;
    token|usage)
        shift; bash "$CCCONFIG_DIR/option-usage/token-usage.sh" "$@" ;;
    token-run)
        bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill --include-today ;;
    mcp)     shift; bash "$LIB_DIR/mcp-manager.sh" "$@" ;;
    llmswitch|llm-switch|gate)
        shift; bash "$CCCONFIG_DIR/option-llmswitch/init.sh" "$@" ;;
    test|bootstrap|regression)
        shift; bash "$CCCONFIG_DIR/bin/test-bootstrap.sh" "$@" ;;
    *)  echo "用法: bash maintain.sh [status|self|upgrade|sync|monitor|deps|fix|example|setup|upgrade-ccprivate|token|mcp|llmswitch|test|menu]"; exit 1 ;;
esac
