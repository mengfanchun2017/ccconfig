#!/bin/bash
# lib/tailscale-guard.sh — tailscale accept-routes 防护（防单位内网被黑洞）
#
# 背景（ADR 0051）：tailnet 上若有节点把**单位内网段**广告进来（subnet router），
# 本机开着 accept-routes 时会把去单位 LLM 网关的流量拐进 Tailscale 隧道 → 对端没有
# 该服务 → 静默超时（conn 无回包，非拒绝）。症状是"tailscale 一启动 office* 就挂、
# 关掉就好"，极易误判成 bridge / 网关问题。修法是**本机关掉 accept-routes**：
# 不动别人的 subnet router（它有别的用途），只让自己豁免。
#
# 判定：只有当「当前 preset 的 upstream 是私有内网地址、且不在 tailnet 自身网段」
# 时才需要防护。office*（10.x/172.16-31/192.168/内部域名）命中；home*（100.64/10
# tailnet CGNAT）不命中 —— 后者本来就是走 tailnet 访问，关 accept-routes 无影响但也
# 不需要强制。公网端点（api.deepseek.com 等）不命中。
#
# 依赖: 调用方已 source lib/colors.sh（info/warn/ok）

# tailscale CLI 位置：WSL 内通常没有，跑在 Windows 侧
_ts_exe() {
    if command -v tailscale &>/dev/null; then echo "tailscale"; return 0; fi
    local w="/mnt/c/Program Files/Tailscale/tailscale.exe"
    [[ -f "$w" ]] && { echo "$w"; return 0; }
    return 1
}

# tailscale 是否可用（CLI 存在 + 能查询状态）
tailscale_available() {
    local exe; exe="$(_ts_exe)" || return 1
    timeout 15 "$exe" status &>/dev/null
}

# 从 upstream URL 判断是否为「非 tailnet 的私有内网地址」。
# 返回 0=是（需要关 accept-routes）  1=否
# 用法: _upstream_is_private_intranet <url> [<host_header>]
#
# why host_header 非空就直接跳过：host_header 的存在意味着「base_url 指向 tailnet 跳板
# 节点、靠 Host/SNI 透传到单位」—— 这正是 home* 系列的形态，它**本来就该走 tailnet**，
# 关掉 accept-routes 反而可能坏事。只有 office*（base_url 直接是单位内网地址、无
# host_header）才是在"既要走 tailnet 又要直连单位内网"的矛盾场景。
_upstream_is_private_intranet() {
    local url="$1" hh="${2:-}"
    [[ -z "$url" ]] && return 1
    [[ -n "$hh" ]] && return 1     # tailnet 跳板透传形态（home*），不涉及
    local host="${url#*://}"; host="${host%%/*}"; host="${host%%:*}"

    # tailnet CGNAT 100.64.0.0/10 —— 这是 tailscale 自己的网段，不算"外部内网"
    if [[ "$host" =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\. ]]; then
        return 1
    fi
    # RFC1918 私有段
    if [[ "$host" =~ ^10\. ]]; then return 0; fi
    if [[ "$host" =~ ^192\.168\. ]]; then return 0; fi
    if [[ "$host" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then return 0; fi
    # 域名形态：解析后落在私有段也算（officeds* 用内网域名指向单位 IP 的情形）。
    # 只对"看起来有域名"的做解析，避免对 IP 字面量做无谓 DNS。
    if [[ "$host" == *[a-zA-Z]* ]]; then
        local ip
        ip="$(getent hosts "$host" 2>/dev/null | awk '{print $1; exit}')"
        if [[ -n "$ip" ]]; then
            [[ "$ip" =~ ^10\. || "$ip" =~ ^192\.168\. || "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && return 0
        fi
    fi
    return 1
}

# 查询 accept-routes 当前是否为 true。返回 0=true 1=false/未知
_tailscale_accept_routes() {
    local exe; exe="$(_ts_exe)" || return 1
    local v
    v="$(timeout 15 "$exe" debug prefs 2>/dev/null | grep -oE '"RouteAll":[[:space:]]*(true|false)' | grep -oE 'true|false' | head -1)"
    [[ "$v" == "true" ]]
}

# 防护入口：upstream 是外部私有内网 + 本机 accept-routes=true → 关掉它。
# 返回 0=无需处理或已修好  1=需要处理但失败
# 用法: tailscale_guard_intranet_upstream <upstream_url> [<host_header>]
tailscale_guard_intranet_upstream() {
    local url="$1" hh="${2:-}"
    _upstream_is_private_intranet "$url" "$hh" || return 0   # 公网/tailnet 端点，不涉及

    local exe; exe="$(_ts_exe)" || return 0                   # 没装 tailscale，无从谈起
    timeout 15 "$exe" status &>/dev/null || return 0          # tailscale 没跑，无路由劫持

    _tailscale_accept_routes || return 0                      # 已是 false，无需处理

    warn "  检测到 tailscale accept-routes 已开启，而当前 upstream 是外部内网地址"
    warn "  这会让去 $url 的流量被拐进 Tailscale 隧道 → 静默超时（ADR 0051）"
    info "  自动关闭 accept-routes（不影响 subnet router 本身，只让本机豁免）..."
    if timeout 25 "$exe" set --accept-routes=false &>/dev/null; then
        ok "  已关闭 accept-routes（持久化，重启 tailscale 保持）"
        return 0
    fi
    warn "  关闭失败 — 手动（Windows PowerShell）:"
    warn "    & \"\$env:ProgramFiles\\Tailscale\\tailscale.exe\" set --accept-routes=false"
    return 1
}

# 状态报告：用于 status.sh / maintain status
# 输出 0=正常/不适用  1=风险未处理
tailscale_guard_report() {
    local url="${1:-}"
    if ! tailscale_available; then
        echo "  tailscale 防护: ${GRAY}不可用（未装或未运行）${NC}"
        return 0
    fi
    local ar="false"
    _tailscale_accept_routes && ar="true"
    if [[ -n "$url" ]] && _upstream_is_private_intranet "$url"; then
        if [[ "$ar" == "true" ]]; then
            echo -e "  tailscale 防护: ${YELLOW}⚠ accept-routes=true 且 upstream 是内网 → 有黑洞风险${NC}"
            echo -e "    ${GRAY}修: bash lib/tailscale-guard.sh fix${NC}"
            return 1
        fi
        echo -e "  tailscale 防护: ${GREEN}✅ 内网 upstream + accept-routes=false（安全）${NC}"
        return 0
    fi
    echo -e "  tailscale 防护: ${GRAY}accept-routes=$ar（当前 upstream 非内网，不涉及）${NC}"
    return 0
}

# 命令行入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _sd="$(dirname "${BASH_SOURCE[0]}")"
    [[ -f "$_sd/colors.sh" ]] && source "$_sd/colors.sh"

    # 取当前 preset 的 upstream（有 merged 缓存用缓存，否则读 llm-current）
    _cur_upstream() {
        local cfg="$HOME/.cache/llm-merged.json" name="$HOME/.claude/llm-current"
        [[ -f "$name" ]] || { echo ""; return; }
        local p; p="$(tr -d '[:space:]' < "$name")"
        [[ -f "$cfg" ]] || { echo ""; return; }
        python3 -c "
import json,sys
try:
    d=json.load(open('$cfg')); l=d.get('llms',{}).get('$p',{})
    print((l.get('base_url','') or '') + '\t' + (l.get('host_header','') or ''))
except Exception: print('')
"
    }

    case "${1:-report}" in
        fix)
            IFS=$'\t' read -r u h <<< "$(_cur_upstream)"
            tailscale_guard_intranet_upstream "$u" "$h"
            ;;
        report)
            IFS=$'\t' read -r u h <<< "$(_cur_upstream)"
            tailscale_guard_report "$u"
            ;;
        available) tailscale_available && echo yes || echo no ;;
        accept-routes) _tailscale_accept_routes && echo true || echo false ;;
        *) echo "用法: $0 {fix|report|available|accept-routes}"; exit 2 ;;
    esac
fi