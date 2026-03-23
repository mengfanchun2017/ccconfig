#!/bin/bash

# ==============================================
# Git + GitHub CLI 环境初始化脚本
# 功能：安装 gh、登录 GitHub、克隆配置仓库
# ==============================================

# set -e 会导致 read 在某些情况下退出，改用 trap 捕获错误
# set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

GH_VERSION="2.63.2"
GH_DIR="$HOME/.local/bin"

# -------------------------- 检查并安装 git --------------------------
print_info "检查 git..."
if command -v git &> /dev/null; then
    print_success "git 已安装: $(git --version)"
else
    print_warning "git 未安装，请先安装: sudo apt install git"
    exit 1
fi

# -------------------------- 检查/配置 Git 用户身份 --------------------------
print_info "检查 Git 用户身份..."
GIT_EMAIL=$(git config --global user.email 2>/dev/null)
GIT_NAME=$(git config --global user.name 2>/dev/null)

if [[ -z "$GIT_EMAIL" || -z "$GIT_NAME" ]]; then
    print_warning "Git 用户身份未配置，正在设置..."
    if [[ -z "$GIT_EMAIL" ]]; then
        echo ""
        echo "=========================================="
        echo "  请输入 GitHub 注册邮箱"
        echo "=========================================="
        echo -n "邮箱: "
        read GIT_EMAIL
        if [[ -n "$GIT_EMAIL" ]]; then
            git config --global user.email "$GIT_EMAIL"
        fi
    fi
    if [[ -z "$GIT_NAME" ]]; then
        echo ""
        echo "=========================================="
        echo "  请输入 GitHub 用户名"
        echo "=========================================="
        echo -n "用户名: "
        read GIT_NAME
        if [[ -n "$GIT_NAME" ]]; then
            git config --global user.name "$GIT_NAME"
        fi
    fi
    echo ""
    print_success "Git 用户身份已配置: $(git config --global user.email)"
else
    print_success "Git 用户身份已配置: $GIT_EMAIL ($GIT_NAME)"
fi

# -------------------------- 检查并安装 gh --------------------------
print_info "检查 GitHub CLI (gh)..."
if command -v gh &> /dev/null; then
    print_success "gh 已安装: $(gh --version)"
else
    print_warning "gh 未安装，正在下载..."

    # 下载 gh
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o gh.tar.gz

    if [[ ! -f gh.tar.gz ]]; then
        print_error "下载失败，请检查网络"
        exit 1
    fi

    tar xzf gh.tar.gz
    mkdir -p "$GH_DIR"
    cp "gh_${GH_VERSION}_linux_amd64/bin/gh" "$GH_DIR/"
    chmod +x "$GH_DIR/gh"

    # 配置 PATH
    if ! grep -q '~/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$GH_DIR:$PATH"

    print_success "gh 已安装到 $GH_DIR"
    cd - > /dev/null
    rm -rf "$TMP_DIR"
fi

# 確保 PATH 生效
export PATH="$GH_DIR:$PATH"

# -------------------------- GitHub 登录 --------------------------
print_info "检查 GitHub 登录状态..."
if gh auth status &> /dev/null; then
    print_success "已登录 GitHub: $(gh api user --jq '.login')"
else
    echo ""
    echo "=========================================="
    echo "  GitHub 登录"
    echo "=========================================="
    echo ""
    echo "将启动 GitHub Device Flow 授权..."
    echo ""
    echo "操作步骤:"
    echo "  1. 下方会显示一个 8 位代码 (如 AAA7-55E5)"
    echo "  2. 复制这个代码"
    echo "  3. 打开浏览器访问 https://github.com/login/device"
    echo "  4. 输入代码并点击授权"
    echo "  5. 授权完成后此脚本会自动继续"
    echo ""

    # 使用 script 创建伪终端，让 gh auth login 能交互式运行并显示 8 位码
    # -t 分配伪终端，-q 静默模式
    # 输出到当前终端，用户可以看到 8 位码
    script -t /dev/null -q gh auth login --hostname github.com

    # 验证登录状态
    if gh auth status &> /dev/null; then
        print_success "GitHub 登录成功: $(gh api user --jq '.login')"
    else
        print_warning "登录未完成，可以稍后运行 'gh auth login'"
    fi
fi

# -------------------------- 获取仓库信息 --------------------------
echo ""
echo "=========================================="
echo "📦 仓库信息"
echo "=========================================="
echo ""

# 仓库信息
echo -n "GitHub 用户名/仓库名 [默认: <your-github-username>/claude-config]: "
read REPO
REPO="${REPO:-<your-github-username>/claude-config}"

# 目标目录
DEFAULT_TARGET="$HOME/git/claude-config"
echo -n "克隆到目录 [默认: $DEFAULT_TARGET]: "
read TARGET_DIR
TARGET_DIR="${TARGET_DIR:-$DEFAULT_TARGET}"

# -------------------------- 克隆仓库 --------------------------
print_info "正在克隆仓库..."
print_info "仓库: $REPO"
print_info "目标: $TARGET_DIR"

# 确保目标目录的父目录存在
PARENT_DIR=$(dirname "$TARGET_DIR")
mkdir -p "$PARENT_DIR"

# 重试逻辑
MAX_RETRIES=3
RETRY_COUNT=0

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    if gh repo clone "$REPO" "$TARGET_DIR" 2>&1; then
        print_success "克隆完成!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
            echo ""
            print_warning "网络错误 (尝试 $RETRY_COUNT/$MAX_RETRIES)"
            echo ""
            echo "请选择："
            echo "  [R] 重试 - 网络弄好了继续"
            echo "  [Q] 退出"
            echo ""
            read -p "请输入 [R]: " choice
            choice="${choice:-R}"
            if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
                print_info "已退出"
                exit 0
            fi
        else
            print_error "已达到最大重试次数"
            exit 1
        fi
    fi
done

# -------------------------- 安装 Claude Code --------------------------
echo ""
echo "=========================================="
echo "📦 安装 Claude Code"
echo "=========================================="
echo ""

# 检查 Claude Code 是否已安装
if command -v claude &> /dev/null; then
    print_success "Claude Code 已安装: $(claude --version)"
else
    print_info "正在安装 Claude Code..."

    # 检测系统架构
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        ARCH_NAME="amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        ARCH_NAME="arm64"
    else
        ARCH_NAME="amd64"
    fi

    # 下载最新版本
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"

    # 获取最新版本号
    LATEST_VERSION=$(curl -s https://api.github.com/repos/anthropics/claude-code/releases/latest | grep -o '"tag_name": *[^,]*' | cut -d'"' -f4)
    if [[ -z "$LATEST_VERSION" ]]; then
        LATEST_VERSION="latest"
    fi

    print_info "下载版本: $LATEST_VERSION"

    # 下载二进制
    curl -fsSL "https://github.com/anthropics/claude-code/releases/download/${LATEST_VERSION}/claude-linux-${ARCH_NAME}" -o claude

    if [[ ! -f claude ]]; then
        print_error "下载失败，请检查网络"
        cd - > /dev/null
        rm -rf "$TMP_DIR"
        exit 1
    fi

    chmod +x claude

    # 安装到用户本地 bin
    mkdir -p "$HOME/.local/bin"
    mv claude "$HOME/.local/bin/claude"

    # 添加到 PATH
    if ! grep -q '~/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$HOME/.local/bin:$PATH"

    cd - > /dev/null
    rm -rf "$TMP_DIR"

    print_success "Claude Code 已安装到 ~/.local/bin/claude"
fi

# 验证安装
if command -v claude &> /dev/null; then
    print_success "Claude Code 版本: $(claude --version)"
fi

# -------------------------- 符号链接检查 --------------------------
echo ""
echo "========================================"
echo "  🔍 符号链接状态检查"
echo "========================================"

CLAUDE_DIR="$HOME/.claude"

check_symlink() {
    local link="$1"
    local name="$2"
    if [ -L "$link" ]; then
        if [ -e "$link" ]; then
            echo "   ✅ $name: 正常"
            return 0
        else
            echo "   ❌ $name: 链接断开"
            return 1
        fi
    elif [ -e "$link" ]; then
        echo "   ⚠️  $name: 是文件而非链接"
        return 2
    else
        echo "   ⭕ $name: 未配置"
        return 3
    fi
}

check_symlink "$CLAUDE_DIR/settings.json" "settings.json"
check_symlink "$HOME/CLAUDE.md" "CLAUDE.md"
check_symlink "$CLAUDE_DIR/projects/home-francis-git/memory/MEMORY.md" "MEMORY.md"

echo ""

# -------------------------- 完成 --------------------------
echo "🎉 环境初始化完成！"
echo ""
echo "仓库位置: $TARGET_DIR"
echo "Claude Code: $(claude --version 2>/dev/null || echo '已安装')"
echo ""
echo "========================================"
echo "  📋 下一步操作"
echo "========================================"
echo ""
echo "  1. 运行 start.sh 建立符号链接并拉取配置："
echo "     cd $TARGET_DIR"
echo "     bash claude-config/scripts/bash/start.sh"
echo ""
echo "  2. 配置 LLM API："
echo "     bash claude-config/scripts/bash/initclaude.sh"
echo ""
echo "  3. 安装 MCP 环境（如需要）："
echo "     bash claude-config/scripts/bash/initmcp.sh"
echo ""
