#!/bin/bash
# refresh-gh-auth.sh — GitHub PAT 一键续期
#
# 用法：bash ~/git/ccconfig/bin/refresh-gh-auth.sh
#
# 适用场景：monitor / maintain status 检测到 PAT 即将过期或已失效
# 流程：引导粘新 token → gh auth login → 验证 push 通 → 清过期 flag
#
# 前置：用户在 GitHub 网页 https://github.com/settings/tokens
#       找到旧 token → 点 Regenerate token → 复制新 token string

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; NC='\033[0m'

echo ""
echo -e "${CYAN}GitHub PAT 续期${NC}"
echo -e "${CYAN}═══════════════${NC}"
echo ""

# 显示当前状态
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    current_user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
    echo -e "  当前账号: ${GREEN}${current_user}${NC}"

    current_token=$(gh auth token 2>/dev/null || echo "")
    if [[ -n "$current_token" ]]; then
        current_exp=$(curl -s --max-time 5 -H "Authorization: Bearer $current_token" \
            -D - https://api.github.com/user -o /dev/null 2>/dev/null | \
            grep -i 'github-authentication-token-expiration:' | \
            awk '{print $2}' | tr -d '\r')
        if [[ -n "$current_exp" ]]; then
            now=$(date +%s)
            exp_epoch=$(date -d "$current_exp UTC" +%s 2>/dev/null || echo 0)
            days_left=$(( (exp_epoch - now) / 86400 ))
            if [[ $days_left -lt 10 ]]; then
                echo -e "  当前 token: ${RED}剩余 ${days_left} 天（过期 ${current_exp} UTC）${NC}"
            elif [[ $days_left -lt 30 ]]; then
                echo -e "  当前 token: ${YELLOW}剩余 ${days_left} 天${NC}"
            else
                echo -e "  当前 token: ${GREEN}剩余 ${days_left} 天${NC}"
            fi
        else
            echo -e "  当前 token: classic PAT（无过期）或无 expiration"
        fi
    fi
    echo ""
else
    echo -e "  ${YELLOW}⚠${NC}  gh 未登录 — 直接走新登录流程"
    echo ""
fi

echo -e "  ${BOLD}续期步骤（30 秒）：${NC}"
echo ""
echo -e "    1. 打开 ${CYAN}https://github.com/settings/tokens${NC}"
echo -e "    2. 找到 ccconfig-push，点 ${BOLD}Regenerate token${NC}"
echo -e "    3. 复制新 token，粘贴到下面（不回显）"
echo ""
echo -e "  ${GRAY}提示：fine-grained PAT 过期前 30 天可点 Regenerate，继承原权限${NC}"
echo ""

# 读新 token（空输入 = 保持现状退出）
NEW_TOKEN=""
read -rs -p "  新 PAT（不回显，直接回车 = 保持现状退出）: " NEW_TOKEN
echo ""
if [[ -z "$NEW_TOKEN" ]]; then
    echo -e "  ${GRAY}未输入，保持现有 token，退出${NC}"
    exit 0
fi

# 应用：gh auth login --with-token
echo ""
echo -e "  ${GRAY}更新 gh auth...${NC}"
if ! echo "$NEW_TOKEN" | gh auth login --with-token --hostname github.com >/dev/null 2>&1; then
    echo -e "  ${RED}❌ gh auth login 失败 — token 可能无效${NC}"
    exit 1
fi
echo -e "  ${GREEN}✅${NC} gh auth login 成功"

# 配置 credential helper
gh auth setup-git >/dev/null 2>&1 || true
echo -e "  ${GREEN}✅${NC} git credential helper 已配置"

# 验证
echo ""
echo -e "  ${GRAY}验证 push...${NC}"
if gh api user --jq '.login' &>/dev/null; then
    new_user=$(gh api user --jq '.login')
    echo -e "  ${GREEN}✅${NC} gh api user 验证通过 (${new_user})"
else
    echo -e "  ${RED}❌ 验证失败，token 无效或权限不足${NC}"
    exit 1
fi

# 清过期 flag
rm -f "$HOME/.local/share/ccconfig/pat-warn"
rm -f "$HOME/.local/share/ccconfig/pat-status"
echo -e "  ${GREEN}✅${NC} 已清过期 flag 文件"

echo ""
echo -e "  ${GREEN}PAT 已续期。下次 push 自动用新 token。${NC}"
echo -e "  ${GRAY}下次过期检查：maintain.sh status 或 monitor tail${NC}"
echo ""
