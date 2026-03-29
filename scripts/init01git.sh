#!/bin/bash

# ==============================================
# Git + GitHub CLI 环境初始化脚本
# 功能：安装 gh、登录 GitHub、克隆配置仓库
# 不包含：Claude Code 安装（由 initclaude.sh 负责）
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

# 简单的 read 函数，用于需要默认值的场景
# 用法: read_input "提示" "默认值"
read_input() {
    local prompt="$1"
    local default="$2"
    echo -n "$prompt"
    read input
    echo "${input:-$default}"
}

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

if [[ -z "$GIT_EMAIL" && -z "$GIT_NAME" ]]; then
    # 两者都没有，完全新配置
    echo ""
    echo "=========================================="
    echo "  请输入 GitHub 注册信息"
    echo "=========================================="
    GIT_EMAIL=$(read_input "邮箱: " "" "60")
    if [[ -n "$GIT_EMAIL" ]]; then
        git config --global user.email "$GIT_EMAIL"
    fi
    GIT_NAME=$(read_input "GitHub 用户名: " "" "60")
    if [[ -n "$GIT_NAME" ]]; then
        git config --global user.name "$GIT_NAME"
    fi
    echo ""
    if [[ -n "$GIT_EMAIL" && -n "$GIT_NAME" ]]; then
        print_success "Git 用户身份已配置: $GIT_EMAIL ($GIT_NAME)"
    fi
elif [[ -z "$GIT_EMAIL" || -z "$GIT_NAME" ]]; then
    # 只有一个有值，提示用户补充
    print_warning "Git 用户身份不完整，正在补充..."
    if [[ -z "$GIT_EMAIL" ]]; then
        GIT_EMAIL=$(read_input "请输入 GitHub 注册邮箱: " "" "60")
        if [[ -n "$GIT_EMAIL" ]]; then
            git config --global user.email "$GIT_EMAIL"
        fi
    fi
    if [[ -z "$GIT_NAME" ]]; then
        GIT_NAME=$(read_input "请输入 GitHub 用户名: " "" "60")
        if [[ -n "$GIT_NAME" ]]; then
            git config --global user.name "$GIT_NAME"
        fi
    fi
    echo ""
    if [[ -n "$GIT_EMAIL" && -n "$GIT_NAME" ]]; then
        print_success "Git 用户身份已配置: $GIT_EMAIL ($GIT_NAME)"
    fi
else
    # 两者都有，显示并询问是否修改
    print_success "Git 用户身份: $GIT_EMAIL ($GIT_NAME)"
    modify=$(read_input "是否修改? [y/N]: " "N" "10")
    if [[ "$modify" =~ ^[Yy]$ ]]; then
        new_email=$(read_input "新邮箱 [留空保持不变]: " "" "30")
        [[ -n "$new_email" ]] && git config --global user.email "$new_email"
        new_name=$(read_input "新用户名 [留空保持不变]: " "" "30")
        [[ -n "$new_name" ]] && git config --global user.name "$new_name"
        GIT_EMAIL=$(git config --global user.email 2>/dev/null)
        GIT_NAME=$(git config --global user.name 2>/dev/null)
        print_success "Git 用户身份已更新: $GIT_EMAIL ($GIT_NAME)"
    fi
fi

# -------------------------- 检查并安装 gh --------------------------
print_info "检查 GitHub CLI (gh)..."

# 先确保 PATH 包含 ~/.local/bin（可能刚写入 .bashrc 但当前会话未加载）
export PATH="$HOME/.local/bin:$PATH"

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

    # 配置 PATH（只有不存在时才添加，避免重复）
    if ! grep -q "\.local/bin" "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    # 立即更新当前会话 PATH，确保安装后能找到 gh
    export PATH="$GH_DIR:$PATH"

    print_success "gh 已安装到 $GH_DIR"
    cd - > /dev/null
    rm -rf "$TMP_DIR"
fi

# 確保 PATH 生效
export PATH="$GH_DIR:$PATH"

# -------------------------- GitHub 登录 --------------------------
print_info "检查 GitHub 登录状态..."
# 先确保 PATH 包含 gh
export PATH="$GH_DIR:$PATH"

auth_result=$(gh auth status 2>&1)
if echo "$auth_result" | grep -q "Logged in to"; then
    print_success "已登录 GitHub: $(gh api user --jq '.login')"
else
    echo ""
    echo "=========================================="
    echo "  GitHub 登录"
    echo "=========================================="
    echo ""
    echo "提示: gh 凭据状态: $(echo "$auth_result" | head -1)"
    echo ""
    echo "操作步骤:"
    echo "  1. 下方会显示一个 8 位代码和网址"
    echo "  2. 在浏览器中打开显示的网址"
    echo "  3. 输入代码并点击授权"
    echo "  4. 授权完成后回到此终端按 Enter 继续"
    echo ""

    echo "启动 GitHub Device Flow 授权..."
    echo ""

    # 运行 gh auth login，它会显示代码和网址
    # --git-protocol https 跳过协议选择
    # BROWSER=true 防止自动打开浏览器
    # 使用 script 创建伪终端以便显示输出
    script -q -c "BROWSER=true gh auth login --git-protocol https --skip-ssh-key --hostname github.com" || true

    echo ""
    echo "提示："
    echo "  如果上方未显示代码，请在浏览器中手动打开:"
    echo "  https://github.com/login/device"
    echo ""
    read_input "完成授权后按 Enter 继续..." "" "120"

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
REPO=$(read_input "GitHub 用户名/仓库名 [默认: <your-github-username>/claude-config]: " "<your-github-username>/claude-config" "30")

# 目标目录
DEFAULT_TARGET="$HOME/git/claude-config"
TARGET_DIR=$(read_input "克隆到目录 [默认: $DEFAULT_TARGET]: " "$DEFAULT_TARGET" "30")

# -------------------------- 检查/克隆仓库 --------------------------
print_info "仓库: $REPO"
print_info "目标: $TARGET_DIR"

# 确保目标目录的父目录存在
PARENT_DIR=$(dirname "$TARGET_DIR")
mkdir -p "$PARENT_DIR"

# 检查目标目录是否已存在
if [[ -d "$TARGET_DIR" ]]; then
    # 目录已存在，检查是否是 git 仓库
    if [[ -d "$TARGET_DIR/.git" ]]; then
        # 是 git 仓库，检查是否是同一个仓库
        cd "$TARGET_DIR"
        CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')
        EXPECTED_REMOTE="https://github.com/$REPO"

        if [[ "$CURRENT_REMOTE" == "$EXPECTED_REMOTE" ]] || [[ "git@github.com:$REPO" == "$CURRENT_REMOTE" ]]; then
            echo ""
            print_info "检测到已有仓库: $TARGET_DIR"
            echo ""
            echo "请选择操作："
            echo "  1) 更新仓库 (git pull) - 拉取最新代码"
            echo "  2) 跳过克隆 - 保持现有状态"
            echo "  3) 退出"
            echo ""
            clone_choice=$(read_input "请输入选项 [1]: " "1" "30")

            if [[ "$clone_choice" == "1" ]]; then
                print_info "正在更新仓库..."
                if git pull origin main; then
                    print_success "仓库更新完成!"
                else
                    print_warning "更新失败，请手动检查"
                fi
            elif [[ "$clone_choice" == "2" ]]; then
                print_info "跳过克隆操作"
            else
                print_info "已退出"
                exit 0
            fi
        else
            # 目录存在但不是同一个仓库
            echo ""
            print_warning "目标目录已存在，但不是同一个仓库"
            echo "  当前仓库: $CURRENT_REMOTE"
            echo "  期望仓库: $EXPECTED_REMOTE"
            echo ""
            echo "请选择操作："
            echo "  1) 删除旧目录并重新克隆"
            echo "  2) 改名克隆到其他目录"
            echo "  3) 退出"
            echo ""
            fix_choice=$(read_input "请输入选项 [2]: " "2" "30")

            if [[ "$fix_choice" == "1" ]]; then
                print_info "删除旧目录..."
                rm -rf "$TARGET_DIR"
            elif [[ "$fix_choice" == "2" ]]; then
                TIMESTAMP=$(date +%Y%m%d%H%M%S)
                NEW_TARGET="${TARGET_DIR}-old-${TIMESTAMP}"
                print_info "将旧目录移动到: $NEW_TARGET"
                mv "$TARGET_DIR" "$NEW_TARGET"
            else
                print_info "已退出"
                exit 0
            fi
        fi
    else
        # 目录存在但不是 git 仓库
        echo ""
        print_warning "目标目录已存在，但不是 git 仓库"
        echo ""
        echo "请选择操作："
        echo "  1) 删除并重新克隆"
        echo "  2) 改名克隆到其他目录"
        echo "  3) 退出"
        echo ""
        fix_choice=$(read_input "请输入选项 [2]: " "2" "30")

        if [[ "$fix_choice" == "1" ]]; then
            rm -rf "$TARGET_DIR"
        elif [[ "$fix_choice" == "2" ]]; then
            TIMESTAMP=$(date +%Y%m%d%H%M%S)
            NEW_TARGET="${TARGET_DIR}-old-${TIMESTAMP}"
            print_info "将旧目录移动到: $NEW_TARGET"
            mv "$TARGET_DIR" "$NEW_TARGET"
        else
            print_info "已退出"
            exit 0
        fi
    fi
fi

# 如果目录不存在，执行克隆
if [[ ! -d "$TARGET_DIR" ]]; then
    print_info "正在克隆仓库..."

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
                choice=$(read_input "请输入 [R]: " "R" "30")
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
fi

# -------------------------- 完成 --------------------------
echo "🎉 Git + GitHub 环境初始化完成！"
echo ""
echo "仓库位置: $TARGET_DIR"
echo ""
echo "========================================"
echo "  📋 下一步操作"
echo "========================================"
echo ""
echo "  1. 安装并配置 Claude Code："
echo "     bash claude-config/scripts/init02claude.sh"
echo ""
