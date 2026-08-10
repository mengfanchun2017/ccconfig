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
#   bash maintain.sh fix monitor         # 修 monitor：装 inotify-tools + 重启
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

# ── Monitor 修复（inotify-tools 死了就重新装 + 重启 monitor） ──
fix_monitor() {
    echo -e "${CYAN}━━━ Monitor 修复（inotify-tools + 重启）━━━${NC}"
    echo ""

    # 1. inotify-tools 装/补
    source "$LIB_DIR/install-inotify.sh"
    if ! install_inotify; then
        err "inotify-tools 装不上 — 手动: sudo apt install inotify-tools"
        return 1
    fi

    # 2. 停旧 monitor（PIDFile + 僵尸 inotifywait 一起清）
    if bash "$LIB_DIR/monitor.sh" stop 2>/dev/null; then
        info "旧 monitor 已停止"
    fi
    pkill -f "inotifywait.*$HOME/git" 2>/dev/null || true

    # 3. 重启
    if bash "$LIB_DIR/monitor.sh" start; then
        echo ""
        ok "Monitor 已修复并重启"
        bash "$LIB_DIR/monitor.sh" status
    else
        err "Monitor 启动失败"
        return 1
    fi
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
    local c; c=$(menu_select "ccconfig 运维中心" \
        "1) 状态检查" "2) Monitor" "3) 自我更新" \
        "4) Git 同步" "5) 组件升级" "6) 依赖检查" \
        "7) 一键修复" "8) 模板同步" "9) ccprivate 升级" \
        "10) Bill\\&Token" "11) MCP" "12) llmswitch" \
        "13) 飞书管理" "14) 回归测试" "15) GitHub PAT" \
        "16) LLM 切换" "17) getnote" "0) 退出")
    [[ -z "$c" ]] && { show_menu; return; }
    c="${c:0:1}"
    [[ ! "$c" =~ ^[0-9]+$ ]] && { show_menu; return; }

    case "$c" in
        1) bash "$LIB_DIR/status.sh" "$@" ;;
        2) submenu_monitor ;;
        3) do_self all ;;
        4) bash "$LIB_DIR/sync.sh" ;;
        5) bash "$LIB_DIR/update.sh" menu ;;
        6) bash "$LIB_DIR/deps-check.sh" ;;
        7) do_finalize ;;
        8) bash "$LIB_DIR/example-sync.sh" status
           local ex_sel; ex_sel=$(menu_select "模板同步" "d) 查看差异" "f) 正向" "r) 反向" "0) 返回")
           case "${ex_sel:0:1}" in d) bash "$LIB_DIR/example-sync.sh" diff;; f) bash "$LIB_DIR/example-sync.sh" promote;; r) bash "$LIB_DIR/example-sync.sh" reverse;; esac ;;
        9) bash "$LIB_DIR/ccprivate-upgrade.sh" ;;
        10) submenu_bill_token ;;
        11) bash "$LIB_DIR/mcp-manager.sh" config ;;
        12) submenu_llmswitch ;;
        13) submenu_feishu ;;
        14) bash "$CCCONFIG_DIR/bin/test-bootstrap.sh" "$@" ;;
        15) bash "$CCCONFIG_DIR/bin/refresh-gh-auth.sh" ;;
        16) bash "$LIB_DIR/init-llm.sh" ;;
        17) submenu_getnote ;;
        0) echo ""; exit 0 ;;
    esac
    echo ""; read -p "按回车返回菜单..." dummy
    show_menu
}

submenu_bill_token() {
    local c; c=$(menu_select "Bill\\&Token" \
        "1) Bill(模型单价)" "2) 用量统计" "3) 按日报告" \
        "4) 按天归档" "5) 推飞书" "6) timer 管理" \
        "7) 手动触发" "0) 返回")
    [[ -z "$c" ]] && { submenu_bill_token; return; }
    c="${c:0:1}"
    case "$c" in
        1) bash "$LIB_DIR/init-llm.sh" bill ;;
        2) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --stats ;;
        3) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --report ;;
        4) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ;;
        5) url=$(prompt "飞书 URL"); bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ${url:+--feishu \"$url\"} ;;
        6) bash "$CCCONFIG_DIR/option-usage/init.sh" status
           local ts; ts=$(menu_select "timer" "i) 安装" "u) 卸载" "c) 配置" "b) 返回")
           case "${ts:0:1}" in i) bash "$CCCONFIG_DIR/option-usage/init.sh" install;; u) bash "$CCCONFIG_DIR/option-usage/init.sh" uninstall;; c) bash "$CCCONFIG_DIR/option-usage/init.sh" config;; esac ;;
        7) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;;
    esac
    echo ""; read -p "按回车返回..." dummy
    submenu_bill_token
}

submenu_monitor() {
    local c; c=$(menu_select "Monitor" \
        "1) 启动" "2) 停止" "3) 看状态" "4) 追踪" "5) 文件变更" "6) 修复" "0) 返回")
    [[ -z "$c" ]] && return
    c="${c:0:1}"
    case "$c" in
        1) bash "$LIB_DIR/monitor.sh" start ;;
        2) bash "$LIB_DIR/monitor.sh" stop ;;
        3) bash "$LIB_DIR/monitor.sh" status ;;
        4) bash "$LIB_DIR/monitor.sh" tail ;;
        5) bash "$LIB_DIR/monitor.sh" monitor ;;
        6) fix_monitor ;;
    esac
}

submenu_llmswitch() {
    local c; c=$(menu_select "llmswitch" \
        "1) 启动" "2) 停止" "3) 重启" "4) 状态" "5) 切换 LLM" "0) 返回")
    [[ -z "$c" ]] && return
    c="${c:0:1}"
    case "$c" in
        1) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --start ;;
        2) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --stop ;;
        3) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --restart ;;
        4) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --status ;;
        5) bash "$LIB_DIR/init-llm.sh" ;;
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
        echo "  8) 飞书测试         ─ E2E 集成测试（安装/授权/文档/Base/权限/API 兼容）"
        echo ""
        echo "  0) 返回主菜单"
        echo ""
        c=$(menu_select "飞书管理" \
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
            8) bash "$LIB_DIR/test-feishu.sh"
               read -p "  按回车返回飞书菜单..." dummy ;;
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
        local sub; sub=$(menu_select "lark-cli" \
            "a) 重置配置" "k) OAuth 状态" "l) 列出账号" "0) 返回")
        [[ -z "$sub" ]] && return 0
        case "${sub:0:1}" in
            a) bash "$feishu_lc" ;;
            k) bash "$feishu_switch" ;;
            l) bash "$feishu_switch" --list ;;
            0) return 0 ;;
        esac
    done
}

submenu_feishu_larkbridge() {
    local feishu_lb="$CCCONFIG_DIR/option-larkbridge/init.sh"

    while true; do
        echo ""
        bash "$feishu_lb" --status 2>&1 | grep -v '^$'
        echo ""
        echo "  ─ 启动 ─"
        echo "    1) 前台启动（调试用，Ctrl+C 退出）"
        echo "    2) 后台启动（nohup）"
        echo "    3) 停止 profile"
        echo "    4) 重启 profile"
        echo ""
        echo "  ─ 日志 ─"
        echo "    5) 看最新日志（tail -f，Ctrl+C 退出）"
        echo "    6) 看日志目录（选文件看）"
        echo ""
        echo "  ─ 配置 ─"
        echo "    n) 新增 profile       ─ add（ccprivate 配置 or 扫码）"
        echo "    r) 删除 profile       ─ remove"
        echo "    d) 设为默认           ─ default"
        echo ""
        local sub; sub=$(menu_select "larkbridge" \
            "1) 前台启动" "2) 后台启动" "3) 停止" "4) 重启" \
            "5) 看日志" "6) 日志目录" \
            "n) 新增 profile" "r) 删除" "d) 设为默认" "0) 返回")
        [[ -z "$sub" ]] && continue
        case "${sub:0:1}" in
            1) bash "$feishu_lb" --run ;;
            2) bash "$feishu_lb" --bg ;;
            3) bash "$feishu_lb" --stop ;;
            4) bash "$feishu_lb" --restart ;;
            5) bash "$feishu_lb" --logs ;;
            6) info "日志目录: $HOME/.lark-channel/profiles/"; ls -lt "$HOME/.lark-channel/profiles/"*/logs/*.jsonl 2>/dev/null || warn "暂无" ;;
            n|N) bash "$feishu_lb" --profile add ;;
            r|R) bash "$feishu_lb" --profile remove ;;
            d|D) bash "$feishu_lb" --profile default ;;
            0) return 0 ;;
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
    # 发消息前先确认 larkbridge 在运行
    local lb_running=false
    if command -v lark-channel-bridge &>/dev/null; then
        if systemctl --user is-active lark-channel-bridge.service &>/dev/null 2>&1 || pgrep -f "lark-channel-bridge" &>/dev/null; then
            lb_running=true
        fi
    fi
    $lb_running || warn "  larkbridge 未运行，消息可能收不到（先启动再试）"

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
    local oid rc
    oid="$(_feishu_resolve_recipient "$target")"; rc=$?
    [ "$rc" -ne 0 ] && { warn "取消（未设置收件人）"; return 0; }
    [ -n "$oid" ] || { warn "取消（未设置收件人）"; return 0; }

    local msg_text="ccconfig 飞书测试消息 ✅ from $target"
    echo ""
    info "  → 目标 app: $target"
    info "  → 收件人: $oid"
    info "  → 内容: $msg_text"
    echo ""
    read -p "  发送? [Y/n]: " cf
    [[ "$cf" =~ ^[Nn]$ ]] && { info "取消"; return 0; }

    info "  拿 tenant_access_token..." >&2
    local token
    token=$(curl -s --connect-timeout 5 --max-time 10 -X POST \
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
        -H "Content-Type: application/json" \
        -d "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
    [ -z "$token" ] && { warn "  拿 access_token 失败（appId/appSecret 不对？）"; return 0; }

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
        good "  ✅ 已发送（message_id: ${msg_id:-?}）"
        info "  在飞书查收"
    else
        warn "  发送失败:"
        local err_msg; err_msg=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('msg',''))" 2>/dev/null || echo "")
        [ -n "$err_msg" ] && echo "    $err_msg"
        info "  常见原因: app 未开通 im:message 权限，或收件人 open_id 不对"
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
            local name appid desc lc_on lb_on
            IFS=$'\t' read -r name appid desc lc_on lb_on < <(echo "$line" | python3 -c "
import json, sys
a = json.load(sys.stdin)
i = a.get('appId','')
lb = a.get('larkbridge') or a.get('larkBridge') or {}
print('\t'.join([
    a.get('name','?'),
    (i[:14] + '…') if len(i) > 14 else i,
    a.get('description',''),
    'Y' if a.get('larkCli',{}).get('enabled') else 'N',
    'Y' if lb.get('enabled') else 'N',
]))" 2>/dev/null)
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

# ── getnote MCP 账号管理子菜单 ──
submenu_getnote() {
    local sw="$CCCONFIG_DIR/option-getnote/getnote-switch.sh"
    local init="$CCCONFIG_DIR/option-getnote/init.sh"

    while true; do
        echo ""; section "getnote 账号"
        bash "$sw" --list 2>/dev/null || echo -e "  ${YELLOW}无 getnote 账号${NC}"
        echo ""
        local c; c=$(menu_select "配置调整" \
            "1) 添加" "2) 删除" "3) 切换(session)" "4) 切换(持久化)" "0) 返回")
        [[ -z "$c" ]] && continue
        case "${c:0:1}" in
            1) bash "$init" add ;;
            2) bash "$init" remove ;;
            3) target=$(prompt "账号名"); [ -n "$target" ] && bash "$sw" "$target" ;;
            4) target=$(prompt "账号名"); [ -n "$target" ] && bash "$sw" "$target" -p ;;
            0) return 0 ;;
        esac
        echo ""; read -p "按回车返回..." dummy
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

    local oid rc
    oid="$(_feishu_resolve_recipient "$target")"; rc=$?
    [ "$rc" -ne 0 ] && { warn "取消（未设置收件人）"; return 0; }
    [ -n "$oid" ] || { warn "取消（未设置收件人）"; return 0; }

    local msg_text="ccconfig 飞书测试消息 ✅ from $target"
    echo ""
    info "  → 目标 app: $target"
    info "  → 收件人: $oid"
    info "  → 内容: $msg_text"
    read -p "  发送? [Y/n]: " cf
    [[ "$cf" =~ ^[Nn]$ ]] && { info "取消"; return 0; }

    info "  拿 tenant_access_token..." >&2
    local token
    token=$(curl -s --connect-timeout 5 --max-time 10 -X POST \
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
        -H "Content-Type: application/json" \
        -d "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
    [ -z "$token" ] && { warn "  拿 access_token 失败（appId/appSecret 不对？）"; return 0; }

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
        good "  ✅ 已发送（message_id: ${msg_id:-?}）"
        info "  在飞书查收"
    else
        warn "  发送失败:"
        local err_msg; err_msg=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('msg',''))" 2>/dev/null || echo "")
        [ -n "$err_msg" ] && echo "    $err_msg"
        if [ "$code" = "99991672" ]; then
            echo ""
            warn "  → 应用未开通 im:message:send / send_as_bot 权限"
            info "  → 走飞书子菜单 7) 申请权限 一键跳转开通（要发布版本才生效）"
        fi
    fi
}

# ── 入口 ──
case "${1:-menu}" in
    menu|"")   show_menu ;;
    setup|finalize|first|init)  do_finalize ;;
    status)    shift; bash "$LIB_DIR/status.sh" "$@" ;;
    self)      shift; do_self "${1:-all}" ;;
    upgrade)   shift; bash "$LIB_DIR/update.sh" "$@" ;;
    sync)      shift; bash "$LIB_DIR/sync.sh" "$@" ;;
    monitor)   shift; bash "$LIB_DIR/monitor.sh" "${1:-}" ;;
    deps)      bash "$LIB_DIR/deps-check.sh" ;;
    fix)
        shift
        case "${1:-all}" in
            monitor) fix_monitor ;;
            all|"")  do_finalize ;;
            *)       err "未知 fix 子命令: $1（可用: monitor）"; exit 1 ;;
        esac
        ;;
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
    llm|llm-init|switch-llm)
        shift; bash "$LIB_DIR/init-llm.sh" "$@" ;;
    pat|pat-refresh|gh-auth)
        bash "$CCCONFIG_DIR/bin/refresh-gh-auth.sh" ;;
    test|bootstrap|regression)
        shift; bash "$CCCONFIG_DIR/bin/test-bootstrap.sh" "$@" ;;
    feishu)
        shift
        case "${1:-test}" in
            test) bash "$LIB_DIR/test-feishu.sh" "$@" ;;
            *) echo "用法: bash maintain.sh feishu [test]" ;;
        esac ;;
    *)  echo "用法: bash maintain.sh [status|self|upgrade|sync|monitor|deps|fix|example|setup|upgrade-ccprivate|token|pat|mcp|llmswitch|llm|test|menu]"; exit 1 ;;
esac
