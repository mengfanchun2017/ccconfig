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
source "$SCRIPT_DIR/lib/path-helper.sh"
CONFIG_FILE="$SCRIPT_DIR/conf/llm.json"
LLMSWITCH_CONF="$SCRIPT_DIR/option-llmswitch/conf/llmswitch.json"
LLMSWITCH_INIT="$SCRIPT_DIR/option-llmswitch/init.sh"
LLMSWITCH_WATCHDOG="$SCRIPT_DIR/option-llmswitch/watchdog.sh"
CLAUDE_JSON="$HOME/.claude.json"

ensure_config "$CONFIG_FILE" "conf/llm.json" || exit 1

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# ========== Gateway 辅助 ==========
is_proxy_running() {
    local pid_file="$HOME/.cache/llmswitch.pid"
    [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

get_proxy_health() {
    curl -s --max-time 3 "http://127.0.0.1:8899/health" 2>/dev/null || echo '{}'
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

# ========== 切换 LLM ==========
switch_llm() {
    local name="$1"

    if [[ "$name" == "gateway" ]]; then
        # TODO: 等 CC 修复 thinking 块兼容后取消注释
        # switch_to_gateway
        # return $?
        warn "Gateway 暂不可用 — 等 Claude Code 更新后启用"
        return 1
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

    # 获取配置
    CONFIG=$(get_llm_config "$name") || { error "无法获取 LLM 配置: $name"; return 1; }
    IFS='|' read -r BASE_URL MODEL_NAME API_KEY SMALL_MODEL <<< "$CONFIG"

    info "切换到: $name"
    info "  API: $BASE_URL"
    info "  模型: $MODEL_NAME"
    info "  小模型: $SMALL_MODEL"

    # 先 export，让 heredoc 里的 Python 能读到
    export BASE_URL MODEL_NAME API_KEY SMALL_MODEL

    # 更新 ~/.claude.json 和 settings.json（一次 Python 进程写两个文件）
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

claude_json = os.path.expanduser(os.environ.get('CLAUDE_JSON', '~/.claude.json'))
try:
    with open(claude_json, 'r') as f:
        config = json.load(f)
except:
    config = {}
config.setdefault('env', {}).update(env_update)
with open(claude_json, 'w') as f:
    json.dump(config, f, indent=4)
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
    json.dump(sconfig, f, indent=4)
print("~/.claude/settings.json 已更新")
PYEOF

    # 更新 conf/llm.json 的 current
    export CONFIG_FILE NAME="$name"
    python3 << 'PYEOF'
import json, os

config_file = os.environ['CONFIG_FILE']
name = os.environ['NAME']

with open(config_file, 'r') as f:
    config = json.load(f)

config['current'] = name

with open(config_file, 'w') as f:
    json.dump(config, f, indent=4)
print("conf/llm.json 已更新")
PYEOF

    success "LLM 已切换为: $name"
    warn "切换后会报 \"API Error: Failed to parse JSON\"，需 /exit 后 claude 重连"
}

switch_to_gateway() {
    info "切换到 Gateway 模式"

    # 启动 proxy（如未运行）
    if ! is_proxy_running; then
        info "启动 LLM 网关代理..."
        bash "$LLMSWITCH_INIT" --start || { error "代理启动失败"; return 1; }
    else
        info "网关代理已在运行"
    fi

    # 确保 watchdog 运行（监控 proxy 健康 + 路由变更通知）
    local watchdog_pid_file="$HOME/.cache/llmswitch-watchdog.pid"
    if ! [ -f "$watchdog_pid_file" ] || ! kill -0 "$(cat "$watchdog_pid_file")" 2>/dev/null; then
        nohup bash "$LLMSWITCH_WATCHDOG" --daemon >> "$HOME/.cache/llmswitch-watchdog.log" 2>&1 &
        info "watchdog 已启动"
    fi

    # 从 llm.json 读 gateway 条目获取 model/small_model
    local CONFIG=$(get_llm_config "gateway") || { error "无法获取 Gateway 配置"; return 1; }
    IFS='|' read -r BASE_URL MODEL_NAME API_KEY SMALL_MODEL <<< "$CONFIG"

    info "  API: $BASE_URL"
    info "  模型: $MODEL_NAME → $(read_gateway_routes)"
    info "  小模型: $SMALL_MODEL"

    export BASE_URL MODEL_NAME SMALL_MODEL

    python3 << 'PYEOF'
import json, os

env_update = {
    "ANTHROPIC_BASE_URL": os.environ.get('BASE_URL', ''),
    "ANTHROPIC_MODEL": os.environ.get('MODEL_NAME', ''),
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ.get('SMALL_MODEL', os.environ.get('MODEL_NAME', ''))
}

claude_json = os.path.expanduser(os.environ.get('CLAUDE_JSON', '~/.claude.json'))
try:
    with open(claude_json, 'r') as f:
        config = json.load(f)
except:
    config = {}
config.setdefault('env', {}).update(env_update)
with open(claude_json, 'w') as f:
    json.dump(config, f, indent=4)
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
    json.dump(sconfig, f, indent=4)
print("~/.claude/settings.json 已更新")
PYEOF

    export CONFIG_FILE NAME="gateway"
    python3 << 'PYEOF'
import json, os
with open(os.environ['CONFIG_FILE'], 'r') as f:
    config = json.load(f)
config['current'] = os.environ['NAME']
with open(os.environ['CONFIG_FILE'], 'w') as f:
    json.dump(config, f, indent=4)
print("conf/llm.json 已更新")
PYEOF

    success "LLM 已切换为: Gateway"
    warn "切换后会报 \"API Error: Failed to parse JSON\"，需 /exit 后 claude 重连"
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
    printf "当前 LLM：%s\n" "$current"
    echo ""

    # 显示选项
    local idx=1
    local names=()
    while IFS='|' read -r marker name display_name model base_url small; do
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
        local route_str=""
        if [[ "$name" == "gateway" ]]; then
            route_str="  — $(read_gateway_routes)  [等 CC 更新后启用]"
        fi
        if [[ "$marker" == "◀" ]]; then
            printf "  %d) %s (%s)%s%s ◀ 当前\n" "$idx" "$display_name" "$model" "$small_str" "$route_str"
        else
            printf "  %d) %s (%s)%s%s\n" "$idx" "$display_name" "$model" "$small_str" "$route_str"
        fi
        ((idx++))
    done < <(echo "$lines")

    # TODO: 等 CC 修复 thinking 块兼容后启用 Gateway 强制路由测试
    # if is_proxy_running; then
    #     echo ""
    #     echo "  Gateway 测试（强制路由）："
    #     echo "  D) Gateway → DeepSeek"
    #     echo "  M) Gateway → MiniMax"
    # fi

    echo ""
    printf "输入数字 [1-%d] 选择，0 保持当前 (%s): " "$total" "$current"
    read -r choice

    if [[ -z "$choice" ]] || [[ "$choice" == "0" ]]; then
        info "保持当前: $current"
        return 0
    fi

    # TODO: 等 CC 修复后取消注释
    # if [[ "$choice" == "D" || "$choice" == "d" ]]; then
    #     if is_proxy_running; then
    #         switch_to_gateway
    #         bash "$LLMSWITCH_INIT" --mode manual deepseek
    #         info "Gateway → DeepSeek (手动强制)"
    #     fi
    #     return 0
    # fi
    # if [[ "$choice" == "M" || "$choice" == "m" ]]; then
    #     if is_proxy_running; then
    #         switch_to_gateway
    #         bash "$LLMSWITCH_INIT" --mode manual minimax
    #         info "Gateway → MiniMax (手动强制)"
    #     fi
    #     return 0
    # fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$total" ]]; then
        target="${names[$((choice-1))]}"
        if [[ "$target" == "gateway" ]]; then
            warn "Gateway 暂不可用 — 等 Claude Code 更新后启用"
            info "建议使用 1) MiniMax 或 2) DeepSeek"
            return 1
        fi
        switch_llm "$target"
    else
        error "无效选择: $choice"
        return 1
    fi
}

# ========== 主流程 ==========
main() {
    local cmd="${1:-}"

    if [[ "$cmd" == "list" ]]; then
        show_list
    elif [[ -z "$cmd" ]]; then
        # 无参数：交互式选择
        interactive_select
    else
        # 直接指定 LLM 名称
        switch_llm "$cmd"
    fi
}

main "$@"