#!/bin/bash
# option-filepull/init.sh — 跨机取件（SMB C$ + tsxfer 专用账户）
#
# agent 从任意 tailnet 客户机拉取/回写文件的主机与凭据管理。
# ADR: docs/adr/0044-agent-smb-file-bridge.md
# 凭据真相源: ccprivate/conf/smb.json（跨机 git 同步）
#
# 用法:
#   bash init.sh --status        # 探活 conf 中所有主机（maintain status 自动调用）
#   bash init.sh add             # 交互添加主机（生成密码 + 打印 A 侧 PowerShell 命令）
#   bash init.sh probe [host]    # 探活主机（缺省全部）
#   bash init.sh --install       # 非交互：已配置则 OK，否则提示手动 add
#   bash init.sh                 # 交互菜单（从 init-option 选入）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/dry-run.sh" 2>/dev/null || true
source "$SCRIPT_DIR/../lib/colors.sh"
source "$SCRIPT_DIR/../lib/interact.sh" 2>/dev/null || true

CONF="${CCPRIVATE_HOME:-$HOME/git/ccprivate}/conf/smb.json"
PS_EXE="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

# ── 探活：对单主机建 SMB 映射测 C$ 根 ──
# 输出首行: PROBE_OK | PROBE_DENIED <msg> | PROBE_UNREACH <msg> | PROBE_ERR <msg>
# ⚠️ 调用方式坑（2026-10-12 实测）：env 会被 WSL interop 吞掉（$env: 为空）；
# -Command <字符串> 模式后续 argv 被拼进命令文本（不绑 $args）。
# 故用 python 生成脚本 + -EncodedCommand（base64 UTF-16LE），转义全免疫。
_probe_one() {
    local ip="$1" user="$2" pw="$3"
    local b64
    b64=$(python3 - "$ip" "$user" "$pw" <<'PYEOF'
import base64, sys
ip, user, pw = (a.replace("'", "''") for a in sys.argv[1:4])
ps = f"""
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$path = '\\\\{ip}\\C$'
Remove-SmbMapping -RemotePath $path -Force -ErrorAction SilentlyContinue | Out-Null
try {{
  $m = New-SmbMapping -RemotePath $path -UserName '{user}' -Password '{pw}' -Persistent:$false -ErrorAction Stop
  $ok = Test-Path $path
  Remove-SmbMapping -RemotePath $path -Force -ErrorAction SilentlyContinue | Out-Null
  if ($ok) {{ Write-Output "PROBE_OK" }} else {{ Write-Output "PROBE_ERR Test-Path false" }}
}} catch {{
  $msg = $_.Exception.Message -replace "[\\r\\n]+", " "
  if ($msg -match "拒绝访问|Access is denied|Unauthorized") {{ Write-Output "PROBE_DENIED $msg" }}
  elseif ($msg -match "找不到|not find|No network|network path|network name|timed out") {{ Write-Output "PROBE_UNREACH $msg" }}
  else {{ Write-Output "PROBE_ERR $msg" }}
}}
"""
print(base64.b64encode(ps.encode("utf-16-le")).decode())
PYEOF
    )
    timeout 12 "$PS_EXE" -NoProfile -EncodedCommand "$b64" 2>&1 | head -1
}

# ── 读 conf 输出 "name|ip|user|pass" 每行一条 ──
_list_hosts() {
    [ -f "$CONF" ] || return 0
    python3 - "$CONF" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
for name, h in d.items():
    print(f"{name}|{h.get('ip','')}|{h.get('user','tsxfer')}|{h.get('pass','')}")
PYEOF
}

# ── 探活报告: 返回 0=通 1=拒 2=不可达 3=其他/缺环境 ──
# 入参: name ip user pass; 打印详情行（ANSI），状态由返回码表达
_probe_report() {
    local name="$1" ip="$2" user="$3" pw="$4"
    if [ ! -x "$PS_EXE" ]; then
        echo -e "  ${GRAY}✗ $name — 缺 powershell.exe（非 WSL 或 interop 关闭）${NC}"
        return 3
    fi
    local out
    out=$(_probe_one "$ip" "$user" "$pw")
    case "$out" in
        PROBE_OK*)
            echo -e "  ${GREEN}✓${NC} $name ($ip) C\$ 可达"
            return 0 ;;
        PROBE_DENIED*)
            echo -e "  ${RED}✗${NC} $name ($ip) 拒绝访问 — A 侧三条命令未跑全（尤其 reg add LocalAccountTokenFilterPolicy）"
            return 1 ;;
        PROBE_UNREACH*)
            echo -e "  ${RED}✗${NC} $name ($ip) 不可达 — 目标机 tailscale 离线或 445 未开"
            return 2 ;;
        *)
            echo -e "  ${RED}✗${NC} $name ($ip) ${out:-无输出}"
            return 3 ;;
    esac
}

do_status() {
    if [ ! -f "$CONF" ]; then
        echo "MISSING filepull 未配置主机（bash option-filepull/init.sh add）"
        return 0
    fi
    local hosts
    hosts=$(_list_hosts)
    if [ -z "$hosts" ]; then
        echo "MISSING filepull conf 无主机条目（bash option-filepull/init.sh add）"
        return 0
    fi

    local ok=0 total=0 fail_names=() ok_names=() details=""
    while IFS='|' read -r name ip user pw; do
        [ -z "$name" ] && continue
        total=$((total + 1))
        local detail
        if detail=$(_probe_report "$name" "$ip" "$user" "$pw"); then
            ok=$((ok + 1)); ok_names+=("$name")
        else
            fail_names+=("$name")
        fi
        details+="${detail}"$'\n'
    done <<< "$hosts"

    # 首行状态契约（无 ANSI，init-option/maintain 取 head -1）
    if [ "$ok" -eq "$total" ]; then
        echo "OK filepull $ok/$total 台主机可达 (${ok_names[*]})"
    elif [ "$ok" -gt 0 ]; then
        echo "WARN filepull $ok/$total 台可达: ${ok_names[*]:-} ✓ / ${fail_names[*]} ✗"
    else
        echo "MISSING filepull 0/$total 台可达 (${fail_names[*]})"
    fi
    echo ""
    printf '%s' "$details"
}

do_probe() {
    local only="${1:-}"
    local hosts
    hosts=$(_list_hosts)
    if [ -z "$hosts" ]; then
        warn "无主机配置: bash option-filepull/init.sh add"
        return 0
    fi
    while IFS='|' read -r name ip user pw; do
        [ -z "$name" ] && continue
        [ -n "$only" ] && [ "$name" != "$only" ] && continue
        _probe_report "$name" "$ip" "$user" "$pw" || true
    done <<< "$hosts"
}

_gen_pw() {
    python3 - <<'PYEOF'
import secrets, string, random
a = string.ascii_letters + string.digits
pw = secrets.choice(string.ascii_uppercase) + secrets.choice(string.ascii_lowercase) + secrets.choice(string.digits) + ''.join(secrets.choice(a) for _ in range(11))
print(''.join(random.SystemRandom().sample(pw, len(pw))))
PYEOF
}

do_add() {
    local host ip
    host=$(prompt "主机名（tailscale 设备名，如 redmipro）")
    [ -z "$host" ] && { err "主机名不能为空"; return 1; }
    ip=$(prompt "Tailscale IP（100.x.x.x）")
    if ! [[ "$ip" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        err "IP 格式不对: $ip"; return 1
    fi

    if python3 - "$CONF" "$host" <<'PYEOF'
import json, os, sys
if os.path.exists(sys.argv[1]) and sys.argv[2] in json.load(open(sys.argv[1])):
    sys.exit(0)
sys.exit(1)
PYEOF
    then
        confirm "主机 $host 已存在，覆盖？" n || { info "已取消"; return 0; }
    fi

    local pw; pw=$(_gen_pw)

    if _dry_run_enabled "$@" 2>/dev/null; then
        printf 'would: add %s (%s) tsxfer -> %s\n' "$host" "$ip" "$CONF"
        return 0
    fi

    python3 - "$CONF" "$host" "$ip" "$pw" <<'PYEOF'
import json, os, sys
from datetime import date
conf, host, ip, pw = sys.argv[1:5]
d = {}
if os.path.exists(conf):
    d = json.load(open(conf))
d[host] = {"ip": ip, "user": "tsxfer", "pass": pw, "share": "C$",
           "note": "专用 SMB 取件账户（非交互登录，只走 tailnet 445）。A 侧三命令见 option-filepull/init.sh add 输出或 ADR 0044。",
           "created": date.today().isoformat()}
os.makedirs(os.path.dirname(conf), exist_ok=True)
with open(conf, "w") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
print(f"conf 已写入: {conf} [{host}]")
PYEOF

    echo ""
    info "在 $host 上开管理员 PowerShell（UAC 可用 PIN 过），粘贴以下三行："
    echo ""
    cat <<EOF
net user tsxfer ${pw} /add
net localgroup administrators tsxfer /add
reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f
EOF
    echo ""
    if ! confirm "已在 $host 管理员窗口跑完？（探活验证）" y; then
        info "稍后自行验证: bash option-filepull/init.sh probe $host"
        return 0
    fi

    local entry
    entry=$(_list_hosts | grep "^${host}|" || true)
    if [ -z "$entry" ]; then err "conf 读取异常"; return 1; fi
    IFS='|' read -r n ip2 user pw2 <<< "$entry"
    if _probe_report "$n" "$ip2" "$user" "$pw2"; then
        echo ""
        ok "$host 就绪。用法：对 agent 说「分析 $host 的 <路径>」或「把 <路径> tailscale 过来」"
    else
        echo ""
        warn "探活未过。逐条排查：① 三行命令是否都跑了（尤其 reg add）② net user tsxfer 是否建成 ③ 目标机 445/tailnet"
        return 1
    fi
}

usage() {
    cat <<'EOF'
option-filepull — 跨机取件（SMB C$ + tsxfer）

  bash init.sh --status     探活所有主机（maintain status 自动调用）
  bash init.sh add          添加主机（生成密码 + 打印 A 侧 PowerShell 命令）
  bash init.sh probe [host] 探活（缺省全部）
  bash init.sh --install    非交互：已配置则 OK

凭据: ccprivate/conf/smb.json ｜ ADR: docs/adr/0044-agent-smb-file-bridge.md
EOF
}

case "${1:-}" in
    --status|status|-s) do_status ;;
    add) shift; do_add "$@" ;;
    probe) shift; do_probe "${1:-}" ;;
    --install|--yes|-y)
        count=0
        if [ -f "$CONF" ]; then count=$(_list_hosts | grep -c . || true); fi
        if [ "$count" -gt 0 ]; then
            echo "OK filepull 已配置 $count 台主机"
        else
            echo "OK filepull 未配置（手动添加: bash option-filepull/init.sh add）"
        fi
        ;;
    ""|menu|--menu)
        do_status || true
        echo ""
        sel=$(menu_select "跨机取件" "添加主机" "探活全部" "返回")
        case "$sel" in
            "1") do_add ;;
            "2") do_probe ;;
            *) : ;;
        esac
        ;;
    *) usage; exit 1 ;;
esac
