#!/bin/bash
# bootstrap-gh-auth.sh — ccconfig 一行式起步（curl | bash 入口）
#
# 全新 WSL/Ubuntu 一行命令：
#   curl -fsSL https://raw.githubusercontent.com/mengfanchun2017/ccconfig/main/bootstrap-gh-auth.sh | bash
#
# 职责（pre-bootstrap，自包含，不 source 任何 lib）：
#   1. 装 git（apt，缺失才装）
#   2. clone ccconfig 到 ~/git/ccconfig（缺失才 clone，已有则 pull）
#   3. 输出下一步: bash ~/git/ccconfig/init-bootstrap.sh
#
# gh auth + ccprivate 由 init-bootstrap.sh 接管，本脚本不重复。
# 自包含原因：curl|bash 运行时 ccconfig 还没 clone，source 不到 lib/。
#
# 环境变量：
#   CCCONFIG_REPO=myuser/ccconfig  fork 用（默认 mengfanchun2017/ccconfig）
#   CCP_GH_USER                   指定 GitHub 用户名（clone HTTPS 时复用 gh 凭证用，可选）

set -euo pipefail

CCCONFIG_REPO="${CCCONFIG_REPO:-mengfanchun2017/ccconfig}"
CCCONFIG_DIR="$HOME/git/ccconfig"

# ── 自包含输出函数（不依赖 lib/colors.sh）──
info() { printf '\033[0;34mℹ️  %s\033[0m\n' "$1"; }
ok()   { printf '\033[0;32m✅ %s\033[0m\n' "$1"; }
warn() { printf '\033[0;33m⚠️  %s\033[0m\n' "$1"; }
err()  { printf '\033[0;31m❌ %s\033[0m\n' "$1"; }

echo ""
echo "ccconfig 一行式起步 — 装 git + clone"
echo "════════════════════════════════════════"
echo ""

# ========== Step 1: 装 git ==========
if command -v git &>/dev/null; then
    ok "git 已装: $(git --version | cut -d' ' -f3)"
else
    info "git 未找到，安装中..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y git
    else
        err "无 apt-get，请手动装 git 后重跑"
        exit 1
    fi
    ok "git 已装: $(git --version | cut -d' ' -f3)"
fi

# ========== Step 2: clone ccconfig ==========
if [[ -d "$CCCONFIG_DIR/.git" ]]; then
    info "ccconfig 已存在，拉取最新..."
    git -C "$CCCONFIG_DIR" pull --ff-only 2>/dev/null || warn "pull 失败（可能有本地改动），继续"
else
    info "clone ccconfig → $CCCONFIG_DIR"
    mkdir -p "$HOME/git"
    if [[ -n "${CCP_GH_USER:-}" ]]; then
        git clone "https://github.com/${CCP_GH_USER}/ccconfig.git" "$CCCONFIG_DIR" 2>/dev/null \
            || git clone "https://github.com/${CCCONFIG_REPO}/ccconfig.git" "$CCCONFIG_DIR"
    else
        git clone "https://github.com/${CCCONFIG_REPO}/ccconfig.git" "$CCCONFIG_DIR"
    fi
fi
ok "ccconfig 就绪: $CCCONFIG_DIR"

# ========== Step 3: 输出下一步 ==========
echo ""
ok "起步完成 🎉"
echo ""
echo "  下一步：gh 认证 + ccprivate 配置"
echo ""
echo "    bash $CCCONFIG_DIR/init-bootstrap.sh"
echo ""
echo "  全流程（按顺序）："
echo "    1. bash init-bootstrap.sh   # gh auth + ccprivate（建仓或 clone 已有）"
echo "    2. bash init-base.sh all     # Ubuntu 环境 + LLM + 收尾链接/服务"
echo "    3. bash init-option.sh       # （可选）MCP/Skills/CLI 附加组件"
echo "    4. bash maintain.sh status   # 全量状态检查"
echo ""
echo "  完整手册: cat $CCCONFIG_DIR/BOOTSTRAP.md"
echo ""
