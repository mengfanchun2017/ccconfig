#!/bin/bash

# ==============================================
# Git + GitHub CLI 环境初始化脚本
# 功能：安装 gh、登录 GitHub、克隆配置仓库
# 配置：从 claude-config/config/initconf.json 读取
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/initconf.json"

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

# -------------------------- 读取配置 --------------------------
read_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "配置文件不存在: $CONFIG_FILE"
        echo ""
        echo "请先创建配置文件："
        echo "  1. 创建目录: mkdir -p claude-config/config"
        echo "  2. 创建配置文件 initconf.json"
        echo "  3. 运行 bash claude-config/scripts/init01git.sh"
        exit 1
    fi

    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        config = json.load(f)
    git = config.get('git', {})
    print(f"{git.get('repo', '')}|{git.get('target_dir', '')}|{git.get('email', '')}|{git.get('username', '')}")
except:
    print("|||")
PYEOF
}

# -------------------------- 检查并安装 git --------------------------
print_info "检查 git..."
if command -v git &> /dev/null; then
    print_success "git 已安装: $(git --version)"
else
    print_error "git 未安装，请先安装: sudo apt install git"
    exit 1
fi

# -------------------------- 检查/配置 Git 用户身份 --------------------------
print_info "检查 Git 用户身份..."
GIT_EMAIL=$(git config --global user.email 2>/dev/null)
GIT_NAME=$(git config --global user.name 2>/dev/null)

# 读取配置
CONFIG_DATA=$(read_config)
IFS='|' read -r REPO TARGET_DIR CONFIG_EMAIL CONFIG_USERNAME <<< "$CONFIG_DATA"

if [[ -z "$GIT_EMAIL" || -z "$GIT_NAME" ]]; then
    print_warning "Git 用户身份不完整"
    if [[ -z "$GIT_EMAIL" ]]; then
        git config --global user.email "$CONFIG_EMAIL"
    fi
    if [[ -z "$GIT_NAME" ]]; then
        git config --global user.name "$CONFIG_USERNAME"
    fi
    print_success "Git 用户身份已配置: $(git config --global user.email) ($(git config --global user.name))"
else
    print_success "Git 用户身份: $GIT_EMAIL ($GIT_NAME)"
fi

# -------------------------- 检查并安装 gh --------------------------
print_info "检查 GitHub CLI (gh)..."

export PATH="$HOME/.local/bin:$PATH"
GH_DIR="$HOME/.local/bin"
GH_VERSION="2.63.2"

if ! command -v gh &> /dev/null; then
    print_warning "gh 未安装，正在下载安装..."
    mkdir -p "$GH_DIR"
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz
    tar -xzf /tmp/gh.tar.gz -C /tmp
    mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh "$GH_DIR/"
    chmod +x "$GH_DIR/gh"
    rm -rf /tmp/gh.tar.gz /tmp/gh_${GH_VERSION}_linux_amd64
    print_success "gh 已安装到 $GH_DIR"
fi

# 确保 PATH 生效
export PATH="$GH_DIR:$PATH"

# -------------------------- 检查/登录 GitHub --------------------------
print_info "检查 GitHub 登录状态..."

if gh auth status &> /dev/null; then
    GH_USER=$(gh api user --jq '.login' 2>/dev/null)
    print_success "已登录 GitHub: $GH_USER"
else
    echo ""
    echo "=========================================="
    echo "  GitHub 登录 (Device Flow)"
    echo "=========================================="
    echo ""
    echo "步骤："
    echo "  1. 下方会显示一个 8 位数代码和网址"
    echo "  2. 在浏览器中打开显示的网址"
    echo "  3. 输入代码并点击授权"
    echo "  4. 授权完成后此脚本会自动继续"
    echo ""

    gh auth login --git-protocol https --skip-ssh-key --hostname github.com

    echo ""
    if gh auth status &> /dev/null; then
        print_success "GitHub 登录成功: $(gh api user --jq '.login')"
    else
        print_error "GitHub 登录失败"
        exit 1
    fi
fi

# -------------------------- 读取仓库配置 --------------------------
CONFIG_DATA=$(read_config)
IFS='|' read -r REPO TARGET_DIR CONFIG_EMAIL CONFIG_USERNAME <<< "$CONFIG_DATA"

# 修正路径中的 ~
TARGET_DIR=$(eval echo "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")

print_info "仓库: $REPO"
print_info "目标目录: $TARGET_DIR"

# -------------------------- 检查/克隆仓库 --------------------------
PARENT_DIR=$(dirname "$TARGET_DIR")
mkdir -p "$PARENT_DIR"

if [[ -d "$TARGET_DIR" ]]; then
    if [[ -d "$TARGET_DIR/.git" ]]; then
        cd "$TARGET_DIR"
        CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')
        EXPECTED_REMOTE="https://github.com/$REPO"

        if [[ "$CURRENT_REMOTE" == "$EXPECTED_REMOTE" ]] || [[ "git@github.com:$REPO" == "$CURRENT_REMOTE" ]]; then
            print_info "检测到已有仓库: $TARGET_DIR"
            print_info "正在更新仓库..."
            if git pull origin main; then
                print_success "仓库更新完成!"
            else
                print_warning "更新失败，请手动检查"
            fi
        else
            print_warning "目标目录已存在，但不是同一个仓库"
            print_info "当前: $CURRENT_REMOTE"
            print_info "期望: $EXPECTED_REMOTE"
            print_info "跳过更新操作"
        fi
    else
        print_warning "目标目录已存在，但不是 git 仓库"
        print_info "跳过更新操作"
    fi
else
    print_info "正在克隆仓库..."
    if gh repo clone "$REPO" "$TARGET_DIR"; then
        print_success "仓库克隆完成!"
    else
        print_error "克隆失败"
        exit 1
    fi
fi

echo ""
print_success "Git + GitHub 环境初始化完成！"
