#!/bin/bash
# refresh-gh-auth.sh — GitHub PAT 一键续期
#
# 用法：bash ~/git/ccconfig/bin/refresh-gh-auth.sh
#
# 前置：GitHub 网页 https://github.com/settings/tokens
#       找到旧 token → 点 Regenerate token → 复制新 token string

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"
source "$SCRIPT_DIR/../lib/colors.sh"
source "$SCRIPT_DIR/../lib/interact.sh"

echo ""
echo -e "${CYAN}GitHub PAT 续期${NC}"
echo -e "${CYAN}═══════════════${NC}"
echo ""

# 显示当前状态
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    current_user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
    echo -e "  当前账号: ${GREEN}${current_user}${NC}"
    if gh api user &>/dev/null 2>&1; then
        echo -e "  当前 token: ${GREEN}✅ 有效${NC}（push 失败来续期，直接粘贴新 token）"
    else
        echo -e "  当前 token: ${RED}❌ 失效${NC}"
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
echo -e "  ${GRAY}提示：token 选 No expiration 通常无需续期；push 失败时点 Regenerate 可继承原权限${NC}"
echo ""

# 读新 token（空输入 = 保持现状退出）
NEW_TOKEN=""
NEW_TOKEN=$(prompt_password "新 PAT（不回显，直接回车 = 保持现状退出）")
if [[ -z "$NEW_TOKEN" ]]; then
    info "未输入，保持现有 token，退出"
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
echo ""
