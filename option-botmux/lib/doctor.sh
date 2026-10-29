#!/bin/bash
# ccconfig/option-botmux/lib/doctor.sh — botmux 健康体检 / 自动修复
#
# 背景（2026-10-29 实测故障）：botmux daemon 与飞书长连接全部「在线」，
#   botmux status / list 都显示正常，但飞书里发消息毫无反馈。真因是会话的
#   worker 卡死 + tmux pane 已死，消息只堆进 ~/.botmux/data/queues/*.jsonl。
#   结构性教训：**botmux 自带的状态命令只反映 daemon/supervisor 存活，
#   不反映「会话能否真的干活」**。本模块补的正是这段盲区。
#
# 判定原则：只信权威信号，不做猜测
#   · cliId 取值与对应可执行名 —— 从二进制预设表提取（见 CLI_EXEC 表）
#   · cliPathOverride —— botmux 自己支持的显式覆盖字段，非猜测
#   · cliRuntime —— 自定义 runtime，不可静态判定，跳过而非误报
#   · wrapperCli / cliLaunchMode —— 网关包装，包了一层，单独提示
#
# 退出码：0 = 全部通过（可能有 warn）；1 = 有 error（需修）；2 = botmux 未安装

set -uo pipefail

_BMX_DOCTOR_RC=0
_BMX_ERR=0
_BMX_WARN=0

_bmx_d_pass() { echo "  ${GREEN-}✓${NC-} $*"; }
_bmx_d_warn() { echo "  ${YELLOW-}!${NC-} $*"; _BMX_WARN=$((_BMX_WARN + 1)); }
_bmx_d_err()  { echo "  ${RED-}✗${NC-} $*"; _BMX_ERR=$((_BMX_ERR + 1)); }

# ── cliId → 可执行名（从 botmux 二进制预设表提取，v3.54.0）──
# 特殊项：
#   codex-app  = 桌面 App，非 CLI，不做命令检查
#   mira       = Web API，非本地 CLI
#   oh-my-pi   = 第三方，命令名与 cliId 同名
#   cursor     = 仅作为 ttadk-x-cursor 的底层，本机无独立 cursor CLI 时告警合理
_bmx_cli_exec() {
    case "$1" in
        claude-code) echo "claude" ;;
        codex)       echo "codex" ;;
        codex-app)   echo "" ;;          # 桌面 App
        mira)        echo "" ;;          # Web API
        aiden)       echo "aiden" ;;
        traex)       echo "traex" ;;
        coco)        echo "coco" ;;
        gemini)      echo "gemini" ;;
        opencode)    echo "opencode" ;;
        opencode2)   echo "opencode2" ;;
        cursor)      echo "cursor" ;;
        mir)         echo "mircli" ;;
        oh-my-pi)    echo "oh-my-pi" ;;
        pi)          echo "pi" ;;
        *)           echo "__UNKNOWN__" ;;
    esac
}

# ── 1. 单个 bot 的配置体检 ──
# 参数： <bot.json 的 python 解析结果（每行一个 JSON）>
_bmx_check_bots() {
    local bots_json="$1"
    echo "${BOLD-}配置（bots.json）${NC-}"

    local n
    n="$(printf '%s' "$bots_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d))' 2>/dev/null || echo 0)"
    if [ "$n" = "0" ]; then
        _bmx_d_warn "未配置任何 bot（跑 guide 扫码建应用）"
        return
    fi

    printf '%s' "$bots_json" | python3 -c '
import json,sys
for b in json.load(sys.stdin):
    app=b.get("larkAppId","")
    print("\t".join([
        app,
        b.get("cliId","") or "",
        b.get("cliPathOverride","") or "",
        b.get("wrapperCli","") or "",
        b.get("cliLaunchMode","") or "",
        ("yes" if b.get("cliRuntime") else "no"),
        ",".join(b.get("allowedUsers",[]) or []),
    ]))
' | while IFS=$'\t' read -r app cliid pathov wrapper launchmode hasruntime owners; do
        local tag="${app:0:12}…"
        echo "  ${GRAY-}[$tag]${NC-}"

        # owner 必须存在 —— 没有它 bot 拒绝所有人（实测：空 allowedUsers 收不到任何消息）
        if [ -z "$owners" ]; then
            _bmx_d_err "allowedUsers 为空 → 该 bot 会拒绝所有消息"
        else
            _bmx_d_pass "owner: $owners"
        fi

        # cliRuntime 是自定义运行时，静态判不了，明确跳过而不是猜
        if [ "$hasruntime" = "yes" ]; then
            _bmx_d_warn "cliId=$cliid 走自定义 cliRuntime —— 可执行性无法静态判定，跳过"
            continue
        fi

        # cliPathOverride 是 botmux 显式支持的覆盖字段，优先信它
        if [ -n "$pathov" ]; then
            if [ -x "$pathov" ]; then
                _bmx_d_pass "cliPathOverride: $pathov"
            else
                _bmx_d_err "cliPathOverride 指向的文件不存在或不可执行: $pathov"
                _bmx_d_err "  → bot 会话起不来。修正或删掉该字段"
            fi
        else
            local exe; exe="$(_bmx_cli_exec "$cliid")"
            if [ "$exe" = "__UNKNOWN__" ]; then
                _bmx_d_warn "未知 cliId=$cliid（本机 botmux 可能比本脚本新，检查适配器是否已装）"
            elif [ -z "$exe" ]; then
                _bmx_d_pass "cliId=$cliid（非 CLI 型适配器，无需本机命令）"
            elif command -v "$exe" >/dev/null 2>&1; then
                _bmx_d_pass "cliId=$cliid → $exe 已安装"
            else
                _bmx_d_err "cliId=$cliid 需要命令 [$exe]，但本机【未安装】"
                _bmx_d_err "  → 这是最隐蔽的坑：daemon 与长连接都显示正常，"
                _bmx_d_err "     但每次消息都起不来 CLI，飞书里表现为【完全无反馈】"
                _bmx_d_err "  → 修：装 $exe，或把 cliId 改回已装的 CLI（见 fix）"
            fi
        fi

        # 网关包装类：包了一层命令，底层 CLI 还得另查
        [ -n "$wrapper" ] && _bmx_d_warn "wrapperCli=$wrapper（网关包装：须已完成该网关登录，且底层 $cliid 已装）"
        [ -n "$launchmode" ] && _bmx_d_warn "cliLaunchMode=$launchmode（特殊启动模式，依赖对应网关）"
    done
}

# ── 2. 会话健康：查「会话真的能干活吗」──
# 这是本次故障的核心盲区：daemon 在线 ≠ 会话可用
_bmx_check_sessions() {
    echo "${BOLD-}会话健康（daemon 在线 ≠ 会话能干活）${NC-}"

    local list_out
    list_out="$(bmx list --plain 2>/dev/null || true)"

    if printf '%s' "$list_out" | grep -qE '没有活跃会话|No active sessions'; then
        _bmx_d_pass "无活跃会话（正常，下条消息会冷启动）"
        _bmx_check_queue
        return
    fi

    # 逐个会话核验：tmux pane 是否存活 + worker 是否卡在 D 状态
    local rows
    rows="$(printf '%s' "$list_out" | awk -F'│' '/│/{gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$6); gsub(/^ +| +$/,"",$7); if($2!=""&&$2!="id") print $2"\t"$6"\t"$7"}' || true)"
    [ -z "$rows" ] && rows="$(printf '%s' "$list_out" | grep -oE '^[0-9a-f]{8}' | sed 's/$/\t\t/' || true)"

    if [ -z "$rows" ]; then
        _bmx_d_warn "无法解析会话列表（botmux 输出格式可能变了）"
    else
        while IFS=$'\t' read -r sid pid status; do
            [ -z "$sid" ] && continue
            local bad=0

            # worker 卡 D 状态 = 不可中断 I/O 等待，SIGKILL 都杀不掉（实测：
            # 自持 FIFO 读写端导致 anon_pipe_write 永久阻塞）
            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                local st
                st="$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null || true)"
                if [ "$st" = "D" ]; then
                    _bmx_d_err "会话 $sid worker($pid) 卡在 D 状态（不可中断 I/O）→ 该会话永久无响应"
                    _bmx_d_err "  → SIGKILL 无效，只能重启 daemon 清理（见 fix）"
                    bad=1
                fi
            fi

            # tmux pane 已死 = 前端没了，消息只会堆积
            local pane
            pane="$(tmux -L botmux list-panes -t "bmx-${sid:0:8}" -F '#{pane_dead}' 2>/dev/null | head -1 || true)"
            if [ "$pane" = "1" ]; then
                _bmx_d_err "会话 $sid 的 tmux pane 已死 → 该话题消息只堆积、不处理"
                bad=1
            fi

            [ "$bad" = "0" ] && _bmx_d_pass "会话 $sid 正常（pid=${pid:-?} ${status:-}）"
        done <<< "$rows"
    fi

    _bmx_check_queue
}

# ── 3. 消息队列积压：故障最直接的可见症状 ──
_bmx_check_queue() {
    local total=0 dangling=0 f lines
    # ICP 探测：与 daemon 同进程级验证。daemon 活着但队列不消费 = 明显异常
    for f in "$HOME"/.botmux/data/queues/*.jsonl; do
        [ -e "$f" ] || continue
        lines="$(wc -l < "$f" 2>/dev/null || echo 0)"
        total=$((total + lines))
        [ "$lines" -gt 0 ] && dangling=$((dangling + 1))
    done

    if [ "$total" -eq 0 ]; then
        _bmx_d_pass "消息队列空"
    else
        # 有活跃会话时队列非空是正常的（正在处理）；无活跃会话 + 队列非空 = 卡死
        local has_sess
        has_sess="$(bmx list --plain 2>/dev/null | grep -cE '^[0-9a-f]{8}' || true)"
        if [ "${has_sess:-0}" -eq 0 ]; then
            _bmx_d_err "队列积压 $total 条消息，但没有活跃会话消费 → 飞书里发消息【无任何反馈】"
            _bmx_d_warn "  → 见 fix：清队列并重启（队列已备份到 data/queues.bak/）"
        else
            _bmx_d_warn "队列有 $total 条待处理（存在活跃会话，可能正在消费）"
        fi
    fi
}

# ── 4. 上游状态：botmux 与飞书官方侧的连接 ──
_bmx_check_upstream() {
    echo "${BOLD-}上游与飞书侧${NC-}"

    # 长连接是否建立（这是消息能进来的前提）
    local logf="$HOME/.botmux/logs/daemon-0-out.log"
    if [ -f "$logf" ]; then
        if tail -200 "$logf" 2>/dev/null | grep -q 'Daemon WSClient started'; then
            _bmx_d_pass "飞书长连接已建立（WSClient started）"
        else
            _bmx_d_err "日志里未见「Daemon WSClient started」→ 长连接可能未建立，消息根本进不来"
        fi
        # worker 无响应时 botmux 自己的告警（本次故障留下的确证）
        if tail -300 "$logf" 2>/dev/null | grep -qE 'worker did not exit after SIGTERM'; then
            _bmx_d_warn "近期出现过「worker SIGTERM 无响应」→ 确认有卡死 worker（见会话健康）"
        fi
        if tail -300 "$logf" 2>/dev/null | grep -q 'Ignored unbound input commit'; then
            _bmx_d_warn "近期有「Ignored unbound input commit」→ 首条消息提交未确认，消息会被丢弃"
        fi
    else
        _bmx_d_warn "找不到 daemon 日志 $logf"
    fi

    # botmux 与飞书官方各自报的权限缺口（不阻断，但会让部分能力失效）
    if tail -300 "$HOME/.botmux/logs/daemon-0-err.log" 2>/dev/null | grep -q 'vcMeetingAgent 已启用但缺'; then
        _bmx_d_warn "缺 VC 会议权限 vc:meeting.bot.realtime:write（仅影响会议智能体，不阻断聊天）"
    fi

    # runtime-sweep 对已删会话目录的噪音（本次清理后残留，无害但会刷日志）
    if tail -100 "$HOME/.botmux/logs/daemon-0-err.log" 2>/dev/null | grep -q 'runtime-sweep.*ENOTDIR'; then
        _bmx_d_warn "runtime-sweep 残留噪音（已删会话的 env-stamp 目录）——无害，重启后仍在说明是历史记录"
    fi
}

# ── 5. 上游版本漂移：本脚本的 cliId 表可能落后于已装的 botmux ──
_bmx_check_version_drift() {
    local ver; ver="$(botmux_version 2>/dev/null || echo "")"
    [ -z "$ver" ] && return
    local bin; bin="$(_botmux_bin 2>/dev/null || true)"
    [ -z "$bin" ] && return

    # 从二进制里现取 cliId 集合，与本脚本表比对 —— 官方加了适配器就能发现
    local live
    live="$(python3 - "$bin" <<'PY' 2>/dev/null || true
import re,sys
try:
    d=open(sys.argv[1],'rb').read()
except Exception: sys.exit(0)
ids=set()
for m in re.finditer(rb'cliId:"([a-z0-9\-_]+)"', d):
    ids.add(m.group(1).decode())
print(" ".join(sorted(ids)))
PY
)"
    [ -z "$live" ] && return

    local known="claude-code codex codex-app mira aiden traex coco gemini opencode opencode2 cursor mir oh-my-pi pi"
    local new=""
    for id in $live; do
        case " $known " in *" $id "*) ;; *) new="$new $id" ;; esac
    done
    if [ -n "$new" ]; then
        _bmx_d_warn "botmux $ver 有本脚本未收录的 cliId:$new → 体检表需更新（option-botmux/lib/doctor.sh）"
    else
        _bmx_d_pass "cliId 表与 botmux $ver 一致"
    fi
}

# ── 主入口 ──
bmx_doctor() {
    local do_fix="${1:-}"
    _BMX_DOCTOR_RC=0; _BMX_ERR=0; _BMX_WARN=0

    echo "${BOLD-}botmux 体检${NC-}"

    if ! has_botmux; then
        _bmx_d_err "botmux 未安装"
        return 2
    fi
    _bmx_d_pass "botmux $(botmux_version)"

    # daemon 存活（必要但不充分 —— 本次故障 daemon 全程"在线"）
    if daemon_running; then
        _bmx_d_pass "daemon 在运行"
    else
        _bmx_d_err "daemon 未运行 → 飞书消息无人接收"
    fi

    local bots_json
    bots_json="$(bmx setup list --json 2>/dev/null | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); b=d.get("bots") if isinstance(d,dict) else d
    print(json.dumps(b if isinstance(b,list) else []))
except Exception: print("[]")' 2>/dev/null || echo '[]')"

    echo ""
    _bmx_check_bots "$bots_json"
    echo ""
    _bmx_check_sessions
    echo ""
    _bmx_check_upstream
    echo ""
    _bmx_check_version_drift

    echo ""
    if [ "$_BMX_ERR" -gt 0 ]; then
        echo "  ${RED-}$_BMX_ERR 项错误、$_BMX_WARN 项警告${NC-}"
        if [ "$do_fix" = "--fix" ]; then
            bmx_doctor_fix
        else
            echo "  ${GRAY-}自动修复: bash option-botmux/init.sh fix${NC-}"
        fi
        return 1
    elif [ "$_BMX_WARN" -gt 0 ]; then
        echo "  ${GREEN-}无错误${NC-}，$_BMX_WARN 项警告（多为环境/权限提示，不阻断核心功能）"
        return 0
    else
        echo "  ${GREEN-}全部通过${NC-}"
        return 0
    fi
}

# ── 自动修复 ──
# 只做「安全且确定有效」的动作；不确定的一律只打印建议，不擅自改用户配置。
bmx_doctor_fix() {
    echo ""
    echo "${BOLD-}自动修复${NC-}"

    # 修复 1：cliId 指向未安装的 CLI —— 这是本次故障的触发条件之一。
    # 改配置属于「改变行为」，故必须用户确认；非交互下只提示不动手。
    local bots_json
    bots_json="$(bmx setup list --json 2>/dev/null | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); b=d.get("bots") if isinstance(d,dict) else d
    print(json.dumps(b if isinstance(b,list) else []))
except Exception: print("[]")' 2>/dev/null || echo '[]')"

    local broken=""
    broken="$(printf '%s' "$bots_json" | python3 -c '
import json,sys,shutil,subprocess
M={"claude-code":"claude","codex":"codex","aiden":"aiden","traex":"traex","coco":"coco",
   "gemini":"gemini","opencode":"opencode","opencode2":"opencode2","cursor":"cursor",
   "mir":"mircli","oh-my-pi":"oh-my-pi","pi":"pi","codex-app":"","mira":""}
for b in json.load(sys.stdin):
    if b.get("cliRuntime") or b.get("cliPathOverride"): continue
    cid=b.get("cliId","")
    exe=M.get(cid)
    if exe and shutil.which(exe) is None:
        print(f"{b.get(\"larkAppId\",\"\")}\t{cid}\t{exe}")
' 2>/dev/null || true)"

    if [ -n "$broken" ]; then
        printf '%s\n' "$broken" | while IFS=$'\t' read -r app cid exe; do
            warn "cliId=$cid 需要的 [$exe] 未安装"
            info "  两个修法（选一个）："
            info "    A) 安装 $exe"
            info "    B) 改回已装的 CLI：飞书里对 bot 发  /botconfig set cli claude-code"
        done
    else
        ok "无 cliId 指向未安装 CLI 的问题"
    fi

    # 修复 2：清积压队列 + 重启 daemon（本次故障的确定解法）
    local qtotal=0 f
    for f in "$HOME"/.botmux/data/queues/*.jsonl; do
        [ -e "$f" ] || continue
        qtotal=$((qtotal + $(wc -l < "$f" 2>/dev/null || echo 0)))
    done
    if [ "$qtotal" -gt 0 ]; then
        warn "队列积压 $qtotal 条"
        if [ "${NONINTERACTIVE:-false}" = "true" ] || ! has_tty; then
            info "非交互环境 —— 请手动确认后执行: bash option-botmux/init.sh fix"
        else
            if confirm "备份并清空队列 + 重启 daemon？" y; then
                local bak="$HOME/.botmux/data/queues.bak"
                mkdir -p "$bak"
                cp "$HOME"/.botmux/data/queues/*.jsonl "$bak/" 2>/dev/null || true
                ok "已备份到 $bak"
                run bmx stop >/dev/null 2>&1 || true
                sleep 2
                : > "$HOME"/.botmux/data/queues/*.jsonl 2>/dev/null || true
                run bmx start >/dev/null 2>&1 || true
                sleep 5
                if daemon_running; then
                    ok "已清队列并重启 daemon"
                else
                    err "重启失败，看日志: bash option-botmux/init.sh logs"
                fi
            else
                info "已跳过"
            fi
        fi
    fi

    # 修复 3：卡死 worker（D 状态）—— 唯一解是重启 daemon
    local stuck
    stuck="$(ps -eo pid,stat,cmd 2>/dev/null | awk '$2 ~ /^D/ && /botmux.*__worker/ {print $1}' || true)"
    if [ -n "$stuck" ]; then
        warn "有 worker 卡在 D 状态（SIGKILL 无效）: $(echo $stuck | tr '\n' ' ')"
        if [ "${NONINTERACTIVE:-false}" = "true" ] || ! has_tty; then
            info "非交互环境 —— 请手动执行: bash option-botmux/init.sh restart"
        else
            if confirm "重启 daemon 以清理卡死 worker？" y; then
                run bmx restart >/dev/null 2>&1 || true
                sleep 6
                if ps -eo pid,stat,cmd 2>/dev/null | awk '$2 ~ /^D/ && /botmux.*__worker/' | grep -q .; then
                    err "仍有卡死 worker —— 可能需要重启 WSL（内核 I/O 卡死）"
                else
                    ok "卡死 worker 已清除"
                fi
            fi
        fi
    fi
    echo ""
    info "修完复查: bash option-botmux/init.sh doctor"
}