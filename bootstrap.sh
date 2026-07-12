#!/bin/bash
# bootstrap.sh — ccconfig 起步阶段 2：装 gh + GitHub 认证
#
# 设计：三步流程中的第二步。
#   Step 1: git clone https://github.com/mengfanchun2017/ccconfig.git ~/git/ccconfig
#   Step 2: bash bootstrap.sh           ← 你在这里
#   Step 3: cd ~/git/ccconfig && bash init.sh all
#
# 职责：
#   - 装 GitHub CLI (gh)，apt 优先，二进制兜底
#   - gh auth 登录（如已有 SSH 密钥则跳过）
#   - 配置 git 用户身份（从 gh api 拿）
#   - 配置 git credential helper（gh 接管）
#   - 输出下一步引导
#
# 环境变量：
#   BOOTSTRAP_NOSUDO=1  跳过 sudo apt，用二进制装 gh（适合受限环境）
#
# 依赖：git 已装（Step 1 装的）+ sudo（apt 路径需要，NOSUDO 模式除外）

set -euo pipefail

# ========== 颜色 ==========
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0:0m'; NC='\033[0m'

info() { echo -e "  ${GRAY}$1${NC}"; }
ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
err()  { echo -e "  ${RED}❌ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

LOCAL_BIN="$HOME/.local/bin"
NOSUDO="${BOOTSTRAP_NOSUDO:-}"

# get_gh_version: 优先从 ccconfig 的 path-helper.sh 拿，回退写死值
get_gh_version() {
    local helper="$OLDPWD/lib/path-helper.sh"
    if [[ -f "$helper" ]]; then
        (source "$helper" && get_gh_version) 2>/dev/null && return
    fi
    echo "2.65.0"
}

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   ccconfig bootstrap — 装 gh + GitHub 认证  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""
[[ -n "$NOSUDO" ]] && info "模式: NO-SUDO（用 binary 装 gh）"

# ========== Step 1: 前置检查 ==========
section "Step 1/5 前置检查"

if ! command -v git &>/dev/null; then
    err "git 未装"
    err "  漏跑 Step 1？先: sudo apt install git"
    err "  或直接: git clone https://github.com/mengfanchun2017/ccconfig.git ~/git/ccconfig"
    exit 1
fi
ok "git: $(git --version | cut -d' ' -f3)"

# 把 ~/.local/bin 放进 PATH
export PATH="$LOCAL_BIN:$PATH"
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        info "已追加 PATH → ~/.bashrc（新终端生效）"
    fi
fi
mkdir -p "$LOCAL_BIN"

# ========== Step 2: 装 gh ==========
section "Step 2/5 装 GitHub CLI (gh)"

if command -v gh &>/dev/null; then
    ok "gh 已装: $(gh --version | head -1)"
elif [[ -n "$NOSUDO" ]] || ! command -v sudo &>/dev/null; then
    info "下载 gh 二进制（NO-SUDO 模式）..."
    gh_ver=$(get_gh_version)
    curl -fsSL "https://github.com/cli/cli/releases/download/v${gh_ver}/gh_${gh_ver}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz
    tar -xzf /tmp/gh.tar.gz -C /tmp
    mv "/tmp/gh_${gh_ver}_linux_amd64/bin/gh" "$LOCAL_BIN/gh"
    chmod +x "$LOCAL_BIN/gh"
    rm -rf /tmp/gh.tar.gz "/tmp/gh_${gh_ver}_linux_amd64"
    ok "gh 已装: $(gh --version | head -1)"
else
    info "运行: sudo apt-get update && sudo apt-get install -y gh"
    sudo apt-get update -qq
    sudo apt-get install -y gh
    ok "gh 已装: $(gh --version | head -1)"
fi

# ========== Step 3: gh auth 登录 ==========
section "Step 3/5 GitHub 认证"

if gh auth status &>/dev/null 2>&1; then
    ok "GitHub 已登录: $(gh api user --jq '.login' 2>/dev/null)"
elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    info "gh 未登录，但 SSH 密钥已存在 → 跳过 gh 认证"
    info "（git 操作走 SSH，不需 gh token）"
else
    echo ""
    echo -e "  ${BOLD}请在浏览器中授权 GitHub:${NC}"
    echo ""
    gh auth login --git-protocol https --skip-ssh-key --hostname github.com
fi

# ========== Step 4: git 用户身份 + credential helper ==========
section "Step 4/5 git 用户身份"

if gh auth status &>/dev/null 2>&1; then
    gh_email=$(gh api user --jq '.email // empty' 2>/dev/null)
    gh_name=$(gh api user --jq '.name // .login' 2>/dev/null)
    [[ -n "$gh_email" ]] && git config --global user.email "$gh_email"
    [[ -n "$gh_name" ]]  && git config --global user.name  "$gh_name"
    ok "git user: $(git config --global user.name) <$(git config --global user.email)>"
    gh auth setup-git >/dev/null 2>&1 || true
    ok "git credential helper → gh"
elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    info "SSH 密钥已配，跳过 git 身份设置"
    info "  请手动: git config --global user.email \"you@example.com\""
    info "         git config --global user.name  \"Your Name\""
else
    warn "GitHub 未认证，git 身份未配置"
    warn "  手动: git config --global user.email \"you@example.com\""
    warn "        git config --global user.name  \"Your Name\""
fi

# ========== Step 5: 引导下一步 ==========
section "Step 5/5 准备完成"

echo ""
echo -e "  ${GREEN}ccconfig 已就绪 🎉${NC}"
echo ""
echo -e "  ${BOLD}下一步:${NC}"
echo ""
echo -e "    ${CYAN}cd ~/git/ccconfig && bash init.sh all${NC}"
echo ""
echo -e "  ${GRAY}这一步会自动做 5 件事:${NC}"
echo -e "  ${GRAY}  1. Ubuntu 环境（Node/Claude Code/symlink）${NC}"
echo -e "  ${GRAY}  2. LLM 配置（自动写 ANTHROPIC_AUTH_TOKEN）${NC}"
echo -e "  ${GRAY}  3. MCP 服务器（Tavily/MiniMax/Supabase/Cloudflare）${NC}"
echo -e "  ${GRAY}  4. Skills 同步${NC}"
echo -e "  ${GRAY}  5. 状态验证${NC}"
echo ""
echo -e "  ${YELLOW}⚠️  首次运行会问:${NC}"
echo -e "  ${YELLOW}  - sudo 密码（装系统包）${NC}"
echo -e "  ${YELLOW}  - LLM API Key（DeepSeek/MiniMax/Claude 至少一个）${NC}"
echo ""
echo -e "  ${BOLD}其他选项:${NC}"
echo -e "    ${CYAN}bash init.sh${NC}              # 交互菜单（单步）"
echo -e "    ${CYAN}bash status.sh${NC}           # 看当前状态"
echo -e "    ${CYAN}cat BOOTSTRAP.md${NC}         # 完整手册"
echo ""