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
CONFIG_FILE="$CCCONFIG_ROOT/conf/llm.json"
LLMSWITCH_CONF="$CCCONFIG_ROOT/option-llmswitch/conf/llmswitch.json"
LLMSWITCH_INIT="$CCCONFIG_ROOT/option-llmswitch/init.sh"
LLMSWITCH_WATCHDOG="$CCCONFIG_ROOT/option-llmswitch/watchdog.sh"
CLAUDE_JSON="$HOME/.claude.json"

ensure_config "$CONFIG_FILE" "conf/llm.json" || exit 1

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

routes = config.get('routes', {}).get('llmgateway', {})
peak = routes.get('peak', '?')
off_peak = routes.get('off_peak', '?')
peak_hours = config.get('peak_hours', [])
blocks = []
for b in peak_hours:
    blocks.append(f"{b['start']}-{b['end']}")
print(f"高峰 {','.join(blocks)} → {peak} ｜ 非高峰 → {off_peak}")
PYEOF
}

get_gateway_status_one_liner() {
    if ! is_proxy_running; then
        echo "未运行"
        return
    fi
    local h=$(get_proxy_health)
    local mode=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('mode','?'))" 2>/dev/null || echo "?")
    local peak=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak',False))" 2>/dev/null || echo "False")
    local route=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_route','?'))" 2>/dev/null || echo "?")
    local peak_str=""
    [ "$peak" = "True" ] && peak_str=" (高峰)"
    local watchdog_pid="$HOME/.cache/llmswitch-watchdog.pid"
    local watchdog_str="✗"
    [ -f "$watchdog_pid" ] && kill -0 "$(cat "$watchdog_pid")" 2>/dev/null && watchdog_str="✓"
    local auto_str="✗"
    [ "$mode" = "auto" ] && [ "$watchdog_str" = "✓" ] && auto_str="✓"
    echo "→ $route$peak_str | mode:$mode | auto-switch:$auto_str | watchdog:$watchdog_str"
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
import json, os, sys

PLACEHOLDER_KW = ['请填入', '请替换', 'your key', 'your_key', 'placeholder', 'changeme', '<your-']

def is_placeholder(val):
    if not val or not isinstance(val, str):
        return True
    v = val.lower()
    for p in PLACEHOLDER_KW:
        if p.lower() in v:
            return True
    return False

def mask_key(k):
    if not k or len(k) < 8:
        return "(空)"
    return f"...{k[-4:]}"

def read_existing_token():
    """从 ~/.claude/settings.json 读取已有的 ANTHROPIC_AUTH_TOKEN"""
    sf = os.path.expanduser("~/.claude/settings.json")
    try:
        with open(sf, 'r') as f:
            d = json.load(f)
        tok = d.get('env', {}).get('ANTHROPIC_AUTH_TOKEN', '')
        if tok and not is_placeholder(tok):
            return tok
    except:
        pass
    return ''

def write_json(path, updater):
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except:
        data = {}
    updater(data)
    with open(path, 'w') as f:
        json.dump(data, f, indent=4)

api_key = os.environ.get('API_KEY', '')
existing_token = read_existing_token()

# ── Key 决策 ──
if api_key and not is_placeholder(api_key):
    # llm.json 中是真 key
    final_token = api_key
    print(f"\033[0;32m  Key: {mask_key(api_key)}\033[0m")
elif existing_token:
    # llm.json 是占位符，但 settings.json 已有真 key（来自 ccprivate）
    final_token = existing_token
    print(f"\033[0;32m  Key: 来自已有配置 {mask_key(existing_token)}\033[0m")
else:
    # 两者都没有真 key
    final_token = ''
    print(f"\033[1;33m  Key: 未配置，后续可在 Claude 中或编辑 llm.json 填入\033[0m")

# ── 写 llm.json 的 current 和 key ──
def update_llm_json(d):
    d['current'] = os.environ['NAME']
    if final_token:
        # 回写真 key 到 llm.json（替换占位符）
        llms = d.get('llms', {})
        cur = os.environ['NAME']
        if cur in llms:
            llms[cur]['key'] = final_token
write_json(os.environ['CONFIG_FILE'], update_llm_json)
print("conf/llm.json 已更新")

# ── 写 env ──
env_update = {
    "ANTHROPIC_BASE_URL": os.environ.get('BASE_URL', ''),
    "ANTHROPIC_MODEL": os.environ.get('MODEL_NAME', ''),
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
    "ENABLE_PROMPT_CACHING_1H": "1",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ.get('SMALL_MODEL', os.environ.get('MODEL_NAME', ''))
}
if final_token:
    env_update["ANTHROPIC_AUTH_TOKEN"] = final_token

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

# ========== Custom (临时输入任意 Anthropic-compatible 端点) ==========
# 用法: switch_custom
# 不写 llm.json，不持久化，只切当前会话；可选择后续保存为预设
switch_custom() {
    # 切到直连前先停 watchdog + proxy（同 switch_llm 行为）
    if is_proxy_running; then
        info "停止网关代理..."
        local watchdog_pid_file="$HOME/.cache/llmswitch-watchdog.pid"
        if [ -f "$watchdog_pid_file" ]; then
            kill "$(cat "$watchdog_pid_file")" 2>/dev/null || true
            rm -f "$watchdog_pid_file"
        fi
        bash "$LLMSWITCH_INIT" --stop 2>/dev/null || true
    fi

    echo ""
    echo "  ── 自定义 Anthropic-compatible 端点 ──"
    echo "  示例: OpenRouter https://openrouter.ai/api/v1"
    echo "        自部署网关 https://your-llm.example.com/anthropic"
    echo ""
    read -p "  Base URL: " custom_url
    if [[ -z "$custom_url" ]]; then
        error "Base URL 不能为空"
        return 1
    fi

    read -p "  Model 名称: " custom_model
    if [[ -z "$custom_model" ]]; then
        error "Model 名称不能为空"
        return 1
    fi

    read -p "  API Key (留空 = 复用当前 key): " custom_key

    # 复用逻辑：用户留空就从 settings.json 取
    if [[ -z "$custom_key" ]]; then
        custom_key=$(python3 -c "
import json, os
try:
    with open(os.path.expanduser('~/.claude/settings.json')) as f:
        d = json.load(f)
    tok = d.get('env', {}).get('ANTHROPIC_AUTH_TOKEN', '')
    print(tok)
except: pass
" 2>/dev/null || echo "")
    fi

    echo ""
    read -p "  是否保存为预设 (Y/n): " save_choice
    local save_preset="n"
    case "$save_choice" in
        [Yy]|"") save_preset="y" ;;
    esac

    if [[ "$save_preset" == "y" ]]; then
        # 用户想持久化：写 llm.json + 切到新预设
        local preset_name
        read -p "  预设名称 (英文, 如 my-llm): " preset_name
        preset_name=$(echo "$preset_name" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
        if [[ -z "$preset_name" ]]; then
            error "预设名称不能为空，跳过保存"
            save_preset="n"
        else
            # 写到 llm.json（不覆盖已有 providers）
            python3 - <<PYEOF
import json, os
p = "${CONFIG_FILE}"
try:
    with open(p, 'r') as f:
        d = json.load(f)
except Exception:
    d = {}
llms = d.setdefault('llms', {})
key_val = """${custom_key}""".strip() if """${custom_key}""" else ''
llms["${preset_name}"] = {
    "name": "${preset_name}",
    "base_url": "${custom_url}",
    "model": "${custom_model}",
    "key": key_val,
    "small_model": "${custom_model}",
}
d['current'] = '${preset_name}'
with open(p, 'w') as f:
    json.dump(d, f, indent=4, ensure_ascii=False)
print(f"llm.json 已写入预设: ${preset_name}")
PYEOF
            info "已保存为预设: $preset_name（下次菜单可见）"
        fi
        # 切到新预设
        switch_llm "$preset_name"
        return $?
    fi

    if [[ "$save_preset" != "y" ]]; then
        # 临时模式：直接写 env，不动 llm.json
        info "临时切换（不保存），切换到: ${custom_url} | ${custom_model}"
        export CONFIG_FILE CLAUDE_JSON BASE_URL="$custom_url" MODEL_NAME="$custom_model" SMALL_MODEL="$custom_model" API_KEY="$custom_key" NAME="custom"
        _write_llm_config "custom" "$custom_url" "$custom_model" "$custom_model" "$custom_key"
        # current 字段记录为 custom 标记（不污染 llm.json 的预设列表）
        python3 -c "
import json
p = '${CONFIG_FILE}'
try:
    with open(p, 'r') as f: d = json.load(f)
except: d = {}
d['current'] = 'custom'
with open(p, 'w') as f: json.dump(d, f, indent=4)
" 2>/dev/null
    fi
}

# ========== OpenAI Bridge 自动启动 ==========
# 给 OpenAI-only 端点（不含 /anthropic 也不是 127.0.0.1）启 bridge
# 用法: _ensure_openai_bridge <upstream_base> <model> <key>
# 返回 0=已启成功, 1=失败
_ensure_openai_bridge() {
    local upstream="$1" model="$2" key="$3"
    local port=8898
    local health=$(curl -s --max-time 2 "http://127.0.0.1:${port}/health" 2>/dev/null)

    if [[ -n "$health" ]] && echo "$health" | grep -q "\"upstream\":\"$upstream\""; then
        # bridge 已启且 upstream 匹配，复用
        info "  [bridge] 已运行且 upstream 匹配"
        return 0
    fi

    if [[ -n "$health" ]]; then
        # bridge 已启但 upstream 不对，杀掉重启
        pkill -f "openai_bridge.py.*--port ${port}" 2>/dev/null || true
        sleep 1
    fi

    # 启新 bridge（unset 代理 env 直连上游）
    cd "$CCCONFIG_ROOT"
    nohup env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
        OPENAI_BRIDGE_UPSTREAM="$upstream" \
        OPENAI_BRIDGE_KEY="$key" \
        OPENAI_BRIDGE_MODEL="$model" \
        python3 option-llmswitch/openai_bridge.py --port "$port" \
        > "$HOME/.cache/openai_bridge.log" 2>&1 &
    disown

    # 等待启动
    for i in 1 2 3 4 5; do
        sleep 1
        health=$(curl -s --max-time 2 "http://127.0.0.1:${port}/health" 2>/dev/null)
        [[ -n "$health" ]] && break
    done

    if [[ -z "$health" ]]; then
        return 1
    fi
    return 0
}


# ========== 切换 LLM ==========
switch_llm() {
    local name="$1"

    case "$name" in
        gateway)
            switch_to_gateway
            return $?
            ;;
        custom|-c)
            switch_custom
            return $?
            ;;
    esac

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

    # 检测 OpenAI-only 端点（不是 Anthropic compatible），自动启 bridge + 改写 base_url
    if [[ "$base_url" != *"/anthropic"* ]] && [[ "$base_url" != *"://127.0.0.1"* ]]; then
        info "  检测到 OpenAI-only 端点，自动启用 Anthropic↔OpenAI bridge..."
        if _ensure_openai_bridge "$base_url" "$model_name" "$api_key"; then
            base_url="http://127.0.0.1:8898"
            info "  Bridge 已就绪，base_url → $base_url"
        else
            error "  bridge 启动失败，请检查 ~/.cache/openai_bridge.log"
            return 1
        fi
    fi

    # 占位符 key → 尝试从已有配置读取，都没有就交互输入
    if echo "$api_key" | grep -qE '请填入|请替换|your.key|placeholder|changeme|<your-'; then
        local existing_key
        existing_key=$(python3 -c "
import json, os
try:
    with open(os.path.expanduser('~/.claude/settings.json')) as f:
        d = json.load(f)
    tok = d.get('env', {}).get('ANTHROPIC_AUTH_TOKEN', '')
    print(tok)
except: pass
" 2>/dev/null)
        if [[ -n "$existing_key" ]] && ! echo "$existing_key" | grep -qE '请填入|请替换|your.key|placeholder|changeme|<your-'; then
            info "  Key: 来自已有配置 ...${existing_key: -4}"
            api_key="$existing_key"
        elif [[ -t 0 ]]; then
            # 交互式终端 → 提示输入
            echo ""
            echo -e "  ${YELLOW}未找到 ${name} 的 API Key${NC}"
            echo -e "  ${GRAY}（新终端首次需输入，之后存到 ccprivate 供其他终端复用）${NC}"
            read -p "  输入 ${name} API Key: " api_key
        fi
    fi

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

    local summary=$(get_gateway_status_one_liner)
    success "Gateway 已切换 $summary"
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
        if [[ "$current" == "gateway" ]]; then
            local status=$(get_gateway_status_one_liner)
            info "当前: Gateway $status"
        else
            info "当前: $current"
        fi
    fi
}

# ========== Delete (删除预设) ==========
# 用法: delete_preset [name]
# - 不带参数时交互式选
# - 内置 provider (minimax/deepseek/gateway) 拒绝删
# - 当前正在 current 的预设拒绝删（需先 switch 到别的）
delete_preset() {
    local target="${1:-}"
    if [[ -n "$target" ]]; then
        _delete_preset_confirm "$target"
        return $?
    fi

    # 交互式：只列可删的（内置不显示）
    echo ""
    echo "可删除的自定义预设（内置不可删）："
    local idx=1
    local deletable_names=()
    while IFS='|' read -r name display_name model base_url; do
        if [[ -z "$name" ]]; then continue; fi
        # 跳过内置
        if [[ "$name" == "minimax" || "$name" == "deepseek" || "$name" == "gateway" ]]; then
            continue
        fi
        printf "  %d) %s (%s)\n" "$idx" "$display_name" "$model"
        deletable_names+=("$name")
        idx=$((idx + 1))
    done < <(python3 - <<PYEOF
import json, sys
p = "${CONFIG_FILE}"
try:
    with open(p, 'r') as f:
        d = json.load(f)
except:
    sys.exit(0)
for name, cfg in d.get('llms', {}).items():
    print(f"{name}|{cfg.get('name', name)}|{cfg.get('model', '')}|{cfg.get('base_url', '')}")
PYEOF
    )

    if [[ ${#deletable_names[@]} -eq 0 ]]; then
        echo ""
        error "没有可删除的自定义预设"
        return 1
    fi

    echo ""
    read -p "输入编号 [1-$((idx-1))] 删除（留空取消）: " choice
    if [[ -z "$choice" ]]; then
        info "已取消"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 )) || (( choice > ${#deletable_names[@]} )); then
        error "无效编号: $choice"
        return 1
    fi
    target="${deletable_names[$((choice-1))]}"
    _delete_preset_confirm "$target"
}

_delete_preset_confirm() {
    local target="$1"

    # 守卫 1: 内置
    if [[ "$target" == "minimax" || "$target" == "deepseek" || "$target" == "gateway" ]]; then
        error "内置预设 '$target' 不可删除"
        return 1
    fi

    # 守卫 2: 是否存在
    if ! python3 -c "
import json, sys
p = '${CONFIG_FILE}'
try:
    with open(p, 'r') as f: d = json.load(f)
except: sys.exit(1)
sys.exit(0 if '${target}' in d.get('llms', {}) else 2)
" 2>/dev/null; then
        error "预设 '$target' 不存在"
        return 1
    fi

    # 守卫 3: 是否为当前 current
    local cur=$(python3 -c "
import json
try:
    with open('${CONFIG_FILE}') as f: d = json.load(f)
    print(d.get('current', ''))
except: pass
")
    if [[ "$cur" == "$target" ]]; then
        error "预设 '$target' 正在被使用（current=$target），请先切换到别的 provider 再删除"
        return 1
    fi

    # 二次确认
    read -p "确认删除预设 '$target'？(y/N): " ans
    case "$ans" in
        [Yy]|[Yy][Ee][Ss]) ;;
        *) info "已取消"; return 0 ;;
    esac

    # 删除
    python3 - <<PYEOF
import json
p = "${CONFIG_FILE}"
with open(p, 'r') as f:
    d = json.load(f)
llms = d.get('llms', {})
if "${target}" in llms:
    del llms["${target}"]
    with open(p, 'w') as f:
        json.dump(d, f, indent=4, ensure_ascii=False)
    print(f"已删除预设: ${target}")
else:
    print(f"预设 ${target} 不存在", file=sys.stderr)
PYEOF
    success "预设 '$target' 已删除"
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

    # Custom + Delete + Configure Gateway 是固定选项
    local custom_idx=$((selectable + 1))
    local delete_idx=$((selectable + 2))
    local gateway_conf_idx=$((selectable + 3))
    printf "  %d) %s\n" "$custom_idx" "Custom (输入任意 base_url + model + key)"
    printf "  %d) %s\n" "$delete_idx" "Delete (删除已保存的自定义预设)"
    printf "  %d) %s\n" "$gateway_conf_idx" "Configure Gateway (peak_hours / routes / mode)"

    echo ""
    printf "输入数字 [1-%d] 选择，0 保持当前 (%s): " "$gateway_conf_idx" "$current"
    read -r choice

    if [[ -z "$choice" ]] || [[ "$choice" == "0" ]]; then
        info "保持当前: $current"
        return 0
    fi

    if [[ "$choice" == "$custom_idx" ]]; then
        switch_custom
        return $?
    fi

    if [[ "$choice" == "$delete_idx" ]]; then
        delete_preset
        return $?
    fi

    if [[ "$choice" == "$gateway_conf_idx" ]]; then
        bash "$LLMSWITCH_INIT" --config
        return $?
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
    elif [[ "$cmd" == "custom" ]] || [[ "$cmd" == "-c" ]]; then
        switch_custom
    elif [[ "$cmd" == "delete" ]] || [[ "$cmd" == "-d" ]]; then
        # 可选第二参数：要删的预设名
        delete_preset "${2:-}"
    elif [[ -z "$cmd" ]]; then
        # 无参数：交互式选择
        interactive_select
    else
        # 直接指定 LLM 名称（或从 INIT_LLM_NAME env 读取）
        switch_llm "$cmd"
    fi
}

main "$@"