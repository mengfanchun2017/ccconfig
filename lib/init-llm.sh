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

# 内置预设 key（不可删除），须与 conf/llm.json.example 顶层 llms key 一致
BUILTIN_LLMS="minimax deepseek_flash gateway"

# CONFIG_FILE already resolved via resolve_conf() above

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
    # 返回 "高峰 09:00-12:00 → model ｜ 非高峰 → model" 格式的路由摘要
    # $1: llmswitch.json 路径；$2: llm.json 路径（用于路由 key → model 名映射）
    python3 - "${1:-$LLMSWITCH_CONF}" "${2:-$CONFIG_FILE}" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        sw = json.load(f)
except Exception:
    sys.exit(0)

key_to_model = {}
try:
    with open(sys.argv[2]) as f:
        llm_cfg = json.load(f)
    for k, v in llm_cfg.get('llms', {}).items():
        key_to_model[k] = v.get('model', k)
except Exception:
    pass

routes = sw.get('routes', {}).get('llmgateway', {})
peak_key = routes.get('peak', '?')
off_peak_key = routes.get('off_peak', '?')
peak = key_to_model.get(peak_key, peak_key)
off_peak = key_to_model.get(off_peak_key, off_peak_key)
peak_hours = sw.get('peak_hours', [])
blocks = [f"{b['start']}-{b['end']}" for b in peak_hours]
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
    python3 - "$CONFIG_FILE" "$LLMSWITCH_CONF" << 'PYEOF'
import json, sys, os

with open(sys.argv[1], 'r') as f:
    config = json.load(f)

llms = config.get('llms', {})
current = config.get('current', '')

# 读 llmswitch.json 真实 model（gateway 显示用）
sw_model = ''
sw_small = ''
sw_path = sys.argv[2]
if sw_path and os.path.exists(sw_path):
    try:
        with open(sw_path) as f:
            sw = json.load(f)
        sw_model = sw.get('model_name', '')
        sw_small = sw.get('small_model_name', '')
    except Exception:
        pass

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
    # Gateway 占位符替换为 llmswitch.json 真实值
    if name == 'gateway':
        if sw_model:
            model = sw_model
        if sw_small:
            small = sw_small
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

# ~/.claude/settings.json — 写入 env + 顶层 model 字段
# .claude.json 已移除，配置全部由 settings.json 承载
sf = os.path.expanduser("~/.claude/settings.json")
if os.path.islink(sf) and not os.path.exists(sf):
    os.unlink(sf)
model_name = os.environ.get('MODEL_NAME', '')
def updater(d):
    d.setdefault('env', {}).update(env_update)
    if model_name:
        d['model'] = model_name
write_json(sf, updater)
print("~/.claude/settings.json 已更新")
PYEOF

    success "LLM 已切换为: $name"
}

# ========== Custom (临时输入任意 Anthropic-compatible 端点) ==========
# 用法: switch_custom
# 不写 llm.json，不持久化，只切当前会话；可选择后续保存为预设
switch_custom() {
    # dry-run gate: 写操作前必须先预览
    if _dry_run_enabled; then
        echo "  [DRY-RUN] switch_custom: would prompt for URL/model/key and write to llm.json + claude.json + settings.json"
        return 0
    fi
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
    echo "  示例: OpenRouter / 自部署网关"
    echo ""
    local custom_url; custom_url=$(prompt "Base URL")
    [[ -z "$custom_url" ]] && { error "Base URL 不能为空"; return 1; }
    local custom_model; custom_model=$(prompt "Model 名称")
    [[ -z "$custom_model" ]] && { error "Model 名称不能为空"; return 1; }
    local custom_key; custom_key=$(prompt_password "API Key（留空复用当前）")

    # 复用逻辑
    if [[ -z "$custom_key" ]]; then
        custom_key=$(python3 -c "import json,os; print(json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('env',{}).get('ANTHROPIC_AUTH_TOKEN',''))" 2>/dev/null || echo "")
    fi

    echo ""
    if confirm "保存为预设？" y; then
        local save_preset="y"
        local preset_name; preset_name=$(prompt "预设名称")
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

# ========== 切换 LLM ==========
switch_llm() {
    local name="$1"
    if _dry_run_enabled; then
        echo "  [DRY-RUN] switch_llm: would switch to '$name' (write llm.json + claude.json + settings.json)"
        return 0
    fi

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

    local config=$(get_llm_config "$name") || { error "无法获取 LLM 配置: $name"; return 1; }
    IFS='|' read -r base_url model_name api_key small_model <<< "$config"

    # 检查是否有 SSH 隧道配置（内网 LLM 通过跳板机访问）
    local has_tunnel=false
    local tunnel_ssh_host="" tunnel_remote="" tunnel_listen_port=""
    local tunnel_info
    tunnel_info=$(python3 - "$CONFIG_FILE" "$name" << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    llm = d.get('llms', {}).get(sys.argv[2], {})
    t = llm.get('ssh_tunnel', {})
    if t.get('ssh_host') and t.get('remote'):
        print(f"{t['ssh_host']}|{t['remote']}|{t.get('listen_port',8890)}")
    else:
        sys.exit(1)
except:
    sys.exit(1)
PYEOF
) || true
    if [[ -n "$tunnel_info" ]]; then
        IFS='|' read -r tunnel_ssh_host tunnel_remote tunnel_listen_port <<< "$tunnel_info"
        has_tunnel=true
    fi

    # 切到直连前先停 watchdog + proxy + ssh 隧道（如果之前是隧道模式）
    if is_ssh_tunnel_running; then
        stop_ssh_tunnel
    fi
    if is_proxy_running; then
        info "停止网关代理..."
        local watchdog_pid_file="$HOME/.cache/llmswitch-watchdog.pid"
        if [ -f "$watchdog_pid_file" ]; then
            kill "$(cat "$watchdog_pid_file")" 2>/dev/null || true
            rm -f "$watchdog_pid_file"
        fi
        bash "$LLMSWITCH_INIT" --stop 2>/dev/null || true
    fi

    # SSH 隧道模式：先启隧道，再启 bridge 转发到本地端口
    if $has_tunnel; then
        info "检测到 SSH 隧道配置: $tunnel_ssh_host → $tunnel_remote"
        start_ssh_tunnel "$tunnel_ssh_host" "$tunnel_remote" "$tunnel_listen_port" || {
            error "SSH 隧道启动失败"
            return 1
        }
        # SSH 隧道转发到远程端点，bridge 指向本地隧道端口做 Anthropic↔OpenAI 转换
        info "  启用 Anthropic↔OpenAI bridge (upstream: http://127.0.0.1:$tunnel_listen_port)"
        if ensure_bridge "http://127.0.0.1:${tunnel_listen_port}" "$model_name" "$api_key"; then
            base_url="http://127.0.0.1:8898"
            info "  Bridge 已就绪，base_url → $base_url"
        else
            error "  bridge 启动失败"
            stop_ssh_tunnel
            return 1
        fi
    # 检测 OpenAI-only 端点（不是 Anthropic compatible），自动启 bridge + 改写 base_url
    elif [[ "$base_url" != *"/anthropic"* ]] && [[ "$base_url" != *"://127.0.0.1"* ]]; then
        info "  检测到 OpenAI-only 端点，自动启用 Anthropic↔OpenAI bridge..."
        if ensure_bridge "$base_url" "$model_name" "$api_key"; then
            base_url="http://127.0.0.1:8898"
            info "  Bridge 已就绪，base_url → $base_url"
        else
            error "  bridge 启动失败，请检查 ~/.cache/openai_bridge.log"
            return 1
        fi
    else
        # 切到直连/本地端点，bridge 无需求 → 关残留进程
        if pgrep -f "openai_bridge.py" >/dev/null 2>&1; then
            info "  切换目标不需要 bridge，关闭残留 openai_bridge 进程..."
            pkill -f "openai_bridge.py" 2>/dev/null || true
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
            echo ""; api_key=$(prompt_password "输入 ${name} API Key")
        fi
    fi

    info "切换到: $name"
    _write_llm_config "$name" "$base_url" "$model_name" "$small_model" "$api_key"
}

switch_to_gateway() {
    info "切换到 Gateway 模式"

    # 确保 llmswitch.json 存在，没有则从模板复制
    if [ ! -f "$LLMSWITCH_CONF" ]; then
        if [ -f "$LLMSWITCH_CONF.example" ]; then
            info "配置不存在，从模板初始化..."
            cp "$LLMSWITCH_CONF.example" "$LLMSWITCH_CONF"
            success "配置文件已创建: $LLMSWITCH_CONF"
        else
            error "配置模板不存在: $LLMSWITCH_CONF.example"
            return 1
        fi
    fi

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

    # 从 llmswitch.json 读取真实模型名（替换 llm.json 占位符）
    local gw_model=$(python3 -c "import json; print(json.load(open('$LLMSWITCH_CONF')).get('model_name','llmgateway'))" 2>/dev/null || echo "llmgateway")
    local gw_small=$(python3 -c "import json; print(json.load(open('$LLMSWITCH_CONF')).get('small_model_name',''))" 2>/dev/null || echo "")
    [ -z "$gw_small" ] && gw_small="$gw_model"

    # 从 llm.json 读 base_url（gateway entry 存的就是本地 proxy URL）
    local base_url=$(get_llm_config "gateway" | cut -d'|' -f1) || { error "无法获取 Gateway 配置"; return 1; }

    # 用真实模型名写入 env
    _write_llm_config "gateway" "$base_url" "$gw_model" "$gw_small" ""

    local summary=$(get_gateway_status_one_liner)
    success "Gateway 已切换 ($gw_model) $summary"
}

# ========== 状态诊断 ==========
# 一次性整合 llm.json / env / settings.json / 进程 四个数据源
# 用途: 用户问"我现在到底用的哪个模型"时跑一次
show_status() {
    local llm_current=$(python3 -c "
import json
try:
    with open('${CONFIG_FILE}') as f: d = json.load(f)
    print(d.get('current',''))
except: pass
" 2>/dev/null)

    local sett_env=$(python3 -c "
import json, os
p = os.path.expanduser('~/.claude/settings.json')
try:
    with open(p) as f: d = json.load(f)
    e = d.get('env', {})
    print(f\"{e.get('ANTHROPIC_BASE_URL','')}|{e.get('ANTHROPIC_MODEL','')}|{e.get('ANTHROPIC_AUTH_TOKEN','')}\")
except: print('||')
" 2>/dev/null)
    local sett_model=$(python3 -c "
import json, os
p = os.path.expanduser('~/.claude/settings.json')
try:
    with open(p) as f: d = json.load(f)
    print(d.get('model',''))
except: pass
" 2>/dev/null)

    echo ""
    info "── LLM 状态诊断 ──"
    printf "  llm.json current          : %s\n" "${llm_current:-<未设置>}"
    if [[ -n "$sett_env" ]]; then
        IFS='|' read -r base model tok <<< "$sett_env"
        printf "  env.ANTHROPIC_BASE_URL    : %s\n" "${base:-<未设置>}"
        printf "  env.ANTHROPIC_MODEL       : %s   (下次请求实际生效)\n" "${model:-<未设置>}"
        if [[ -n "$tok" ]]; then
            printf "  env.ANTHROPIC_AUTH_TOKEN  : ...%s\n" "${tok: -4}"
        fi
    fi
    printf "  settings 顶层 model       : %s   (session 启动时锁定, 只读参考)\n" "${sett_model:-<未设置>}"

    # 桥接诊断
    if [[ "$sett_env" == *"://127.0.0.1:8898"* ]]; then
        local h=$(curl -s --max-time 2 "http://127.0.0.1:8898/health" 2>/dev/null)
        if [[ -n "$h" ]]; then
            local up=$(echo "$h" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('upstream','?')+'|'+d.get('upstream_model','?'))" 2>/dev/null)
            IFS='|' read -r up_base up_model <<< "$up"
            info "  bridge (port 8898)       : ✓ upstream=$up_base model=$up_model"
        else
            error "  bridge (port 8898)       : ✗ 未响应 (env 指向 8898 但 bridge 没起)"
        fi
    elif is_proxy_running; then
        info "  网关代理                  : $(get_gateway_status_one_liner)"
    fi

    # 一致性检查
    echo ""
    # 一致性: model 是 env 真值, base_url 在 OpenAI-only 端点下会被 bridge 改写属正常
    local preset_state="N"
    if [[ -n "$llm_current" && -n "$sett_env" ]]; then
        IFS='|' read -r env_base env_model _ <<< "$sett_env"
        preset_state=$(python3 - "$CONFIG_FILE" "$llm_current" "$env_base" "$env_model" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f: d = json.load(f)
    llm = d.get('llms', {}).get(sys.argv[2], {})
    if not llm or llm.get('model','') != sys.argv[4]:
        print('N'); sys.exit(0)
    pb, eb = llm.get('base_url',''), sys.argv[3]
    # 直连: base_url 必须等; bridge: preset 是 OpenAI-only 端点, env 是 127.0.0.1:8898
    if pb == eb:
        print('Y')
    elif pb and '/anthropic' not in pb and '127.0.0.1' not in pb and eb == 'http://127.0.0.1:8898':
        print('B')  # bridge 改写后一致
    else:
        print('N')
except: print('N')
PYEOF
)
    fi
    case "$preset_state" in
        Y) success "  三处配置一致" ;;
        B) info "  bridge 改写后一致 (preset=$llm_current → 127.0.0.1:8898)" ;;
        N) warn "  注意: llm.json current=$llm_current 与 env 不一致, 建议重新跑一次 init-llm" ;;
    esac
    echo ""
}

# ========== 测试连接（非破坏性） ==========
# 读 llm.json 预设的 base_url/model/key，curl 端点发最小请求验证 200
# 不写 ~/.claude.json / settings.json，不影响全局
test_llm() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        error "用法: bash init-llm.sh test <preset-name>"
        return 1
    fi

    local config=$(get_llm_config "$target") || { error "无法获取 LLM 配置: $target"; return 1; }
    IFS='|' read -r base_url model_name api_key small_model <<< "$config"

    if [[ -z "$api_key" ]] || echo "$api_key" | grep -qE '请填入|请替换|your.key|placeholder|changeme|<your-'; then
        error "预设 '$target' 无有效 API Key（占位符或空）"
        return 1
    fi

    info "测试: $target"
    info "  base_url: $base_url"
    info "  model: $model_name"
    info "  key: ...${api_key: -4}"

    local body_file=$(mktemp)
    local status

    # OpenAI-only 端点用 /chat/completions 协议
    if [[ "$base_url" != *"/anthropic"* ]] && [[ "$base_url" != *"://127.0.0.1"* ]]; then
        info "  协议: OpenAI /chat/completions"
        status=$(curl -s --max-time 30 -o "$body_file" -w "%{http_code}" \
            -X POST "${base_url%/}/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $api_key" \
            -d "{\"model\":\"$model_name\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
    else
        info "  协议: Anthropic /v1/messages"
        status=$(curl -s --max-time 30 -o "$body_file" -w "%{http_code}" \
            -X POST "${base_url%/}/v1/messages" \
            -H "Content-Type: application/json" \
            -H "anthropic-version: 2023-06-01" \
            -H "Authorization: Bearer $api_key" \
            -d "{\"model\":\"$model_name\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
    fi

    echo ""
    if [[ "$status" == "200" ]]; then
        success "✓ HTTP 200 — 预设 '$target' 可用"
        python3 -c "
import json
try:
    d = json.load(open('$body_file'))
    if 'model' in d:
        print(f\"  返回 model: {d.get('model','?')} | stop: {d.get('stop_reason', d.get('choices',[{}])[0].get('finish_reason','?'))}\")
    else:
        print(f\"  响应: {str(d)[:200]}\")
except: pass
" 2>/dev/null || true
        rm -f "$body_file"
        return 0
    else
        error "✗ HTTP $status"
        echo "  响应:"
        head -5 "$body_file" | sed 's/^/    /'
        rm -f "$body_file"
        return 1
    fi
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
            route_info="  — $(read_gateway_routes "$LLMSWITCH_CONF" "$CONFIG_FILE")"
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
# ========== Bill (Pricing 配置) ==========
# 从 llm.json 的 llms.* 自动读 model 名作为可选列表
# 排除 gateway 占位符（<your-gateway-model>）—— gateway 也路由到上面的模型
# 4 个独立字段：input / output / cache_read / cache_creation
# cache_creation 缺省 = input × 1.25（Anthropic 标准）
# deepseek/MiniMax 等 OpenAI 兼容端点没有 cache_creation，留空或 0
# 用法: bill_config [model_name]   不带参：交互菜单（循环直到 0 退出）
bill_config() {
    local target="${1:-}"

    # 从 llm.json 读 llms.*.model 字段，去重保序，排除 gateway 占位符
    local models_json
    models_json="$(python3 - "$CONFIG_FILE" << 'PYEOF' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except: sys.exit(0)
seen = []
for k, v in d.get('llms', {}).items():
    if k == 'gateway':
        continue  # gateway 路由到上游模型，无独立价格
    m = v.get('model', '')
    if m and m not in seen:
        seen.append(m)
# 加上已在 pricing 但不在 llms 的孤儿（删 model 后残留）
for m in d.get('pricing', {}).keys():
    if m and m not in seen:
        seen.append(m)
print(json.dumps(seen, ensure_ascii=False))
PYEOF
)"

    # 循环直到用户输 0 返回
    while true; do
        echo ""
        echo "═══ Bill (模型 token 单价, CNY ¥ / 1M tokens) ═══"
        echo ""

        # 展示已配价格 + 模型列表（标 ✓=已配）
        python3 - "$CONFIG_FILE" "$models_json" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
models = json.loads(sys.argv[2])
pricing = d.get("pricing", {})
print("  模型列表（✓=已配价格）:")
for i, m in enumerate(models, 1):
    mark = "✓" if m in pricing else " "
    print(f"    {i:>2}) [{mark}] {m}")
print()
if pricing:
    print("  ── 当前价格 ──")
    for m, v in pricing.items():
        print(f"    {m}:")
        print(f"      input=¥{v.get('input', 0)}/1M  output=¥{v.get('output', 0)}/1M  cache_read=¥{v.get('cache_read', 0)}/1M", end="")
        cc = v.get('cache_creation')
        if cc is not None:
            print(f"  cache_creation=¥{cc}/1M")
        else:
            print(f"  cache_creation=(默认=input×1.25)")
PYEOF

        if [[ -n "$target" ]]; then
            _bill_set "$target"
            target=""
            continue
        fi

        echo ""
        local op; op=$(menu_select "操作" \
            "a) 添加/修改" "d) 删除" "0) 返回")
        [[ -z "$op" ]] && continue

        case "${op:0:1}" in
            a|A)
                local sel; sel=$(prompt "模型序号或名称")
                local model; model=$(python3 - "$models_json" "$sel" << 'PYEOF'
import json, sys
models = json.loads(sys.argv[1])
sel = sys.argv[2].strip()
if sel.isdigit() and 1 <= int(sel) <= len(models):
    print(models[int(sel) - 1])
elif sel in models:
    print(sel)
else:
    sys.exit(1)
PYEOF
)
                if [[ -z "$model" ]]; then
                    error "无效选择: $sel"
                    continue
                fi
                _bill_set "$model"
                ;;
            d|D)
                local sel; sel=$(prompt "模型序号或名称")
                local model; model=$(python3 - "$models_json" "$sel" << 'PYEOF'
import json, sys
models = json.loads(sys.argv[1])
sel = sys.argv[2].strip()
if sel.isdigit() and 1 <= int(sel) <= len(models):
    print(models[int(sel) - 1])
elif sel in models:
    print(sel)
else:
    sys.exit(1)
PYEOF
)
                if [[ -z "$model" ]]; then
                    error "无效选择: $sel"
                    continue
                fi
                _bill_del "$model"
                ;;
            0) return 0 ;;
            *) error "无效选择" ;;
        esac
    done
}

_bill_set() {
    local model="$1"
    [[ -z "$model" ]] && { warn "模型名不能为空"; return 1; }
    echo ""
    echo "为 '$model' 输入价格 (CNY ¥ / 1M tokens)，留空跳过："
    local in_v; in_v=$(prompt "input  单价"); in_v="${in_v:-0}"
    local out_v; out_v=$(prompt "output 单价"); out_v="${out_v:-0}"
    local cr_v; cr_v=$(prompt "cache_read 单价"); cr_v="${cr_v:-0}"
    local cc_v; cc_v=$(prompt "cache_creation 单价（默认 = input×1.25）")
    python3 - "$CONFIG_FILE" "$model" "$in_v" "$out_v" "$cr_v" "$cc_v" << 'PYEOF'
import json, sys
path, model, in_v, out_v, cr_v, cc_v = sys.argv[1:7]
with open(path) as f: d = json.load(f)
if "pricing" not in d: d["pricing"] = {}
entry = {"input": float(in_v), "output": float(out_v), "cache_read": float(cr_v)}
if cc_v.strip(): entry["cache_creation"] = float(cc_v)
d["pricing"][model] = entry
with open(path, "w") as f: json.dump(d, f, indent=4, ensure_ascii=False)
print(f"OK: {model} 已保存")
PYEOF
}

_bill_del() {
    local model="$1"
    python3 - "$CONFIG_FILE" "$model" << 'PYEOF'
import json, sys
path, model = sys.argv[1:3]
with open(path) as f: d = json.load(f)
if d.get("pricing", {}).pop(model, None) is not None:
    with open(path, "w") as f: json.dump(d, f, indent=4, ensure_ascii=False)
    print(f"OK: {model} 已删除")
else:
    print(f"NOT_FOUND: {model}")
PYEOF
}

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
        if [[ " $BUILTIN_LLMS " == *" $name "* ]]; then
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
    local choice; choice=$(menu_select "选择要删除的预设" "${deletable_names[@]}")
    [[ -z "$choice" ]] && { info "已取消"; return 0; }
    target="$choice"
    for ((di=0; di<${#deletable_names[@]}; di++)); do
        [[ "${deletable_names[$di]}" == "$choice" ]] && { target="$choice"; break; }
    done
    _delete_preset_confirm "$target"
}

_delete_preset_confirm() {
    local target="$1"

    # 守卫 1: 内置
    if [[ " $BUILTIN_LLMS " == *" $target "* ]]; then
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

    confirm "确认删除预设 '$target'？" n || { info "已取消"; return 0; }

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
            route_str="  — $(read_gateway_routes "$LLMSWITCH_CONF" "$CONFIG_FILE")"
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

    # Custom + Delete + Configure Gateway + Bill 是固定选项
    local custom_idx=$((selectable + 1))
    local delete_idx=$((selectable + 2))
    local gateway_conf_idx=$((selectable + 3))
    local bill_idx=$((selectable + 4))
    printf "  %d) %s\n" "$custom_idx" "Custom (输入任意 base_url + model + key)"
    printf "  %d) %s\n" "$delete_idx" "Delete (删除已保存的自定义预设)"
    printf "  %d) %s\n" "$gateway_conf_idx" "Configure Gateway (peak_hours / routes / mode)"
    printf "  %d) %s\n" "$bill_idx" "Bill (配置模型 token 单价，用于 token-usage 计费)"

    echo ""
    printf "输入数字 [1-%d] 选择（直接回车保持当前 (%s)): " "$bill_idx" "$current"
    read -r choice

    if [[ -z "$choice" ]]; then
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

    if [[ "$choice" == "$bill_idx" ]]; then
        bill_config
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
    elif [[ "$cmd" == "status" ]]; then
        show_status
    elif [[ "$cmd" == "test" ]] || [[ "$cmd" == "-t" ]]; then
        # 第二参数：要测试的预设名
        test_llm "${2:-}"
    elif [[ "$cmd" == "custom" ]] || [[ "$cmd" == "-c" ]]; then
        switch_custom
    elif [[ "$cmd" == "delete" ]] || [[ "$cmd" == "-d" ]]; then
        # 可选第二参数：要删的预设名
        delete_preset "${2:-}"
    elif [[ "$cmd" == "bill" ]] || [[ "$cmd" == "pricing" ]] || [[ "$cmd" == "-p" ]]; then
        # 配置模型价格（option-usage 计费用）
        bill_config "${2:-}"
    elif [[ -z "$cmd" ]]; then
        # 无参数：交互式选择
        interactive_select
    else
        # 直接指定 LLM 名称（或从 INIT_LLM_NAME env 读取）
        # 拼写保护：接近 "bill"/"pricing" 的拼错字提示而不是切 LLM
        if [[ "$cmd" =~ ^b[i1]l[1l]?$ ]] || [[ "$cmd" =~ ^pr[i1]c[i1]ng$ ]]; then
            error "猜你想用 'bill'（账单/计费配置）？运行: bash init-llm.sh bill"
            return 1
        fi
        switch_llm "$cmd"
    fi
}

# TEST_MODE=1 时 source 不执行 main（供单元测试加载函数）
[[ "${TEST_MODE:-0}" == "1" ]] || main "$@"