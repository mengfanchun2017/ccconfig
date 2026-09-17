#!/bin/bash
# ==============================================
# LLM 配置管理脚本（精简版）
#
# 使用：
#   bash init-llm.sh                 # 交互菜单
#   bash init-llm.sh <name>          # 直接切预设
#   bash init-llm.sh list            # 列预设
#   bash init-llm.sh status          # 当前链路诊断
#   bash init-llm.sh test <name>     # 真实链路探测（走 bridge + 流式）
#   bash init-llm.sh sync            # 修 /model 污染
#   bash init-llm.sh delete <name>   # 删预设
#   bash init-llm.sh bill            # 用量统计（拆 init-llm-bill.sh）
#
# 新增/修改预设：直接编辑 conf/llm.json（schema 见 docs/init-llm.md §六）
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
CLAUDE_JSON="$HOME/.claude.json"

# 机器本地 current 文件（不参与 ccprivate 同步）
LOCAL_CURRENT_FILE="$HOME/.claude/llm-current"

# ccconfig 自带预设 key —— builtin 分类以代码为准，不依赖用户 llm.json 的 builtin 字段
# 用户 llm.json 可能缺该字段或被手改，会导致菜单内建/自定义分组错乱
BUILTIN_PRESETS=(minimax deepseek_flash)

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

# 读 provider 的 host_header 字段（可选，tailscale/SSH 透传场景用）
get_provider_host_header() {
    python3 - "$CONFIG_FILE" "$1" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r') as f: d = json.load(f)
    llm = d.get('llms', {}).get(sys.argv[2], {})
    print(llm.get('host_header', ''))
except Exception:
    print('')
PYEOF
}

# ========== 本地 current 读写（不碰 ccprivate llm.json.current）==========
# 读本地 llm-current，不存在则 fallback 读 llm.json.current（兼容旧机器）
read_local_current() {
    if [[ -f "$LOCAL_CURRENT_FILE" ]]; then
        cat "$LOCAL_CURRENT_FILE"
    else
        python3 -c "
import json
p = '$CONFIG_FILE'
try: print(json.load(open(p)).get('current',''))
except: pass
" 2>/dev/null || echo ""
    fi
}

# 写本地 llm-current（不写 llm.json.current）
write_local_current() {
    local name="$1"
    mkdir -p "$(dirname "$LOCAL_CURRENT_FILE")"
    printf '%s' "$name" > "$LOCAL_CURRENT_FILE"
    info "llm-current: $name"
}

list_llms() {
    local cur
    cur=$(read_local_current)
    export LIST_CUR="$cur"
    BUILTIN_KEYS="${BUILTIN_PRESETS[*]}" python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys, os
builtin_set = set(os.environ.get('BUILTIN_KEYS','').split())
with open(sys.argv[1]) as f: d = json.load(f)
llms = d.get('llms', {}); cur = os.environ.get('LIST_CUR', d.get('current', ''))
print(f"TOTAL:{len(llms)}")
print(f"CURRENT:{cur}")
for name, llm in llms.items():
    model = llm.get('model', '')
    marker = "◀" if name == cur else " "
    small = llm.get('small_model', '')
    is_builtin = '1' if (name in builtin_set or llm.get('builtin', False)) else '0'
    print(f"{marker}|{name}|{llm.get('name', name)}|{model}|{llm.get('base_url','')}|{small}|{is_builtin}")
PYEOF
}

# ========== 写配置（settings.json env + llm-current） ==========
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

# 写 llm.json（保留 key 同步，不写 current——current 在本地 llm-current）
cfg = os.environ['CONFIG_FILE']
with open(cfg) as f: d = json.load(f)
if final:
    llms = d.setdefault('llms', {})
    if os.environ['NAME'] in llms:
        llms[os.environ['NAME']]['key'] = final
with open(cfg, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
print("llm.json 已更新（provider key）")

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

    write_local_current "$name"
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

# 停 bridge（如有）
stop_bridge() {
    stop_bridge_watchdog
    local pid
    pid=$( { lsof -ti :${BRIDGE_PORT} 2>/dev/null || true; } | head -1 || true)
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
}

# 读 use_bridge 标记
# 返回：True / False（显式设置）/ 空（字段缺失 → 走 auto-bridge 兜底）
# why: 区分 absent 与 explicit-false，守卫只拦显式 false，缺字段不报错
get_use_bridge() {
    python3 - "$CONFIG_FILE" "$1" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
v = d.get('llms', {}).get(sys.argv[2], {}).get('use_bridge', '__ABSENT__')
print('' if v == '__ABSENT__' else v)
PYEOF
}

# ========== 切换主入口 ==========
switch_llm() {
    local name="$1"
    if _dry_run_enabled; then
        echo "  [DRY-RUN] switch_llm: would switch to '$name'"
        return 0
    fi

    local config
    config=$(get_llm_config "$name") || { error "未知预设: $name"; return 1; }
    local base_url model key small
    IFS='|' read -r base_url model key small <<< "$config"

    # host_header（tailscale/SSH 透传场景：证书 SAN 签的是单位内网 IP，客户端连的是跳板机 IP → SNI+Host 改回单位 IP）
    local host_header
    host_header=$(get_provider_host_header "$name")

    info "  选定 upstream: $base_url${host_header:+ (host: $host_header)}"

    # 读 use_bridge 标记
    local use_bridge
    use_bridge=$(get_use_bridge "$name")

    # 是否走 bridge
    if [[ "$use_bridge" == "True" ]]; then
        info "  用户指定 bridge 代理..."
        if ensure_bridge "$base_url" "$model" "$key" "$host_header" "$CONFIG_FILE" "$name"; then
            base_url="http://127.0.0.1:${BRIDGE_PORT}"
            info "  bridge 就绪 → $base_url"
        else
            error "  bridge 启动失败，查 log: tail -30 ~/.cache/openai_bridge.log"
            return 1
        fi
    elif [[ "$base_url" != *"/anthropic"* ]] && [[ "$base_url" != *"://127.0.0.1"* ]]; then
        # OpenAI-only 端点
        if [[ "$use_bridge" == "False" ]]; then
            # why: use_bridge:false 显式要直连，但 Claude Code 只支持 Anthropic Messages 格式
            # OpenAI-only URL（如 paas/v4）直连必失败 → 早报错，避免静默走 auto-bridge 违背用户意图
            error "  base_url '$base_url' 是 OpenAI-only 端点 + use_bridge:false → 不兼容"
            error "  Claude Code 只支持 Anthropic Messages 格式，直连必失败"
            error "  修：use_bridge:true 走 bridge / 换含 /anthropic 的 Anthropic 兼容 URL"
            return 1
        fi
        # use_bridge 未显式 False（或缺失）→ 保留旧 auto-bridge 行为
        info "  OpenAI-only 端点 → 启动 bridge..."
        if ensure_bridge "$base_url" "$model" "$key" "$host_header" "$CONFIG_FILE" "$name"; then
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

    # 真实链路探测：test_llm 会走 bridge（若需要）+ 流式请求 + 完整判据。
    # 探测不通过就中止切换，避免切到一个实际跑不通的配置。
    test_llm "$name" || {
        warn "流式链路探测未通过，切换中止（settings.json 未改动）"
        return 1
    }

    write_llm_config "$name" "$base_url" "$model" "$small" "$key"

    # 提示重启 Claude session：settings.json 改了，但当前 claude 进程不 reload 旧连接池
    # why: 不重启会看到 "waiting 4m" 卡顿（旧连接断了重试）— 新 session 才会读新 BASE_URL
    warn "切 LLM 后必须 /exit 退出当前 Claude session，然后 'claude -c' 续最近会话"
}

# ========== 状态 ==========
# 探 bridge /health，输出 "state|upstream|model"（state: up/down）
# show_status 与菜单头共用，避免两处各写一遍解析
_bridge_health() {
    local h
    h=$(curl -s --max-time 2 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null) || true
    if [[ -z "$h" ]]; then
        printf 'down||'
        return
    fi
    printf '%s' "$h" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(f\"up|{d.get('upstream','?')}|{d.get('upstream_model','?')}\")
except Exception:
    print('down||')" 2>/dev/null || printf 'down||'
}

show_status() {
    local llm_cur sett_env sett_model
    llm_cur=$(read_local_current)

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
        local st ub um
        IFS='|' read -r st ub um <<< "$(_bridge_health)"
        if [[ "$st" == "up" ]]; then
            printf "bridge (%d)              : ✓ upstream=%s model=%s\n" "$BRIDGE_PORT" "$ub" "$um"
        else
            printf "bridge (%d)              : ✗ 未响应（env 指向但没起，跑 init-llm.sh <name> 重启）\n" "$BRIDGE_PORT"
        fi
    fi
    echo ""
}

# ========== 测试连接（非破坏性）==========
# 把 base_url 改成探测用 URL：
# - 默认用原 base_url
# - 若 host_header（如 tailscale 跳板机场景证书 SAN 签的是域名但 URL 是 IP），用域名 + --resolve 改 SNI
_probe_url() {
    local base_url="$1" host_header="$2"
    if [[ -n "$host_header" ]]; then
        # 提取原 host:port（如 100.96.236.22:18080），用 host_header 替换 host 部分
        local orig_host_port path_part
        orig_host_port=$(echo "$base_url" | sed -E 's|^https?://([^/]+).*|\1|')
        path_part=$(echo "$base_url" | sed -E 's|^https?://[^/]+||')
        local port
        port=$(echo "$orig_host_port" | sed -E 's|.*:||')
        [[ "$port" == "$orig_host_port" ]] && port="443"
        echo "https://${host_header}:${port}${path_part}"
        return 0
    fi
    echo "$base_url"
}

# 把 --resolve host_header:port:ip 参数打印出来（空则不打印）
_probe_resolve_args() {
    local base_url="$1" host_header="$2"
    [[ -z "$host_header" ]] && return 0
    local orig_host port ip_part
    orig_host=$(echo "$base_url" | sed -E 's|^https?://([^:/]+).*|\1|')
    port=$(echo "$base_url" | sed -E 's|^https?://[^:/]+:([0-9]+).*|\1|')
    [[ "$port" == "$base_url" ]] && port="443"
    # 解析原 host 为 IP（--resolve 需要 IP 而非域名）
    ip_part=$(getent ahosts "$orig_host" 2>/dev/null | awk 'NR==1{print $1}')
    [[ -z "$ip_part" ]] && return 0
    echo "--resolve ${host_header}:${port}:${ip_part}"
}

test_llm() {
    local target="${1:-}"
    [[ -z "$target" ]] && { error "用法: init-llm.sh test <preset>"; return 1; }
    local config
    config=$(get_llm_config "$target") || { error "未知预设: $target"; return 1; }
    # why local：bash 动态作用域下，不加 local 的 read 会改写调用者（switch_llm）的同名变量，
    # 把已设好的 bridge 地址覆盖回上游地址 → settings.json 写成 OpenAI 端点直连必挂
    local base_url model key
    IFS='|' read -r base_url model key _ <<< "$config"
    local host_header; host_header=$(get_provider_host_header "$target")

    local _is_ph=0
    [[ -z "$key" ]] && _is_ph=1
    [[ $_is_ph -eq 0 ]] && case "$key" in *请填入*|*请替换*|*your.key*|*placeholder*|*changeme*) _is_ph=1 ;; esac
    if [[ $_is_ph -eq 1 ]]; then
        error "预设 '$target' 无有效 Key"; return 1
    fi

    info "测试: $target ($model @ $base_url)"
    [[ -n "$host_header" ]] && info "  host_header: $host_header"

    # 走 Claude Code 真实路径：走 bridge 的 preset 必须经 bridge 测，否则测的是上游
    # 直连（能通）而非 bridge 转换链路（真正会挂的地方）
    local use_bridge need_bridge=0
    use_bridge=$(get_use_bridge "$target")
    if [[ "$use_bridge" == "True" ]]; then
        need_bridge=1
    elif [[ "$use_bridge" != "False" && "$base_url" != *"/anthropic"* && "$base_url" != *"://127.0.0.1"* ]]; then
        need_bridge=1
    fi

    local probe_url expect resolve_args=""
    if (( need_bridge )); then
        info "  bridge 链路（真实路径）..."
        ensure_bridge "$base_url" "$model" "$key" "$host_header" "$CONFIG_FILE" "$target" \
            || { error "  ✗ bridge 启动失败 — 查 tail -30 ~/.cache/openai_bridge.log"; return 1; }
        probe_url="http://127.0.0.1:${BRIDGE_PORT}/v1/messages"
        expect="message_stop"
    else
        probe_url=$(_probe_url "$base_url" "$host_header")
        if [[ "$probe_url" == *"/anthropic"* ]]; then
            probe_url="${probe_url%/}/v1/messages"; expect="message_stop"
        else
            probe_url="${probe_url%/}/chat/completions"; expect="\\[DONE\\]"
        fi
        resolve_args=$(_probe_resolve_args "$base_url" "$host_header")
    fi

    # why 流式 + 查终止标记：Claude Code 全程 stream:true。非流式探测只能证明"上游活着"，
    # 证明不了流式链路完整 —— 流式包装器在流尾抛异常的 bug 下它照样返回 200。
    local out http_code body_file
    body_file=$(mktemp)
    # shellcheck disable=SC2086
    http_code=$(curl -sN -k --max-time 60 --noproxy '*' -o "$body_file" -w "%{http_code}" -X POST $resolve_args "$probe_url" \
        -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
        -H "Authorization: Bearer $key" \
        -d "{\"model\":\"$model\",\"max_tokens\":16,\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" 2>/dev/null) || http_code="000"
    out=$(cat "$body_file" 2>/dev/null); rm -f "$body_file"
    [[ -z "$http_code" ]] && http_code="000"

    if printf '%s' "$out" | grep -q "$expect" && ! printf '%s' "$out" | grep -q '"type":"error"'; then
        success "✓ 流式链路完整（收到 $expect）— '$target' 可用"
        return 0
    fi
    case "$http_code" in
        000) error "✗ 不可达 — $probe_url（查 DNS / 出口 / VPN）" ;;
        401|403) warn "⚠ HTTP $http_code — 链路通但鉴权失败（key 可能无效）"; return 0 ;;
        *)   if printf '%s' "$out" | grep -q '"type":"error"'; then
                 error "✗ 流式链路报错（upstream 中断或被截断）"
             else
                 error "✗ 流式链路失败（HTTP $http_code，未收到 $expect）"
             fi ;;
    esac
    printf '%s' "$out" | head -6 | sed 's/^/    /'
    return 1
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
        local info_small=""
        [[ -n "$small" ]] && info_small=" ${DIM}(小: $small)${NC}"
        printf "  %s %-10s %-20s%b\n" "$marker" "$display" "$model" "$info_small"
    done < <(echo "$lines")
    echo ""
    if [[ -n "$current" ]]; then
        info "当前: $current"
    fi
}

# ========== 删预设 ==========
delete_preset() {
    local target="${1:-}"

    # 读 builtin 列表（以代码定义为准，兼容用户 builtin 字段）
    local builtin_list
    builtin_list=$(BUILTIN_KEYS="${BUILTIN_PRESETS[*]}" python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys, os
builtin_set = set(os.environ.get('BUILTIN_KEYS','').split())
with open(sys.argv[1]) as f: d = json.load(f)
names = [k for k, v in d.get('llms', {}).items() if k in builtin_set or v.get('builtin')]
print(' '.join(names))
PYEOF
    )

    if [[ -z "$target" ]]; then
        local items=() names=()
        while IFS='|' read -r _ name display model _ _ is_builtin; do
            [[ -z "$name" ]] && continue
            [[ "$is_builtin" == "1" ]] && continue
            names+=("$name")
            items+=("$display ($model)")
        done < <(list_llms)
        [[ ${#items[@]} -eq 0 ]] && { info "无可删预设"; return 0; }
        items+=("返回上层")
        local sel; sel=$(menu_select "可删除的模型" "${items[@]}")
        [[ -z "$sel" || "$sel" == "0" ]] && return 0
        (( sel == ${#items[@]} )) && return 0
        target="${names[$((sel-1))]}"
    fi
    [[ -z "$target" ]] && { error "未指定预设"; return 1; }

    if [[ " $builtin_list " == *" $target "* ]]; then
        error "内置预设 '$target' 不可删"; return 1
    fi
    if [[ "$(read_local_current)" == "$target" ]]; then
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

_llm_status_header() {
    local current="${1:-}"
    echo -e ""
    if [[ -z "$current" ]]; then
        echo -e "  ${LIGHT_BLUE}生效配置: 未配置${NC}"
        echo -e ""
        return
    fi

    # 一次 python 取齐：预设显示名/model + settings.json 的 env.ANTHROPIC_BASE_URL
    local display model sf_url st _ub um st _ub um
    IFS='|' read -r display model sf_url < <(CUR="$current" CONFIG_FILE="$CONFIG_FILE" python3 - << 'PYEOF'
import json, os
d = json.load(open(os.environ['CONFIG_FILE']))
llm = d.get('llms', {}).get(os.environ['CUR'], {})
try:
    sf = json.load(open(os.path.expanduser('~/.claude/settings.json')))
    base = sf.get('env', {}).get('ANTHROPIC_BASE_URL', '')
except Exception:
    base = ''
print(f"{llm.get('name', os.environ['CUR'])}|{llm.get('model','')}|{base}")
PYEOF
    ) 2>/dev/null
    [[ -z "$display" ]] && display="$current"
    echo -e "  ${LIGHT_BLUE}生效配置: $display${NC} ${DIM}($model)${NC}"

    # bridge 状态：仅当 settings.json 的 env 指向 bridge 端口时才有意义
    if [[ "$sf_url" == "http://127.0.0.1:${BRIDGE_PORT}"* ]]; then
        local st _ub um
        IFS='|' read -r st _ub um <<< "$(_bridge_health)"
        if [[ "$st" == "up" ]]; then
            echo -e "  ${LIGHT_BLUE}bridge: ${GREEN}✓${NC} ${DIM}model=$um${NC}"
        else
            echo -e "  ${LIGHT_BLUE}bridge: ${RED}✗ 无响应${NC}"
        fi
    fi
    echo -e ""
}

# 动作后停顿，让用户看清结果再重渲染（防止输出堆积、clear 抖动）
_pause_continue() {
    echo ""
    printf "  ${DIM}按回车返回菜单...${NC}"
    read -r _ < /dev/tty 2>/dev/null || true
    echo ""
}

interactive_select() {
    local -a item_name
    local letters="ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    while true; do
        clear 2>/dev/null || true
        local lines; lines=$(list_llms)
        local current; current=$(echo "$lines" | grep "^CURRENT:" | cut -d: -f2)
        _llm_status_header "$current"
        item_name=()
        local idx=0
        echo -e "  ${BOLD_GRAY}--LLM--${NC}"
        while IFS='|' read -r marker name display_name model base_url small is_builtin; do
            [[ "$marker" == "TOTAL:"* || "$marker" == "CURRENT:"* || -z "$name" ]] && continue
            local small_str=""
            [[ -n "$small" ]] && small_str=" ${DIM}[小模型: $small]${NC}"
            local cur_mark=" "
            [[ "$marker" == "◀" ]] && cur_mark="${GREEN}${marker}${NC}"
            local letter="${letters:$idx:1}"
            echo -e "  ${BOLD_GREEN}1${letter}${NC} ${cur_mark} ${display_name} ${DIM}${model}${NC}${small_str}"
            item_name+=("$name")
            idx=$((idx+1))
        done < <(echo "$lines")

        echo -e "  ${BOLD_GRAY}--LLM配置--${NC}"
        printf "  ${BOLD_GREEN}2A${NC}  %-26s ${DIM}%s${NC}\n" "删除模型" "删除已保存预设"
        printf "  ${BOLD_GREEN}2B${NC}  %-26s ${DIM}%s${NC}\n" "用量统计" "按 model+day 聚合 ccprivate/usage/*.csv"
        printf "  ${DIM}新增/修改预设：直接编辑 conf/llm.json 后重进菜单${NC}\n"
        echo -e "  ${BOLD_GREEN}0${NC}  退出"
        printf "  ${BOLD_GREEN}输入 (如 1A, 2D): ${NC}"
        read -r choice

        [[ -z "$choice" || "$choice" == "0" ]] && { info "已退出"; return 0; }

        if [[ "$choice" =~ ^([0-9]+)([A-Za-z])$ ]]; then
            local cat="${BASH_REMATCH[1]}"
            local letter_m="${BASH_REMATCH[2]^^}"
            if [[ "$cat" == "2" ]]; then
                case "$letter_m" in
                    A) delete_preset ;;
                    B) bash "$SCRIPT_DIR/init-llm-bill.sh" ;;
                    *) warn "配置: A=删模型 B=用量统计"; continue ;;
                esac
                _pause_continue
                continue
            fi
            if [[ "$cat" == "1" ]]; then
                local pos=-1 j
                for ((j=0; j<${#letters}; j++)); do
                    [[ "${letters:$j:1}" == "$letter_m" ]] && { pos=$j; break; }
                done
                if (( pos >= 0 && pos < ${#item_name[@]} )); then
                    switch_llm "${item_name[$pos]}"
                    _pause_continue
                    continue 2
                fi
            fi
            warn "未找到 ${cat}${letter_m}"
            continue
        fi

        warn "无效输入: $choice (格式: 1A, 2D)"
    done
}

# ========== 主流程 ==========
main() {
    local cmd="${1:-${INIT_LLM_NAME:-}}"

    case "$cmd" in
        list)        show_list ;;
        status)      show_status ;;
        test|-t)
            if [[ "${2:-}" == "all" ]]; then
                warn "'test all' 已移除（预设变少后价值不大），改用 test <预设名>"
                return 1
            fi
            test_llm "${2:-}" ;;
        switch)      switch_llm "${2:-}" ;;
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
