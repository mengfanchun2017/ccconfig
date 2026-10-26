#!/bin/bash
# lib/net.sh — GitHub 网络辅助
#
# 大陆网络 github.com 主域被 GFW 阻断（TLS/SNI 层丢包，TCP connect 通但 TLS ClientHello 被丢），
# 仅 api.github.com / raw.githubusercontent.com 直连通。github.com 主域访问须走本机 Clash 代理。
# ADR: docs/adr/0011-git-auth-fine-grained-pat.md
#
# 用法：
#   source lib/net.sh
#   proxy=$(net_gh_proxy)      # 取 github.com 可用代理 URL（或空）
#   net_gh_probe [URL]         # 探测 URL 可达性，直连失败自动换代理。0=可达
#   github_reachable           # 布尔：github.com 主域是否可达（升级预检用）
#   gh_latest_tag <owner/repo> [stripv]   # release 最新 tag；0=拿到，1=取不到

# 取可用代理。优先级：环境变量 → 本机 Clash 端口（7897/7890）
net_gh_proxy() {
    local p
    p="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
    [ -n "$p" ] && { echo "$p"; return 0; }
    for p in 7897 7890; do
        if timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/$p" 2>/dev/null; then
            echo "http://127.0.0.1:$p"
            return 0
        fi
    done
    echo ""
}

# 探测 URL（默认 https://github.com）是否可达；有代理且直连失败时自动走代理
net_gh_probe() {
    local url="${1:-https://github.com}"
    local proxy
    proxy=$(net_gh_proxy)
    if [ -n "$proxy" ]; then
        curl -sI --connect-timeout 5 --max-time 8 -x "$proxy" "$url" -o /dev/null 2>/dev/null
    else
        curl -sI --connect-timeout 5 --max-time 8 "$url" -o /dev/null 2>/dev/null
    fi
}

github_reachable() {
    net_gh_probe "https://github.com"
}

# 取 release 最新 tag（默认去 v 前缀）。
#   gh_latest_tag <owner/repo> [keepv]   → stdout: tag；0=成功，1=取不到
#
# 为什么不用裸 curl api.github.com：匿名配额是 **60 次/小时/IP**，而一台机器上
# 多个 WSL 实例 + 多个升级步骤共用同一个出口 IP → 几个来回就 403
# `API rate limit exceeded`。401/403 的 JSON 里没有 tag_name，裸 curl 管道解析后
# 得到空串，调用方只能笼统报「无法获取最新版本」——与"真的没发布"无法区分，
# 这正是 maintain upgrade 里 OfficeCLI 那句报错的来源。
# gh 已登录时走 `gh api`（5000 次/小时，per-token），彻底绕开 IP 池。
gh_latest_tag() {
    local repo="$1" keepv="${2:-0}"
    local tag=""

    if command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
        tag=$(timeout 15 gh api "repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null) || tag=""
    fi

    # 兜底：匿名 curl（共享 IP 池，可能 403）。用 message 字段区分限流与真失败
    if [ -z "$tag" ]; then
        local resp
        resp=$(curl -s --connect-timeout 5 --max-time 15 \
            "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null) || resp=""
        # 有 message 字段 = 401/403（限流/凭据问题），不是"仓库没有 release"
        if printf '%s' "$resp" | grep -q '"message"'; then
            return 1
        fi
        tag=$(printf '%s' "$resp" | python3 -c \
            "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null) || tag=""
    fi

    [ -n "$tag" ] || return 1
    [ "$keepv" = "1" ] || tag="${tag#v}"
    printf '%s\n' "$tag"
    return 0
}
