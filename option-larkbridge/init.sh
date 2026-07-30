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

# ========== 交互选择 app 创建 profile ==========
# 返回 profile 名称，或空串表示取消
_interactive_select_app() {
    local ws="${1:-$HOME/git}"

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

    # 收集已有 profile
    local -a existing_profiles=()
    if [ -f "$HOME/.lark-channel/config.json" ]; then
        while IFS= read -r p; do
            [ -n "$p" ] && existing_profiles+=("$p")
        done < <(python3 -c "import json; d=json.load(open(os.path.expanduser('~/.lark-channel/config.json'))); [print(p) for p in d.get('profiles',{}).keys()]" 2>/dev/null || true)
    fi

    echo -e "${CYAN}── 选择飞书应用 ──${NC}"
    echo ""

    local idx=1

    # 已有 profile（可直接启动）
    if [ ${#existing_profiles[@]} -gt 0 ]; then
        echo -e "  ${GRAY}已有 profile:${NC}"
        for p in "${existing_profiles[@]}"; do
            local active_mark=""
            local active=$(python3 -c "import json; d=json.load(open(os.path.expanduser('~/.lark-channel/config.json'))); print(d.get('activeProfile',''))" 2>/dev/null || echo "")
            [ "$p" = "$active" ] && active_mark=" ${CYAN}← 当前${NC}"
            echo -e "  ${idx}) ${p}${active_mark}"
            idx=$((idx + 1))
        done
        echo ""
    fi

    # feishu.json 中可用的 app
    if [ ${#app_names[@]} -gt 0 ]; then
        echo -e "  ${GRAY}ccprivate 中已有配置:${NC}"
        local i=0
        while [ $i -lt ${#app_names[@]} ]; do
            local name="${app_names[$i]}"
            local id="${app_ids[$i]}"
            local id_short="${id:0:12}..."
            # 检查是否已有同名 profile
            local exist_mark=""
            local p2
            for p2 in "${existing_profiles[@]}"; do
                [ "$p2" = "$name" ] && exist_mark=" ${GRAY}(已创建)${NC}" && break
            done
            echo -e "  ${idx}) ${name} (${id_short})${exist_mark}"
            idx=$((idx + 1))
            i=$((i + 1))
        done
        echo ""
    fi

    echo -e "  ${idx}) ${YELLOW}扫码新建 PersonalAgent 应用${NC}"
    local scan_idx=$idx
    idx=$((idx + 1))
    echo -e "  0) 返回"
    echo ""

    read -p "  选择 [0-${scan_idx}]: " sel
    [ -z "$sel" ] && return 1
    [ "$sel" = "0" ] && return 1

    # 检查是否选了已有 profile
    if [ ${#existing_profiles[@]} -gt 0 ] && [ "$sel" -le ${#existing_profiles[@]} ]; then
        local selected_profile="${existing_profiles[$((sel - 1))]}"
        echo "$selected_profile"
        return 0
    fi
    local offset=${#existing_profiles[@]}

    # 选了 feishu.json 中的 app
    local feishu_idx=$((sel - 1 - offset))
    if [ "$sel" -ge $((offset + 1)) ] && [ "$sel" -lt "$scan_idx" ] && [ $feishu_idx -ge 0 ] && [ $feishu_idx -lt ${#app_names[@]} ]; then
        local name="${app_names[$feishu_idx]}"
        local id="${app_ids[$feishu_idx]}"
        local secret="${app_secrets[$feishu_idx]}"
        info "  创建 profile: $name (${id:0:12}...)"
        lark-channel-bridge profile create "$name" \
            --agent claude \
            --workspace "$ws" \
            --app-id "$id" \
            --app-secret "$secret" 2>&1
        echo "$name"
        return 0
    fi

    # 选了扫码新建
    if [ "$sel" = "$scan_idx" ]; then
        echo -e "${YELLOW}  扫码创建后建议手动保存凭据:${NC}"
        echo -e "  ${GRAY}    1. 复制 App ID 和 App Secret${NC}"
        echo -e "  ${GRAY}    2. 写入 ccprivate/conf/feishu.json 的对应 app${NC}"
        echo -e "  ${GRAY}    3. 设置 larkbridge.enabled: true${NC}"
        echo ""
        read -p "  按回车开始扫码..." dummy
        echo ""
        # lark-channel-bridge run 内部会创建 profile
        # profile 名由 bridge 自动分配，完成后读取
        lark-channel-bridge run --workspace "$ws" &
        local pid=$!
        wait $pid 2>/dev/null || true
        # 读取刚创建的 profile 名
        local new_profile
        new_profile=$(python3 -c "import json,os; d=json.load(open(os.path.expanduser('~/.lark-channel/config.json'))); print(d.get('activeProfile',''))" 2>/dev/null || echo "")
        if [ -n "$new_profile" ]; then
            echo "$new_profile"
            return 0
        fi
    fi

    return 1
}

# ========== 首次配置（交互选择 + 前台运行） ==========
run_foreground() {
    if ! command -v lark-channel-bridge &>/dev/null; then
        bad "  lark-channel-bridge 未安装，先运行 $0"
        return 1
    fi

    local ws="${LARK_WORKSPACE:-$HOME/git}"
    local profile_name
    profile_name=$(_interactive_select_app "$ws")
    [ -z "$profile_name" ] && return 0

    echo ""
    good "  ✓ 启动 $profile_name"
    lark-channel-bridge run --profile "$profile_name" --workspace "$ws"
}

# ========== 创建 profile（仅创建不启动，供 --start 调用） ==========
run_foreground_create_only() {
    local ws="${1:-$HOME/git}"
    _interactive_select_app "$ws" > /dev/null
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
        # 无 profile 时先创建（从 feishu.json 或扫码）
        if [ ! -f "$HOME/.lark-channel/config.json" ] || ! lark-channel-bridge profile list &>/dev/null; then
            echo ""
            run_foreground_create_only
        fi
        echo ""
        setup_service
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
        echo "    (无参数)     安装 + 提示下一步"
        echo "    --run        前台运行（首次扫码绑定）"
        echo "    --start      后台服务（systemd）"
        echo ""
        echo "  管理:"
        echo "    --stop       停止服务"
        echo "    --restart    重启服务"
        echo "    --status     查看状态"
        echo "    --logs       查看日志（tail -f）"
        echo "    --config     修改配置指南"
        echo ""
        echo "  示例:"
        echo "    bash ccconfig/option-larkbridge/init.sh --run     # 首次安装+扫码"
        echo "    bash ccconfig/option-larkbridge/init.sh --start   # 转为后台服务"
        echo "    bash ccconfig/option-larkbridge/init.sh --status  # 查看状态"
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
