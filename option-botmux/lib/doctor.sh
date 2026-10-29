#!/bin/bash
# ccconfig/option-botmux/lib/doctor.sh — botmux 健康体检 / 自动修复
#
# 背景（2026-10-29 实测故障）：botmux daemon 与飞书长连接全部「在线」，
#   botmux status / list 都显示正常，但飞书里发消息毫无反馈。真因是会话的
#   worker 卡死（D 状态，SIGKILL 无效）+ tmux pane 已死，消息只堆进
#   ~/.botmux/data/queues/*.jsonl 无人消费。
#   结构性教训：**botmux 自带的状态命令只反映 daemon/supervisor 存活，
#   不反映「会话能否真的干活」**。本模块补的正是这段盲区。
#
# 判定原则：只信权威信号，不做猜测
#   · cliId 取值与对应可执行名 —— 从二进制预设表提取（见 _bmx_check_bots 的 EXEC 表）
#   · cliPathOverride —— botmux 自己支持的显式覆盖字段，非猜测
#   · cliRuntime —— 自定义 runtime，静态判不了，跳过而非误报
#   · wrapperCli / cliLaunchMode —— 网关包装，包了一层，单独提示
#
# 调用方约束（init.sh 带 set -e）：本文件所有对外函数末尾必须 return 0，
#   否则 `[ -n "$x" ] && cmd` 这类断言在条件不成立时返回 1 会让整个脚本静默退出。
#   同理：凡是要累加计数的循环，必须用 `< <(...)` 而非 `... | while`，
#   否则 while 落在子 shell 里，计数改动传不回父 shell。
#
# 退出码：0 = 无错误；1 = 有错误；2 = botmux 未安装

set -uo pipefail

_BMX_ERR=0
_BMX_WARN=0

_bmx_d_pass() { echo "  ✓ $*"; }
_bmx_d_warn() { echo "  ! $*"; _BMX_WARN=$((_BMX_WARN + 1)); }
_bmx_d_err()  { echo "  ✗ $*"; _BMX_ERR=$((_BMX_ERR + 1)); }

# ── cliId → 可执行名（从 botmux v3.54.0 二进制预设表提取）──
# 空串 = 该 cliId 不是本机 CLI（桌面 App / Web API），无需查命令
# __UNKNOWN__ = 本脚本不认识（botmux 可能新增了适配器）
# 解析真正的平台二进制（非 launcher 壳）—— 只用于扫描内嵌预设表。
# npm 布局：$prefix/lib/node_modules/botmux/node_modules/botmux-linux-*/botmux
# 大小阈值 1MB：launcher 才百来字节，拿它去扫预设表会永远扫不到。
_bmx_bin_real() {
    local c p
    c="$(command -v botmux 2>/dev/null || true)"
    if [ -n "$c" ]; then
        c="$(readlink -f "$c" 2>/dev/null || echo "$c")"
        [ -f "$c" ] && [ "$(stat -c%s "$c" 2>/dev/null || echo 0)" -gt 1048576 ] && { echo "$c"; return 0; }
    fi
    for p in "${NPM_PREFIX:-}"/lib/node_modules/botmux/node_modules/botmux-linux-*/botmux; do
        [ -f "$p" ] && { echo "$p"; return 0; }
    done
    return 0
}

# ── CLI 依赖：cliId → 公开 npm 安装包 ──
# botmux 只桥接，不负责装底层 CLI —— 装了 botmux 但没装 CLI 是「静默失败」
# 的重灾区（daemon 全绿、飞书零反馈）。
#
# 返回：
#   <包名>      可用 npm 公开安装
#   __INTERNAL__  仅内部渠道（本机无法从公网装）—— 只提示，不给命令
#   __NONE__    非 CLI 型适配器（桌面 App / Web API / 内建 agent）
#
# 包名均为实测 `npm view <pkg> version` 可解析者；未验证的一律标 __INTERNAL__
# 或留空，宁可不给命令，也不给一条装不上的命令。
_bmx_cli_install_pkg() {
    case "$1" in
        claude-code) echo "@anthropic-ai/claude-code" ;;
        codex)       echo "@openai/codex" ;;
        gemini)      echo "@google/gemini-cli" ;;
        opencode)    echo "opencode-ai" ;;
        mtr)         echo "@metamove-code/mtr-cli" ;;
        # CodeM = 飞书官方 AI 研发智能体 CLI（serverUrl codem.feishu.cn），
        # 公网可装。走官方 install.sh 而非 npm：它把 CLI + core 运行时装进
        # 版本化目录 ~/.codem/runtime/versions/<ver>/，并用 ~/.codem/bin/codem
        # 做指针解析启动器 —— 直接 npm -g 装不成那个布局。
        codem)       echo "__CODEM_SH__" ;;
        # 以下为内部渠道发行（字节 bytedcli 生态 / 未公开上架）——
        # botmux 公开文档明确不提供其安装说明，本机内部源亦不可达。
        aiden)       echo "__INTERNAL__" ;;
        coco)        echo "__INTERNAL__" ;;
        traex)       echo "__INTERNAL__" ;;
        codex-app)   echo "__NONE__" ;;   # 桌面 App
        mira)        echo "__NONE__" ;;   # Web API
        riff)        echo "__NONE__" ;;   # 内建云 agent
        *)           echo "__UNVERIFIED__" ;;
    esac
}
_bmx_bots_json() {
    local raw
    raw="$(bmx setup list --json 2>/dev/null || true)"
    [ -z "$raw" ] && { echo '[]'; return 0; }
    printf '%s' "$raw" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("[]"); sys.exit(0)
b=d.get("bots") if isinstance(d,dict) else d
if not isinstance(b,list): b=[]
safe=[{k:v for k,v in x.items() if "Secret" not in k and "Token" not in k} for x in b if isinstance(x,dict)]
print(json.dumps(safe,ensure_ascii=False))
' 2>/dev/null || echo '[]'
}

# ── 1. 配置体检（bots.json）──
# python 一次算出结论，输出「级别|文本」行；shell 只渲染。
# 走 < <(...) 而非管道 —— 保证 _BMX_ERR/_BMX_WARN 的累加能回到父 shell。
_bmx_check_bots() {
    local bots_json="$1"
    echo "配置（bots.json）"

    if [ "$(printf '%s' "$bots_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)" = "0" ]; then
        _bmx_d_warn "未配置任何 bot（跑 guide 扫码建应用）"
        return 0
    fi

    local lvl txt
    while IFS='|' read -r lvl txt; do
        [ -z "$lvl" ] && continue
        case "$lvl" in
            PASS) _bmx_d_pass "$txt" ;;
            WARN) _bmx_d_warn "$txt" ;;
            ERR)  _bmx_d_err "$txt" ;;
            INFO) echo "  · $txt" ;;
        esac
    done < <(printf '%s' "$bots_json" | python3 -c '
import json,sys,shutil
# cliId -> 可执行名；空串 = 非本机 CLI（桌面 App / Web API / 内建 agent）
EXEC={"claude-code":"claude","codex":"codex","codex-app":"","mira":"",
      "aiden":"aiden","traex":"traex","coco":"coco","gemini":"gemini",
      "opencode":"opencode","opencode2":"opencode2","cursor":"cursor",
      "mir":"mircli","oh-my-pi":"oh-my-pi","pi":"pi",
      "dsh":"dsh","dsh-tui":"dsh-tui","riff":"",
      "codem":"codem"}
# cliId -> 公开 npm 安装包；"" = 非 CLI 型；"INTERNAL" = 仅内部渠道
PKG={"claude-code":"@anthropic-ai/claude-code","codex":"@openai/codex",
     "gemini":"@google/gemini-cli","opencode":"opencode-ai",
     "mtr":"@metamove-code/mtr-cli",
     "codem":"CODEM_SH",
     "aiden":"INTERNAL","traex":"INTERNAL","coco":"INTERNAL"}
try:
    bots=json.load(sys.stdin)
except Exception:
    bots=[]
for b in bots:
    app=str(b.get("larkAppId",""))[:12]
    cid=b.get("cliId","") or ""
    pathov=(b.get("cliPathOverride","") or "").strip()
    wrap=(b.get("wrapperCli","") or "").strip()
    lm=(b.get("cliLaunchMode","") or "").strip()
    rt=b.get("cliRuntime")
    owners=b.get("allowedUsers") or []
    print(f"INFO|[{app}…] cliId={cid}")
    if not owners:
        print("ERR|  allowedUsers 为空 → 该 bot 会拒绝所有消息")
    else:
        print(f"PASS|  owner: {chr(44).join(map(str,owners))}")
    if rt:
        print(f"WARN|  cliId={cid} 走自定义 cliRuntime —— 可执行性无法静态判定，跳过")
    elif pathov:
        import os
        if shutil.which(pathov) or (os.path.isfile(pathov) and os.access(pathov,os.X_OK)):
            print(f"PASS|  cliPathOverride: {pathov}")
        else:
            print(f"ERR|  cliPathOverride 不存在或不可执行: {pathov} → 会话起不来")
    else:
        exe=EXEC.get(cid,"__UNKNOWN__")
        pkg=PKG.get(cid,"")
        if exe=="__UNKNOWN__":
            print(f"WARN|  未知 cliId={cid}（botmux 可能比本脚本新）")
        elif exe=="":
            print(f"PASS|  cliId={cid}（非 CLI 型适配器，无需本机命令）")
        elif shutil.which(exe):
            print(f"PASS|  cliId={cid} → {exe} 已安装")
        else:
            print(f"ERR|  cliId={cid} 需要命令 [{exe}]，但本机【未安装】")
            print(f"ERR|    → 最隐蔽的坑：daemon 与长连接都显示正常，")
            print(f"ERR|      但每次消息都起不来 CLI，飞书里表现为【完全无反馈】")
            if pkg == "CODEM_SH":
                print(f"ERR|    → 修 A) CodeM 是飞书官方 CLI，走官方脚本装（非 npm -g）:")
                print(f"ERR|       curl -fsSL https://codem-public.tos-cn-beijing.volces.com/codem/install.sh | bash -s -- --no-sudo")
                print(f"ERR|       装完 codem login（扫码），再 botmux restart")
                print(f"ERR|       （botmux 会自动探测 ~/.codem/bin/codem，无需加 PATH）")
                print(f"ERR|      修 B) 改回已装 CLI：飞书里 /botconfig set cli claude-code")
            elif pkg and pkg not in ("INTERNAL",""):
                print(f"ERR|    → 修 A) npm install -g {pkg}")
                print(f"ERR|      修 B) 改回已装 CLI：飞书里 /botconfig set cli claude-code")
            elif pkg=="INTERNAL":
                print(f"ERR|    → [{exe}] 仅内部渠道发行，botmux 公开文档未给安装方式，")
                print(f"ERR|      本机也无可达内部源 —— 请按内部文档自行安装")
                print(f"ERR|      或改回已装 CLI：飞书里 /botconfig set cli claude-code")
            else:
                print(f"ERR|    → 修 A) 自行安装 {exe}")
                print(f"ERR|      修 B) 改回已装 CLI：飞书里 /botconfig set cli claude-code")
    if wrap:
        print(f"WARN|  wrapperCli={wrap}（网关包装：须已完成该网关登录，底层 {cid} 也须已装）")
    if lm:
        print(f"WARN|  cliLaunchMode={lm}（特殊启动模式，依赖对应网关）")
' 2>/dev/null || true)
    return 0
}

# ── 2. 会话健康 —— 本次故障的核心盲区：daemon 在线 ≠ 会话能干活 ──
_bmx_check_sessions() {
    echo "会话健康（daemon 在线 ≠ 会话能干活）"

    local list_out
    list_out="$(bmx list --plain 2>/dev/null || true)"

    if printf '%s' "$list_out" | grep -qE '没有活跃会话|No active sessions'; then
        _bmx_d_pass "无活跃会话（正常：下条消息会冷启动）"
        _bmx_check_queue
        return 0
    fi

    # 解析会话表：id 列 + pid 列。tab 已塌缩不了 —— 只取两个明确列。
    local rows
    rows="$(printf '%s' "$list_out" | awk -F'│' '
        /│/ {
            gsub(/^[ \t]+|[ \t]+$/,"",$2)
            gsub(/^[ \t]+|[ \t]+$/,"",$5)
            if ($2 != "" && $2 != "id") print $2 "|" $5
        }' || true)"

    if [ -z "$rows" ]; then
        _bmx_d_warn "无法解析会话列表（botmux 输出格式可能变了）"
        _bmx_check_queue
        return 0
    fi

    local sid pid st pane
    while IFS='|' read -r sid pid; do
        [ -z "$sid" ] && continue
        local bad=0

        # worker 卡 D 状态 = 不可中断 I/O 等待，SIGKILL 都杀不掉
        # （实测：worker 自持 FIFO 读写端 → anon_pipe_write 永久阻塞）
        if [ -n "$pid" ] && [ -r "/proc/$pid/stat" ]; then
            st="$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null || true)"
            if [ "$st" = "D" ]; then
                _bmx_d_err "会话 $sid worker($pid) 卡在 D 状态（不可中断 I/O）→ 该会话永久无响应"
                _bmx_d_err "  → SIGKILL 无效，只能重启 daemon（见 fix）"
                bad=1
            fi
        fi

        # tmux pane 已死 = 前端没了，消息只会堆积
        pane="$(tmux -L botmux list-panes -t "bmx-${sid:0:8}" -F '#{pane_dead}' 2>/dev/null | head -1 || true)"
        if [ "$pane" = "1" ]; then
            _bmx_d_err "会话 $sid 的 tmux pane 已死 → 该话题消息只堆积、不处理"
            bad=1
        fi
        if [ "$bad" = "0" ]; then
            _bmx_d_pass "会话 $sid 正常（pid=${pid:-?}）"
        fi
    done < <(printf '%s' "$rows")

    _bmx_check_queue
    return 0
}

# ── 3. 队列积压 —— 故障最直接的可见症状 ──
_bmx_check_queue() {
    local total=0 f lines
    for f in "$HOME"/.botmux/data/queues/*.jsonl; do
        [ -e "$f" ] || continue
        lines="$(wc -l < "$f" 2>/dev/null || echo 0)"
        total=$((total + lines))
    done

    if [ "$total" -eq 0 ]; then
        _bmx_d_pass "消息队列空"
        return 0
    fi

    # 有活跃会话时队列非空属正常（正在消费）；无会话 + 非空 = 卡死
    local has_sess
    has_sess="$(bmx list --plain 2>/dev/null | grep -cE '^[0-9a-f]{8}' || true)"
    if [ "${has_sess:-0}" -eq 0 ]; then
        _bmx_d_err "队列积压 $total 条，但没有活跃会话消费 → 飞书发消息【零反馈】"
        _bmx_d_warn "  → 见 fix：备份并清队列 + 重启 daemon"
    else
        _bmx_d_warn "队列有 $total 条待处理（有活跃会话，可能正在消费）"
    fi
    return 0
}

# ── 4. 上游与飞书侧 ──
_bmx_check_upstream() {
    echo "上游与飞书侧"
    local logf="$HOME/.botmux/logs/daemon-0-out.log" errf="$HOME/.botmux/logs/daemon-0-err.log"

    if [ -f "$logf" ]; then
        if tail -300 "$logf" 2>/dev/null | grep -q 'Daemon WSClient started'; then
            _bmx_d_pass "飞书长连接已建立（WSClient started）"
        else
            _bmx_d_err "日志未见「Daemon WSClient started」→ 长连接未建立，消息根本进不来"
        fi
        if tail -400 "$logf" 2>/dev/null | grep -qE 'worker did not exit after SIGTERM'; then
            _bmx_d_warn "近期出现过「worker SIGTERM 无响应」→ 确有卡死 worker（见会话健康）"
        fi
        if tail -400 "$logf" 2>/dev/null | grep -q 'Ignored unbound input commit'; then
            _bmx_d_warn "近期有「Ignored unbound input commit」→ 首条消息提交未确认，消息会被丢弃"
        fi
    else
        _bmx_d_warn "找不到 daemon 日志 $logf"
    fi

    if [ -f "$errf" ]; then
        if tail -400 "$errf" 2>/dev/null | grep -q 'vcMeetingAgent 已启用但缺'; then
            _bmx_d_warn "缺 VC 会议权限 (vc:meeting.bot.realtime:write) —— 仅影响会议智能体，不阻断聊天"
        fi
        if tail -200 "$errf" 2>/dev/null | grep -q 'runtime-sweep.*ENOTDIR'; then
            _bmx_d_warn "runtime-sweep 残留噪音（已删会话的 env-stamp 目录）—— 无害，仅刷日志"
        fi
    fi
    return 0
}

# ── 5. 版本漂移：本脚本的 cliId 表 vs 已装 botmux ──
_bmx_check_version_drift() {
    # _botmux_bin 优先返回的可能是 npm launcher 脚本（仅 ~128 字节），
    # 里头没有预设表 —— 必须解析到真正的平台二进制（~133MB）才扫得到 cliId。
    local bin; bin="$(_bmx_bin_real 2>/dev/null || true)"
    [ -z "$bin" ] && return 0

    local live
    live="$(python3 - "$bin" <<'PY' 2>/dev/null || true
import re,sys
try:
    d=open(sys.argv[1],'rb').read()
except Exception:
    sys.exit(0)
ids=set()
for m in re.finditer(rb'cliId:"([a-z0-9\-_]+)"', d):
    ids.add(m.group(1).decode())
print(" ".join(sorted(ids)))
PY
)"
    [ -z "$live" ] && return 0

    # 收录的适配器 cliId。哨兵值（botmux-gateway / unknown）不是适配器，
    # 出现在这里会被当作"未收录"误报，故一并列出。
    local known="claude-code codex codex-app mira aiden traex coco gemini opencode opencode2 cursor mir oh-my-pi pi dsh dsh-tui riff botmux-gateway unknown"
    local new="" id
    for id in $live; do
        case " $known " in
            *" $id "*) : ;;
            *) new="$new $id" ;;
        esac
    done
    if [ -n "$new" ]; then
        _bmx_d_warn "botmux $(botmux_version) 有本脚本未收录的 cliId:$new → 更新 option-botmux/lib/doctor.sh"
    else
        _bmx_d_pass "cliId 表与 botmux $(botmux_version) 一致"
    fi
    return 0
}

# ── 主入口 ──
bmx_doctor() {
    _BMX_ERR=0; _BMX_WARN=0

    if ! has_botmux; then
        _bmx_d_err "botmux 未安装"
        return 2
    fi
    echo "botmux 体检"
    _bmx_d_pass "botmux $(botmux_version)"

    # daemon 存活是必要条件但不充分 —— 本次故障 daemon 全程"在线"
    if daemon_running; then
        _bmx_d_pass "daemon 在运行"
    else
        _bmx_d_err "daemon 未运行 → 飞书消息无人接收"
    fi

    local bots_json; bots_json="$(_bmx_bots_json)"
    echo ""
    _bmx_check_bots "$bots_json"
    echo ""
    _bmx_check_sessions
    echo ""
    _bmx_check_upstream
    echo ""
    _bmx_check_version_drift
    echo ""

    local rc=0
    if [ "$_BMX_ERR" -gt 0 ]; then
        echo "  $_BMX_ERR 项错误、$_BMX_WARN 项警告"
        [ "${1:-}" != "--fix" ] && echo "  自动修复: bash option-botmux/init.sh fix"
        rc=1
    elif [ "$_BMX_WARN" -gt 0 ]; then
        echo "  无错误，$_BMX_WARN 项警告（多为环境/权限提示，不阻断核心功能）"
    else
        echo "  全部通过"
    fi

    # fix 模式无条件进入修复段 —— 即便体检无 error，也可能有可修项
    # （队列积压被判为 WARN、或体检项覆盖不到的残留），不该因为"体检通过"就跳过。
    [ "${1:-}" = "--fix" ] && bmx_doctor_fix
    return $rc
}

# ── 自动修复 ──
# 只做「安全且确定有效」的动作；改用户配置一律先问，非交互下只提示不动手。
bmx_doctor_fix() {
    echo ""
    echo "自动修复"

    # 修复 1：cliId 指向未安装的 CLI（本次故障的触发条件）
    # 输出 cid|exe|pkg，pkg 为空 = 无公开安装包（内部渠道/未知）
    local broken
    broken="$(printf '%s' "$(_bmx_bots_json)" | python3 -c '
import json,sys,shutil
EXEC={"claude-code":"claude","codex":"codex","aiden":"aiden","traex":"traex","coco":"coco",
      "gemini":"gemini","opencode":"opencode","opencode2":"opencode2","cursor":"cursor",
      "mir":"mircli","oh-my-pi":"oh-my-pi","pi":"pi"}
PKG={"claude-code":"@anthropic-ai/claude-code","codex":"@openai/codex",
     "gemini":"@google/gemini-cli","opencode":"opencode-ai",
     "mtr":"@metamove-code/mtr-cli","codem":"CODEM_SH"}
# 仅内部渠道发行，无公开包 —— 与"未知"区分，避免给出装不上的命令
INTERNAL={"aiden","traex","coco"}
try:
    bots=json.load(sys.stdin)
except Exception:
    bots=[]
for b in bots:
    if b.get("cliRuntime") or b.get("cliPathOverride"): continue
    cid=b.get("cliId","") or ""
    exe=EXEC.get(cid)
    if not exe or shutil.which(exe): continue
    pkg=PKG.get(cid,"")
    if not pkg and cid in INTERNAL: pkg=""
    print(cid + "|" + exe + "|" + pkg)
' 2>/dev/null || true)"

    if [ -n "$broken" ]; then
        local cid exe pkg
        while IFS='|' read -r cid exe pkg; do
            [ -z "$cid" ] && continue
            warn "cliId=$cid 需要的 [$exe] 未安装"
            if [ "$pkg" = "CODEM_SH" ]; then
                info "  修法 A) 装 CodeM（飞书官方 CLI，走官方脚本）:"
                info "      curl -fsSL https://codem-public.tos-cn-beijing.volces.com/codem/install.sh | bash -s -- --no-sudo"
                info "      装完 codem login 扫码；botmux 自动探测 ~/.codem/bin/codem"
            elif [ -n "$pkg" ]; then
                info "  修法 A) 装它: npm install -g $pkg"
                if [ "${NONINTERACTIVE:-false}" != "true" ] && has_tty \
                   && confirm "  现在就装 $pkg ？" n; then
                    run npm install -g "$pkg" --no-audit --no-fund \
                        && ok "已装 $pkg（重开会话后生效）" \
                        || err "安装失败，手动试: npm install -g $pkg"
                fi
            else
                info "  修法 A) [$exe] 仅内部渠道发行，botmux 公开文档未提供安装方式，"
                info "          本机也无可达内部源 —— 请按内部文档自行安装"
            fi
            info "  修法 B) 改回已装的 CLI: 飞书里对 bot 发  /botconfig set cli claude-code"
        done <<< "$broken"
    else
        ok "无 cliId 指向未安装 CLI 的问题"
    fi

    # 修复 2：卡死 worker（D 状态）—— 唯一解是重启 daemon
    local stuck
    stuck="$(ps -eo pid,stat,cmd 2>/dev/null | awk '$2 ~ /^D/ && /botmux.*__worker/ {print $1}' || true)"
    if [ -n "$stuck" ]; then
        warn "worker 卡在 D 状态（SIGKILL 无效）: $(echo "$stuck" | tr '\n' ' ')"
        if [ "${NONINTERACTIVE:-false}" = "true" ] || ! has_tty; then
            info "非交互环境 —— 请手动执行: bash option-botmux/init.sh restart"
        elif confirm "重启 daemon 以清理卡死 worker？" y; then
            run bmx restart >/dev/null 2>&1 || true
            sleep 6
            if ps -eo pid,stat,cmd 2>/dev/null | awk '$2 ~ /^D/ && /botmux.*__worker/' | grep -q .; then
                err "仍有卡死 worker —— 可能需重启 WSL（内核 I/O 卡死）"
            else
                ok "卡死 worker 已清除"
            fi
        fi
    else
        ok "无卡死 worker"
    fi

    # 修复 3：清积压队列 + 重启（本次故障的确定解法）
    local qtotal=0 f
    for f in "$HOME"/.botmux/data/queues/*.jsonl; do
        [ -e "$f" ] || continue
        qtotal=$((qtotal + $(wc -l < "$f" 2>/dev/null || echo 0)))
    done
    if [ "$qtotal" -gt 0 ]; then
        warn "队列积压 $qtotal 条"
        if [ "${NONINTERACTIVE:-false}" = "true" ] || ! has_tty; then
            info "非交互环境 —— 请手动确认后执行: bash option-botmux/init.sh fix"
        elif confirm "备份并清空队列 + 重启 daemon？" y; then
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
    else
        ok "队列无积压"
    fi

    echo ""
    info "修完复查: bash option-botmux/init.sh doctor"
    return 0
}