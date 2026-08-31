#!/bin/bash
# ==============================================
# LLM 配置管理脚本（精简版）
#
# 使用：
#   bash init-llm.sh                 # 交互菜单
#   bash init-llm.sh <name>          # 直接切预设
#   bash init-llm.sh list            # 列预设
#   bash init-llm.sh status          # 当前链路诊断
#   bash init-llm.sh test <name>     # 非破坏性探测
#   bash init-llm.sh sync            # 修 /model 污染
#   bash init-llm.sh custom          # 自定义临时端点
#   bash init-llm.sh delete <name>   # 删预设
#   bash init-llm.sh bill            # 模型单价（拆 init-llm-bill.sh）
#
# 设计原则：
#   - 单文件真相源：llm.json（providers + current）
#   - Claude 唯一读 env：settings.json env 段
#   - bridge 仅在 OpenAI-only 端点自动起，自愈靠 status.sh SessionStart hook
#   - 切失败不自动回滚（让用户看清楚错误）
# ==============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/path-helper.sh"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/dry-run.sh"
source "$SCRIPT_DIR/interact.sh"
source "$SCRIPT_DIR/ensure-bridge.sh"

CONFIG_FILE="$(resolve_conf llm.json)" || exit 1
LLMSWITCH_CONF="$CCCONFIG_ROOT/option-llmswitch/conf/llmswitch.json"
LLMSWITCH_INIT="$CCCONFIG_ROOT/option-llmswitch/init.sh"
LLMSWITCH_WATCHDOG="$CCCONFIG_ROOT/option-llmswitch/watchdog.sh"
CLAUDE_JSON="$HOME/.claude.json"

# ========== 读取配置 ==========
get_llm_config() {
    python3 - "$CONFIG_FILE" "$1" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f: d = json.load(f)
llm = d.get('llms', {}).get(sys.argv[2])
if not llm: print("ERROR:Unknown LLM"); sys.exit(1)
small = llm.get('small_model', llm.get('model', ''))
print(f"{llm.get('base_url','')}|{llm.get('model','')}|{llm.get('key','')}|{small}")
PYEOF
}

list_llms() {
    python3 - "$CONFIG_FILE" "$LLMSWITCH_CONF" << 'PYEOF'
import json, sys, os
with open(sys.argv[1]) as f: d = json.load(f)
llms = d.get('llms', {}); cur = d.get('current', '')
sw_model = sw_small = ''
if os.path.exists(sys.argv[2]):
    try:
        sw = json.load(open(sys.argv[2]))
        sw_model = sw.get('model_name', '')
        sw_small = sw.get('small_model_name', '')
    except: pass
print(f"TOTAL:{len(llms)}")
print(f"CURRENT:{cur}")
for name, llm in llms.items():
    model = llm.get('model', '')
    if name == 'gateway' and sw_model:
        model = sw_model
    marker = "◀" if name == cur else " "
    small = (sw_small if name == 'gateway' and sw_small else llm.get('small_model', ''))
    is_builtin = '1' if llm.get('builtin', False) else '0'
    print(f"{marker}|{name}|{llm.get('name', name)}|{model}|{llm.get('base_url','')}|{small}|{is_builtin}")
PYEOF
}

# ========== Gateway 辅助 ==========
is_proxy_running() {
    local pf="$HOME/.cache/llmswitch.pid"
    [[ -f "$pf" ]] && kill -0 "$(cat "$pf")" 2>/dev/null
}

get_gateway_status() {
    local port="${LLMSWITCH_PORT:-8899}"
    if ! is_proxy_running; then echo "未运行"; return; fi
    local h mode peak route
    h=$(curl -s --max-time 3 "http://127.0.0.1:${port}/health" 2>/dev/null || echo '{}')
    IFS='|' read -r mode peak route < <(echo "$h" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('mode','?')+'|'+str(d.get('peak',False))+'|'+d.get('current_route','?'))" 2>/dev/null || echo "?|False|?")
    local ps=""
    [[ "$peak" == "True" ]] && ps=" (高峰)"
    echo "→ $route$ps | mode:$mode"
}

# 从 llmswitch.json 读 peak/off-peak 路由摘要（菜单显示用）
read_gateway_routes() {
    python3 - "${1:-$LLMSWITCH_CONF}" "${2:-$CONFIG_FILE}" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f: sw = json.load(f)
except Exception:
    sys.exit(0)

key_to_model = {}
try:
    with open(sys.argv[2]) as f: llm_cfg = json.load(f)
    for k, v in llm_cfg.get('llms', {}).items():
        key_to_model[k] = v.get('model', k)
except Exception: pass

routes = sw.get('routes', {}).get('llmgateway', {})
peak_key = routes.get('peak', '?')
off_peak_key = routes.get('off_peak', '?')
peak = key_to_model.get(peak_key, peak_key)
off_peak = key_to_model.get(off_peak_key, off_peak_key)
peak_hours = sw.get('peak_hours', [])
blocks = [f"{b['start']}-{b['end']}" for b in peak_hours]
print(f"高峰 {','.join(blocks)}→{peak}, 非高峰→{off_peak}")
PYEOF
}

# ========== 探测 endpoint（不自动回滚）==========
# 用法: verify_endpoint <name> <base_url> <model> <key>
# 返回 0=链路通或鉴权失败 1=不可达
verify_endpoint() {
    local name="$1" base_url="$2" model="$3" key="$4"
    [[ -z "$key" ]] && return 0
    case "$key" in *请填入*|*请替换*|*your.key*|*placeholder*|*changeme*) return 0 ;; esac

    local probe_path
    if [[ "$base_url" == *"://127.0.0.1"* ]]; then
        local port="${base_url##*:}"; port="${port%%/*}"
        # /health 探测：retry 3 次
        local h=""
        for _ in 1 2 3; do
            h=$(curl -s --max-time 3 "http://127.0.0.1:${port}/health" 2>/dev/null) || true
            [[ -n "$h" ]] && break
            sleep 1
        done
        [[ -z "$h" ]] && { error "  ✗ bridge (port $port) 无响应 — bridge 进程可能挂了"; return 1; }
        probe_path="${base_url%/}/v1/messages"
    elif [[ "$base_url" == *"/anthropic"* ]]; then
        probe_path="${base_url%/}/v1/messages"
    else
        probe_path="${base_url%/}/chat/completions"
    fi

    local body="{\"model\":\"$model\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
    local headers=(-H "Content-Type: application/json" -H "Authorization: Bearer $key")
    [[ "$probe_path" == *"/v1/messages" ]] && headers+=(-H "anthropic-version: 2023-06-01")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 35 -X POST "$probe_path" "${headers[@]}" -d "$body" 2>/dev/null) || status="000"
    [[ -z "$status" || "$status" =~ ^0+$ ]] && status="000"

    case "$status" in
        200) info "  ✓ endpoint 探测成功 ($name)"; return 0 ;;
        000) error "  ✗ endpoint 不可达 (连接超时/拒绝) — VPN/防火墙可能拦了 $base_url"; return 1 ;;
        401|403) info "  ⚠ HTTP $status — 链路通但鉴权错"; return 0 ;;
        400) warn "  ⚠ HTTP 400 — endpoint 路径/参数可能不对 $base_url"; return 0 ;;
        *) info "  ⚠ HTTP $status"; return 0 ;;
    esac
}

# ========== 写配置（直连 + gateway 共用） ==========
# 占位符 key 检测 + 复用 settings.json 已有 token
write_llm_config() {
    local name="$1" base_url="$2" model="$3" small="$4" key="${5:-}"

    info "  API: $base_url"
    info "  模型: $model"
    info "  小模型: $small"

    export CONFIG_FILE="$CONFIG_FILE" BASE_URL="$base_url" MODEL_NAME="$model" SMALL_MODEL="$small" API_KEY="$key" NAME="$name"

    python3 << 'PYEOF'
import json, os

PLACEHOLDER_KW = ['请填入','请替换','your key','your_key','placeholder','changeme','<your-']
def is_placeholder(v):
    if not v or not isinstance(v, str): return True
    vl = v.lower()
    return any(p.lower() in vl for p in PLACEHOLDER_KW)
def mask_key(k):
    return f"...{k[-4:]}" if k and len(k) >= 8 else "(空)"

# 复用已有 key
api_key = os.environ.get('API_KEY', '')
existing = ''
try:
    with open(os.path.expanduser("~/.claude/settings.json")) as f:
        existing = json.load(f).get('env', {}).get('ANTHROPIC_AUTH_TOKEN', '')
except: pass
if api_key and not is_placeholder(api_key):
    final = api_key
    print(f"\033[0;32m  Key: {mask_key(api_key)}\033[0m")
elif existing and not is_placeholder(existing):
    final = existing
    print(f"\033[0;32m  Key: 复用已有 ...{existing[-4:]}\033[0m")
else:
    final = ''
    print(f"\033[1;33m  Key: 未配置\033[0m")

# 写 llm.json
cfg = os.environ['CONFIG_FILE']
with open(cfg) as f: d = json.load(f)
d['current'] = os.environ['NAME']
if final:
    llms = d.setdefault('llms', {})
    if os.environ['NAME'] in llms:
        llms[os.environ['NAME']]['key'] = final
with open(cfg, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
print("llm.json 已更新")

# 写 settings.json env + 顶层 model
env_upd = {
    "ANTHROPIC_BASE_URL": os.environ['BASE_URL'],
    "ANTHROPIC_MODEL": os.environ['MODEL_NAME'],
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
    "ENABLE_PROMPT_CACHING_1H": "1",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ.get('SMALL_MODEL') or os.environ['MODEL_NAME'],
}
if final:
    env_upd["ANTHROPIC_AUTH_TOKEN"] = final

sf = os.path.expanduser("~/.claude/settings.json")
if os.path.islink(sf) and not os.path.exists(sf):
    os.unlink(sf)
try:
    with open(sf) as f: sd = json.load(f)
except: sd = {}
sd.setdefault('env', {}).update(env_upd)
if os.environ['MODEL_NAME']:
    sd['model'] = os.environ['MODEL_NAME']
with open(sf, 'w') as f: json.dump(sd, f, indent=4, ensure_ascii=False)
print("settings.json 已更新")
PYEOF

    success "LLM 已切换为: $name"
    sync_top_model
}

# 同步 settings.json 顶层 model 为 env.ANTHROPIC_MODEL（修 /model 污染）
sync_top_model() {
    python3 - <<'PYEOF'
import json, os
sf = os.path.expanduser("~/.claude/settings.json")
try:
    with open(sf) as f: d = json.load(f)
except: sys.exit(0)
em = d.get('env', {}).get('ANTHROPIC_MODEL', '')
tm = d.get('model', '')
if em and em != tm:
    d['model'] = em
    with open(sf, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
    print(f"sync: 顶层 model {tm or '(空)'} → {em}")
PYEOF
}

# 停 gateway 代理（如在跑）
stop_gateway() {
    if ! is_proxy_running; then return 0; fi
    local wpf="$HOME/.cache/llmswitch-watchdog.pid"
    [[ -f "$wpf" ]] && kill "$(cat "$wpf")" 2>/dev/null || true
    rm -f "$wpf"
    bash "$LLMSWITCH_INIT" --stop 2>/dev/null || true
}

# 停 bridge（如有）
stop_bridge() {
    local pid
    pid=$( { lsof -ti :${BRIDGE_PORT} 2>/dev/null || true; } | head -1 || true)
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
}

# 读 use_bridge 标记
get_use_bridge() {
    python3 - "$CONFIG_FILE" "$1" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
print(d.get('llms', {}).get(sys.argv[2], {}).get('use_bridge', False))
PYEOF
}

# ========== 切换主入口 ==========
switch_llm() {
    local name="$1"
    if _dry_run_enabled; then
        echo "  [DRY-RUN] switch_llm: would switch to '$name'"
        return 0
    fi

    case "$name" in
        gateway) switch_to_gateway; return $? ;;
        custom|-c) switch_custom; return $? ;;
    esac

    local config
    config=$(get_llm_config "$name") || { error "未知预设: $name"; return 1; }
    IFS='|' read -r base_url model key small <<< "$config"

    # 占位符 key → 交互输入
    local _is_ph=0
    [[ -z "$key" ]] && _is_ph=1
    [[ $_is_ph -eq 0 ]] && case "$key" in *请填入*|*请替换*|*your.key*|*placeholder*|*changeme*) _is_ph=1 ;; esac
    if [[ $_is_ph -eq 1 ]]; then
        if [[ -t 0 ]]; then
            echo ""; key=$(prompt_password "输入 ${name} API Key")
        fi
    fi

    # 停 gateway（切直连前）
    stop_gateway

    # 读 use_bridge 标记
    local use_bridge
    use_bridge=$(get_use_bridge "$name")

    # 是否走 bridge
    if [[ "$use_bridge" == "True" ]]; then
        info "  用户指定 bridge 代理..."
        if ensure_bridge "$base_url" "$model" "$key"; then
            base_url="http://127.0.0.1:${BRIDGE_PORT}"
            info "  bridge 就绪 → $base_url"
        else
            error "  bridge 启动失败，查 log: tail -30 ~/.cache/openai_bridge.log"
            return 1
        fi
    elif [[ "$base_url" != *"/anthropic"* ]] && [[ "$base_url" != *"://127.0.0.1"* ]]; then
        # 自动检测：OpenAI-only 端点 → 启 bridge
        info "  OpenAI-only 端点 → 启动 bridge..."
        if ensure_bridge "$base_url" "$model" "$key"; then
            base_url="http://127.0.0.1:${BRIDGE_PORT}"
            info "  bridge 就绪 → $base_url"
        else
            error "  bridge 启动失败，查 log: tail -30 ~/.cache/openai_bridge.log"
            return 1
        fi
    else
        # 直连 → 停 bridge（如有）
        stop_bridge
    fi

    info "切换到: $name"

    # 先探测 endpoint（gateway 本机 proxy 不走 verify）
    if [[ "$name" != "gateway" ]]; then
        verify_endpoint "$name" "$base_url" "$model" "$key" || {
            warn "endpoint 不可达，切换中止（llm.json 未改动）"
            return 1
        }
    fi

    write_llm_config "$name" "$base_url" "$model" "$small" "$key"
}

switch_to_gateway() {
    if _dry_run_enabled; then
        echo "  [DRY-RUN] switch_to_gateway: would start proxy + write config"
        return 0
    fi
    info "切换到 Gateway 模式"
    stop_bridge
    if [[ ! -f "$LLMSWITCH_CONF" ]]; then
        [[ -f "$LLMSWITCH_CONF.example" ]] || { error "模板不存在: $LLMSWITCH_CONF.example"; return 1; }
        cp "$LLMSWITCH_CONF.example" "$LLMSWITCH_CONF"
    fi
    if ! is_proxy_running; then
        bash "$LLMSWITCH_INIT" --start || { error "代理启动失败"; return 1; }
    fi
    local wpf="$HOME/.cache/llmswitch-watchdog.pid"
    if ! [[ -f "$wpf" ]] || ! kill -0 "$(cat "$wpf")" 2>/dev/null; then
        nohup bash "$LLMSWITCH_WATCHDOG" --daemon >> "$HOME/.cache/llmswitch-watchdog.log" 2>&1 &
    fi

    local gw_model gw_small
    read -r gw_model gw_small < <(python3 - "$LLMSWITCH_CONF" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get('model_name','llmgateway'))
print(d.get('small_model_name',''))
PYEOF
    2>/dev/null || echo -e "llmgateway\n")
    [[ -z "$gw_small" ]] && gw_small="$gw_model"

    local base_url
    base_url=$(get_llm_config "gateway" | cut -d'|' -f1) || { error "无法获取 Gateway 配置"; return 1; }
    write_llm_config "gateway" "$base_url" "$gw_model" "$gw_small" ""
    success "Gateway 已切换 ($gw_model) $(get_gateway_status)"
}

switch_custom() {
    if _dry_run_enabled; then
        echo "  [DRY-RUN] switch_custom"; return 0
    fi
    stop_gateway
    stop_bridge

    echo ""
    echo "  💡 WSL + Tailscale subnet router 场景：base_url 填内网 IP（如 10.x.x.x:port）"
    echo "     详见 docs/adr/0016-tailscale-subnet-router.md（自动启用 Windows curl.exe 转发）"
    echo ""
    echo "  ── 自定义 Anthropic-compatible 端点 ──"
    local url; url=$(prompt "Base URL")
    [[ -z "$url" ]] && { error "URL 不能为空"; return 1; }
    local model; model=$(prompt "Model 名称")
    [[ -z "$model" ]] && { error "Model 不能为空"; return 1; }
    local small; small=$(prompt "小模型名称（回车默认同大模型）")
    [[ -z "$small" ]] && small="$model"
    local key; key=$(prompt "API Key（留空复用当前）")
    if [[ -n "$key" ]]; then
        info "  Key: ${key:0:4}...${key: -4}"
    else
        key=$(python3 -c "
import json,os
try:
    print(json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('env',{}).get('ANTHROPIC_AUTH_TOKEN',''))
except: pass" 2>/dev/null)
        [[ -n "$key" ]] && info "  Key: 复用已有 ...${key: -4}"
    fi

    local preset_name; preset_name=$(prompt "预设名称（小写无空格）" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    [[ -z "$preset_name" ]] && { error "预设名称不能为空"; return 1; }

    local use_bridge="False"
    local bridge_choice; bridge_choice=$(prompt "使用 bridge 代理? (y/N)" | tr '[:upper:]' '[:lower:]')
    [[ "$bridge_choice" == "y" ]] && use_bridge="True"

    CONFIG_FILE="$CONFIG_FILE" PRESET_NAME="$preset_name" URL="$url" MODEL="$model" SMALL="$small" KEY="$key" USE_BRIDGE="$use_bridge" \
        python3 - <<'PYEOF'
import json, os
p = os.environ['CONFIG_FILE']
with open(p) as f: d = json.load(f)
d.setdefault('llms', {})[os.environ['PRESET_NAME']] = {
    "name": os.environ['PRESET_NAME'],
    "base_url": os.environ['URL'],
    "model": os.environ['MODEL'],
    "key": os.environ['KEY'],
    "small_model": os.environ['SMALL'],
    "use_bridge": os.environ['USE_BRIDGE'] == 'True',
}
with open(p, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
PYEOF
    info "预设 '$preset_name' 已保存，手动切换：菜单选 2X 或 bash init-llm.sh $preset_name"
}

# ========== 状态 ==========
show_status() {
    local llm_cur sett_env sett_model
    llm_cur=$(python3 -c "
import json
try: print(json.load(open('${CONFIG_FILE}')).get('current',''))
except: pass" 2>/dev/null)

    sett_env=$(python3 -c "
import json, os
try:
    e = json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('env', {})
    print(f\"{e.get('ANTHROPIC_BASE_URL','')}|{e.get('ANTHROPIC_MODEL','')}|{e.get('ANTHROPIC_AUTH_TOKEN','')}\")
except: print('||')" 2>/dev/null)
    sett_model=$(python3 -c "
import json, os
try: print(json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('model',''))
except: pass" 2>/dev/null)

    echo ""
    printf "━━━ LLM 链路诊断 ──\n"
    printf "llm.json current          : %s\n" "${llm_cur:-<未设置>}"
    if [[ -n "$sett_env" && "$sett_env" != "||" ]]; then
        IFS='|' read -r base model tok <<< "$sett_env"
        printf "env.ANTHROPIC_BASE_URL    : %s\n" "${base:-<未设置>}"
        printf "env.ANTHROPIC_MODEL       : %s\n" "${model:-<未设置>}"
        [[ -n "$tok" ]] && printf "env.ANTHROPIC_AUTH_TOKEN  : ...%s\n" "${tok: -4}"
    fi
    printf "settings 顶层 model       : %s\n" "${sett_model:-<未设置>}"

    if [[ "$sett_env" == *"://127.0.0.1:${BRIDGE_PORT}"* ]]; then
        local h
        h=$(curl -s --max-time 2 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null) || true
        if [[ -n "$h" ]]; then
            local up
            up=$(echo "$h" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('upstream','?')+'|'+d.get('upstream_model','?'))" 2>/dev/null || echo "?|?")
            IFS='|' read -r ub um <<< "$up"
            printf "bridge (%d)              : ✓ upstream=%s model=%s\n" "$BRIDGE_PORT" "$ub" "$um"
        else
            printf "bridge (%d)              : ✗ 未响应（env 指向但没起，跑 init-llm.sh <name> 重启）\n" "$BRIDGE_PORT"
        fi
    elif is_proxy_running; then
        printf "gateway 代理              : %s\n" "$(get_gateway_status)"
    fi
    echo ""
}

# ========== 测试连接（非破坏性）==========
test_llm() {
    local target="${1:-}"
    [[ -z "$target" ]] && { error "用法: init-llm.sh test <preset>"; return 1; }
    local config
    config=$(get_llm_config "$target") || { error "未知预设: $target"; return 1; }
    IFS='|' read -r base_url model key _ <<< "$config"

    local _is_ph=0
    [[ -z "$key" ]] && _is_ph=1
    [[ $_is_ph -eq 0 ]] && case "$key" in *请填入*|*请替换*|*your.key*|*placeholder*|*changeme*) _is_ph=1 ;; esac
    if [[ $_is_ph -eq 1 ]]; then
        error "预设 '$target' 无有效 Key"; return 1
    fi

    info "测试: $target ($model @ $base_url)"
    local body_file; body_file=$(mktemp)
    local path
    if [[ "$base_url" == *"/anthropic"* ]] || [[ "$base_url" == *"://127.0.0.1"* ]]; then
        path="${base_url%/}/v1/messages"
    else
        path="${base_url%/}/chat/completions"
    fi
    local headers=(-H "Content-Type: application/json" -H "Authorization: Bearer $key")
    [[ "$path" == *"/v1/messages" ]] && headers+=(-H "anthropic-version: 2023-06-01")

    local status
    status=$(curl -s --max-time 30 -o "$body_file" -w "%{http_code}" -X POST "$path" "${headers[@]}" \
        -d "{\"model\":\"$model\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" 2>/dev/null) || status="000"

    if [[ "$status" == "200" ]]; then
        success "✓ HTTP 200 — '$target' 可用"
        rm -f "$body_file"
    else
        error "✗ HTTP $status"
        head -5 "$body_file" 2>/dev/null | sed 's/^/    /'
        rm -f "$body_file"
        return 1
    fi
}

# ========== 列预设 ==========
show_list() {
    echo ""
    echo "可用 LLM："
    echo ""
    local lines; lines=$(list_llms)
    local current
    current=$(echo "$lines" | grep "^CURRENT:" | cut -d: -f2)

    while IFS='|' read -r marker name display model base small is_builtin; do
        [[ "$marker" == "TOTAL:"* || "$marker" == "CURRENT:"* || -z "$name" ]] && continue
        local tag=""
        [[ "$is_builtin" == "1" ]] && tag=" ${DIM}[内建]${NC}"
        local info_small=""
        [[ -n "$small" ]] && info_small=" ${DIM}(小: $small)${NC}"
        printf "  %s %-10s %-20s%s%s\n" "$marker" "$display" "$model" "$tag" "$info_small"
    done < <(echo "$lines")
    echo ""
    if [[ -n "$current" && "$current" == "gateway" ]]; then
        info "当前: Gateway $(get_gateway_status)"
    elif [[ -n "$current" ]]; then
        info "当前: $current"
    fi
}

# ========== 删预设 ==========
delete_preset() {
    local target="${1:-}"

    # 读 builtin 列表
    local builtin_list
    builtin_list=$(python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
names = [k for k, v in d.get('llms', {}).items() if v.get('builtin')]
print(' '.join(names))
PYEOF
    )

    if [[ -z "$target" ]]; then
        echo "可删除的自定义预设："
        local names=()
        while IFS='|' read -r _ name display model _ _ is_builtin; do
            [[ -z "$name" ]] && continue
            [[ "$is_builtin" == "1" ]] && continue
            names+=("$name")
            printf "  %d) %s (%s)\n" "${#names[@]}" "$display" "$model"
        done < <(list_llms)
        [[ ${#names[@]} -eq 0 ]] && { info "无可删预设"; return 0; }
        local sel; sel=$(prompt "选择序号")
        [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#names[@]} )) && target="${names[$((sel-1))]}"
    fi
    [[ -z "$target" ]] && { error "未指定预设"; return 1; }

    if [[ " $builtin_list " == *" $target "* ]]; then
        error "内置预设 '$target' 不可删"; return 1
    fi
    if [[ "$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('current',''))" 2>/dev/null)" == "$target" ]]; then
        error "当前正在用 '$target'，先切别的再删"; return 1
    fi
    confirm "确认删除 '$target'？" n || { info "已取消"; return 0; }

    python3 - <<PYEOF
import json
p = "${CONFIG_FILE}"
with open(p) as f: d = json.load(f)
if "${target}" in d.get('llms', {}):
    del d['llms']["${target}"]
    with open(p, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
    print("OK")
else:
    print("NOT_FOUND")
PYEOF
}

# ========== 修改预设 ==========
edit_preset() {
    local target="${1:-}"

    # 读 builtin 列表
    local builtin_list
    builtin_list=$(python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
names = [k for k, v in d.get('llms', {}).items() if v.get('builtin')]
print(' '.join(names))
PYEOF
    )

    if [[ -z "$target" ]]; then
        echo "可修改的自定义预设："
        local names=()
        while IFS='|' read -r _ name display model _ _ is_builtin; do
            [[ -z "$name" ]] && continue
            [[ "$is_builtin" == "1" ]] && continue
            names+=("$name")
            printf "  %d) %s (%s)\n" "${#names[@]}" "$display" "$model"
        done < <(list_llms)
        [[ ${#names[@]} -eq 0 ]] && { info "无可修改预设"; return 0; }
        local sel; sel=$(prompt "选择序号")
        [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#names[@]} )) && target="${names[$((sel-1))]}"
    fi
    [[ -z "$target" ]] && { error "未指定预设"; return 1; }

    local config
    config=$(get_llm_config "$target") || { error "未知预设: $target"; return 1; }
    IFS='|' read -r cur_url cur_model cur_key cur_small <<< "$config"

    local cur_use_bridge
    cur_use_bridge=$(get_use_bridge "$target")

    echo ""
    info "修改预设: $target"
    echo "  当前: base_url=$cur_url"
    echo "         model=$cur_model"
    echo "         small_model=$cur_small"
    echo "         use_bridge=$cur_use_bridge"
    echo "         key=...${cur_key: -4}"
    echo ""

    local new_url; new_url=$(prompt "Base URL（回车保持）")
    [[ -z "$new_url" ]] && new_url="$cur_url"

    local new_model; new_model=$(prompt "Model（回车保持）")
    [[ -z "$new_model" ]] && new_model="$cur_model"

    local new_small; new_small=$(prompt "小模型（回车保持）")
    [[ -z "$new_small" ]] && new_small="$cur_small"

    local new_key; new_key=$(prompt "API Key（回车保持，输=覆盖）")
    [[ -z "$new_key" ]] && new_key="$cur_key"

    local new_bridge="$cur_use_bridge"
    local bridge_choice; bridge_choice=$(prompt "使用 bridge 代理? (y/N 当前: $cur_use_bridge)" | tr '[:upper:]' '[:lower:]')
    if [[ "$bridge_choice" == "y" ]]; then
        new_bridge="True"
    elif [[ "$bridge_choice" == "n" ]]; then
        new_bridge="False"
    fi

    confirm "确认修改 '$target'？" y || { info "已取消"; return 0; }

    CONFIG_FILE="$CONFIG_FILE" TARGET="$target" URL="$new_url" MODEL="$new_model" SMALL="$new_small" KEY="$new_key" USE_BRIDGE="$new_bridge" \
        python3 - <<'PYEOF'
import json, os
p = os.environ['CONFIG_FILE']
with open(p) as f: d = json.load(f)
llm = d.setdefault('llms', {}).get(os.environ['TARGET'])
if llm:
    llm['base_url'] = os.environ['URL']
    llm['model'] = os.environ['MODEL']
    llm['small_model'] = os.environ['SMALL']
    llm['key'] = os.environ['KEY']
    llm['use_bridge'] = os.environ['USE_BRIDGE'] == 'True'
    with open(p, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
    print("OK")
else:
    print("NOT_FOUND")
PYEOF
    success "预设 '$target' 已更新"
}

# ========== 交互式菜单（保留原字母 1A/2B/3C 样式）==========
_llm_status_header() {
    local current="${1:-}"
    echo -e ""
    if [[ -z "$current" ]]; then
        echo -e "  ${LIGHT_BLUE}生效配置: 未配置${NC}"
        echo -e ""
        return
    fi

    local display model base_url
    IFS='|' read -r display model base_url < <(CUR="$current" CONFIG_FILE="$CONFIG_FILE" python3 - << 'PYEOF'
import json, os
d = json.load(open(os.environ['CONFIG_FILE']))
llm = d.get('llms', {}).get(os.environ['CUR'], {})
print(f"{llm.get('name', os.environ['CUR'])}|{llm.get('model','')}|{llm.get('base_url','')}")
PYEOF
    ) 2>/dev/null
    [[ -z "$display" ]] && display="$current"
    echo -e "  ${LIGHT_BLUE}生效配置: $display${NC} ${DIM}($model)${NC}"

    # bridge 状态：settings.json env 指向 bridge 端口
    local _sf_url
    _sf_url=$(python3 -c "
import json, os
try: print(json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('env',{}).get('ANTHROPIC_BASE_URL',''))
except: pass" 2>/dev/null)
    if [[ "$_sf_url" == "http://127.0.0.1:${BRIDGE_PORT}"* ]]; then
        local _bh
        _bh=$(curl -s --max-time 1 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null) || true
        if [[ -n "$_bh" ]]; then
            local up
            up=$(echo "$_bh" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('upstream_model','?'))" 2>/dev/null || echo "?")
            echo -e "  ${LIGHT_BLUE}bridge: ${GREEN}✓${NC} ${DIM}upstream=$up${NC}"
        else
            echo -e "  ${LIGHT_BLUE}bridge: ${RED}✗ 无响应${NC}"
        fi
    fi

    # tailscale 状态：当前预设 base_url 是 RFC1918 私网段（10/172.16-31/192.168）
    if [[ "$base_url" =~ ^https?://(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
        if command -v curl.exe &>/dev/null; then
            local ts_code
            ts_code=$(curl.exe -s -o /dev/null -w "%{http_code}" --max-time 3 -k "$base_url" 2>/dev/null || echo "000")
            if [[ "$ts_code" == "000" ]]; then
                echo -e "  ${LIGHT_BLUE}tailscale: ${RED}✗ 不可达${NC}"
            else
                echo -e "  ${LIGHT_BLUE}tailscale: ${GREEN}✓ 就绪${NC} ${DIM}(HTTP $ts_code)${NC}"
            fi
        else
            echo -e "  ${LIGHT_BLUE}tailscale: ${YELLOW}? curl.exe 不可用${NC}"
        fi
    fi
    echo -e ""
}

interactive_select() {
    local -a item_cat item_letter item_name
    local -a builtin_r custom_r

    while true; do
        clear
        local lines; lines=$(list_llms)
        local current; current=$(echo "$lines" | grep "^CURRENT:" | cut -d: -f2)
        _llm_status_header "$current"
        builtin_r=(); custom_r=(); item_cat=(); item_letter=(); item_name=()
        while IFS='|' read -r marker name display_name model base_url small is_builtin; do
            [[ "$marker" == "TOTAL:"* || "$marker" == "CURRENT:"* || -z "$name" ]] && continue
            if [[ "$is_builtin" == "1" ]]; then
                builtin_r+=("$name|$display_name|$model|$small|$marker|$base_url")
            else
                custom_r+=("$name|$display_name|$model|$small|$marker|$base_url")
            fi
        done < <(echo "$lines")
        echo -e "  ${BOLD_GRAY}--内建 llm--${NC}"
        local letter="A"
        for entry in "${builtin_r[@]}"; do
            IFS='|' read -r name display_name model small marker base_url <<< "$entry"
            local small_str="" route_str=""
            [[ -n "$small" ]] && small_str=" ${DIM}[小模型: $small]${NC}"
            [[ "$name" == "gateway" ]] && route_str=" ${YELLOW}$(read_gateway_routes "$LLMSWITCH_CONF" "$CONFIG_FILE" 2>/dev/null)${NC}"
            echo -e "  ${BOLD_GREEN}1${letter}${NC}  ${display_name} ${DIM}${model}${NC}${small_str}${route_str}"
            item_cat+=("1"); item_letter+=("$letter"); item_name+=("$name")
            case "$letter" in A) letter=B;; B) letter=C;; C) letter=D;; D) letter=E;; E) letter=F;; F) letter=G;; G) letter=H;; H) letter=I;; I) letter=J;; J) letter=K;; K) letter=L;; L) letter=M;; M) letter=N;; N) letter=O;; O) letter=P;; P) letter=Q;; Q) letter=R;; R) letter=S;; S) letter=T;; T) letter=U;; U) letter=V;; V) letter=W;; W) letter=X;; X) letter=Y;; Y) letter=Z;; *) letter=A;; esac
        done

        echo -e "  ${BOLD_GRAY}--自定义 llm--${NC}"
        letter="A"
        for entry in "${custom_r[@]}"; do
            IFS='|' read -r name display_name model small marker base_url <<< "$entry"
            local small_str="" route_str=""
            [[ -n "$small" ]] && small_str=" ${DIM}[小模型: $small]${NC}"
            [[ "$name" == "gateway" ]] && route_str=" ${YELLOW}$(read_gateway_routes "$LLMSWITCH_CONF" "$CONFIG_FILE" 2>/dev/null)${NC}"
            echo -e "  ${BOLD_GREEN}2${letter}${NC}  ${display_name} ${DIM}${model}${NC}${small_str}${route_str}"
            item_cat+=("2"); item_letter+=("$letter"); item_name+=("$name")
            case "$letter" in A) letter=B;; B) letter=C;; C) letter=D;; D) letter=E;; E) letter=F;; F) letter=G;; G) letter=H;; H) letter=I;; I) letter=J;; J) letter=K;; K) letter=L;; L) letter=M;; M) letter=N;; N) letter=O;; O) letter=P;; P) letter=Q;; Q) letter=R;; R) letter=S;; S) letter=T;; T) letter=U;; U) letter=V;; V) letter=W;; W) letter=X;; X) letter=Y;; Y) letter=Z;; *) letter=A;; esac
        done

        echo -e "  ${BOLD_GRAY}--llm 配置--${NC}"
        printf "  ${BOLD_GREEN}3A${NC}  %-26s ${DIM}%s${NC}\n" "新增自定义" "输入任意 base_url + model + key"
        printf "  ${BOLD_GREEN}3B${NC}  %-26s ${DIM}%s${NC}\n" "修改自定义" "修改已保存的自定义预设"
        printf "  ${BOLD_GREEN}3C${NC}  %-26s ${DIM}%s${NC}\n" "删除自定义" "删除已保存的自定义预设"
        printf "  ${BOLD_GREEN}3D${NC}  %-26s ${DIM}%s${NC}\n" "Gateway 切换规则" "peak_hours/routes/mode → llmswitch 管理"
        echo ""
        printf "  ${BOLD_GREEN}3E${NC}  %-26s ${DIM}%s${NC}\n" "Bill 模型单价" "配置 token 单价，用于 token-usage 计费"
        echo "  0) 退出"
        printf "  输入 (如 1A, 2B, 3D) 或数字选择: "
        read -r choice

        [[ -z "$choice" || "$choice" == "0" ]] && { info "已退出"; return 0; }

        if [[ "$choice" =~ ^([0-9]+)([A-Za-z])$ ]]; then
            local cat="${BASH_REMATCH[1]}"
            local letter_m="${BASH_REMATCH[2]^^}"
            if [[ "$cat" == "3" ]]; then
                case "$letter_m" in
                    A) switch_custom ;;
                    B) edit_preset ;;
                    C) delete_preset ;;
                    D) bash "$LLMSWITCH_INIT" --config ;;
                    E) bash "$SCRIPT_DIR/init-llm-bill.sh" ;;
                    *) warn "配置: A=新增 B=修改 C=删除 D=Gateway E=Bill"; continue ;;
                esac
                continue
            fi
            for i in "${!item_cat[@]}"; do
                if [[ "${item_cat[$i]}" == "$cat" && "${item_letter[$i]}" == "$letter_m" ]]; then
                    switch_llm "${item_name[$i]}"
                    continue 2
                fi
            done
            warn "未找到 ${cat}${letter_m}"
            continue
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            [[ "$choice" == "3" ]] && { switch_custom; continue; }
            for i in "${!item_cat[@]}"; do
                if [[ "${item_cat[$i]}" == "$choice" ]]; then
                    switch_llm "${item_name[$i]}"
                    continue 2
                fi
            done
            warn "分类 $choice 无 LLM 项"
            continue
        fi

        warn "无效输入: $choice (格式: 1A, 2B, 3C)"
    done
}

# ========== 主流程 ==========
main() {
    local cmd="${1:-${INIT_LLM_NAME:-}}"

    case "$cmd" in
        list)        show_list ;;
        status)      show_status ;;
        test|-t)     test_llm "${2:-}" ;;
        switch)      switch_llm "${2:-}" ;;
        custom|-c)   switch_custom ;;
        delete|-d)   delete_preset "${2:-}" ;;
        bill|pricing|-p) bash "$SCRIPT_DIR/init-llm-bill.sh" "${2:-}" ;;
        sync)        sync_top_model ;;
        heal)
            selfheal_bridge "$CONFIG_FILE" \
                && success "bridge 健康" \
                || error "bridge 自愈失败"
            ;;
        "")          interactive_select ;;
        *)
            if [[ "$cmd" =~ ^b[i1]l[1l]?$ ]] || [[ "$cmd" =~ ^pr[i1]c[i1]ng$ ]]; then
                error "猜你想用 'bill'（账单）？运行: bash init-llm.sh bill"
                return 1
            fi
            switch_llm "$cmd"
            ;;
    esac
}

[[ "${TEST_MODE:-0}" == "1" ]] || main "$@"
