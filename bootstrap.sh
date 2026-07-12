#!/bin/bash
# bootstrap.sh — ccconfig 起步阶段 2：装 gh + GitHub 认证
#
# 设计：四步流程中的第二步。
#   Step 1: git clone https://github.com/mengfanchun2017/ccconfig.git ~/git/ccconfig
#   Step 2: bash bootstrap.sh                       ← 你在这里
#   Step 3: bash bin/init-ccprivate.sh              ← 创建 ccprivate 私有仓库
#   Step 4: bash init.sh all                        ← 全量初始化
#
# 职责：
#   - 装 GitHub CLI (gh)，apt 优先，二进制兜底
#   - gh auth 登录（PAT 路径，向导生成 classic PAT）
#   - 配置 git 用户身份（从 gh api 拿）
#   - 配置 git credential helper（gh 接管）
#   - 输出下一步引导
#
# 环境变量：
#   BOOTSTRAP_NOSUDO=1  跳过 sudo apt，用二进制装 gh（适合受限环境）
#   GH_TOKEN            直接用此 PAT 登录（CI 友好，跳过交互）
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
echo -e "  ${GRAY}做什么${NC}  确认 git 已装 + ~/.local/bin 在 PATH"
echo -e "  ${GRAY}为什么${NC}  bootstrap 只管 gh，不重复装 git（Step 1 clone 已装）"
echo -e "  ${GRAY}预计${NC}    < 1 s"

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
echo -e "  ${GRAY}做什么${NC}  装 GitHub CLI（gh 命令），sudo apt 优先（稳），curl 二进制兜底（NOSUDO 模式）"
echo -e "  ${GRAY}为什么${NC}  私仓交互全靠 gh；有了它才能做 Step 3 认证 + Step 4 配 git 身份"
echo -e "  ${GRAY}预计${NC}    ~15 s（apt）/ ~30 s（curl 二进制）"

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
echo -e "  ${GRAY}做什么${NC}  登录 GitHub（PAT 方式）"
echo -e "  ${GRAY}为什么${NC}  gh 能调 GitHub API 全靠已登录的 token；没它 Step 4 拿不到 git 身份、"
echo -e "           后续也无法 gh repo create / gh api 等操作"
echo -e "  ${GRAY}预计${NC}    ~1 min（含浏览器操作）"

if gh auth status &>/dev/null 2>&1; then
    ok "GitHub 已登录: $(gh api user --jq '.login' 2>/dev/null)"
elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    info "gh 未登录，但 SSH 密钥已存在 → 跳过 gh 认证"
    info "（git 操作走 SSH，不需 gh token）"
elif [[ -n "${GH_TOKEN:-}" ]]; then
    # 自动化/CI 路径：env var 直传
    echo "$GH_TOKEN" | gh auth login --hostname github.com --with-token
    ok "GitHub 已登录（via \$GH_TOKEN）"
else
    # 交互路径：让用户在 https://github.com/settings/tokens/new 生成 PAT
    # 推荐 classic PAT，勾选 repo / read:org / gist scopes
    echo ""
    echo -e "  ${BOLD}推荐路径：生成 PAT 并粘贴（最稳）${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} 浏览器打开: ${BOLD}https://github.com/settings/tokens/new${NC}"
    echo -e "     - Note: 随便填（如 ccconfig-$(hostname)）"
    echo -e "     - Expiration: 90 days 或更长"
    echo -e "     - Scopes: 勾选 ${YELLOW}repo${NC} + ${YELLOW}read:org${NC} + ${YELLOW}gist${NC}"
    echo -e "     - 点 Generate token → 复制 ${RED}ghp_xxx${NC} 开头的字符串"
    echo ""
    echo -e "  ${CYAN}2)${NC} 回到这里粘贴（输入隐藏）："
    echo ""
    read -rs -p "    PAT: " GH_TOKEN_INPUT
    echo ""
    if [[ -z "$GH_TOKEN_INPUT" ]]; then
        err "未输入 PAT，退出"
        err "  重跑 bootstrap.sh，或手动: gh auth login --with-token"
        exit 1
    fi
    # 去 Windows CRLF（git bash / WSL 常见问题）
    GH_TOKEN_INPUT=$(echo "$GH_TOKEN_INPUT" | tr -d '\r\n')
    echo "$GH_TOKEN_INPUT" | gh auth login --hostname github.com --with-token
    ok "GitHub 已登录: $(gh api user --jq '.login' 2>/dev/null)"
fi

# ========== Step 4: git 用户身份 + credential helper ==========
section "Step 4/5 git 用户身份"
echo -e "  ${GRAY}做什么${NC}  从 gh api 取 GitHub 用户名+邮箱 → 写入 git config --global；配 gh credential helper"
echo -e "  ${GRAY}为什么${NC}  git commit 需要 user.name / user.email；gh credential helper 让 clone/push 免密"
echo -e "  ${GRAY}预计${NC}    < 5 s"

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
echo -e "  ${BOLD}还剩两步（四步流程的 Step 3 + Step 4）:${NC}"
echo ""
echo -e "    ${CYAN}bash bin/init-ccprivate.sh${NC}"
echo -e "      ${GRAY}创建 ccprivate 私有仓库（API Key / Token / 个人配置），约 30 s${NC}"
echo ""
echo -e "    ${CYAN}bash init.sh all${NC}"
echo -e "      ${GRAY}全量初始化：Ubuntu 环境 → LLM → MCP → Skills → 验证，约 5 min${NC}"
echo ""
echo -e "  ${YELLOW}⚠️  init.sh all 首次运行会问:${NC}"
echo -e "  ${YELLOW}  - sudo 密码（装系统包）${NC}"
echo -e "  ${YELLOW}  - LLM API Key（DeepSeek/MiniMax/Claude 至少一个）${NC}"
echo ""
echo -e "  ${BOLD}其他选项:${NC}"
echo -e "    ${CYAN}bash init.sh${NC}              # 交互菜单（单步）"
echo -e "    ${CYAN}bash status.sh${NC}           # 看当前状态"
echo -e "    ${CYAN}cat BOOTSTRAP.md${NC}         # 完整手册"
echo ""