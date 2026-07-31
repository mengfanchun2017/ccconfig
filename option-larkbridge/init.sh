#!/bin/bash
# ccconfig/option-larkbridge/init.sh — 飞书 lark-channel-bridge 安装/配置/管理
#
# lark-channel-bridge: 飞书 ↔ Claude Code 双向通信 Bridge
# 安装: npm i -g lark-channel-bridge，首次启动扫码绑 PersonalAgent 应用
# 配置源: ccprivate/conf/feishu.json（同一配置源）
#
# 用法:
#   bash ccconfig/option-larkbridge/init.sh               # 安装 + 首次启动
#   bash ccconfig/option-larkbridge/init.sh --start       # 后台服务（systemd）
#   bash ccconfig/option-larkbridge/init.sh --stop        # 停止服务
#   bash ccconfig/option-larkbridge/init.sh --restart      # 重启服务
#   bash ccconfig/option-larkbridge/init.sh --status       # 状态
#   bash ccconfig/option-larkbridge/init.sh --run          # 前台运行（首次配置）
#   bash ccconfig/option-larkbridge/init.sh --logs         # 查看日志

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_DIR/lib/path-helper.sh" 2>/dev/null || true
source "$CCCONFIG_DIR/lib/colors.sh" 2>/dev/null || true

NODE_BIN="$(find_node_bin 2>/dev/null || echo "")"
export PATH="$HOME/.local/bin:${NODE_BIN}:$PATH"
SERVICE_NAME="lark-channel-bridge"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

# fallback colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

good() { echo -e "${GREEN}$1${NC}"; }
bad()  { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
info() { echo -e "${GRAY}$1${NC}"; }

# ========== 安装 ==========
install() {
    echo -e "${CYAN}── 安装 lark-channel-bridge ──${NC}"

    if command -v lark-channel-bridge &>/dev/null; then
        local ver
        ver=$(lark-channel-bridge --version 2>/dev/null | head -1 || echo "?")
        good "  ✓ 已安装: $ver"
        return 0
    fi

    echo -n "  安装中 ... "
    if npm install -g lark-channel-bridge 2>&1 | tail -1; then
        # symlink
        local npm_bin
        npm_bin="$(npm prefix -g 2>/dev/null)/bin"
        mkdir -p "$HOME/.local/bin"
        if [ -x "$npm_bin/lark-channel-bridge" ]; then
            ln -sf "$npm_bin/lark-channel-bridge" "$HOME/.local/bin/lark-channel-bridge"
        fi
        good "✅"
    else
        bad "❌ 安装失败"
        return 1
    fi
}

# ========== 读取 feishu.json 中启用了 larkbridge 的 app 列表 ==========
# 输出: name|appId|appSecret 每行一个
_list_larkbridge_apps() {
    local conf="$1"
    python3 - "$conf" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for a in d.get('apps', []):
    lb = a.get('larkbridge', {})
    if lb.get('enabled', False):
        print(f"{a.get('name','?')}|{a.get('appId','')}|{a.get('appSecret','')}")
PYEOF
}

# ========== 读取 feishu.json 并初始化 larkbridge 配置 ==========
# 交互选择已有 app 或扫码新建，结果写入 _PROFILE_RESULT
_interactive_select_app() {
    local ws="${1:-$HOME/git}"
    local result_file="$HOME/.lark-channel/.select_result"

    local feishu_conf=""
    if [ -f "$HOME/git/ccprivate/conf/feishu.json" ]; then
        feishu_conf="$HOME/git/ccprivate/conf/feishu.json"
    elif command -v resolve_conf &>/dev/null; then
        feishu_conf=$(resolve_conf feishu.json 2>/dev/null) || true
    fi

    local -a app_names app_ids app_secrets
    if [ -n "$feishu_conf" ]; then
        while IFS='|' read -r name id secret; do
            [ -z "$name" ] && continue
            app_names+=("$name")
            app_ids+=("$id")
            app_secrets+=("$secret")
        done < <(_list_larkbridge_apps "$feishu_conf")
    fi

    local -a existing_profiles=()
    if [ -f "$HOME/.lark-channel/config.json" ]; then
        while IFS= read -r p; do
            [ -n "$p" ] && existing_profiles+=("$p")
        done < <(python3 -c "import json,os; d=json.load(open(os.path.expanduser('~/.lark-channel/config.json'))); [print(p) for p in d.get('profiles',{}).keys()]" 2>/dev/null || true)
    fi

    echo -e "${CYAN}── 选择飞书应用 ──${NC}" >&2

    # 检测进程占用
    local busy_profiles=""
    if command -v lark-channel-bridge &>/dev/null; then
        busy_profiles=$(lark-channel-bridge ps 2>/dev/null | grep -oP '(?<=Bot\s{3}).*?(?=\s{2,})' || true)
    fi

    local idx=1
    local -a menu_items=() # 存每项对应的指令：profile名 / s(s扫码) / r(重启)

    # ─── 生效 profile ───
    if [ ${#existing_profiles[@]} -gt 0 ]; then
        echo -e "  ${GRAY}--生效 profile--${NC}" >&2
        for p in "${existing_profiles[@]}"; do
            local active=$(python3 -c "import json,os; d=json.load(open(os.path.expanduser('~/.lark-channel/config.json'))); print(d.get('activeProfile',''))" 2>/dev/null || echo "")
            local am=""
            local busy_mark=""
            [ "$p" = "$active" ] && am=" ${CYAN}← 当前${NC}"
            echo "$busy_profiles" | grep -q "$p" && busy_mark=" ${GREEN}● 运行中${NC}"
            echo -e "  ${idx}) ${p}${am}${busy_mark}" >&2
            menu_items+=("profile:$p")
            idx=$((idx + 1))
        done
        echo "" >&2
    fi

    # ─── ccprivate 配置 ───
    if [ ${#app_names[@]} -gt 0 ]; then
        echo -e "  ${GRAY}--ccprivate 配置--${NC}" >&2
        local i=0
        while [ $i -lt ${#app_names[@]} ]; do
            local name="${app_names[$i]}"
            local id_short="${app_ids[$i]:0:12}..."
            local em=""
            for p2 in "${existing_profiles[@]}"; do [ "$p2" = "$name" ] && em=" ${GRAY}(profile 已存在)${NC}" && break; done
            echo -e "  ${idx}) ${name} (${id_short})${em}" >&2
            menu_items+=("create:$name")
            idx=$((idx + 1))
            i=$((i + 1))
        done
        echo "" >&2
    fi

    # ─── 扫码新建 ───
    echo -e "  ${GRAY}--扫码新建配置--${NC}" >&2
    echo -e "  s) ${YELLOW}扫码新建 PersonalAgent${NC}" >&2
    echo "" >&2

    # ─── 服务重启 ───
    if [ -f "$SERVICE_FILE" ]; then
        echo -e "  ${GRAY}--服务--${NC}" >&2
        local svc_status="${GRAY}未运行${NC}"
        systemctl --user is-active "${SERVICE_NAME}" &>/dev/null && svc_status="${GREEN}运行中${NC}"
        echo -e "  r) 重启系统服务 (${svc_status})" >&2
        echo "" >&2
    fi

    echo -e "  0) 返回" >&2
    echo "" >&2

    read -p "  选择 [0-${idx} / s / r]: " sel
    [ -z "$sel" ] && return 1
    [ "$sel" = "0" ] && echo -n "" > "$result_file" && return 1

    # 服务重启
    if [ "$sel" = "r" ] && [ -f "$SERVICE_FILE" ]; then
        systemctl --user restart "${SERVICE_NAME}" 2>&1 && good "  ✅ 已重启" >&2 || bad "  ❌ 重启失败" >&2
        return 1
    fi

    # 扫码新建
    if [ "$sel" = "s" ]; then
        echo -e "${YELLOW}  扫码后会保存到 ~/.lark-channel${NC}" >&2
        echo -e "  ${GRAY}  如需持久化，创建后复制 appId/secret 到 ccprivate${NC}" >&2
        read -p "  按回车开始扫码..." dummy
        lark-channel-bridge run --workspace "$ws" &
        local pid=$!
        wait $pid 2>/dev/null || true
        local np
        np=$(python3 -c "import json,os; d=json.load(open(os.path.expanduser('~/.lark-channel/config.json'))); print(d.get('activeProfile',''))" 2>/dev/null || echo "")
        echo "${np:-}" > "$result_file"
        return 0
    fi

    # 数字选择
    [ "$sel" -ge 1 ] 2>/dev/null || return 1
    local menu_idx=$((sel - 1))
    [ $menu_idx -lt 0 ] || [ $menu_idx -ge ${#menu_items[@]} ] && return 1
    local chosen="${menu_items[$menu_idx]}"

    case "$chosen" in
        profile:*)
            # 已有 profile
            local pname="${chosen#profile:}"
            echo "$pname" > "$result_file"
            return 0
            ;;
        create:*)
            # feishu.json app
            local cname="${chosen#create:}"
            local fi=0
            while [ $fi -lt ${#app_names[@]} ]; do
                [ "${app_names[$fi]}" = "$cname" ] && break
                fi=$((fi + 1))
            done
            local id="${app_ids[$fi]}"
            local secret="${app_secrets[$fi]}"
            # 检查同名 profile 是否已存在
            local exists=0
            for p2 in "${existing_profiles[@]}"; do [ "$p2" = "$cname" ] && exists=1 && break; done
            if [ "$exists" = "1" ]; then
                echo -e "${GRAY}  profile $cname 已存在，直接使用${NC}" >&2
            else
                echo -e "${GRAY}  创建 profile: $cname ...${NC}" >&2
                lark-channel-bridge profile create "$cname" \
                    --agent claude \
                    --workspace "$ws" \
                    --app-id "$id" \
                    --app-secret "$secret" 2>&1
            fi
            echo "$cname" > "$result_file"
            return 0
            ;;
    esac

    return 1
}

_get_profile_result() {
    local f="$HOME/.lark-channel/.select_result"
    if [ -f "$f" ]; then
        cat "$f"
        rm -f "$f"
    fi
}

# ========== 前台运行（交互选择 + 启动） ==========
run_foreground() {
    if ! command -v lark-channel-bridge &>/dev/null; then
        bad "  lark-channel-bridge 未安装" >&2
        return 1
    fi

    local ws="${LARK_WORKSPACE:-$HOME/git}"
    _interactive_select_app "$ws"
    local profile_name; profile_name=$(_get_profile_result)
    [ -z "$profile_name" ] && return 0

    echo "" >&2
    good "  ✓ 启动 $profile_name" >&2
    lark-channel-bridge run --profile "$profile_name" --workspace "$ws"
}

# ========== 创建 profile（不启动，供 --start 调用） ==========
run_foreground_create_only() {
    local ws="${1:-$HOME/git}"
    _interactive_select_app "$ws"
}

# ========== systemd 服务 ==========
setup_service() {
    echo -e "${CYAN}── systemd 服务 ──${NC}"

    if ! systemctl --user daemon-reload 2>/dev/null; then
        warn "  systemd --user 不可用，跳过服务"
        return 1
    fi
    loginctl enable-linger "$USER" 2>/dev/null || true

    mkdir -p "$HOME/.config/systemd/user"

    cat > "$SERVICE_FILE" << SERVICEOF
[Unit]
Description=Lark Channel Bridge — Feishu ↔ Claude Code
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${HOME}/.local/bin/lark-channel-bridge start
Restart=on-failure
RestartSec=15
Environment=PATH=${HOME}/.local/bin:${NODE_BIN}:/usr/local/bin:/usr/bin:/bin
Environment=LARK_CHANNEL_HOME=${HOME}/.lark-channel

[Install]
WantedBy=default.target
SERVICEOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable "${SERVICE_NAME}" 2>/dev/null || true

    if systemctl --user restart "${SERVICE_NAME}" 2>&1; then
        good "  ✅ 服务运行中"
        echo ""
        info "  管理命令:"
        info "    状态: systemctl --user status ${SERVICE_NAME}"
        info "    日志: journalctl --user -u ${SERVICE_NAME} -f"
        info "    重启: bash ccconfig/option-larkbridge/init.sh --restart"
        info "    停止: bash ccconfig/option-larkbridge/init.sh --stop"
    else
        warn "  ⚠ 服务启动失败（检查 journalctl 日志）"
        journalctl --user -u "${SERVICE_NAME}" --no-pager -n 20 2>/dev/null || true
    fi
}

# ========== 状态 ==========
show_status() {
    # --status 规范：第一行给 init-option.sh 解析
    # 机器可读行在前，人友好行在后
    if command -v lark-channel-bridge &>/dev/null; then
        local ver
        ver=$(lark-channel-bridge --version 2>/dev/null | head -1)
        if systemctl --user is-active "${SERVICE_NAME}" &>/dev/null 2>&1; then
            echo "OK lark-channel-bridge $ver (systemd 运行中)"
        elif pgrep -f "lark-channel-bridge" > /dev/null 2>&1; then
            echo "OK lark-channel-bridge $ver (进程运行中)"
        elif [ -f "$SERVICE_FILE" ]; then
            echo "WARN lark-channel-bridge $ver (已装未运行)"
        else
            echo "OK lark-channel-bridge $ver (已安装)"
        fi
    else
        echo "MISSING lark-channel-bridge 未安装"
    fi

    echo -n "  安装 ... "
    if command -v lark-channel-bridge &>/dev/null; then
        good "✅ $(lark-channel-bridge --version 2>/dev/null | head -1)"
    else
        echo -e "${YELLOW}○${NC} 未安装"
    fi

    echo -n "  服务 ... "
    if systemctl --user is-active "${SERVICE_NAME}" &>/dev/null 2>&1; then
        good "● 运行中 (systemd)"
    elif pgrep -f "lark-channel-bridge" > /dev/null 2>&1; then
        good "● 运行中 (进程)"
    elif [ -f "$SERVICE_FILE" ]; then
        warn "○ 已装未运行"
    else
        echo -e "${GRAY}－${NC} 未安装"
    fi

    if [ -f "$HOME/.lark-channel/config.json" ]; then
        local bot_name
        bot_name=$(python3 -c "
import json,sys
try:
    with open('$HOME/.lark-channel/config.json') as f:
        d = json.load(f)
    profiles = d.get('profiles', {})
    active = d.get('activeProfile', list(profiles.keys())[0] if profiles else '')
    p = profiles.get(active, {})
    print(f'profile: {active}')
    print(f'agent: {p.get(\"agentKind\", \"?\")}')
    acc = p.get('access', {})
    users = acc.get('allowedUsers', [])
    groups = acc.get('allowedChats', [])
    print(f'允许: {len(users)} 用户, {len(groups)} 群组')
except Exception as e:
    print(f'无法解析: {e}')
" 2>/dev/null || echo "?")
        echo ""
        echo -e "${CYAN}── 配置 ──${NC}"
        echo "$bot_name" | while IFS= read -r line; do
            [ -n "$line" ] && echo "  $line"
        done

        local work_dir
        work_dir=$(python3 -c "
import json,sys
try:
    with open('$HOME/.lark-channel/config.json') as f:
        d = json.load(f)
    profiles = d.get('profiles', {})
    active = d.get('activeProfile', list(profiles.keys())[0] if profiles else '')
    p = profiles.get(active, {})
    ws = p.get('workspaces', {}).get('default', '')
    print(ws or '（未设置，用 /cd 切换）')
except:
    print('?')
" 2>/dev/null)
        echo "  工作目录: $work_dir"
        echo ""
        info "  飞书命令:"
        info "    /help      — 帮助"
        info "    /status    — 状态"
        info "    /cd <dir>  — 切换工作目录"
        info "    /ws save/list/use/remove — 工作区管理"
        info "    /config    — 显示设置"
        info "    /new       — 重置 session"
    fi
}

# ========== 日志 ==========
show_logs() {
    if systemctl --user is-active "${SERVICE_NAME}" &>/dev/null 2>&1; then
        journalctl --user -u "${SERVICE_NAME}" -f
    else
        local log_dir="$HOME/.lark-channel/profiles/"
        if [ -d "$log_dir" ]; then
            local latest
            latest=$(find "$log_dir" -name '*.jsonl' -type f 2>/dev/null | sort -r | head -1)
            if [ -n "$latest" ]; then
                info "日志: $latest"
                tail -f "$latest" | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        d = json.loads(line)
        time = d.get('time','')[:19]
        event = d.get('event','')
        msg = d.get('message','')
        print(f'{time} [{event}] {msg}')
    except:
        print(line.rstrip())" 2>/dev/null || tail -f "$latest"
            else
                warn "暂无日志"
            fi
        else
            warn "日志目录不存在"
        fi
    fi
}

# ========== 重新配置 / 修改配置 ==========
reconfigure() {
    echo -e "${CYAN}── 重新配置 lark-channel-bridge ──${NC}"
    echo ""
    echo "  1. 编辑 ~/.lark-channel/config.json 直接修改"
    echo "  2. 或删除配置文件重新扫码绑定:"
    echo ""
    echo -e "  ${YELLOW}rm -rf ~/.lark-channel${NC}"
    echo -e "  ${YELLOW}$0 --run${NC}"
    echo ""
    echo "  常用配置项:"
    echo "    profiles.<name>.workspaces.default — 默认工作目录"
    echo "    profiles.<name>.permissions.defaultAccess — full|workspace|read-only"
    echo "    profiles.<name>.access.allowedUsers — 允许的用户 open_id 列表"
    echo "    profiles.<name>.access.allowedChats — 允许的群组 chat_id 列表"
    echo ""
    info "  修改后执行 systemctl --user restart ${SERVICE_NAME} 生效"
    info "  或在飞书内用 /config /invite 命令配置"
}

# ========== 主程序 ==========
case "${1:-}" in
    --start|-s)
        install
        if [ ! -f "$HOME/.lark-channel/config.json" ] || ! lark-channel-bridge profile list &>/dev/null; then
            echo ""; run_foreground_create_only
        fi
        echo ""
        setup_service
        ;;
    --start-webui)
        install
        if [ ! -f "$HOME/.lark-channel/config.json" ] || ! lark-channel-bridge profile list &>/dev/null; then
            echo ""; run_foreground_create_only
        fi
        echo -e "${CYAN}── systemd 服务 (web-ui 模式) ──${NC}"
        mkdir -p "$HOME/.config/systemd/user"
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Lark Channel Bridge — Web UI (all profiles)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${HOME}/.local/bin/lark-channel-bridge start --web-ui
Restart=on-failure
RestartSec=15
Environment=PATH=${HOME}/.local/bin:${NODE_BIN}:/usr/local/bin:/usr/bin:/bin
Environment=LARK_CHANNEL_HOME=${HOME}/.lark-channel

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload && systemctl --user enable --now "${SERVICE_NAME}" 2>&1 && good "  ✅ web-ui 服务 (多 profile)" || warn "  ⚠ 服务启动失败"
        ;;
    --switch)
        if [ ! -f "$HOME/.lark-channel/config.json" ]; then
            warn "尚未配置，先运行 $0 --run"; exit 1
        fi
        echo -e "${CYAN}── 切换 profile ──${NC}"
        # 收集 profile 名到临时文件
        python3 -c "import json,os; d=json.load(open(os.path.expanduser('~/.lark-channel/config.json'))); profs=list(d.get('profiles',{}).keys()); print(' '.join(profs))" 2>/dev/null > /tmp/.lb_plist.txt
        plist_str=$(cat /tmp/.lb_plist.txt 2>/dev/null); rm -f /tmp/.lb_plist.txt
        if [ -z "$plist_str" ]; then warn "没有 profile"; exit 1; fi
        active=$(python3 -c "import json,os; print(json.load(open(os.path.expanduser('~/.lark-channel/config.json'))).get('activeProfile',''))" 2>/dev/null)
        i=1
        for p in $plist_str; do
            am=""; [ "$p" = "$active" ] && am=" ← 当前"
            echo "  $i) $p$am"; i=$((i + 1))
        done
        count=$((i - 1))
        echo ""
        read -p "  选择 [1-$count]: " sel
        [ -z "$sel" ] && exit 0
        [ "$sel" -lt 1 ] || [ "$sel" -gt "$count" ] && { warn "无效选择"; exit 1; }
        # 取第 sel 个 profile
        target=$(echo "$plist_str" | cut -d' ' -f"$sel")
        lark-channel-bridge profile use "$target" 2>&1
        good "  ✓ 已切换，重启服务生效: systemctl --user restart ${SERVICE_NAME}"
        ;;
    --stop)
        if [ -f "$SERVICE_FILE" ]; then
            systemctl --user stop "${SERVICE_NAME}" 2>/dev/null && good "✅ 已停止" || warn "⚠ 停止失败"
        else
            pkill -f "lark-channel-bridge" 2>/dev/null && good "✅ 已停止" || warn "⚠ 未运行"
        fi
        ;;
    --restart)
        if [ -f "$SERVICE_FILE" ]; then
            systemctl --user restart "${SERVICE_NAME}" 2>/dev/null && good "✅ 已重启" || warn "⚠ 重启失败"
        else
            warn "服务未安装，请先运行 $0 --start"
        fi
        ;;
    --status)
        show_status
        ;;
    --run)
        install
        echo ""
        run_foreground
        ;;
    --logs|-l)
        show_logs
        ;;
    --config|-c)
        reconfigure
        ;;
    --help|-h)
        echo "用法: bash ccconfig/option-larkbridge/init.sh <command>"
        echo ""
        echo "  安装/运行:"
        echo "    --run              交互选择 app + 前台运行"
        echo "    --start            后台服务（当前 profile）"
        echo "    --start-webui      后台服务（web-ui，管理所有 profile）"
        echo ""
        echo "  管理:"
        echo "    --switch           切换活动 profile"
        echo "    --stop             停止服务"
        echo "    --restart          重启服务"
        echo "    --status           查看状态"
        echo "    --logs             查看日志"
        echo "    --config           修改配置指南"
        echo ""
        echo "  示例:"
        echo "    bash ccconfig/option-larkbridge/init.sh --run       # 交互选择 + 运行"
        echo "    bash ccconfig/option-larkbridge/init.sh --start     # 后台运行"
        echo "    bash ccconfig/option-larkbridge/init.sh --status    # 查看状态"
        ;;
    *)
        # 无参数或未知参数：安装 + 提示下一步
        install
        echo ""
        info "安装完成。下一步："
        info "  1. bash ccconfig/option-larkbridge/init.sh --run    # 飞书扫码绑定"
        info "  2. bash ccconfig/option-larkbridge/init.sh --start  # 转后台服务"
        info "  3. 飞书私聊 PersonalAgent 即可收发消息"
        ;;
esac
