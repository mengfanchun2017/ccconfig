#!/bin/bash
# ==============================================
# LLM 配置管理脚本
# 功能：
#   - 列出所有可用 LLM（MiniMax / DeepSeek / Gateway）
#   - 切换 LLM
#   - 查看当前 LLM
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
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/path-helper.sh"
source "$SCRIPT_DIR/colors.sh"
CONFIG_FILE="$CCCONFIG_ROOT/conftemp/llm.json"
LLMSWITCH_CONF="$CCCONFIG_ROOT/option-llmswitch/conf/llmswitch.json"
LLMSWITCH_INIT="$CCCONFIG_ROOT/option-llmswitch/init.sh"
LLMSWITCH_WATCHDOG="$CCCONFIG_ROOT/option-llmswitch/watchdog.sh"
CLAUDE_JSON="$HOME/.claude.json"

ensure_config "$CONFIG_FILE" "conftemp/llm.json" || exit 1

# ========== Gateway 辅助 ==========
is_proxy_running() {
    local pid_file="$HOME/.cache/llmswitch.pid"
    [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

get_proxy_health() {
    local port="${LLMSWITCH_PORT:-8899}"
    curl -s --max-time 3 "http://127.0.0.1:${port}/health" 2>/dev/null || echo '{}'
}

read_gateway_routes() {
    # 返回 "高峰→MiniMax / 非高峰→DeepSeek" 格式的路由摘要
    python3 - "$LLMSWITCH_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
except Exception:
    sys.exit(0)

routes = config.get('routes', {}).get('llmswitch', {})
peak = routes.get('peak', '?')
off_peak = routes.get('off_peak', '?')
peak_hours = config.get('peak_hours', [])
blocks = []
for b in peak_hours:
    blocks.append(f"{b['start']}-{b['end']}")
print(f"高峰 {','.join(blocks)} → {peak} ｜ 非高峰 → {off_peak}")
PYEOF
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
    # Format: marker|name|display_name|model|base_url|small
    # Parser uses IFS='|' so name (config key) is in field 2, display_name in field 3
    print(f"{marker}|{name}|{display_name}|{model}|{base_url}|{small}")
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
print(f"{llm.get('base_url', '')}|{llm.get('model', '')}|{llm.get('key', '')}|{small}")
PYEOF
}

# ========== 写配置（直连 + gateway 共用） ==========
# $1: name  $2: base_url  $3: model  $4: small_model  $5: api_key (optional)
_write_llm_config() {
    local name="$1" base_url="$2" model_name="$3" small_model="$4" api_key="${5:-}"

    info "  API: $base_url"
    info "  模型: $model_name"
    info "  小模型: $small_model"

    export CONFIG_FILE="$CONFIG_FILE" CLAUDE_JSON="$CLAUDE_JSON" BASE_URL="$base_url" MODEL_NAME="$model_name" SMALL_MODEL="$small_model" API_KEY="$api_key" NAME="$name"

    python3 << 'PYEOF'
import json, os

env_update = {
    "ANTHROPIC_BASE_URL": os.environ.get('BASE_URL', ''),
    "ANTHROPIC_MODEL": os.environ.get('MODEL_NAME', ''),
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ.get('SMALL_MODEL', os.environ.get('MODEL_NAME', ''))
}
api_key = os.environ.get('API_KEY', '')
if api_key:
    if any(kw in api_key for kw in ['请填入', '请替换', 'your key', 'your_key', 'placeholder', 'changeme']):
        print(f"\033[1;33m⚠️  API Key 疑似占位符，跳过写入 ANTHROPIC_AUTH_TOKEN: {api_key[:30]}...\033[0m")
        print("   请编辑 conf/llm.json 填入真实 Key 后重试")
    else:
        env_update["ANTHROPIC_AUTH_TOKEN"] = api_key

def write_json(path, updater):
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except:
        data = {}
    updater(data)
    with open(path, 'w') as f:
        json.dump(data, f, indent=4)

# conf/llm.json current（先写源，避免中断导致 settings.json 被写但源未更新）
write_json(os.environ['CONFIG_FILE'], lambda d: d.update({'current': os.environ['NAME']}))
print("conftemp/llm.json 已更新")

# ~/.claude.json
write_json(os.path.expanduser(os.environ.get('CLAUDE_JSON', '~/.claude.json')),
           lambda d: d.setdefault('env', {}).update(env_update))
print("~/.claude.json 已更新")

# ~/.claude/settings.json
sf = os.path.expanduser("~/.claude/settings.json")
if os.path.islink(sf) and not os.path.exists(sf):
    os.unlink(sf)
write_json(sf, lambda d: d.setdefault('env', {}).update(env_update))
print("~/.claude/settings.json 已更新")
PYEOF

    success "LLM 已切换为: $name"
}

# ========== 切换 LLM ==========
switch_llm() {
    local name="$1"

    if [[ "$name" == "gateway" ]]; then
        switch_to_gateway
        return $?
    fi

    # 切到直连前先停 watchdog + proxy
    if is_proxy_running; then
        info "停止网关代理..."
        local watchdog_pid_file="$HOME/.cache/llmswitch-watchdog.pid"
        if [ -f "$watchdog_pid_file" ]; then
            kill "$(cat "$watchdog_pid_file")" 2>/dev/null || true
            rm -f "$watchdog_pid_file"
        fi
        bash "$LLMSWITCH_INIT" --stop 2>/dev/null || true
    fi

    local config=$(get_llm_config "$name") || { error "无法获取 LLM 配置: $name"; return 1; }
    IFS='|' read -r base_url model_name api_key small_model <<< "$config"

    info "切换到: $name"
    _write_llm_config "$name" "$base_url" "$model_name" "$small_model" "$api_key"
}

switch_to_gateway() {
    info "切换到 Gateway 模式"

    if ! is_proxy_running; then
        info "启动 LLM 网关代理..."
        bash "$LLMSWITCH_INIT" --start || { error "代理启动失败"; return 1; }
    else
        info "网关代理已在运行"
    fi

    local watchdog_pid_file="$HOME/.cache/llmswitch-watchdog.pid"
    if ! [ -f "$watchdog_pid_file" ] || ! kill -0 "$(cat "$watchdog_pid_file")" 2>/dev/null; then
        nohup bash "$LLMSWITCH_WATCHDOG" --daemon >> "$HOME/.cache/llmswitch-watchdog.log" 2>&1 &
        info "watchdog 已启动"
    fi

    local config=$(get_llm_config "gateway") || { error "无法获取 Gateway 配置"; return 1; }
    IFS='|' read -r base_url model_name _ small_model <<< "$config"

    info "  模型: $model_name → $(read_gateway_routes)"
    _write_llm_config "gateway" "$base_url" "$model_name" "$small_model" ""
}

# ========== 显示列表 ==========
show_list() {
    echo ""
    echo "可用 LLM："
    echo ""
    # 格式: marker|name|display_name|model|base_url|small
    list_llms | tail -n +2 | while IFS='|' read -r marker name display_name model base_url small; do
        if [[ "$marker" == "TOTAL:"* ]] || [[ "$marker" == "CURRENT:"* ]]; then
            continue
        fi
        if [[ "$base_url" == "CURRENT:"* ]] || [[ "$marker" == "" && "$name" == "" ]]; then
            continue
        fi
        local small_info=""
        if [[ -n "$small" ]]; then
            small_info="  (小模型: $small)"
        fi
        local route_info=""
        if [[ "$name" == "gateway" ]]; then
            route_info="  — $(read_gateway_routes)"
        fi
        printf "  %s %-10s %-20s%s%s\n" "$marker" "$display_name" "$model" "$small_info" "$route_info"
    done
    echo ""

    current=$(grep "^CURRENT:" <(list_llms) | cut -d: -f2)
    if [[ -n "$current" ]]; then
        if [[ "$current" == "gateway" ]] && is_proxy_running; then
            local h=$(get_proxy_health)
            local route=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_route','?'))" 2>/dev/null)
            local peak=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak',False))" 2>/dev/null)
            local peak_str=""
            [ "$peak" = "True" ] && peak_str=" (高峰)"
            info "当前: Gateway → $route$peak_str"
        else
            info "当前: $current"
        fi
    fi
}

# ========== 交互式选择 ==========
interactive_select() {
    local lines=$(list_llms)
    local total=$(echo "$lines" | grep "^TOTAL:" | cut -d: -f2)
    local current=$(echo "$lines" | grep "^CURRENT:" | cut -d: -f2)

    echo ""
    if [[ -n "$current" ]]; then
        printf "当前 LLM：%s\n" "$current"
    else
        echo "当前 LLM：未配置（选择下方编号初始化）"
    fi
    echo ""

    local idx=1
    local selectable=0
    local names=()
    while IFS='|' read -r marker name display_name model base_url small; do
        if [[ "$marker" == "TOTAL:"* ]] || [[ "$marker" == "CURRENT:"* ]]; then
            continue
        fi
        if [[ -z "$name" ]]; then
            continue
        fi
        local small_str=""
        if [[ -n "$small" ]]; then
            small_str=" [小模型: $small]"
        fi
        local route_str=""
        if [[ "$name" == "gateway" ]]; then
            route_str="  — $(read_gateway_routes)"
        fi
        names+=("$name")
        selectable=$((selectable + 1))
        if [[ "$marker" == "◀" ]]; then
            printf "  %d) %s (%s)%s%s ◀ 当前\n" "$idx" "$display_name" "$model" "$small_str" "$route_str"
        else
            printf "  %d) %s (%s)%s%s\n" "$idx" "$display_name" "$model" "$small_str" "$route_str"
        fi
        idx=$((idx + 1))
    done < <(echo "$lines")

    echo ""
    printf "输入数字 [1-%d] 选择，0 保持当前 (%s): " "$selectable" "$current"
    read -r choice

    if [[ -z "$choice" ]] || [[ "$choice" == "0" ]]; then
        info "保持当前: $current"
        return 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$selectable" ]]; then
        target="${names[$((choice-1))]}"
        switch_llm "$target"
    else
        error "无效选择: $choice"
        return 1
    fi
}

# ========== 主流程 ==========
main() {
    local cmd="${1:-${INIT_LLM_NAME:-}}"

    if [[ "$cmd" == "list" ]]; then
        show_list
    elif [[ -z "$cmd" ]]; then
        # 无参数：交互式选择
        interactive_select
    else
        # 直接指定 LLM 名称（或从 INIT_LLM_NAME env 读取）
        switch_llm "$cmd"
    fi
}

main "$@"