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
