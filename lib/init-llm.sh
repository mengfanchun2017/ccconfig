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
print(f"高峰 {','.join(blocks)}→{peak}, 非高峰→{off_peak}")
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

# ========== SSH 隧道管理（Tailscale → 跳板机 → 内网 LLM）==========
# tmux 持久化：Claude 退出后 SSH 隧道 + bridge 继续运行
TUNNEL_TMUX_SESSION="altllm-tunnel"
BRIDGE_TMUX_SESSION="altllm-bridge"
SSH_TUNNEL_LOG_FILE="$HOME/.cache/ssh-tunnel.log"

is_ssh_tunnel_running() {
    tmux has-session -t "$TUNNEL_TMUX_SESSION" 2>/dev/null
}

# $1: host (Tailscale IP)  $2: port (SSH 端口)  $3: user (SSH 用户)  $4: remote (host:port)  $5: listen_port (local)
start_ssh_tunnel() {
    local host="$1" port="$2" user="$3" remote="$4" listen_port="$5"
    [[ -z "$host" || -z "$remote" ]] && { error "SSH 隧道参数缺失: host=$host remote=$remote"; return 1; }

    # 检测 Windows Tailscale 服务是否运行
    if command -v powershell.exe &>/dev/null; then
        local ts_status=$(powershell.exe -NoProfile -Command "(Get-Service -Name Tailscale -ErrorAction SilentlyContinue).Status" 2>/dev/null | tr -d '\r' || echo "Stopped")
        if [[ "$ts_status" != "Running" ]]; then
            error "Windows Tailscale 服务未运行 ($ts_status)，请启动 Tailscale 客户端"
            return 1
        fi
        info "  Windows Tailscale: Running"
    fi

    if is_ssh_tunnel_running; then
        local listen_port_display=$(tmux capture-pane -t "$TUNNEL_TMUX_SESSION" -p 2>/dev/null | tail -3 | grep -oP 'localhost:\K\d+' | head -1 || echo "$listen_port")
        info "SSH 隧道已在运行 (tmux: $TUNNEL_TMUX_SESSION, port: $listen_port_display)"
        return 0
    fi

    # 构建 SSH 连接串
    local ssh_target="$host"
    [[ -n "$user" ]] && ssh_target="${user}@${host}"
    local port_opt=""
    [[ -n "$port" && "$port" != "22" ]] && port_opt="-p $port"

    info "启动 SSH 隧道: ${user}@${host}:${port} → localhost:${listen_port} → ${remote}"

    # 先清可能残留的 stderr 日志
    : > "$SSH_TUNNEL_LOG_FILE"

    # 确保 ssh-agent 运行 + key 已加载
    # tmux 内 ssh 需要访问 agent socket。让 tmux 继承当前 shell 的 SSH_AUTH_SOCK
    if ! ssh-add -l &>/dev/null; then
        if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
            info "  ssh-agent 未运行，自动启动并加载 key..."
            eval $(ssh-agent -s) &>/dev/null || { error "ssh-agent 启动失败"; return 1; }
            export SSH_AUTH_SOCK SSH_AGENT_PID
            ssh-add "$HOME/.ssh/id_ed25519" &>/dev/null || {
                error "ssh key 加载失败，检查 ~/.ssh/id_ed25519 权限"
                return 1
            }
            info "  ssh-agent: PID=$SSH_AGENT_PID, key 已加载"
        else
            error "未找到 ~/.ssh/id_ed25519，无法建立 SSH 隧道"
            return 1
        fi
    fi

    # 在 tmux 中启动 SSH 隧道，继承当前 SSH_AUTH_SOCK
    # detached + pipe stderr to log so we can diagnose failures
    tmux new-session -d -s "$TUNNEL_TMUX_SESSION" \
        "env SSH_AUTH_SOCK='${SSH_AUTH_SOCK:-}' \
         ssh -NL '${listen_port}:${remote}' ${port_opt} '${ssh_target}' \
            -o ExitOnForwardFailure=yes \
            -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 \
            -o TCPKeepAlive=yes \
            -o StrictHostKeyChecking=accept-new \
            -o UserKnownHostsFile=/dev/null \
            2>> '$SSH_TUNNEL_LOG_FILE'" 2>&1

    sleep 2
    if ! is_ssh_tunnel_running; then
        error "SSH 隧道 tmux session 已退出，查看日志: $SSH_TUNNEL_LOG_FILE"
        return 1
    fi

    local retries=10
    while (( retries > 0 )); do
        # 用 ss 验证端口监听（不依赖 pid，tmux 下 ssh 进程可能不在当前 session 可见）
        if ss -tlnp 2>/dev/null | grep -q ":$listen_port "; then
            info "  SSH 隧道就绪: localhost:$listen_port → $remote ($host) [tmux: $TUNNEL_TMUX_SESSION]"
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done

    error "端口 $listen_port 未被监听，SSH 隧道未就绪"
    tmux send-keys -t "$TUNNEL_TMUX_SESSION" "C-c" 2>/dev/null || true
    tmux kill-session -t "$TUNNEL_TMUX_SESSION" 2>/dev/null || true
    return 1
}

stop_ssh_tunnel() {
    if ! is_ssh_tunnel_running; then
        info "SSH 隧道未运行"
        return 0
    fi
    info "停止 SSH 隧道 (tmux: $TUNNEL_TMUX_SESSION)..."
    tmux send-keys -t "$TUNNEL_TMUX_SESSION" "C-c" 2>/dev/null || true
    sleep 1
    tmux kill-session -t "$TUNNEL_TMUX_SESSION" 2>/dev/null || true
    info "SSH 隧道已停止"
}

get_ssh_tunnel_status_one_liner() {
    if ! is_ssh_tunnel_running; then
        echo "未运行"
        return
    fi
    local listen_port=$(ss -tlnp 2>/dev/null | grep "127.0.0.1:" | awk '{print $4}' | cut -d: -f2 | head -1 || echo "?")
    echo "tmux:$TUNNEL_TMUX_SESSION port:$listen_port"
}

# 隧道场景也停 bridge（tmux session 方式）
stop_tmux_bridge() {
    if tmux has-session -t "$BRIDGE_TMUX_SESSION" 2>/dev/null; then
        info "停止 bridge (tmux: $BRIDGE_TMUX_SESSION)..."
        tmux send-keys -t "$BRIDGE_TMUX_SESSION" "C-c" 2>/dev/null || true
        sleep 1
        tmux kill-session -t "$BRIDGE_TMUX_SESSION" 2>/dev/null || true
    fi
    # 也清可能残留的 direct bridge 进程
    if pgrep -f "openai_bridge.py" >/dev/null 2>&1; then
        pkill -f "openai_bridge.py" 2>/dev/null || true
        sleep 1
    fi
}

# SSH 隧道场景的 bridge 启动——绕开 _bridge_supported 对 127.0.0.1 的排除
# tmux 持久化：独立于 Claude 进程
# $1: tunnel_listen_port  $2: model_name  $3: api_key
start_tunnel_bridge() {
    local tunnel_port="$1" model="$2" key="$3"
    local bridge_port=8898

    # 关残留 bridge（tmux 或 direct 都清）
    stop_tmux_bridge

    local env_args="-u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy"
    cd "$CCCONFIG_ROOT"

    tmux new-session -d -s "$BRIDGE_TMUX_SESSION" \
        "cd '$CCCONFIG_ROOT' && \
         env $env_args \
            OPENAI_BRIDGE_UPSTREAM='https://127.0.0.1:${tunnel_port}' \
            OPENAI_BRIDGE_UPSTREAM_ORIGINAL='https://127.0.0.1:${tunnel_port}' \
            OPENAI_BRIDGE_KEY='$key' \
            OPENAI_BRIDGE_MODEL='$model' \
            OPENAI_BRIDGE_SKIP_TLS_VERIFY=1 \
            python3 option-llmswitch/openai_bridge.py --port '$bridge_port' \
         2>&1 | tee '$HOME/.cache/openai_bridge.log'" 2>&1

    local health=""
    for i in 1 2 3 4 5; do
        sleep 1
        health=$(curl -s --max-time 2 "http://127.0.0.1:${bridge_port}/health" 2>/dev/null)
        [[ -n "$health" ]] && break
    done

    [[ -n "$health" ]]
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
key = llm.get('key', '')
# altllm_tail 的 key 为空时从 altllm 继承（消除重复配置）
if target == 'altllm_tail' and (not key or key in ['请填入', '请替换', 'your.key', 'placeholder', 'changeme', '<your-']):
    src = llms.get('altllm', {})
    key = src.get('key', key)
print(f"{llm.get('base_url', '')}|{llm.get('model', '')}|{key}|{small}")
PYEOF
}

# ========== 切换前 snapshot / 回滚 ==========
# 切完探测 endpoint 失败时回滚到上一个 working 状态
# 解决"切完不知道能不能用"——尤其 VPN/防火墙拦截场景
LLM_SWITCH_SNAPSHOT_DIR="$HOME/.cache/llm-switch-snapshot"

_snapshot_config() {
    mkdir -p "$LLM_SWITCH_SNAPSHOT_DIR"
    cp "$HOME/.claude/settings.json" "$LLM_SWITCH_SNAPSHOT_DIR/settings.json.bak" 2>/dev/null || true
    cp "$CONFIG_FILE" "$LLM_SWITCH_SNAPSHOT_DIR/llm.json.bak" 2>/dev/null || true
}

_rollback_config() {
    if [[ -f "$LLM_SWITCH_SNAPSHOT_DIR/settings.json.bak" ]]; then
        cp "$LLM_SWITCH_SNAPSHOT_DIR/settings.json.bak" "$HOME/.claude/settings.json"
        info "  已回滚 ~/.claude/settings.json"
    fi
    if [[ -f "$LLM_SWITCH_SNAPSHOT_DIR/llm.json.bak" ]]; then
        cp "$LLM_SWITCH_SNAPSHOT_DIR/llm.json.bak" "$CONFIG_FILE"
        info "  已回滚 conf/llm.json"
    fi
}

# 探测切换后的 endpoint，给清晰错误（VPN/防火墙/bridge 死/鉴权失败区分开）
# 返回 0=通过 1=不可达（应回滚）
_verify_endpoint() {
    local name="$1" base_url="$2" model_name="$3" api_key="$4"

    # 占位符 key 跳过探测（用户还没填 key 时不应该报错）
    [[ -z "$api_key" ]] && return 0
    if echo "$api_key" | grep -qE '请填入|请替换|your.key|placeholder|changeme|<your-'; then
        return 0
    fi

    # 本地 bridge：先看 /health 再 probe /v1/messages（让 bridge 转发到 upstream）
    # 仅探 /health 不够——bridge 活着不代表 upstream 可达
    if [[ "$base_url" == *"://127.0.0.1"* ]]; then
        local port="${base_url##*:}"; port="${port%%/*}"
        local h=$(curl -s --max-time 3 "http://127.0.0.1:${port}/health" 2>/dev/null)
        if [[ -z "$h" ]]; then
            error "  ✗ 本地 bridge (port $port) 无响应 — bridge 进程可能挂了"
            return 1
        fi
        # 真实 probe：bridge → upstream 全链路
        # 注意：curl timeout 时 -w "%{http_code}" 仍输出 "000"（拼 || echo "000" 会变 "000000"）
        local upstream_status
        upstream_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
            -X POST "${base_url%/}/v1/messages" \
            -H "Content-Type: application/json" \
            -H "anthropic-version: 2023-06-01" \
            -H "Authorization: Bearer $api_key" \
            -d "{\"model\":\"$model_name\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" 2>/dev/null)
        [[ -z "$upstream_status" || "$upstream_status" =~ ^0+$ ]] && upstream_status="000"
        case "$upstream_status" in
            200) info "  ✓ bridge → upstream 探测成功 ($name)"; return 0 ;;
            000|502|503|504)
                error "  ✗ bridge 上游不可达 (HTTP $upstream_status) — VPN/防火墙可能拦了 upstream"
                error "    检查: tail -20 ~/.cache/openai_bridge.log"
                return 1
                ;;
            401|403|400)
                # bridge 把请求成功转发到了 upstream，upstream 返回鉴权/参数错误
                # 说明链路通，仅 key/model 不匹配 — 切 LLM 是成功的，不回滚
                info "  ✓ bridge → upstream 链路通 ($upstream_status — key/model 需核对)"
                return 0
                ;;
            *)
                warn "  ⚠ bridge 转发返回 HTTP $upstream_status（不回滚）"
                return 0
                ;;
        esac
    fi

    # 选协议
    local probe_path
    if [[ "$base_url" == *"/anthropic"* ]]; then
        probe_path="${base_url%/}/v1/messages"
    else
        probe_path="${base_url%/}/chat/completions"
    fi

    local body="{\"model\":\"$model_name\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
    local headers=(-H "Content-Type: application/json" -H "Authorization: Bearer $api_key")
    [[ "$probe_path" == *"/v1/messages" ]] && headers+=(-H "anthropic-version: 2023-06-01")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
        -X POST "$probe_path" "${headers[@]}" \
        -d "$body" 2>/dev/null)
    [[ -z "$status" || "$status" =~ ^0+$ ]] && status="000"

    case "$status" in
        200)
            info "  ✓ endpoint 探测成功 ($name)"
            return 0
            ;;
        000)
            error "  ✗ endpoint 不可达 (连接超时/拒绝) — 可能是 VPN/防火墙拦截 $base_url"
            error "    提示: 公司 VPN 可能拦了 minimaxi.com / deepseek.com 等公网 API"
            error "    验证: curl -v --max-time 5 $probe_path"
            return 1
            ;;
        401|403)
            warn "  ⚠ HTTP $status — endpoint 可达但鉴权失败（key 问题，不回滚）"
            return 0
            ;;
        404)
            error "  ✗ HTTP 404 — 路径不存在 ($probe_path)"
            return 1
            ;;
        *)
            warn "  ⚠ HTTP $status — endpoint 返回非 200（不回滚）"
            return 0
            ;;
    esac
}

# ========== 写配置（直连 + gateway 共用） ==========
# $1: name  $2: base_url  $3: model  $4: small_model  $5: api_key (optional)
_write_llm_config() {
    local name="$1" base_url="$2" model_name="$3" small_model="$4" api_key="${5:-}"

    # 切换前 snapshot，探测失败时回滚
    _snapshot_config

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

    # 验证 endpoint 可达性（探测失败则回滚到切换前状态）
    if ! _verify_endpoint "$name" "$base_url" "$model_name" "$api_key"; then
        _rollback_config
        return 1
    fi

    # 同步 settings.json 顶层 model 为 env.ANTHROPIC_MODEL（覆盖 /model 污染）
    # 自动跑，用户无需手动 sync；只在切换成功时才同步
    sync_llm_config
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
        altllm_tail)
            local tconfig=$(get_llm_config "$name") || { error "无法获取 altllm_tail 配置"; return 1; }
            IFS='|' read -r _ tmodel tkey tsmall <<< "$tconfig"
            # SSH 隧道配置从 llm.json 解析
            local tail_cfg
            tail_cfg=$(python3 - "$CONFIG_FILE" << 'TAILPY'
import json, sys
d = json.load(open(sys.argv[1]))
t = d.get('llms',{}).get('altllm_tail',{}).get('ssh_tunnel',{})
host = t.get('host') or t.get('ssh_host','')
if host and t.get('remote'):
    print(f"{host}|{t.get('port',22)}|{t.get('user','')}|{t['remote']}")
else:
    sys.exit(1)
TAILPY
            ) || { error "altllm_tail SSH 隧道配置不完整"; return 1; }
            IFS='|' read -r thost tport tuser tremote <<< "$tail_cfg"
            # altllm_tail 走独立链路脚本（Tailscale → SSH 隧道 → tail bridge）
            source "$CCCONFIG_ROOT/lib/tail-llm.sh"
            if tail_start "$thost" "$tport" "$tuser" "$tremote" "$tmodel" "$tkey"; then
                info "altllm_tail 链路就绪，写入配置..."
                _write_llm_config "$name" "http://127.0.0.1:8895" "$tmodel" "$tsmall" "$tkey"
                success "LLM 已切换为: $name"
                return 0
            else
                error "altllm_tail 链路启动失败"
                return 1
            fi
            ;;
    esac

    local config=$(get_llm_config "$name") || { error "无法获取 LLM 配置: $name"; return 1; }
    IFS='|' read -r base_url model_name api_key small_model <<< "$config"

    # 检查是否有 SSH 隧道配置（Tailscale → 跳板机 → 内网 LLM）
    local has_tunnel=false
    local tunnel_host="" tunnel_port="" tunnel_user="" tunnel_remote="" tunnel_listen_port=""
    local tunnel_info
    tunnel_info=$(python3 - "$CONFIG_FILE" "$name" << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    llm = d.get('llms', {}).get(sys.argv[2], {})
    t = llm.get('ssh_tunnel', {})
    host = t.get('host') or t.get('ssh_host', '')
    if host and t.get('remote'):
        print(f"{host}|{t.get('port',22)}|{t.get('user','')}|{t['remote']}|{t.get('listen_port',8890)}")
    else:
        sys.exit(1)
except:
    sys.exit(1)
PYEOF
) || true
    if [[ -n "$tunnel_info" ]]; then
        IFS='|' read -r tunnel_host tunnel_port tunnel_user tunnel_remote tunnel_listen_port <<< "$tunnel_info"
        has_tunnel=true
    fi

    # 旧链路清理函数（新链路就绪后调用）
    _stop_old_link() {
        if is_ssh_tunnel_running; then
            info "停止旧 SSH 隧道..."
            stop_ssh_tunnel
        fi
        stop_tmux_bridge
        if is_proxy_running; then
            info "停止旧网关代理..."
            local wpid="$HOME/.cache/llmswitch-watchdog.pid"
            if [ -f "$wpid" ]; then
                kill "$(cat "$wpid")" 2>/dev/null || true
                rm -f "$wpid"
            fi
            bash "$LLMSWITCH_INIT" --stop 2>/dev/null || true
        fi
    }

    local need_stop_old=true

    # SSH 隧道模式：先启隧道，再启 bridge 转发到本地端口
    if $has_tunnel; then
        info "检测到 SSH 隧道配置: ${tunnel_user}@${tunnel_host}:${tunnel_port} → ${tunnel_remote}"
        # 端口冲突检测：新旧 tunnel 同端口时需先停旧
        if is_ssh_tunnel_running && ss -tlnp 2>/dev/null | grep -q ":$tunnel_listen_port "; then
            _stop_old_link
            need_stop_old=false
        fi
        start_ssh_tunnel "$tunnel_host" "$tunnel_port" "$tunnel_user" "$tunnel_remote" "$tunnel_listen_port" || {
            error "SSH 隧道启动失败"
            return 1
        }
        info "  启用 Anthropic↔OpenAI bridge (upstream: http://127.0.0.1:$tunnel_listen_port)"
        if start_tunnel_bridge "$tunnel_listen_port" "$model_name" "$api_key"; then
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
    fi

    # 新链路就绪后清理旧链路（减少切换瞬断窗口）
    if $need_stop_old; then
        _stop_old_link
    fi

    # 停 bridge 进程（仅当新链路不需要 bridge 且旧 bridge 在运行）
    if ! $has_tunnel && [[ "$base_url" != *"://127.0.0.1"* ]] && pgrep -f "openai_bridge.py" >/dev/null 2>&1; then
        info "  切换目标不需要 bridge，关闭残留 openai_bridge 进程..."
        pkill -f "openai_bridge.py" 2>/dev/null || true
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
    printf "━━━ LLM 链路诊断 ──\n"
    printf "llm.json current          : %s\n" "${llm_current:-<未设置>}"
    if [[ -n "$sett_env" ]]; then
        IFS='|' read -r base model tok <<< "$sett_env"
        printf "env.ANTHROPIC_BASE_URL    : %s\n" "${base:-<未设置>}"
        printf "env.ANTHROPIC_MODEL       : %s (下次请求实际生效)\n" "${model:-<未设置>}"
        if [[ -n "$tok" ]]; then
            printf "env.ANTHROPIC_AUTH_TOKEN  : ...%s\n" "${tok: -4}"
        fi
    fi
    printf "settings 顶层 model       : %s (session 启动时锁定, 只读参考)\n" "${sett_model:-<未设置>}"

    if [[ "$sett_env" == *"://127.0.0.1:8898"* ]]; then
        local h=$(curl -s --max-time 2 "http://127.0.0.1:8898/health" 2>/dev/null)
        if [[ -n "$h" ]]; then
            local up=$(echo "$h" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('upstream','?')+'|'+d.get('upstream_model','?'))" 2>/dev/null)
            IFS='|' read -r up_base up_model <<< "$up"
            printf "bridge (8898)              : ✓ upstream=%s model=%s\n" "$up_base" "$up_model"
        else
            printf "bridge (8898)              : ✗ 未响应 (env 指向 8898 但 bridge 没起)\n"
        fi
    elif is_proxy_running; then
        printf "gateway 代理               : %s\n" "$(get_gateway_status_one_liner)"
    fi

    if is_ssh_tunnel_running; then
        local tun_info=$(get_ssh_tunnel_status_one_liner)
        local bridge_info=""
        if tmux has-session -t "altllm-bridge" 2>/dev/null; then
            bridge_info="bridge=✓"
        else
            bridge_info="bridge=✗"
        fi
        printf "SSH 隧道 (tmux:%s)  : %s | %s\n" "$TUNNEL_TMUX_SESSION" "$tun_info" "$bridge_info"
    fi

    echo ""
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
    if pb == eb:
        print('Y')
    elif pb and '/anthropic' not in pb and '127.0.0.1' not in pb and eb == 'http://127.0.0.1:8898':
        print('B')
    else:
        print('N')
except: print('N')
PYEOF
)
    fi
    case "$preset_state" in
        Y) success "三处配置一致" ;;
        B) printf "bridge 改写后一致 (preset=%s → 127.0.0.1:8898)\n" "$llm_current" ;;
        N) printf "注意: llm.json current=%s 与 env 不一致, 建议重新跑一次 init-llm\n" "$llm_current" ;;
    esac

    # Gateway 路由一致性检查
    if [[ "$llm_current" == "gateway" ]] && is_proxy_running; then
        local gh=$(get_proxy_health)
        local gw_route=$(echo "$gh" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('current_route','?'))" 2>/dev/null || echo "?")
        local gw_mode=$(echo "$gh" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('mode','?'))" 2>/dev/null || echo "?")
        IFS='|' read -r env_base env_model _ <<< "$sett_env"
        if [[ "$gw_mode" == "off" ]]; then
            printf "注意: gateway 模式=off（代理运行中但路由未生效）\n"
        elif [[ "$gw_mode" == "manual" ]]; then
            printf "gateway mode=manual → %s\n" "$gw_route"
        else
            printf "gateway auto → %s | env model=%s\n" "$gw_route" "$env_model"
        fi
    fi
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
        # SSH 隧道标记
        local tunnel_mark=""
        if [[ -n "$(python3 - "$CONFIG_FILE" "$name" 2>/dev/null <<< 'import json,sys;d=json.load(open(sys.argv[1]));t=d.get("llms",{}).get(sys.argv[2],{}).get("ssh_tunnel",{});print("🔒" if t.get("ssh_host") else "")' 2>/dev/null)" ]]; then
            tunnel_mark=" 🔒"
        fi
        printf "  %s %-10s %-20s%s%s%s\n" "$marker" "$display_name" "$model" "$small_info" "$route_info" "$tunnel_mark"
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


# ========== Sync (修复 /model 污染) ==========
# 同步 settings.json 顶层 model 字段为 env.ANTHROPIC_MODEL
# 背景: Claude Code /model 命令会改 settings.json 顶层 model（如 "haiku"），
#       但 env.ANTHROPIC_MODEL 仍是 init-llm.sh 切的真实模型名（如 "MiniMax-M3"）。
#       下次开新 session 默认用顶层 model，provider 不认 → 模型错误。
# 用法: bash init-llm.sh sync
sync_llm_config() {
    python3 - <<'PYEOF'
import json, os, sys
sf = os.path.expanduser("~/.claude/settings.json")
try:
    with open(sf) as f:
        d = json.load(f)
except Exception:
    print("settings.json 不存在或无效，跳过")
    sys.exit(0)

env_model = d.get('env', {}).get('ANTHROPIC_MODEL', '')
top_model = d.get('model', '')

if not env_model:
    print("env.ANTHROPIC_MODEL 为空，无法同步")
    sys.exit(0)

if env_model == top_model:
    print(f"已同步: 顶层 model = env.ANTHROPIC_MODEL = {env_model}")
    sys.exit(0)

old = top_model or "(空)"
d['model'] = env_model
with open(sf, 'w') as f:
    json.dump(d, f, indent=4, ensure_ascii=False)
print(f"已同步: 顶层 model {old} → {env_model}")
PYEOF
}


# ========== Heal (手动跑 selfheal) ==========
# 当 SessionStart hook 没及时跑 / 用户不想重启 Claude Code 时，手动拉起 bridge
# 等价于 status.sh 的 check_bridge_selfheal()，但只跑这一个检查，不刷完整状态
# 用法: bash init-llm.sh heal
heal_bridge() {
    info "── bridge / tunnel 自愈 ──"

    local cfg="$CONFIG_FILE"
    local cur
    cur="$(python3 -c "import json; print(json.load(open('$cfg')).get('current',''))" 2>/dev/null)" || {
        warn "无法读取 llm.json current"
        return 1
    }
    [[ -z "$cur" ]] && { info "llm.json current 为空，无需自愈"; return 0; }
    info "  current preset: $cur"

    # settings.json 不指向 127.0.0.1:8898 → 不需要 bridge / 隧道
    if ! grep -q '127.0.0.1:8898' "$HOME/.claude/settings.json" 2>/dev/null; then
        info "  settings.json 不指向 bridge (127.0.0.1:8898)，无需自愈"
        return 0
    fi

    # 解析当前 preset 的 ssh_tunnel 配置（如果有）
    local tunnel_info
    tunnel_info=$(python3 - "$cfg" "$cur" << 'PYEOF' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    llm = d.get('llms', {}).get(sys.argv[2], {})
    t = llm.get('ssh_tunnel', {})
    host = t.get('host') or t.get('ssh_host', '')
    if host and t.get('remote'):
        print(f"{host}|{t.get('port',22)}|{t.get('user','')}|{t['remote']}|{t.get('listen_port',8890)}")
    else:
        sys.exit(1)
except:
    sys.exit(1)
PYEOF
    ) || true

    # SSH 隧道自愈
    if [[ -n "$tunnel_info" ]]; then
        if ! tmux has-session -t "altllm-tunnel" 2>/dev/null; then
            IFS='|' read -r host port user remote listen_port <<< "$tunnel_info"
            warn "  SSH 隧道未运行 (altllm-tunnel)，拉起..."
            if start_ssh_tunnel "$host" "$port" "$user" "$remote" "$listen_port"; then
                success "  SSH 隧道已拉起"
            else
                error "  SSH 隧道拉起失败"
                return 1
            fi
        else
            info "  SSH 隧道已在运行 (altllm-tunnel)"
        fi
    fi

    # bridge 自愈
    if curl -s --max-time 2 http://127.0.0.1:8898/health >/dev/null 2>&1; then
        success "  bridge (8898) 已响应"
        return 0
    fi

    warn "  bridge (8898) 未响应，拉起..."
    if [[ -n "$tunnel_info" ]]; then
        # SSH 隧道场景：bridge 指向本地隧道端口
        local config; config=$(get_llm_config "$cur") || { error "  无法读取 $cur 配置"; return 1; }
        IFS='|' read -r _ model key _ <<< "$config"
        IFS='|' read -r _ _ _ _ listen_port <<< "$tunnel_info"
        if start_tunnel_bridge "$listen_port" "$model" "$key"; then
            success "  隧道桥接已拉起 → 127.0.0.1:8898"
        else
            error "  桥接拉起失败，运行: bash init-llm.sh switch $cur"
            return 1
        fi
    else
        # 普通 OpenAI-only 端点：用 ensure_bridge
        local bc; bc="$(read_bridge_config "$cfg" "$cur")" || { error "  无法读取 $cur bridge 配置"; return 1; }
        IFS='|' read -r base_url model key <<< "$bc"
        if ensure_bridge "$base_url" "$model" "$key"; then
            success "  bridge 已拉起 ($cur) → 127.0.0.1:8898"
        else
            error "  bridge 拉起失败，运行: bash init-llm.sh switch $cur"
            return 1
        fi
    fi
}


# ========== 交互式选择 ==========
_llm_status_header() {
    local current="${1:-}"
    local llm_name="" llm_display=""
    if [[ -n "$current" ]]; then
        llm_name=$(echo "$current" | cut -d'|' -f1)
        llm_display=$(echo "$current" | cut -d'|' -f2)
        [[ -z "$llm_display" ]] && llm_display="$llm_name"
    fi

    echo -e ""
    echo -e "  ${BOLD_GRAY}--当前配置--${NC}"
    if [[ -n "$llm_display" ]]; then
        echo -e "  ${LIGHT_BLUE}生效: $llm_display${NC}"
    else
        echo -e "  ${LIGHT_BLUE}生效: 未配置${NC}"
    fi

    # bridge 活跃时显示 bridge 行
    if curl -s --max-time 1 "http://127.0.0.1:8898/health" >/dev/null 2>&1; then
        local up=$(curl -s --max-time 1 "http://127.0.0.1:8898/health" 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('upstream_model','?'))" 2>/dev/null || echo "?")
        echo -e "  ${LIGHT_BLUE}bridge启用: $up${NC}"
    fi
    echo -e ""
}

interactive_select() {
    local lines=$(list_llms)
    local current=$(echo "$lines" | grep "^CURRENT:" | cut -d: -f2)

    _llm_status_header "$current"

    local -a item_cat item_letter item_name
    local -a builtin_r=() custom_r=()
    while IFS='|' read -r marker name display_name model base_url small; do
        [[ "$marker" == "TOTAL:"* || "$marker" == "CURRENT:"* || -z "$name" ]] && continue
        if [[ "$name" == "minimax" || "$name" == "deepseek_flash" || "$name" == "gateway" ]]; then
            builtin_r+=("$name|$display_name|$model|$small|$marker|$base_url")
        else
            custom_r+=("$name|$display_name|$model|$small|$marker|$base_url")
        fi
    done < <(echo "$lines")

    while true; do
    # ── 渲染内建 llm ──
    echo -e "  ${BOLD_GRAY}--内建 llm--${NC}"
    local letter="A"
    for entry in "${builtin_r[@]}"; do
        IFS='|' read -r name display_name model small marker base_url <<< "$entry"
        local small_str="" route_str=""
        [[ -n "$small" ]] && small_str=" ${DIM}[小模型: $small]${NC}"
        [[ "$name" == "gateway" ]] && route_str=" ${YELLOW}$(read_gateway_routes "$LLMSWITCH_CONF" "$CONFIG_FILE" 2>/dev/null)${NC}"
        local curr_str=""
        [[ "$marker" == "◀" ]] && curr_str="  ${LIGHT_BLUE}◀ 当前${NC}"
        echo -e "  ${BOLD_GREEN}1${letter}${NC}  ${display_name} ${DIM}${model}${NC}${small_str}${route_str}${curr_str}"
        item_cat+=("1"); item_letter+=("$letter"); item_name+=("$name")
        case "$letter" in A) letter=B;; B) letter=C;; C) letter=D;; D) letter=E;; E) letter=F;; F) letter=G;; G) letter=H;; H) letter=I;; I) letter=J;; J) letter=K;; K) letter=L;; L) letter=M;; M) letter=N;; N) letter=O;; O) letter=P;; P) letter=Q;; Q) letter=R;; R) letter=S;; S) letter=T;; T) letter=U;; U) letter=V;; V) letter=W;; W) letter=X;; X) letter=Y;; Y) letter=Z;; *) letter=A;; esac
    done

    # ── 渲染自定义 llm ──
    echo -e "  ${BOLD_GRAY}--自定义 llm--${NC}"
    letter="A"
    for entry in "${custom_r[@]}"; do
        IFS='|' read -r name display_name model small marker base_url <<< "$entry"
        local small_str="" route_str=""
        [[ -n "$small" ]] && small_str=" ${DIM}[小模型: $small]${NC}"
        [[ "$name" == "gateway" ]] && route_str=" ${YELLOW}$(read_gateway_routes "$LLMSWITCH_CONF" "$CONFIG_FILE" 2>/dev/null)${NC}"
        local curr_str=""
        [[ "$marker" == "◀" ]] && curr_str="  ${LIGHT_BLUE}◀ 当前${NC}"
        echo -e "  ${BOLD_GREEN}2${letter}${NC}  ${display_name} ${DIM}${model}${NC}${small_str}${route_str}${curr_str}"
        item_cat+=("2"); item_letter+=("$letter"); item_name+=("$name")
        case "$letter" in A) letter=B;; B) letter=C;; C) letter=D;; D) letter=E;; E) letter=F;; F) letter=G;; G) letter=H;; H) letter=I;; I) letter=J;; J) letter=K;; K) letter=L;; L) letter=M;; M) letter=N;; N) letter=O;; O) letter=P;; P) letter=Q;; Q) letter=R;; R) letter=S;; S) letter=T;; T) letter=U;; U) letter=V;; V) letter=W;; W) letter=X;; X) letter=Y;; Y) letter=Z;; *) letter=A;; esac
    done

    # ── 配置 ──
    echo -e "  ${BOLD_GRAY}--llm 配置--${NC}"
    printf "  ${BOLD_GREEN}3A${NC}  %-26s ${DIM}%s${NC}\n" "新增自定义 preset" "输入任意 base_url + model + key"
    printf "  ${BOLD_GREEN}3B${NC}  %-26s ${DIM}%s${NC}\n" "删除自定义 preset" "删除已保存的自定义预设"
    printf "  ${BOLD_GREEN}3C${NC}  %-26s ${DIM}%s${NC}\n" "Gateway 切换规则" "peak_hours/routes/mode → llmswitch 管理"
    printf "  ${BOLD_GREEN}3D${NC}  %-26s ${DIM}%s${NC}\n" "Bill 模型单价" "配置 token 单价，用于 token-usage 计费"
    echo ""
    echo "  0) 退出"
    printf "  输入 (如 1A, 2B, 3C) 或数字选择: "
    read -r choice

    [[ -z "$choice" || "$choice" == "0" ]] && { info "已退出"; return 0; }

    if [[ "$choice" =~ ^([0-9]+)([A-Za-z])$ ]]; then
        local cat="${BASH_REMATCH[1]}"
        local letter="${BASH_REMATCH[2]^^}"
        if [[ "$cat" == "3" ]]; then
            case "$letter" in
                A) switch_custom ;;
                B) delete_preset ;;
                C) bash "$LLMSWITCH_INIT" ;;
                D) bill_config ;;
                *) warn "配置: A=新增 B=删除 C=Gateway D=Bill"; continue ;;
            esac
            continue
        fi
        for i in "${!item_cat[@]}"; do
            if [[ "${item_cat[$i]}" == "$cat" && "${item_letter[$i]}" == "$letter" ]]; then
                switch_llm "${item_name[$i]}"
                continue 2
            fi
        done
        warn "未找到 ${cat}${letter}"
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

    if [[ "$cmd" == "list" ]]; then
        show_list
    elif [[ "$cmd" == "status" ]]; then
        show_status
    elif [[ "$cmd" == "test" ]] || [[ "$cmd" == "-t" ]]; then
        # 第二参数：要测试的预设名
        test_llm "${2:-}"
    elif [[ "$cmd" == "switch" ]]; then
        # 直接切指定预设: bash init-llm.sh switch <name>
        switch_llm "${2:-}"
    elif [[ "$cmd" == "custom" ]] || [[ "$cmd" == "-c" ]]; then
        switch_custom
    elif [[ "$cmd" == "delete" ]] || [[ "$cmd" == "-d" ]]; then
        # 可选第二参数：要删的预设名
        delete_preset "${2:-}"
    elif [[ "$cmd" == "bill" ]] || [[ "$cmd" == "pricing" ]] || [[ "$cmd" == "-p" ]]; then
        # 配置模型价格（option-usage 计费用）
        bill_config "${2:-}"
    elif [[ "$cmd" == "sync" ]]; then
        # 同步 settings.json 顶层 model 为 env.ANTHROPIC_MODEL（修 /model 污染）
        sync_llm_config
    elif [[ "$cmd" == "heal" ]]; then
        # 手动 selfheal：拉起死掉的 bridge / SSH 隧道（无需重启 Claude Code）
        heal_bridge
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