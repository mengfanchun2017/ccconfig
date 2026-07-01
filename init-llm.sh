#!/bin/bash
# ==============================================
# LLM 配置管理脚本
# 功能：
#   - 列出所有可用 LLM（MiniMax / DeepSeek / Gateway）
#   - 切换 LLM
#   - 查看当前 LLM
#   - Gateway 网关管理（启动/停止/模式/高峰时段）
#
# 使用：
#   bash ccconfig/init-llm.sh               # 交互式选择
#   bash ccconfig/init-llm.sh list          # 仅列出
#   bash ccconfig/init-llm.sh <name>        # 直接切换
#
# 缓存策略:
#   small_model 默认等于 model（同模型方案）
#   理由: 系统任务(haiku)调用零散、间隔常超 5min 缓存 TTL，
#   用不同模型导致缓存命中率极低（<50%），冷启动重复加载 ~31k 系统 token。
#   统一模型使系统任务共享主模型温热缓存（>90% 命中率），
#   虽然单价更高但因系统任务输出极短，省下的输入成本远超输出差价。
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/path-helper.sh"
CONFIG_FILE="$SCRIPT_DIR/conf/llm.json"
LLMSWITCH_CONF="$SCRIPT_DIR/option-llmswitch/conf/llmswitch.json"
LLMSWITCH_INIT="$SCRIPT_DIR/option-llmswitch/init.sh"
PID_FILE="$HOME/.cache/llmswitch.pid"
PREV_PROVIDER_FILE="$HOME/.cache/llmswitch-prev-provider"

ensure_config "$CONFIG_FILE" "conf/llm.json" || exit 1

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GRAY}$1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
hdr()   { echo -e "${BOLD}${CYAN}$1${NC}"; }

# ========== 代理检测 ==========
is_proxy_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

get_health() {
    local port=$(python3 -c "import json; print(json.load(open('$LLMSWITCH_CONF'))['listen']['port'])" 2>/dev/null || echo "8899")
    curl -s --max-time 3 "http://127.0.0.1:$port/health" 2>/dev/null || echo '{}'
}

# ========== 读取配置 ==========
list_llms() {
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    config = json.load(f)

llms = config.get('llms', {})
current = config.get('current', '')

names = list(llms.keys())
print(f"TOTAL:{len(names)}")
print(f"CURRENT:{current}")

for name in names:
    llm = llms[name]
    marker = "◀" if name == current else " "
    small = llm.get('small_model', '')
    base_url = llm.get('base_url', '')
    model = llm.get('model', '')
    display_name = llm.get('name', name)
    has_key = bool(llm.get('key', ''))
    print(f"{marker}|{name}|{display_name}|{model}|{base_url}|{small}|{has_key}")
PYEOF
}

get_llm_config() {
    local target="$1"
    python3 - "$CONFIG_FILE" "$target" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    config = json.load(f)

target = sys.argv[2]
llms = config.get('llms', {})

if target not in llms:
    print("ERROR:Unknown LLM")
    sys.exit(1)

llm = llms[target]
small = llm.get('small_model', llm.get('model', ''))
key = llm.get('key', '')
print(f"{llm.get('base_url', '')}|{llm.get('model', '')}|{key}|{small}")
PYEOF
}

# ========== 高峰时段读取 ==========
read_peak_hours() {
    python3 - "$LLMSWITCH_CONF" << 'PYEOF'
import json, sys

try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
except:
    print("")
    sys.exit(0)

peak_hours = config.get('peak_hours', [])
routes = config.get('routes', {})
main_route = routes.get('llmswitch', {})
if isinstance(main_route, dict):
    peak_provider = main_route.get('peak', 'minimax')
    off_peak_provider = main_route.get('off_peak', 'deepseek')
else:
    peak_provider = 'minimax'
    off_peak_provider = 'deepseek'

# Format: "weekday_desc|start-end|start-end" per block
# Then "PEAK_PROVIDER:xxx" and "OFF_PEAK_PROVIDER:xxx"
day_names = ['日','一','二','三','四','五','六']
for block in peak_hours:
    days = block.get('days', [])
    day_str = '工作日' if days == [0,1,2,3,4] else '周末' if days == [5,6] else ','.join(str(d) for d in days)
    print(f"BLOCK|{day_str}|{block.get('start','')}|{block.get('end','')}")
print(f"PEAK_PROVIDER:{peak_provider}")
print(f"OFF_PEAK_PROVIDER:{off_peak_provider}")
PYEOF
}

# ========== 密钥检查 & 初始化 ==========
check_and_init_keys() {
    local need_keys=()
    local llms_json=$(python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
llms = config.get('llms', {})
for name, llm in llms.items():
    if name == 'gateway':
        continue
    key = llm.get('key', '')
    if not key or key.startswith('请填入'):
        print(f"MISSING:{name}:{llm.get('name', name)}")
PYEOF
)

    if [ -z "$llms_json" ]; then
        return 0
    fi

    echo ""
    warn "检测到缺少 API Key："
    local missing_names=()
    while IFS=: read -r _ type name display; do
        if [ "$type" = "MISSING" ]; then
            echo "  - $display ($name)"
            missing_names+=("$name:$display")
        fi
    done <<< "$llms_json"

    echo ""
    info "请输入对应的 API Key（跳过按回车，之后可在 $CONFIG_FILE 中修改）"
    echo ""

    for entry in "${missing_names[@]}"; do
        local name="${entry%%:*}"
        local display="${entry##*:}"
        read -rp "  ${display} API Key: " key_input

        if [ -n "$key_input" ]; then
            python3 - "$CONFIG_FILE" "$name" "$key_input" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
config['llms'][sys.argv[2]]['key'] = sys.argv[3]
with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
PYEOF
            success "${display} Key 已保存"
        else
            warn "跳过 ${display}（之后可手动编辑 $CONFIG_FILE）"
        fi
    done
}

# ========== 切换 LLM（直连） ==========
switch_llm_direct() {
    local name="$1"

    CONFIG=$(get_llm_config "$name") || { error "无法获取 LLM 配置: $name"; return 1; }
    IFS='|' read -r BASE_URL MODEL_NAME API_KEY SMALL_MODEL <<< "$CONFIG"

    info "切换到: $name"
    info "  API: $BASE_URL"
    info "  模型: $MODEL_NAME"
    info "  小模型: $SMALL_MODEL"

    export BASE_URL MODEL_NAME API_KEY SMALL_MODEL

    python3 << 'PYEOF'
import json, os

env_update = {
    "ANTHROPIC_BASE_URL": os.environ.get('BASE_URL', ''),
    "ANTHROPIC_AUTH_TOKEN": os.environ.get('API_KEY', ''),
    "ANTHROPIC_MODEL": os.environ.get('MODEL_NAME', ''),
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ.get('SMALL_MODEL', os.environ.get('MODEL_NAME', ''))
}

claude_json = os.path.expanduser("~/.claude.json")
try:
    with open(claude_json, 'r') as f:
        config = json.load(f)
except:
    config = {}
config.setdefault('env', {}).update(env_update)
with open(claude_json, 'w') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
print("~/.claude.json 已更新")

settings_file = os.path.expanduser("~/.claude/settings.json")
if os.path.islink(settings_file) and not os.path.exists(settings_file):
    os.unlink(settings_file)
try:
    with open(settings_file, 'r') as f:
        sconfig = json.load(f)
except:
    sconfig = {}
sconfig.setdefault('env', {}).update(env_update)
with open(settings_file, 'w') as f:
    json.dump(sconfig, f, indent=4, ensure_ascii=False)
print("~/.claude/settings.json 已更新")
PYEOF

    # 更新 conf/llm.json 的 current
    python3 - "$CONFIG_FILE" "$name" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
config['current'] = sys.argv[2]
with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
PYEOF

    success "LLM 已切换为: $name (直连)"
}

# ========== 切换到 Gateway ==========
switch_to_gateway() {
    # 检查 gateway 所需的两个 provider 是否有 key
    local missing=""
    local ds_key=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['llms']['deepseek'].get('key',''))" 2>/dev/null || echo "")
    local mm_key=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['llms']['minimax'].get('key',''))" 2>/dev/null || echo "")

    if [ -z "$ds_key" ] || [ "$ds_key" = "请填入你的 DeepSeek API Key" ]; then
        missing="$missing DeepSeek"
    fi
    if [ -z "$mm_key" ] || [ "$mm_key" = "请填入你的 MiniMax API Key" ]; then
        missing="$missing MiniMax"
    fi

    if [ -n "$missing" ]; then
        echo ""
        warn "Gateway 需要 MiniMax + DeepSeek 两个 Key 才能自动切换"
        warn "缺少:$missing"
        echo ""
        info "Gateway 工作原理："
        info "  高峰时段（工作日 9:00-12:00, 14:00-18:00）→ MiniMax"
        info "  非高峰时段 → DeepSeek"
        info "  小模型始终 → MiniMax"
        echo ""

        for provider in deepseek minimax; do
            local pkey=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['llms']['$provider'].get('key',''))" 2>/dev/null || echo "")
            if [ -z "$pkey" ] || [ "$pkey" = "请填入你的"* ]; then
                local pname=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['llms']['$provider'].get('name','$provider'))" 2>/dev/null)
                read -rp "  请输入 ${pname} API Key: " key_input
                if [ -n "$key_input" ]; then
                    python3 - "$CONFIG_FILE" "$provider" "$key_input" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
config['llms'][sys.argv[2]]['key'] = sys.argv[3]
with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
PYEOF
                    success "${pname} Key 已保存"
                else
                    warn "跳过 ${pname}，Gateway 无法启动"
                    return 1
                fi
            fi
        done
    fi

    # 保存当前直连模式（用于恢复）
    local prev=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('current',''))" 2>/dev/null)
    if [ "$prev" != "gateway" ]; then
        echo "$prev" > "$PREV_PROVIDER_FILE"
    fi

    # 安装 & 启动代理
    if ! is_proxy_running; then
        info "启动 LLM 网关代理..."
        bash "$LLMSWITCH_INIT" --start
    else
        info "网关代理已在运行"
    fi

    # 更新 current
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
config['current'] = 'gateway'
with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
PYEOF

    show_gateway_status
}

# ========== Gateway 状态显示 ==========
show_gateway_status() {
    echo ""
    if is_proxy_running; then
        local h=$(get_health)
        local mode=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('mode','?'))" 2>/dev/null)
        local route=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_route','?'))" 2>/dev/null)
        local peak=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak',False))" 2>/dev/null)
        local pid=$(cat "$PID_FILE" 2>/dev/null)

        if [ "$peak" = "True" ]; then
            warn "  网关运行中 | 模式: $mode | 路由: $route (高峰) | PID: $pid"
        else
            success "  网关运行中 | 模式: $mode | 路由: $route (非高峰) | PID: $pid"
        fi

        # 读取并显示高峰时段
        local peak_info=$(read_peak_hours)
        local peak_provider=$(echo "$peak_info" | grep "^PEAK_PROVIDER:" | cut -d: -f2)
        local off_peak_provider=$(echo "$peak_info" | grep "^OFF_PEAK_PROVIDER:" | cut -d: -f2)
        while IFS='|' read -r type days start end; do
            if [ "$type" = "BLOCK" ]; then
                info "  高峰: $days $start-$end → $peak_provider / 非高峰 → $off_peak_provider"
            fi
        done <<< "$peak_info"
    else
        error "  网关未运行"
        if [ -f "$PREV_PROVIDER_FILE" ]; then
            info "  上一个直连模式: $(cat "$PREV_PROVIDER_FILE")"
        fi
    fi
    echo ""
}

# ========== Gateway 管理子菜单 ==========
gateway_submenu() {
    while true; do
        show_gateway_status

        if is_proxy_running; then
            echo "  [S] 停止网关    [M] 切换模式    [P] 修改高峰时段"
            echo "  [L] 查看日志    [Enter] 返回"
        else
            echo "  [S] 启动网关    [P] 修改高峰时段"
            echo "  [Enter] 返回"
        fi
        echo ""
        read -rp "  选择: " choice

        case "$choice" in
            S|s)
                if is_proxy_running; then
                    bash "$LLMSWITCH_INIT" --stop
                    # 恢复上一个直连模式
                    local prev="${PREV_PROVIDER_FILE:+$(cat "$PREV_PROVIDER_FILE" 2>/dev/null)}"
                    if [ -n "$prev" ] && [ "$prev" != "gateway" ]; then
                        info "恢复直连模式: $prev"
                        switch_llm_direct "$prev"
                        rm -f "$PREV_PROVIDER_FILE"
                    else
                        switch_llm_direct "deepseek"
                    fi
                    return 0
                else
                    switch_to_gateway
                fi
                ;;
            M|m)
                if is_proxy_running; then
                    echo ""
                    echo "  模式: auto (按时段自动) | manual (固定后端) | off (直通)"
                    read -rp "  输入模式: " m
                    if [ "$m" = "manual" ]; then
                        read -rp "  后端 (deepseek/minimax): " p
                        bash "$LLMSWITCH_INIT" --mode "$m" "$p"
                    elif [ -n "$m" ]; then
                        bash "$LLMSWITCH_INIT" --mode "$m"
                    fi
                else
                    warn "请先启动网关"
                fi
                ;;
            P|p)
                edit_peak_hours
                ;;
            L|l)
                if is_proxy_running; then
                    local log="$HOME/.cache/llmswitch.log"
                    if [ -f "$log" ]; then
                        tail -30 "$log"
                    else
                        info "无日志文件"
                    fi
                else
                    warn "网关未运行"
                fi
                ;;
            "")
                return 0
                ;;
            *)
                warn "无效选择"
                ;;
        esac
    done
}

# ========== 修改高峰时段 ==========
edit_peak_hours() {
    echo ""
    hdr "=== 修改高峰时段 ==="
    echo ""
    info "当前高峰时段（Gateway 在此时段自动切换到 MiniMax）："
    echo ""

    local peak_info=$(read_peak_hours)
    local peak_provider=$(echo "$peak_info" | grep "^PEAK_PROVIDER:" | cut -d: -f2)
    local off_peak_provider=$(echo "$peak_info" | grep "^OFF_PEAK_PROVIDER:" | cut -d: -f2)

    local idx=1
    while IFS='|' read -r type days start end; do
        if [ "$type" = "BLOCK" ]; then
            echo "  $idx) $days $start - $end"
            ((idx++))
        fi
    done <<< "$peak_info"
    echo ""
    info "  高峰 → $peak_provider"
    info "  非高峰 → $off_peak_provider"

    echo ""
    echo "  操作: [A] 添加时段  [D] 删除时段  [Enter] 返回"
    echo ""
    read -rp "  选择: " choice

    case "$choice" in
        A|a)
            echo ""
            read -rp "  工作日 (1-5=工作日, 0-6=周日-周六, 如: 1-5): " days_input
            read -rp "  开始时间 (HH:MM): " start_input
            read -rp "  结束时间 (HH:MM): " end_input

            local days_json="[0,1,2,3,4]"
            if [ "$days_input" = "1-5" ] || [ "$days_input" = "" ]; then
                days_json="[0,1,2,3,4]"
            elif [ "$days_input" = "0-6" ]; then
                days_json="[0,1,2,3,4,5,6]"
            elif [ "$days_input" = "6-7" ] || [ "$days_input" = "0,6" ]; then
                days_json="[5,6]"
            fi

            if [ -n "$start_input" ] && [ -n "$end_input" ]; then
                python3 - "$LLMSWITCH_CONF" "$days_json" "$start_input" "$end_input" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
config.setdefault('peak_hours', []).append({
    "days": json.loads(sys.argv[2]),
    "start": sys.argv[3],
    "end": sys.argv[4]
})
with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
print("OK")
PYEOF
                success "高峰时段已添加"
            fi
            ;;
        D|d)
            read -rp "  删除第几个时段？" del_idx
            if [ -n "$del_idx" ] && [ "$del_idx" -ge 1 ] 2>/dev/null; then
                python3 - "$LLMSWITCH_CONF" "$del_idx" << 'PYEOF'
import json, sys
idx = int(sys.argv[2]) - 1
with open(sys.argv[1]) as f:
    config = json.load(f)
blocks = config.get('peak_hours', [])
if 0 <= idx < len(blocks):
    removed = blocks.pop(idx)
    print(f"已删除: {removed.get('start')}-{removed.get('end')}")
else:
    print("无效索引")
with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF
            fi
            ;;
        *)
            ;;
    esac

    # 重启代理使新时段生效
    if is_proxy_running; then
        info "重启网关使新时段生效..."
        bash "$LLMSWITCH_INIT" --restart
        success "网关已重启"
    fi
}

# ========== 显示列表 ==========
show_list() {
    echo ""
    echo "可用 LLM："
    echo ""
    # Format: marker|name|display_name|model|base_url|small|has_key
    list_llms | while IFS='|' read -r marker name display_name model base_url small has_key; do
        if [[ "$marker" == "TOTAL:"* ]] || [[ "$marker" == "CURRENT:"* ]]; then
            continue
        fi
        if [[ -z "$name" ]]; then
            continue
        fi
        local small_info=""
        if [[ -n "$small" ]]; then
            small_info="  (小模型: $small)"
        fi
        local mode_info=""
        if [[ "$name" == "gateway" ]]; then
            mode_info=" — 高峰自动切换"
        fi
        printf "  %s %-10s %-20s%s%s\n" "$marker" "$display_name" "$model" "$small_info" "$mode_info"
    done
    echo ""

    local current=$(grep "^CURRENT:" <(list_llms) | cut -d: -f2)
    if [[ -n "$current" ]]; then
        if [ "$current" = "gateway" ]; then
            if is_proxy_running; then
                local h=$(get_health)
                local route=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_route','?'))" 2>/dev/null)
                local peak=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak',False))" 2>/dev/null)
                local peak_str=""
                [ "$peak" = "True" ] && peak_str=" (高峰)"
                info "当前: Gateway → $route$peak_str"
            else
                info "当前: Gateway (代理未运行)"
            fi
        else
            info "当前: $current (直连)"
        fi
    fi
}

# ========== 交互式选择 ==========
interactive_select() {
    echo ""
    echo "请选择 LLM："
    echo ""

    local lines=$(list_llms)
    local total=$(echo "$lines" | grep "^TOTAL:" | cut -d: -f2)
    local current=$(echo "$lines" | grep "^CURRENT:" | cut -d: -f2)

    # Format: marker|name|display_name|model|base_url|small|has_key
    local idx=1
    local names=()
    while IFS='|' read -r marker name display_name model base_url small has_key; do
        if [[ "$marker" == "TOTAL:"* ]] || [[ "$marker" == "CURRENT:"* ]]; then
            continue
        fi
        if [[ -z "$name" ]]; then
            continue
        fi
        names+=("$name")
        local small_str=""
        if [[ -n "$small" ]]; then
            small_str=" [小模型: $small]"
        fi

        # 当前标记和状态
        local cur_str=""
        if [[ "$marker" == "◀" ]]; then
            if [[ "$name" == "gateway" ]]; then
                if is_proxy_running; then
                    local h=$(get_health)
                    local route=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_route','?'))" 2>/dev/null)
                    local peak=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak',False))" 2>/dev/null)
                    local peak_str=""
                    [ "$peak" = "True" ] && peak_str=" (高峰)"
                    cur_str=" ◀ 当前 → $route$peak_str"
                else
                    cur_str=" ◀ 当前 (未运行)"
                fi
            else
                cur_str=" ◀ 当前 (直连)"
            fi
        fi

        if [[ "$name" == "gateway" ]]; then
            printf "  %d) %s (%s) — 高峰 %s / 非高峰 %s%s\n" "$idx" "$display_name" "网关代理" "MiniMax" "DeepSeek" "$cur_str"
        else
            printf "  %d) %s (%s)%s%s\n" "$idx" "$display_name" "$model" "$small_str" "$cur_str"
        fi
        ((idx++))
    done < <(echo "$lines")

    echo ""

    # 显示当前模式摘要
    if [ "$current" = "gateway" ]; then
        if is_proxy_running; then
            local h=$(get_health)
            local mode=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('mode','?'))" 2>/dev/null)
            local route=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_route','?'))" 2>/dev/null)
            local peak=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak',False))" 2>/dev/null)
            local peak_str=""
            [ "$peak" = "True" ] && peak_str=" (高峰)"
            info "当前模式: Gateway (option-llmswitch) → $route$peak_str | 模式: $mode"

            # 高峰时段
            local peak_info=$(read_peak_hours)
            local peak_provider=$(echo "$peak_info" | grep "^PEAK_PROVIDER:" | cut -d: -f2)
            while IFS='|' read -r type days start end; do
                if [ "$type" = "BLOCK" ]; then
                    info "高峰时段: $days $start-$end → $peak_provider"
                fi
            done <<< "$peak_info"

            echo ""
            echo "  网关管理: [S]停止 [M]切换模式 [P]修改高峰时段 [L]日志"
        else
            warn "Gateway 代理未运行"
            echo ""
            echo "  输入数字选择直连模式，或选 Gateway 启动代理"
        fi
    else
        info "当前模式: 直连 → $current"
    fi

    echo ""
    printf "请输入数字 [1-%d]" "$total"
    if [ "$current" = "gateway" ] && is_proxy_running; then
        printf " 或 S/M/P/L"
    fi
    printf ": "
    read -r choice

    if [[ -z "$choice" ]]; then
        info "保持当前: $current"
        return 0
    fi

    # 网关管理快捷键
    if [ "$current" = "gateway" ] && is_proxy_running; then
        case "$choice" in
            S|s) bash "$LLMSWITCH_INIT" --stop
                 local prev="${PREV_PROVIDER_FILE:+$(cat "$PREV_PROVIDER_FILE" 2>/dev/null)}"
                 [ -n "$prev" ] && [ "$prev" != "gateway" ] && switch_llm_direct "$prev" && rm -f "$PREV_PROVIDER_FILE"
                 return 0 ;;
            M|m) echo ""; read -rp "  模式 (auto/manual/off): " m
                 if [ "$m" = "manual" ]; then
                     read -rp "  后端 (deepseek/minimax): " p
                     bash "$LLMSWITCH_INIT" --mode "$m" "$p"
                 elif [ -n "$m" ]; then
                     bash "$LLMSWITCH_INIT" --mode "$m"
                 fi
                 return 0 ;;
            P|p) edit_peak_hours; return 0 ;;
            L|l) local log="$HOME/.cache/llmswitch.log"
                 [ -f "$log" ] && tail -30 "$log" || info "无日志"
                 return 0 ;;
        esac
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$total" ]]; then
        local target="${names[$((choice-1))]}"

        if [ "$target" = "gateway" ]; then
            if is_proxy_running; then
                gateway_submenu
            else
                switch_to_gateway
            fi
        else
            # 切换到直连前，停止网关（如果在运行）
            if is_proxy_running; then
                info "停止网关代理..."
                bash "$LLMSWITCH_INIT" --stop
            fi
            switch_llm_direct "$target"
        fi
    else
        error "无效选择: $choice"
        return 1
    fi
}

# ========== 主流程 ==========
main() {
    local cmd="${1:-}"

    # 首次初始化密钥检查
    check_and_init_keys

    # 检测 LLM 网关代理（提示模式）
    if is_proxy_running; then
        local current=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('current',''))" 2>/dev/null || echo "")
        if [ "$current" != "gateway" ]; then
            # 代理在运行但 current 不是 gateway → 修复不一致状态
            python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
config['current'] = 'gateway'
with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
PYEOF
        fi
    fi

    if [[ "$cmd" == "list" ]]; then
        show_list
    elif [[ -z "$cmd" ]]; then
        interactive_select
    elif [[ "$cmd" == "gateway" ]]; then
        if is_proxy_running; then
            info "Gateway 已在运行"
            show_gateway_status
        else
            switch_to_gateway
        fi
    else
        # 直接指定 LLM 名称
        if is_proxy_running; then
            info "停止网关代理..."
            bash "$LLMSWITCH_INIT" --stop
        fi
        switch_llm_direct "$cmd"
    fi
}

main "$@"
