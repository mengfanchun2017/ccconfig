#!/bin/bash
# lib/ensure-bridge.sh
# Anthropic↔OpenAI bridge 生命周期（port 8898）
# 被 init-llm.sh 切换时 + status.sh SessionStart hook 自愈共用
#
# 简化原则：仅做健康检测 + upstream 匹配 + 启停。WSL 网络问题由 Windows 侧用户处理。
#
# 依赖: 调用方已 source lib/colors.sh（info/warn）

CCCONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_PORT=8898
BRIDGE_WD_PID="$HOME/.cache/bridge-watchdog.pid"
BRIDGE_WD_LOG="$HOME/.cache/bridge-watchdog.log"

_bridge_wd_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$BRIDGE_WD_LOG"; }

# bridge watchdog：只守护进程存活 —— bridge 没了就按「当前」preset 拉起
#
# why 不做 upstream 主动探测：探测失败 ≠ bridge 故障。网络断了重启 bridge 修不了，
#     反而杀掉正在服务的进程、打断进行中的请求（旧版就是这么把好 bridge 换掉的）。
# why 每轮读 llm-current 而非启动时绑参：watchdog wrapper 是启动时一次性生成的，
#     绑参后切 preset 会拿旧 upstream 覆盖用户刚选的 preset。
# 参数: cfg(merged 缓存 llm-merged.json 路径，由 init-llm.sh merge 生成)
start_bridge_watchdog() {
    local cfg="${1:-}"
    local initial_preset="${2:-}"
    [[ -z "$cfg" ]] && return 0

    mkdir -p "$HOME/.cache"
    # 整段用 flock 串行化：并发 ensure_bridge（SessionStart 自愈 + 手工切 preset）
    # 交错执行「stop-all 然后 start」会留下两个 watchdog，双双看到端口掉线 →
    # 互相 kill/spawn 抖动。锁只活在子 shell 里，不污染调用方的 fd。
    (
        flock 9 2>/dev/null || true

        # 无条件清掉残留（旧版只认 PID 文件，被覆盖/失联的老 watchdog 会永久残留）
        stop_bridge_watchdog >/dev/null 2>&1 || true

        local wrapper="$HOME/.cache/bridge-watchdog-$RANDOM-$$.sh"
        cat > "$wrapper" << WDEOF
#!/bin/bash
# 自记 PID：调用方拿到的 \$! 是 setsid 的 pid，而 setsid 在成为进程组长时会 fork，
# 于是父进程写进 PID 文件的是那个短命进程 —— 文件里的值长期是错的，teardown 只能
# 靠 pgrep 兜底。让 wrapper 自己写 \$\$ 才是真实 pid。
echo \$\$ > "${BRIDGE_WD_PID}"
fail=0
while true; do
    if curl -s --max-time 3 http://127.0.0.1:${BRIDGE_PORT}/health >/dev/null 2>&1; then
        [[ \$fail -gt 0 ]] && echo "[\$(date '+%Y-%m-%d %H:%M:%S')] bridge 恢复 (第 \${fail} 次重试)" >> "${BRIDGE_WD_LOG}"
        fail=0
        sleep ${BRIDGE_WD_INTERVAL:-10}
        continue
    fi
    fail=\$((fail + 1))
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] bridge 无响应，按当前 preset 拉起 (第 \${fail} 次)" >> "${BRIDGE_WD_LOG}"
    # 传本 wrapper 启动时的 preset 作 fallback：llm-current 缺失时仍能兜住
    rc=0
    bash "${CCCONFIG_ROOT}/lib/bridge-restart.sh" "${cfg}" "${initial_preset}" >> "${BRIDGE_WD_LOG}" 2>&1 || rc=\$?
    # rc=2 是永久性错误（preset 已从配置删除 / 配置不可用）：重启一万次也没用，
    # 旧版在这里以 60s 上限无限空转刷日志。改为长退避，仍保留恢复能力。
    if [[ \$rc -eq 2 ]]; then
        echo "[\$(date '+%Y-%m-%d %H:%M:%S')] preset 配置不可用（rc=2），300s 后再试；修: bash maintain.sh llm" >> "${BRIDGE_WD_LOG}"
        sleep 300
        continue
    fi
    sleep_sec=\$(( 5 * (1 << (fail - 1)) ))
    [[ \$sleep_sec -gt 60 ]] && sleep_sec=60
    sleep \$sleep_sec
done
WDEOF
        chmod +x "$wrapper"
        setsid nohup "$wrapper" > "$BRIDGE_WD_LOG" 2>&1 < /dev/null &
        disown $! 2>/dev/null || true
        # 等 wrapper 写进它自己的 pid（最多 2s）：不这样，紧接着的 selfheal
        # 会读到空文件、判定"无 watchdog"而再起一个
        local _i
        for _i in 1 2 3 4; do
            sleep 0.5
            [[ -s "$BRIDGE_WD_PID" ]] && break
        done
        _bridge_wd_log "watchdog 启动 (cfg=${cfg} preset=${initial_preset:-<llm-current>})"
    ) 9>"$HOME/.cache/bridge-watchdog.lock"
}

stop_bridge_watchdog() {
    if [[ -f "$BRIDGE_WD_PID" ]]; then
        local wd_pid
        wd_pid=$(cat "$BRIDGE_WD_PID" 2>/dev/null) || true
        if [[ -n "$wd_pid" ]]; then
            kill "$wd_pid" 2>/dev/null || true
            _bridge_wd_log "watchdog 停止 (PID: $wd_pid)"
        fi
        rm -f "$BRIDGE_WD_PID"
    fi
    # PID 文件失联/被覆盖时兜底（pattern 用 [[]] 避免 pgrep 匹配到自己这条命令）
    local p
    for p in $(pgrep -f "bridge-watchdo[g]-" 2>/dev/null || true); do
        [[ "$p" == "$$" ]] && continue
        kill "$p" 2>/dev/null || true
    done
}

# bridge 运行态一致性检查（只读报告 + 可选修复）。
# 返回 0=一致  1=有不一致
# 用法: bridge_state_check [--fix] [<merged_cfg>]
#
# 覆盖三类旧版无人检查的不一致：
#   ① bridge 在跑但当前 preset 是直连（切走后残留的孤儿，占用端口并可能被误连）
#   ② 当前 preset 需要 bridge 但它没在跑
#   ③ bridge 在跑但没有有效 watchdog（bridge 挂掉不会自动拉起）
bridge_state_check() {
    local fix=0 cfg=""
    local a
    for a in "$@"; do
        case "$a" in
            --fix) fix=1 ;;
            *) [[ -n "$a" ]] && cfg="$a" ;;
        esac
    done
    local port="${BRIDGE_PORT:-8898}"
    local running=0
    curl -s --max-time 2 "http://127.0.0.1:${port}/health" >/dev/null 2>&1 && running=1

    local cur=""
    [[ -f "$HOME/.claude/llm-current" ]] && cur="$(tr -d '[:space:]' < "$HOME/.claude/llm-current")"
    local mode=""
    if [[ -n "$cur" && -n "$cfg" && -f "$cfg" ]]; then
        mode="$(preset_bridge_mode "$cur" "$cfg" 2>/dev/null)" || mode=""
    fi

    local problems=0
    if (( running )) && [[ "$mode" == "direct" ]]; then
        warn "bridge($port) 在跑，但当前 preset '${cur:-?}' 是直连 → 孤儿进程"
        problems=1
        if (( fix )); then
            stop_bridge_watchdog >/dev/null 2>&1 || true
            _kill_by_port "$port"
            ok "  已停用孤儿 bridge 与 watchdog"
            running=0   # 必须就地更新：后面判断 watchdog 若还用旧值，会给一个已被
                        # 停掉的 bridge 起 watchdog，而它随后会按直连 preset 空转
        fi
    fi
    if (( ! running )) && [[ "$mode" == "bridge" ]]; then
        warn "当前 preset '$cur' 需要 bridge，但 bridge($port) 没在跑"
        problems=1
        if (( fix )); then
            local bc up model key hh
            bc="$(read_bridge_config "$cfg" "$cur" 2>/dev/null)" || bc=""
            IFS='|' read -r up model key hh <<< "$bc"
            if [[ -n "$up" ]] && ensure_bridge "$up" "$model" "$key" "$hh" "$cfg" "$cur" >/dev/null 2>&1; then
                ok "  已拉起 bridge"
                running=1
            else
                warn "  拉起失败 — tail -30 ~/.cache/openai_bridge.log"
            fi
        fi
    fi
    # watchdog 只在「确实该有 bridge 且它正在跑」时才有意义
    if (( running )) && [[ "$mode" == "bridge" ]]; then
        local wd=""
        [[ -f "$BRIDGE_WD_PID" ]] && wd="$(tr -d '[:space:]' < "$BRIDGE_WD_PID")"
        if [[ -z "$wd" ]] || ! kill -0 "$wd" 2>/dev/null; then
            warn "bridge 在跑但没有有效 watchdog — 它挂掉后不会自动拉起"
            problems=1
            if (( fix )); then
                start_bridge_watchdog "$cfg" "$cur" >/dev/null 2>&1 || true
                ok "  已重启 watchdog"
            fi
        fi
    fi
    # --fix 之后按修完的实态重算：已修好的项不该继续算作"遗留问题"，
    # 否则 `fix && ok` 永远不成立，调用方无法区分"修好了"和"没修好"
    if (( fix )); then
        problems=0
        running=0
        curl -s --max-time 2 "http://127.0.0.1:${port}/health" >/dev/null 2>&1 && running=1
        [[ "$mode" == "direct" ]] && (( running )) && problems=1
        [[ "$mode" == "bridge" ]] && (( ! running )) && problems=1
        if [[ "$mode" == "bridge" ]] && (( running )); then
            local _wd2=""
            [[ -f "$BRIDGE_WD_PID" ]] && _wd2="$(tr -d '[:space:]' < "$BRIDGE_WD_PID")"
            { [[ -z "$_wd2" ]] || ! kill -0 "$_wd2" 2>/dev/null; } && problems=1
        fi
    fi
    (( problems )) && return 1
    return 0
}


_bridge_supported() {
    local upstream="$1"
    [[ -z "$upstream" ]] && return 1
    [[ "$upstream" == *"/anthropic"* ]] && return 1
    [[ "$upstream" == *"://127.0.0.1"* ]] && return 1
    return 0
}

# preset 的接入模式判定 —— **唯一来源**。stdout 输出三态之一：
#   bridge   = 需要 bridge（OpenAI-only 端点）
#   direct   = 不需要（Anthropic 原生端点 / loopback）
#   conflict = 配置冲突（use_bridge:false 却是 OpenAI-only 端点，直连必失败）
# 返回 0=判定成功；1=参数缺失或 preset 不存在
#
# why 抽出来：这套判定原本在 4 处各写一份（ensure_bridge / bridge-restart /
# switch_llm / test_llm），规则已经漂移过一次，每次加字段都得改四处、漏一处就是
# 静默行为不一致。调用方从"自己判断"改为"读这个函数的结论"。
# 用法: preset_bridge_mode <preset> <merged_cfg>
preset_bridge_mode() {
    local preset="$1" cfg="$2"
    [[ -n "$preset" && -n "$cfg" ]] || return 1
    python3 - "$cfg" "$preset" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
llm = d.get('llms', {}).get(sys.argv[2])
if llm is None:
    sys.exit(1)
up = llm.get('base_url') or ''
ub = llm.get('use_bridge')
if not up:
    print('direct'); raise SystemExit(0)
if ub is True:
    print('bridge'); raise SystemExit(0)          # 用户显式点名走桥
if '/anthropic' in up or '://127.0.0.1' in up:
    print('direct'); raise SystemExit(0)          # 原生端点，桥无意义
if ub is False:
    print('conflict'); raise SystemExit(0)        # OpenAI-only + 显式直连 = 必失败
print('bridge')                                    # OpenAI-only，自动走桥
PYEOF
}

# 读 merged 缓存(llm-merged.json)预设的 base_url|model|key|host_header（无 upstream_original 兼容）
# host_header 可选：tailscale/SSH 透传场景证书 SAN 不匹配 IP 时，把 SNI+Host 改成证书里的真实域名/IP
read_bridge_config() {
    python3 - "$1" "$2" << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    llm = d.get('llms', {}).get(sys.argv[2], {})
    print(f"{llm.get('base_url','')}|{llm.get('model','')}|{llm.get('key','')}|{llm.get('host_header','')}")
except Exception:
    sys.exit(1)
PYEOF
}

# 判定是否走 Windows 侧 curl.exe 转发；命中输出 "--use-win-curl"，否则空串。
#
# why 抽成函数：首启（ensure_bridge）与 watchdog 重启（bridge-restart.sh）必须用
#      同一套判定。旧版两处各写一份，watchdog 那份漏了 force_win_curl 且只有字面 IP
#      正则 —— 域名上游首启走 win_curl、一重启就退回 httpx，传输栈静默漂移。
# 用法: bridge_win_curl <upstream> [<cfg>] [<preset>]
bridge_win_curl() {
    local upstream="$1" cfg="${2:-}" preset="${3:-}"
    command -v curl.exe &>/dev/null || return 0
    # RFC1918 (10/8, 172.16/12, 192.168/16) + tailscale CGNAT (100.64/10)：这些段
    # 通常是企业内网 / tailscale 跳板，非镜像网络的 WSL 看不到 Windows 侧路由
    if [[ "$upstream" =~ ://(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.) ]]; then
        echo "--use-win-curl"
        return 0
    fi
    # opt-in：域名形式的上游不命中上面的正则，preset 可显式声明
    if [[ -n "$cfg" && -n "$preset" ]] && python3 -c "
import json, sys
try:
    sys.exit(0 if json.load(open(sys.argv[1])).get('llms', {}).get(sys.argv[2], {}).get('force_win_curl') else 1)
except Exception:
    sys.exit(1)
" "$cfg" "$preset" 2>/dev/null; then
        echo "--use-win-curl"
    fi
    return 0
}

# 按端口杀掉占用进程并等端口真正释放。
# why 循环 kill 而非只 kill head -1：旧版只杀第一个 pid，第二个绑定进程会存活，
#     新 bridge 于是 EADDRINUSE，而失败原因只落在 openai_bridge.log 里。
# why 等释放而非裸 sleep 1：内核收回端口有延迟，只 sleep 1 偶发抢不到。
# 用法: _kill_by_port <port>
_kill_by_port() {
    local port="$1" pid i
    for pid in $( { lsof -ti :"$port" 2>/dev/null || true; } ); do
        kill "$pid" 2>/dev/null || true
    done
    for i in 1 2 3 4 5 6; do
        [[ -z "$( { lsof -ti :"$port" 2>/dev/null || true; } )" ]] && return 0
        sleep 0.5
    done
    return 0
}

# 拉起 bridge 进程（不等 health、不碰 watchdog）—— ensure_bridge 与 bridge-restart.sh
# 共用同一份，避免两处 spawn 逻辑漂移。
#
# why setsid 直起而非写 wrapper 脚本：旧版把 env+命令落成 /tmp/*.sh 再执行，起因是
#     裸 `( cd; nohup ... & )` 的子 shell 退出会 SIGHUP 掉 python。setsid 直接给新
#     会话（无控制终端 → 收不到 SIGHUP）解决同一问题，同时**不必把 API Key 写进
#     磁盘**（旧 wrapper 含明文 Key，脚本被中断时就残留在 /tmp）。
# 用法: _bridge_spawn <upstream> <model> <key> <host_header> <win_curl> [<port>] [<log>]
_bridge_spawn() {
    local upstream="$1" model="$2" key="$3" host_header="$4" win_curl="$5"
    local port="${6:-${BRIDGE_PORT:-8898}}" log="${7:-$HOME/.cache/openai_bridge.log}"
    local extra_args=""
    [[ "$upstream" == https:* ]] && extra_args="--skip-tls-verify"
    mkdir -p "$HOME/.cache"   # 目录不存在会让重定向失败、bridge 根本起不来
    (
        cd "$CCCONFIG_ROOT" || exit 1
        setsid nohup env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy \
            -u ALL_PROXY -u all_proxy \
            OPENAI_BRIDGE_UPSTREAM="$upstream" \
            OPENAI_BRIDGE_KEY="$key" \
            OPENAI_BRIDGE_MODEL="$model" \
            OPENAI_BRIDGE_HOST="$host_header" \
            python3 option-llmswitch/openai_bridge.py --port "$port" $extra_args $win_curl \
            >> "$log" 2>&1 < /dev/null &
    )
    return 0
}

# 确保 bridge 跑且 upstream 正确
# 用法: ensure_bridge <upstream> <model> <key> [<host_header>]
# host_header 可选：tailscale/SSH 透传场景证书 SAN 不匹配 IP 时，把 SNI+Host 改成证书里的真实域名/IP
# 返回 0=就绪 1=失败
ensure_bridge() {
    local upstream="$1" model="$2" key="$3" host_header="${4:-}"
    local cfg="${5:-}" preset="${6:-}"
    _bridge_supported "$upstream" || return 1

    # 依赖预检：openai_bridge.py import httpx/fastapi + uvicorn 启动。
    # 缺了 bridge 静默 ModuleNotFoundError 起不来，且旧版本是"切过去才发现"。
    # 这里先查，缺就说明装法，不让 ensure_bridge 无头绪失败。
    if ! python3 -c "import httpx, fastapi, uvicorn" 2>/dev/null; then
        err "bridge 依赖缺失（httpx/fastapi/uvicorn）"
        err "  修: pip3 install --break-system-packages --user httpx fastapi uvicorn"
        err "  或: bash maintain.sh self（init-ubuntu 按 conf/python-requirements.txt 自动装）"
        return 1
    fi

    # win_curl 期望值必须在 health 比较之前算出来：复用分支要拿它比对运行态，
    # 否则改了 force_win_curl 也不会重启 bridge，配置形同虚设。
    local win_curl
    win_curl="$(bridge_win_curl "$upstream" "$cfg" "$preset")"

    # 已健康且 upstream 匹配 → 确保 watchdog 在跑后返回
    local health
    health=$(curl -s --max-time 1 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null) || true
    local old_pid="" need_restart=1
    # 无条件取占端口的 pid（Why: lsof 无结果时 exit 1 + pipefail + set -e 会顶掉函数，
    # 所以 || true 兜底）。挂在 health 超时后面的旧版在这里拿不到 pid → 不杀 →
    # 新进程 EADDRINUSE 起不来，挂死进程永远占着 8898 用旧配置服务
    old_pid=$( { lsof -ti :${BRIDGE_PORT} 2>/dev/null || true; } | head -1 || true)
    old_pid="${old_pid:-}"
    if [[ -n "$health" ]]; then
        local cur_upstream cur_model cur_wc
        cur_upstream=$(echo "$health" | python3 -c "import json,sys; print(json.load(sys.stdin).get('upstream',''))" 2>/dev/null || echo "")
        # 必须同时比对 model：flash/pro 两个 preset 常用同一个 upstream URL
        # （同网关不同模型），只比 upstream 会复用旧 bridge —— 切 pro 实际仍在
        # 用 flash，且探测"通过"是假阳性（测的是旧 model）
        cur_model=$(echo "$health" | python3 -c "import json,sys; print(json.load(sys.stdin).get('upstream_model',''))" 2>/dev/null || echo "")
        cur_wc=$(echo "$health" | python3 -c "import json,sys; print(json.load(sys.stdin).get('use_win_curl',False))" 2>/dev/null || echo "")
        if [[ "$cur_upstream" == "$upstream" && "$cur_model" == "$model" ]]; then
            # 传输栈也要比，且必须**双向**比：只查「期望开、实际关」会漏掉反向
            # （运行中的 win_curl 残留时换了不该用它上游 → 上游只在 WSL 可达就挂）。
            # 两边任一不符都重启，判据是 health 里的 use_win_curl。
            local want_wc="False"
            [[ -n "$win_curl" ]] && want_wc="True"
            if [[ -n "$cur_wc" && "$cur_wc" != "$want_wc" ]]; then
                info "  win_curl 模式不符（期望 $want_wc，实际 $cur_wc），重启 bridge..."
            else
                start_bridge_watchdog "$cfg" "$preset"
                return 0
            fi
        elif [[ "$cur_upstream" == "$upstream" ]]; then
            info "  model 变化 ($cur_model → $model)，重启 bridge..."
        else
            info "  upstream 变化 ($cur_upstream → $upstream)，重启 bridge..."
        fi
    fi

    # 杀老 bridge 并等端口释放（可能不止一个进程占着）
    _kill_by_port "$BRIDGE_PORT"

    _bridge_spawn "$upstream" "$model" "$key" "$host_header" "$win_curl" "$BRIDGE_PORT"

    # 等启动（最多 5s）
    local h=""
    for _ in 1 2 3 4 5; do
        sleep 1
        h=$(curl -s --max-time 2 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null) || true
        [[ -n "$h" ]] && break
    done

    [[ -n "$h" ]] && start_bridge_watchdog "$cfg" "$preset"
}

# 仅自愈：env 指向 127.0.0.1:8898 但 bridge 死了时拉起
# 用法: selfheal_bridge <merged 缓存路径>
# 返回 0=已检查且健康 / 已成功拉起  1=尝试拉起但失败  10=不适用（未检查，别报"健康"）
#
# why 区分 0 与 10：旧版三条"什么都没做"的分支（无 cfg / env 不指向桥 / 取不到
# preset）也返回 0，调用方于是打印"bridge 健康"—— 其实一次检查都没做，是最难查的
# 那类假阳性。10 让调用方知道这是"跳过"而非"通过"。
selfheal_bridge() {
    local cfg="$1"
    [[ -z "$cfg" ]] && return 10

    # env 不指向 8898 → 当前 preset 不需要 bridge
    local sf="$HOME/.claude/settings.json"
    [[ -f "$sf" ]] || return 10
    if ! grep -q '127.0.0.1:8898' "$sf" 2>/dev/null; then
        return 10
    fi

    # 到这里确实该有 bridge：健康就直接过
    if curl -s --max-time 1 "http://127.0.0.1:${BRIDGE_PORT}/health" >/dev/null 2>&1; then
        return 0
    fi

    # 读「当前」preset 配置拉起。
    # why 先读本地 llm-current 再回落 llm.json.current：ADR-0020 之后 current 的
    #     权威来源是机器本地文件（llm.json.current 只是兼容旧机器的副本，可能过时），
    #     读错会用别的 preset 起 bridge。
    local cur
    cur="$( [[ -f "$HOME/.claude/llm-current" ]] && tr -d '[:space:]' < "$HOME/.claude/llm-current" || true )"
    if [[ -z "$cur" ]]; then
        cur=$(python3 -c "import json; print(json.load(open('$cfg')).get('current',''))" 2>/dev/null) || true
    fi
    if [[ -z "$cur" ]]; then
        warn "  bridge 无响应，但取不到当前 preset（llm-current 与缓存都为空）"
        return 1
    fi

    local bc
    bc=$(read_bridge_config "$cfg" "$cur") || {
        warn "  bridge 无响应，且读不到 preset '$cur' 的配置（preset 可能已删除）"
        return 1
    }
    # why local：防 bash 动态作用域污染调用者同名变量
    local upstream model key host_header
    IFS='|' read -r upstream model key host_header <<< "$bc"
    if [[ -z "$upstream" ]]; then
        warn "  bridge 无响应，preset '$cur' 无 upstream（配置不完整）"
        return 1
    fi

    warn "  bridge ($BRIDGE_PORT) 未响应，自动拉起 ($cur)..."
    ensure_bridge "$upstream" "$model" "$key" "$host_header" "$cfg" "$cur"
}
