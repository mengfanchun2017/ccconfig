#!/bin/bash
# bootstrap.sh — 全新 WSL / Ubuntu 零依赖一行起步
#
# 设计目标：用户复制一条命令就能把空 WSL 拉到 init.sh 入口
#
# 用法（两种）：
#   curl -fsSL https://raw.githubusercontent.com/<user>/ccconfig/main/bootstrap.sh | bash
#   curl -fsSL https://.../bootstrap.sh | CCCONFIG_REPO=<user>/ccconfig bash
#
# 环境变量：
#   CCCONFIG_REPO   GitHub 仓库（默认 mengfanchun2017/ccconfig）
#   CCCONFIG_BRANCH 分支（默认 main；发布版可改 release）
#   BOOTSTRAP_NOSUDO=1  跳过 sudo，用 binary 装（适合受限环境）
#
# 依赖：bash + 网络（curl 或 wget）+ sudo（仅 apt 路径需要）

set -euo pipefail

# ========== 颜色 ==========
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; NC='\033[0m'

info() { echo -e "  ${GRAY}$1${NC}"; }
ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
err()  { echo -e "  ${RED}❌ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

CCCONFIG_REPO="${CCCONFIG_REPO:-mengfanchun2017/ccconfig}"
CCCONFIG_BRANCH="${CCCONFIG_BRANCH:-main}"
CCCONFIG_DIR="${CCCONFIG_HOME:-$HOME/git/ccconfig}"
NOSUDO="${BOOTSTRAP_NOSUDO:-}"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   ccconfig bootstrap — 全新 WSL 一键起步   ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""
info "目标仓库: $CCCONFIG_REPO ($CCCONFIG_BRANCH)"
info "目标路径: $CCCONFIG_DIR"
[[ -n "$NOSUDO" ]] && info "模式: NO-SUDO（用 binary 装）"

# ========== Step 1: 网络工具 + GitHub 连通性 ==========
section "Step 1/4 网络工具 + GitHub 连通性"

have_curl=false; have_wget=false
command -v curl &>/dev/null && have_curl=true
command -v wget &>/dev/null && have_wget=true

if $have_curl || $have_wget; then
    $have_curl && ok "curl 已装" || ok "wget 已装"
else
    err "curl 和 wget 都缺失 — 无法下载任何东西"
    err "  请手动安装一个: sudo apt install curl  或  sudo apt install wget"
    exit 1
fi

# 优先 curl，wget 兜底
fetch() {
    local url="$1" out="$2"
    if $have_curl; then
        curl -fsSL "$url" -o "$out"
    else
        wget -q "$url" -O "$out"
    fi
}

# 检测 GitHub 直连（443）。失败时给清晰的故障指引。
check_github_connectivity() {
    local probe_url="https://raw.githubusercontent.com/${CCCONFIG_REPO}/${CCCONFIG_BRANCH}/README.md"
    if $have_curl; then
        curl -fsS --connect-timeout 8 --max-time 15 -o /dev/null "$probe_url" 2>/dev/null
    else
        wget -q --timeout=15 --tries=1 -O /dev/null "$probe_url" 2>/dev/null
    fi
}

info "测试 GitHub 连通性..."
if check_github_connectivity; then
    ok "GitHub 直连通"
else
    warn "GitHub 直连不通（DNS 失败 / GFW 阻断 / 需代理）"
    echo ""
    echo -e "  ${BOLD}常见修复:${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} 配置代理（推荐，国内环境几乎必备）:"
    echo -e "     export https_proxy=http://127.0.0.1:7897"
    echo -e "     export http_proxy=\$https_proxy"
    echo -e "     然后重跑本条 curl 命令"
    echo ""
    echo -e "  ${CYAN}2)${NC} 用 ghproxy.com 镜像（无需代理）:"
    echo -e "     curl -fsSL https://ghproxy.com/raw.githubusercontent.com/${CCCONFIG_REPO}/${CCCONFIG_BRANCH}/bootstrap.sh | bash"
    echo ""
    echo -e "  ${CYAN}3)${NC} 手动 git clone 后本地跑（git 也读 \$https_proxy，配置后即可）:"
    echo -e "     git clone https://github.com/${CCCONFIG_REPO}.git ~/git/ccconfig"
    echo -e "     cd ~/git/ccconfig && bash init.sh all"
    echo ""
    err "GitHub 不可达，退出。请按上述任一方式修复后重试。"
    exit 1
fi

# ========== Step 2: git（必需） ==========
section "Step 2/4 git"

if command -v git &>/dev/null; then
    ok "git 已装: $(git --version | head -1)"
else
    warn "git 未装"
    if [[ -n "$NOSUDO" ]]; then
        # 从 kernel.org 下 tarball，本地编译太慢，改为提示用户
        err "NO-SUDO 模式无法装 git，请先手动装: sudo apt install git"
        exit 1
    fi
    if ! command -v sudo &>/dev/null; then
        err "sudo 不可用，请手动装: apt install git (root) 或用 sudo 配置 NOPASSWD"
        exit 1
    fi
    info "运行: sudo apt-get update && sudo apt-get install -y git"
    sudo apt-get update -qq
    sudo apt-get install -y git
    ok "git 已装: $(git --version | head -1)"
fi

# ========== Step 3: clone / 更新 ccconfig ==========
section "Step 3/4 ccconfig 仓库"

mkdir -p "$(dirname "$CCCONFIG_DIR")"

if [ -d "$CCCONFIG_DIR/.git" ]; then
    info "ccconfig 已存在，pull 最新"
    cd "$CCCONFIG_DIR"
    git fetch origin "$CCCONFIG_BRANCH" 2>&1 | tail -1 || true
    git checkout "$CCCONFIG_BRANCH" 2>&1 | tail -1
    git pull --ff-only origin "$CCCONFIG_BRANCH" 2>&1 | tail -2 || warn "pull 失败（可能本地有改动），继续"
    ok "ccconfig 已更新"
else
    info "clone $CCCONFIG_REPO → $CCCONFIG_DIR"
    if command -v gh &>/dev/null && gh auth status &>/dev/null; then
        gh repo clone "$CCCONFIG_REPO" "$CCCONFIG_DIR" -- --branch "$CCCONFIG_BRANCH" 2>&1 | tail -2
    else
        # HTTPS clone（无需 auth），public repo 够用
        git clone "https://github.com/${CCCONFIG_REPO}.git" "$CCCONFIG_DIR" --branch "$CCCONFIG_BRANCH" 2>&1 | tail -3
    fi
    ok "ccconfig 已 clone"
fi

cd "$CCCONFIG_DIR"
chmod +x init.sh init-*.sh setup.sh bin/*.sh option-*/init.sh 2>/dev/null || true

# ========== Step 4: 引导下一步 ==========
section "Step 4/4 准备完成"

echo ""
echo -e "  ${GREEN}ccconfig 已就绪 🎉${NC}"
echo ""
echo -e "  ${BOLD}下一步:${NC}"
echo ""
echo -e "    ${CYAN}cd $CCCONFIG_DIR && bash init.sh all${NC}"
echo ""
echo -e "  ${GRAY}这一步会自动做 5 件事:${NC}"
echo -e "  ${GRAY}  1. Ubuntu 环境（git/gh/Node/Claude Code/symlink）${NC}"
echo -e "  ${GRAY}  2. LLM 配置（自动写 ANTHROPIC_AUTH_TOKEN）${NC}"
echo -e "  ${GRAY}  3. MCP 服务器（Tavily/MiniMax/Supabase/Cloudflare）${NC}"
echo -e "  ${GRAY}  4. Skills 同步${NC}"
echo -e "  ${GRAY}  5. 状态验证${NC}"
echo ""
echo -e "  ${YELLOW}⚠️  首次运行会问:${NC}"
echo -e "  ${YELLOW}  - sudo 密码（装系统包）${NC}"
echo -e "  ${YELLOW}  - GitHub 认证（推荐 PAT，比 Web OAuth 稳）${NC}"
echo -e "  ${YELLOW}  - LLM API Key（DeepSeek/MiniMax/Claude 至少一个）${NC}"
echo ""
echo -e "  ${BOLD}其他选项:${NC}"
echo -e "    ${CYAN}bash init.sh${NC}              # 交互菜单（单步）"
echo -e "    ${CYAN}bash status.sh${NC}           # 看当前状态"
echo -e "    ${CYAN}cat BOOTSTRAP.md${NC}         # 完整 7 阶段手册"
echo ""
echo -e "  ${GRAY}完成后日常使用: cd ~/git/ccconfig && claude (配置) 或 cd ~/git/<项目> && claude (开发)${NC}"