#!/bin/bash
# bootstrap-gh-auth.sh — ccconfig 起步阶段 2：装 gh + GitHub 认证
#
# 设计：四步流程中的第二步。
#   Step 1: git clone https://github.com/<your-username>/ccconfig.git ~/git/ccconfig
#   Step 2: bash bootstrap-gh-auth.sh               ← 你在这里
#   Step 3: bash init-ccprivate-repo.sh         ← 创建 ccprivate 私有仓库
#   Step 4: bash init-base.sh all                        ← 全量初始化
#
# 职责：
#   - 装 GitHub CLI (gh)，apt 优先，二进制兜底
#   - gh auth 登录（Web OAuth / PAT / $GH_TOKEN）
#   - 配置 git 用户身份（从 gh api 拿）
#   - 配置 git credential helper（gh 接管）
#   - 输出下一步引导
#
# 环境变量：
#   CCCONFIG_REPO=myuser/ccconfig  指定仓库（fork 用，默认从 clone URL 自动检测）
#   CCCONFIG_BRANCH=release        指定分支（默认 main）
#   BOOTSTRAP_NOSUDO=1  跳过 sudo apt，用二进制装 gh（适合受限环境）
#   GH_TOKEN            直接用此 PAT 登录（CI 友好，跳过交互）
#
# 依赖：git 已装（Step 1 装的）+ sudo（apt 路径需要，NOSUDO 模式除外）

set -euo pipefail

# 颜色/日志函数 — 优先 source 公共定义，兜底自包含
source "${BASH_SOURCE[0]%/*}/lib/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; DIM='\033[2m'; NC='\033[0m'
    ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
    err()   { echo -e "  ${RED}❌ $1${NC}"; }
    warn()  { echo -e "  ${YELLOW}⚠  $1${NC}"; }
    info()  { echo -e "  ${GRAY}$1${NC}"; }
    section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/dry-run.sh"

# dry-run 模式：只打印将执行的步骤，不实际运行
if _dry_run_enabled "$@"; then
    echo ""
    echo -e "${CYAN}ccconfig bootstrap — DRY-RUN${NC}"
    echo -e "${CYAN}══════════════════════════════${NC}"
    echo ""
    echo "  would: Step 2/5 sudo apt-get install -y gh"
    echo "  would: Step 3/5 gh auth login (interactive)"
    echo "  would: Step 4/5 git config --global user.email/name"
    echo "  would: Step 4/5 gh auth setup-git"
    echo ""
    echo "  === dry-run: no changes applied ==="
    exit 0
fi
LOCAL_BIN="$HOME/.local/bin"
NOSUDO="${BOOTSTRAP_NOSUDO:-}"

# get_gh_version: 优先从 ccconfig 的 path-helper.sh 拿，回退写死值
get_gh_version() {
    local helper="$SCRIPT_DIR/lib/path-helper.sh"
    if [[ -f "$helper" ]]; then
        (source "$helper" && get_gh_version) 2>/dev/null && return
    fi
    echo "2.65.0"
}

echo ""
echo -e "${CYAN}ccconfig bootstrap — 装 gh + GitHub 认证${NC}"
echo -e "${CYAN}════════════════════════════════════${NC}"
echo ""
[[ -n "$NOSUDO" ]] && info "模式: NO-SUDO（用 binary 装 gh）"

# ========== Step 1: 前置检查 ==========
section "Step 1/5 前置检查"

if ! command -v git &>/dev/null; then
    err "git 未装"
    err "  漏跑 Step 1？先: sudo apt install git"
    err "  或直接: git clone ${CCCONFIG_REPO:-https://github.com/<your-username>/ccconfig}.git ~/git/ccconfig"
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
echo -e "  ${GRAY}做什么${NC}  登录 GitHub"
echo -e "  ${GRAY}为什么${NC}  gh 调用 API 全靠登录 token；没它 Step 4 拿不到 git 身份、后续 gh repo create 也不行"
echo -e "  ${GRAY}预计${NC}    ~30 s（有代理）/ ~2 min（手动 fine-grained PAT）"

if gh auth status &>/dev/null 2>&1; then
    ok "GitHub 已登录: $(gh api user --jq '.login' 2>/dev/null)"
elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    info "gh 未登录，但 SSH 密钥已存在 → 跳过 gh 认证"
    info "（git 操作走 SSH，不需 gh token）"
elif [[ -n "${GH_TOKEN:-}" ]]; then
    info "检测到 \$GH_TOKEN，自动登录..."
    echo "$GH_TOKEN" | gh auth login --hostname github.com --with-token
    ok "GitHub 已登录（via \$GH_TOKEN）"
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    info "检测到 \$GITHUB_TOKEN，自动登录..."
    echo "$GITHUB_TOKEN" | gh auth login --hostname github.com --with-token
    ok "GitHub 已登录（via \$GITHUB_TOKEN）"
else
    # --- 双选项：A) PAT 粘贴（默认） B) Web OAuth ---
    echo ""
    echo -e "  ${BOLD}选择认证方式:${NC}"
    echo ""
    echo -e "  ${CYAN}A)${NC} ${BOLD}PAT 粘贴（推荐，默认）${NC}"
    echo -e "     - 生成 No-Expiration PAT，一次配置永久有效"
    echo -e "     - Token 仅存在本地 ~/.config/gh/hosts.yml（600 权限，等同于 SSH key 保护级别）"
    echo -e "     - ${GRAY}不会同步到 ccprivate 或任何远程仓库${NC}"
    echo -e "     - 其他终端/机器：GitHub 重新生成或从本机复制"
    echo ""
    echo -e "  ${CYAN}B)${NC} ${BOLD}Web OAuth one-time code${NC}"
    echo -e "     - 浏览器授权，首次配置最简单"
    echo -e "     - Token 有有效期，过期后需重新 ${YELLOW}gh auth login${NC}"
    echo ""
    read -p "  选择 [A]: " gh_auth_choice
    gh_auth_choice="${gh_auth_choice:-A}"

    case "${gh_auth_choice^^}" in
        B|2)
            info "浏览器打开 github.com → 点 Approve（~30 s）"
            gh auth login --web --git-protocol https --hostname github.com
            if ! gh auth status &>/dev/null 2>&1; then
                err "Web OAuth 失败"
                warn "可重试或选 A 方式: bash bootstrap-gh-auth.sh"
            fi
            ;;
        *)
            # PAT 粘贴（默认）
            echo ""
            echo -e "  浏览器打开 → 生成 No-Expiration PAT:"
            echo -e "    ${BOLD}https://github.com/settings/tokens/new${NC}"
            echo ""
            echo -e "  Scopes 勾选:"
            echo -e "    ${YELLOW}repo${NC}         (私有仓库读写，push 必需)"
            echo -e "    ${YELLOW}read:org${NC}     (gh api user 拿身份)"
            echo -e "    ${YELLOW}workflow${NC}     (gh workflow 命令)"
            echo ""
            echo -e "  ${GRAY}Token 存在本地 ~/.config/gh/hosts.yml，仅本机可用。${NC}"
            echo -e "  ${GRAY}不会同步到 ccprivate。其他机器请 GitHub 重新生成或从本机复制。${NC}"
            echo ""
            read -rs -p "  PAT（粘贴，不回显）: " GH_TOKEN_INPUT
            echo ""
            if [[ -z "$GH_TOKEN_INPUT" ]]; then
                echo ""
                warn "跳过认证。之后可手动:"
                warn "  gh auth login"
            else
                GH_TOKEN_INPUT=$(echo "$GH_TOKEN_INPUT" | tr -d '\r\n')
                echo "$GH_TOKEN_INPUT" | gh auth login --hostname github.com --with-token
            fi
            ;;
    esac
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
echo -e "  ${BOLD}还剩两步:${NC}"
echo ""
echo -e "    ${CYAN}bash init-ccprivate-repo.sh${NC}   # Step 3: 创建 ccprivate 私有仓库"
echo -e "    ${CYAN}bash init-base.sh all${NC}             # Step 4: 全量初始化（ccprivate 已就位）"
echo ""
echo -e "  ${GRAY}Step 4 自动做 4 件事:${NC}"
echo -e "  ${GRAY}  1. Ubuntu 环境（Node/Claude Code/symlink）${NC}"
echo -e "  ${GRAY}  2. LLM 配置（从 ccprivate/conf/llm.json 写入）${NC}"
echo -e "  ${GRAY}  3. MCP 服务器（Tavily/MiniMax 等）${NC}"
echo -e "  ${GRAY}  4. 收尾（链接修复 + 状态检查 + auto-sync 启动）${NC}"
echo ""
echo -e "  ${YELLOW}⚠️  可能需要:${NC}"
echo -e "  ${YELLOW}  - sudo 密码（apt 装系统包时）${NC}"
echo ""
echo -e "  ${BOLD}其他选项:${NC}"
echo -e "    ${CYAN}bash init-base.sh${NC}              # 交互菜单（单步）"
echo -e "    ${CYAN}bash maintain.sh status${NC}    # 看当前状态"
echo -e "    ${CYAN}cat BOOTSTRAP.md${NC}         # 完整手册"
echo ""