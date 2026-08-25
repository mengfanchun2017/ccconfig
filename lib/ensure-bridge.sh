#!/bin/bash
# lib/ensure-bridge.sh
# Anthropic↔OpenAI bridge 生命周期（port 8898）
# 被 init-llm.sh 切换时 + status.sh SessionStart hook 自愈共用
#
# 依赖: 调用方已 source lib/colors.sh（info/warn）

CCCONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 只服务 OpenAI-only 端点（非 /anthropic、非本地）
_bridge_supported() {
    local upstream="$1"
    [[ -z "$upstream" ]] && return 1
    [[ "$upstream" == *"/anthropic"* ]] && return 1
    [[ "$upstream" == *"://127.0.0.1"* ]] && return 1
    return 0
}

# 从 llm.json 读预设的 base_url|model|key
# 用法: read_bridge_config <llm.json路径> <preset名>
read_bridge_config() {
    python3 - "$1" "$2" << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    llm = d.get('llms', {}).get(sys.argv[2], {})
    print(f"{llm.get('base_url','')}|{llm.get('model','')}|{llm.get('key','')}")
except Exception:
    sys.exit(1)
PYEOF
}

# 确保 8898 bridge 运行，upstream 不匹配则重启
# 用法: ensure_bridge <upstream> <model> <key>
# 返回 0=就绪 1=失败
ensure_bridge() {
    local upstream="$1" model="$2" key="$3"
    local port=8898
    _bridge_supported "$upstream" || return 1

    # 决策：是否需要 win-curl 模式（WSL 网络可达性）
    # 提前决策，因为 bridge 进程内是不是 win-curl 模式取决于启动时的环境
    local need_win_curl=0
    if command -v curl.exe &>/dev/null; then
        # 拿上游的 hostname 探测（如果不是 IP）
        local probe_host=""
        probe_host=$(echo "$upstream" | python3 -c "
import sys, urllib.parse
p = urllib.parse.urlparse(sys.stdin.read().strip())
try:
    socket.inet_aton(p.hostname)
    print('')  # 已经是 IP
except:
    print(p.hostname or '')
" 2>/dev/null)
        if [[ -n "$probe_host" ]]; then
            # 域名 → 先 DNS 预解析再测
            local resolved_ip=""
            resolved_ip=$(powershell.exe -NoProfile -Command "Resolve-DnsName $probe_host -Type A 2>&1 | Select-Object -First 1 -ExpandProperty IPAddress" 2>/dev/null | tr -d '\r' || echo "")
            if [[ -n "$resolved_ip" ]] && ! python3 -c "
import socket, sys
try:
    s = socket.create_connection(('$resolved_ip', 18080), timeout=5)
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
                need_win_curl=1
            fi
        fi
    fi

    local health=""
    health=$(curl -s --max-time 2 "http://127.0.0.1:${port}/health" 2>/dev/null)
    if [[ -n "$health" ]]; then
        local cur_state=""
        cur_state=$(echo "$health" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    # upstream_original 是 IP 预解析前的域名 URL，用于和调用方传入的 upstream 匹配
    orig = d.get('upstream_original', d.get('upstream',''))
    print(f\"{orig}|{d.get('use_win_curl',False)}\")
except: pass
" 2>/dev/null)
        local cur_upstream="${cur_state%|*}"
        local cur_win_curl="${cur_state#*|}"

        if [[ "$cur_upstream" == "$upstream" ]]; then
            # 转 win-curl 状态变化检测：从直连切到 win-curl (回家) 或反之（到公司）
            if [[ "$cur_win_curl" == "True" && "$need_win_curl" -eq 0 ]]; then
                info "  网络已切回直连（WSL 可达 upstream），重启 bridge 关闭 win-curl..."
                pkill -f "openai_bridge.py" 2>/dev/null || true
                sleep 1
            elif [[ "$cur_win_curl" == "False" && "$need_win_curl" -eq 1 ]]; then
                info "  网络已切到 win-curl（WSL 不可达 upstream），重启 bridge 启用 win-curl..."
                pkill -f "openai_bridge.py" 2>/dev/null || true
                sleep 1
            else
                # upstream 匹配 + win-curl 状态正确 → 做一次快速可达性测试
                local probe=""
                probe=$(curl -s --max-time 5 -X POST "http://127.0.0.1:${port}/v1/messages" \
                    -H "Content-Type: application/json" \
                    -d '{"model":"test","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
                    -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
                if [[ "$probe" != "000" ]] && [[ "$probe" != "502" ]]; then
                    return 0
                fi
                # 桥接已死，重启
                warn "  bridge 可达性检测失败 (HTTP $probe)，正在重启..."
                pkill -f "openai_bridge.py" 2>/dev/null || true
                sleep 1
            fi
        else
            pkill -f "openai_bridge.py" 2>/dev/null || true
            sleep 1
        fi
    fi

    # 预解析 upstream 域名→IP，绕过 Clash fake-ip DNS 干扰
    # 用 python3 socket.getaddrinfo（受系统 DNS 影响）；作为补充，
    # 尝试用 Windows 侧 DNS（Resolve-DnsName）绕开 WSL 的 Clash fake-ip 污染
    local resolved_upstream="$upstream"
    local resolved_host=""
    if command -v powershell.exe &>/dev/null; then
        # 从 Windows 侧解析 DNS（绕过 WSL Clash fake-ip）
        local win_domain=""
        win_domain=$(echo "$upstream" | python3 -c "
import sys, urllib.parse
p = urllib.parse.urlparse(sys.stdin.read().strip())
print(p.hostname or '')
" 2>/dev/null)
        # 已经是 IP 的不需要 DNS 预解析
        if [[ -n "$win_domain" ]] && ! echo "$win_domain" | python3 -c "import sys,socket; sys.exit(0 if socket.inet_aton(sys.stdin.read().strip()) else 1)" 2>/dev/null; then
            local win_ip=""
            # 优先用环境变量指定的 DNS 服务器（公司 VPN DNS），兜底 Windows 默认 DNS
            local dns_server="${OPENAI_BRIDGE_WIN_DNS:-}"
            if [[ -n "$dns_server" ]]; then
                win_ip=$(powershell.exe -NoProfile -Command "Resolve-DnsName $win_domain -Type A -Server $dns_server 2>&1 | Select-Object -First 1 -ExpandProperty IPAddress" 2>/dev/null | tr -d '\r' || echo "")
            fi
            if [[ -z "$win_ip" ]]; then
                # 兜底：不加 DNS 服务器参数，用 Windows 默认 DNS
                win_ip=$(powershell.exe -NoProfile -Command "Resolve-DnsName $win_domain -Type A 2>&1 | Select-Object -First 1 -ExpandProperty IPAddress" 2>/dev/null | tr -d '\r' || echo "")
            fi
            if [[ -n "$win_ip" ]]; then
                # 用 IP 替换 URL 中的域名
                resolved_upstream=$(echo "$upstream" | python3 -c "
import sys, urllib.parse
domain = '$win_domain'
ip = '$win_ip'
url = sys.stdin.read().strip()
p = urllib.parse.urlparse(url)
if p.hostname == domain:
    netloc = f'{ip}:{p.port}' if p.port else ip
    resolved = p._replace(netloc=netloc).geturl()
    print(resolved)
else:
    print(url)
" 2>/dev/null)
                resolved_host="$win_domain"
                info "  DNS 预解析: $win_domain → $win_ip (Windows DNS)"
            fi
        fi
    fi

    # 启新 bridge（unset 代理 env 直连上游）
    local _saved_cwd="$PWD"
    cd "$CCCONFIG_ROOT"
    trap 'cd "$_saved_cwd"' RETURN

    if [[ "$need_win_curl" -eq 1 ]]; then
        info "  WSL 网络不可达 upstream → 启用 Windows 侧 curl.exe 转发"
    fi

    local env_args="-u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy"
    local bridge_env="env $env_args \
        OPENAI_BRIDGE_UPSTREAM=$resolved_upstream \
        OPENAI_BRIDGE_UPSTREAM_ORIGINAL=$upstream \
        OPENAI_BRIDGE_KEY=$key \
        OPENAI_BRIDGE_MODEL=$model \
        OPENAI_BRIDGE_HOST=$resolved_host"
    if [[ "$need_win_curl" -eq 1 ]]; then
        bridge_env="$bridge_env OPENAI_BRIDGE_USE_WIN_CURL=1"
    fi

    # HTTPS upstream 自动跳过 TLS 验证（自签证书场景：tailscale serve、内网 API）
    local extra_args=""
    if [[ "$upstream" == https:* ]]; then
        extra_args="--skip-tls-verify"
    fi

    nohup $bridge_env \
        python3 option-llmswitch/openai_bridge.py --port "$port" $extra_args \
        > "$HOME/.cache/openai_bridge.log" 2>&1 &
    disown

    # 等待启动
    for i in 1 2 3 4 5; do
        sleep 1
        health=$(curl -s --max-time 2 "http://127.0.0.1:${port}/health" 2>/dev/null)
        [[ -n "$health" ]] && break
    done

    [[ -n "$health" ]]
}
