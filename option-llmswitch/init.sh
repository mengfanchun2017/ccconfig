#!/bin/bash
# ==============================================
# option-llmswitch — LLM 网关自动切换
#
# 使用：
#   bash option-llmswitch/init.sh               # 交互式菜单
#   bash option-llmswitch/init.sh --install      # 安装/初始化
#   bash option-llmswitch/init.sh --start        # 启动代理
#   bash option-llmswitch/init.sh --stop         # 停止代理
#   bash option-llmswitch/init.sh --status       # 状态检查
#   bash option-llmswitch/init.sh --mode auto    # 切换模式
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
source "$REPO_DIR/lib/path-helper.sh"

CONF_FILE="$SCRIPT_DIR/conf/llmswitch.json"
CONF_EXAMPLE="$SCRIPT_DIR/conf/llmswitch.json.example"
LLM_CONF="$REPO_DIR/conf/llm.json"
PID_FILE="$HOME/.cache/llmswitch.pid"
LOG_FILE="$HOME/.cache/llmswitch.log"
ORIG_URL_FILE="$HOME/.cache/llmswitch-orig-baseurl"
ORIG_MODEL_FILE="$HOME/.cache/llmswitch-orig-model"
MONITOR_LOG="$REPO_DIR/.monitor-sync.log"
PROXY_PORT="${LLMSWITCH_PORT:-8899}"
PROXY_URL="http://127.0.0.1:$PROXY_PORT"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

good() { echo -e "${GREEN}$1${NC}"; }
bad()  { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
info() { echo -e "${GRAY}$1${NC}"; }
hdr()  { echo -e "${BOLD}${CYAN}$1${NC}"; }

# ========== 代理是否存活 ==========
is_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

# ========== 通知 monitor ==========
notify_monitor() {
    echo "[$(date '+%H:%M:%S')] llmswitch $1" >> "$MONITOR_LOG"
}

# ========== 获取健康信息 ==========
get_health() {
    curl -s --max-time 3 "$PROXY_URL/health" 2>/dev/null || echo '{}'
}

# ========== 读/写 CC 配置 ==========
read_cc_env() {
    python3 - "$ORIG_URL_FILE" "$PROXY_URL" "$LLM_CONF" << 'PYEOF'
import json, os, sys

orig_file, proxy_url, llm_conf = sys.argv[1], sys.argv[2], sys.argv[3]

settings_file = os.path.expanduser("~/.claude/settings.json")
try:
    with open(settings_file) as f:
        config = json.load(f)
except Exception:
    config = {}
env = config.get("env", {})

current_base = env.get("ANTHROPIC_BASE_URL", "")
current_model = env.get("ANTHROPIC_MODEL", "")
print(f"BASE_URL={current_base}")
print(f"MODEL={current_model}")
PYEOF
}

write_cc_env() {
    python3 - "$PROXY_URL" "$CONF_FILE" "$LLM_CONF" << 'PYEOF'
import json, os, sys

proxy_url, proxy_conf_path, llm_conf_path = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(proxy_conf_path) as f:
        pconf = json.load(f)
except Exception:
    pconf = {}
main_model = pconf.get("model_name", "llmswitch")

env_update = {
    "ANTHROPIC_BASE_URL": proxy_url,
    "ANTHROPIC_MODEL": main_model,
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
}

settings_file = os.path.expanduser("~/.claude/settings.json")
try:
    with open(settings_file) as f:
        config = json.load(f)
except Exception:
    config = {}
existing_env = config.get("env", {})
# 如果用户已配置 token 则保留，否则不设默认值（避免 "Bearer llmswitch" 被发到上游）
if existing_env.get("ANTHROPIC_AUTH_TOKEN"):
    env_update["ANTHROPIC_AUTH_TOKEN"] = existing_env["ANTHROPIC_AUTH_TOKEN"]

config.setdefault("env", {}).update(env_update)
with open(settings_file, "w") as f:
    json.dump(config, f, indent=4)

claude_json = os.path.expanduser("~/.claude.json")
try:
    with open(claude_json) as f:
        cconfig = json.load(f)
except Exception:
    cconfig = {}
cconfig.setdefault("env", {}).update(env_update)
with open(claude_json, "w") as f:
    json.dump(cconfig, f, indent=4)

# sync llm.json current → gateway
try:
    with open(llm_conf_path) as f:
        llmconf = json.load(f)
    llmconf["current"] = "gateway"
    with open(llm_conf_path, "w") as f:
        json.dump(llmconf, f, indent=4, ensure_ascii=False)
except Exception:
    pass

print("OK")
PYEOF
}

restore_cc_env() {
    local original_url="$1"
    local original_model="${2:-}"
    python3 - "$original_url" "$original_model" "$LLM_CONF" << 'PYEOF'
import json, os, sys

orig_url, orig_model, llm_conf_path = sys.argv[1], sys.argv[2], sys.argv[3]

env_update = {"ANTHROPIC_BASE_URL": orig_url}
if orig_model:
    env_update["ANTHROPIC_MODEL"] = orig_model

for fpath in [os.path.expanduser("~/.claude/settings.json"),
              os.path.expanduser("~/.claude.json")]:
    try:
        with open(fpath) as f:
            config = json.load(f)
    except Exception:
        config = {}
    config.setdefault("env", {}).update(env_update)
    with open(fpath, "w") as f:
        json.dump(config, f, indent=4)

# sync llm.json current — guess provider from restored URL
try:
    with open(llm_conf_path) as f:
        llmconf = json.load(f)
    for name, llm in llmconf.get("llms", {}).items():
        if llm.get("base_url") == orig_url and name != "gateway":
            llmconf["current"] = name
            break
    with open(llm_conf_path, "w") as f:
        json.dump(llmconf, f, indent=4, ensure_ascii=False)
except Exception:
    pass

print("OK")
PYEOF
}

# ========== 安装 ==========
do_install() {
    hdr "=== option-llmswitch 安装 ==="

    mkdir -p "$(dirname "$PID_FILE")"

    if [ ! -f "$CONF_FILE" ]; then
        if [ -f "$CONF_EXAMPLE" ]; then
            cp "$CONF_EXAMPLE" "$CONF_FILE"
            good "配置已创建: $CONF_FILE"
            warn "请编辑 $CONF_FILE 填入你的配置"
        else
            bad "配置模板不存在: $CONF_EXAMPLE"
            return 1
        fi
    else
        info "配置已存在: $CONF_FILE"
    fi

    pip3 install -q fastapi uvicorn --break-system-packages 2>/dev/null
    good "Python 依赖已安装 (fastapi, uvicorn)"
    echo ""
    info "LLM 网关默认未启动。需要时执行:"
    info "  bash $SCRIPT_DIR/init.sh --start"
    info "或通过 init-llm.sh 的 G 选项启动。"
}

# ========== 启动 ==========
do_start() {
    if is_running; then
        warn "代理已在运行 (PID: $(cat "$PID_FILE"))"
        return 0
    fi

    ensure_config "$CONF_FILE" "option-llmswitch/conf/llmswitch.json" || return 1

    local conf_port=$(python3 -c "import json; print(json.load(open('$CONF_FILE'))['listen']['port'])" 2>/dev/null)
    PROXY_PORT="${conf_port:-8899}"
    PROXY_URL="http://127.0.0.1:$PROXY_PORT"

    if ss -tlnp 2>/dev/null | grep -q ":$PROXY_PORT "; then
        bad "端口 $PROXY_PORT 已被占用"
        return 1
    fi

    # 保存原始 ANTHROPIC_BASE_URL + MODEL
    local cc_env=$(read_cc_env)
    local current_url=$(echo "$cc_env" | grep '^BASE_URL=' | cut -d= -f2-)
    local current_model=$(echo "$cc_env" | grep '^MODEL=' | cut -d= -f2-)
    if [ -n "$current_url" ] && [ "$current_url" != "$PROXY_URL" ]; then
        echo "$current_url" > "$ORIG_URL_FILE"
        echo "$current_model" > "$ORIG_MODEL_FILE"
        info "已保存原始配置: base_url=$current_url model=$current_model"

        # Save previous provider for init-llm.sh restore
        local prev=$(python3 -c "import json; print(json.load(open('$LLM_CONF')).get('current',''))" 2>/dev/null || echo "")
        if [ -n "$prev" ] && [ "$prev" != "gateway" ]; then
            echo "$prev" > "$HOME/.cache/llmswitch-prev-provider"
        fi
    elif [ "$current_url" = "$PROXY_URL" ] && [ -f "$ORIG_URL_FILE" ]; then
        info "当前已指向代理，沿用已保存的原始配置"
    fi

    # 后台启动
    nohup python3 "$SCRIPT_DIR/proxy.py" --host 127.0.0.1 --port "$PROXY_PORT" \
        >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
        bad "代理启动失败，查看日志: $LOG_FILE"
        rm -f "$PID_FILE"
        return 1
    fi

    good "代理已启动 (PID: $pid, 端口: $PROXY_PORT)"

    # 更新 CC 配置指向代理
    write_cc_env
    good "CC 配置已更新 → ANTHROPIC_BASE_URL=$PROXY_URL"

    # 显示当前路由
    local h=$(get_health)
    local mode=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('mode','?'))" 2>/dev/null)
    local route=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_route','?'))" 2>/dev/null)
    local peak=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak',False))" 2>/dev/null)
    if [ "$peak" = "True" ]; then
        warn "  当前路由: $route (高峰时段)"
    else
        info "  当前路由: $route (非高峰)"
    fi

    notify_monitor "started → $route ($([ "$peak" = "True" ] && echo peak || echo off-peak))"
}

# ========== 停止 ==========
do_stop() {
    if ! is_running; then
        info "代理未运行"
        # 代理已崩溃，但 CC 可能还指向代理 URL，尝试恢复
        if [ -f "$ORIG_URL_FILE" ]; then
            local orig_url=$(cat "$ORIG_URL_FILE")
            local orig_model=""
            [ -f "$ORIG_MODEL_FILE" ] && orig_model=$(cat "$ORIG_MODEL_FILE")
            if [ -n "$orig_url" ]; then
                restore_cc_env "$orig_url" "$orig_model"
                good "CC 配置已恢复: base_url=$orig_url model=$orig_model"
            fi
            rm -f "$ORIG_URL_FILE" "$ORIG_MODEL_FILE"
        fi
        rm -f "$PID_FILE"
        return 0
    fi

    local pid=$(cat "$PID_FILE")
    kill "$pid" 2>/dev/null || true
    sleep 1

    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$PID_FILE"
    good "代理已停止"

    # 恢复原始 ANTHROPIC_BASE_URL + MODEL
    if [ -f "$ORIG_URL_FILE" ]; then
        local orig_url=$(cat "$ORIG_URL_FILE")
        local orig_model=""
        [ -f "$ORIG_MODEL_FILE" ] && orig_model=$(cat "$ORIG_MODEL_FILE")
        if [ -n "$orig_url" ]; then
            restore_cc_env "$orig_url" "$orig_model"
            good "CC 配置已恢复: base_url=$orig_url model=$orig_model"
        fi
        rm -f "$ORIG_URL_FILE" "$ORIG_MODEL_FILE"
    fi

    notify_monitor "stopped"
}

# ========== 状态 ==========
do_status() {
    if ! is_running; then
        echo "FAIL llmswitch proxy not running"
        bad "代理未运行"
        return 1
    fi

    local h=$(get_health)
    local mode=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('mode','?'))" 2>/dev/null)
    local route=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_route','?'))" 2>/dev/null)
    local peak=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak',False))" 2>/dev/null)
    local pid=$(cat "$PID_FILE" 2>/dev/null)

    # --status 规范：第一行输出给 status.sh check_option_components
    if [ "$mode" = "auto" ] && [ "$peak" = "True" ]; then
        echo "OK llmswitch running (peak, $route) [PID $pid]"
        warn "  代理运行中 | 模式: $mode | 路由: $route (高峰)"
    elif [ "$mode" = "auto" ]; then
        echo "OK llmswitch running (off-peak, $route) [PID $pid]"
        good "  代理运行中 | 模式: $mode | 路由: $route (非高峰)"
    elif [ "$mode" = "manual" ]; then
        echo "OK llmswitch running (manual: $route) [PID $pid]"
        good "  代理运行中 | 模式: $mode | 路由: $route"
    else
        echo "OK llmswitch running ($mode) [PID $pid]"
        info "  代理运行中 | 模式: $mode"
    fi
    info "  端口: $PROXY_PORT | 日志: $LOG_FILE"

    return 0
}

# ========== 切换模式 ==========
do_mode() {
    local mode="$1"
    local provider="$2"

    if [ "$mode" != "auto" ] && [ "$mode" != "manual" ] && [ "$mode" != "off" ]; then
        bad "无效模式: $mode (可选: auto, manual, off)"
        return 1
    fi

    if [ "$mode" = "manual" ] && [ -z "$provider" ]; then
        provider="minimax"
    fi

    if ! is_running; then
        # 直接写配置文件
        python3 - "$CONF_FILE" "$mode" "${provider:-}" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
config["mode"] = sys.argv[2]
if sys.argv[3]:
    config["manual_provider"] = sys.argv[3]
with open(sys.argv[1], "w") as f:
    json.dump(config, f, indent=2)
print("OK")
PYEOF
        good "模式已设为 $mode (代理未运行，下次启动生效)"
        notify_monitor "mode → $mode (offline)${provider:+ ($provider)}"
        return 0
    fi

    # 代理运行中，通过 API 热切换
    local data="{\"mode\":\"$mode\""
    if [ -n "$provider" ]; then
        data="$data, \"provider\":\"$provider\""
    fi
    data="$data}"

    local resp=$(curl -s --connect-timeout 5 --max-time 10 -X POST "$PROXY_URL/admin/mode" \
        -H "Content-Type: application/json" \
        -d "$data" 2>/dev/null)
    if echo "$resp" | grep -q '"ok"'; then
        good "热切换成功: $mode"
        notify_monitor "mode → $mode${provider:+ ($provider)}"
        do_status
    else
        bad "热切换失败: $resp"
        return 1
    fi
}

# ========== 日志 ==========
do_log() {
    if [ -f "$LOG_FILE" ]; then
        tail -50 "$LOG_FILE"
    else
        info "无日志文件"
    fi
}

# ========== 更新 ==========
do_update() {
    hdr "=== option-llmswitch 更新 ==="
    pip3 install -q --upgrade fastapi uvicorn --break-system-packages 2>/dev/null
    good "Python 依赖已更新"

    if is_running; then
        info "重启代理..."
        do_stop
        sleep 1
        do_start
    fi
}

# ========== 交互式菜单 ==========
do_menu() {
    echo ""
echo -e "${CYAN}LLM Gateway Manager${NC}"
    echo -e "${CYAN}══════════════════${NC}"
    echo ""

    if is_running; then
        do_status
    else
        bad "  代理未运行"
    fi

    echo ""
    echo -e "  ${BOLD}操作:${NC}"
    echo -e "  ${GREEN}1)${NC} 启动代理"
    echo -e "  ${RED}2)${NC} 停止代理"
    echo -e "  ${YELLOW}3)${NC} 重启代理"
    echo -e "  ${CYAN}4)${NC} 切换模式"
    echo ""
    echo -e "  ${GRAY}5)${NC} 查看日志"
    echo -e "  ${GRAY}6)${NC} 安装/重新安装"
    echo -e "  ${GRAY}0)${NC} 退出"
    echo ""

    read -rp "  选择 [0-6]: " choice

    case "$choice" in
        1) do_start ;;
        2) do_stop ;;
        3) do_stop; sleep 1; do_start ;;
        4)
            echo ""
            echo -e "  模式: ${GREEN}auto${NC} | ${YELLOW}manual${NC} | ${GRAY}off${NC}"
            read -rp "  输入模式: " m
            if [ "$m" = "manual" ]; then
                read -rp "  后端 (deepseek/minimax): " p
                do_mode "$m" "$p"
            else
                do_mode "$m"
            fi
            ;;
        5) do_log ;;
        6) do_install ;;
        0) return 0 ;;
        *) bad "无效选择" ;;
    esac
}

# ========== 主流程 ==========
main() {
    case "${1:-}" in
        --install|-i)    do_install ;;
        --start|-S)      do_start ;;
        --stop|-K)       do_stop ;;
        --restart|-R)    do_stop; sleep 1; do_start ;;
        --status|-s)     do_status; exit $? ;;
        --mode|-m)       do_mode "${2:-}" "${3:-}" ;;
        --log|-l)        do_log ;;
        --update|-u)     do_update ;;
        *)               do_menu ;;
    esac
}

main "$@"
