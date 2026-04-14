#!/bin/bash
# ==============================================
# Ubuntu 环境初始化脚本（合并版）
# 功能：一次性完成所有环境配置
#
# 合并了：
#   - init01git.sh (git/gh + 克隆仓库)
#   - init02claude.sh (Claude Code + API 配置 + Hook)
#   - init03env.sh (Node.js/uv/字体/符号链接/auto-sync)
#
# 使用：
#   bash ccconfig/ubuntuinit.sh
#
# 注意：MCP 服务器安装需要在进入 Claude 后手动执行：
#   bash ccconfig/claudeinit.sh
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/conf-ubuntu.json"
CLAUDE_DIR="$HOME/.claude"
LOCAL_BIN="$HOME/.local/bin"

# 版本
NODE_VERSION="20.11.0"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# ========== 读取配置 ==========
read_git_config() {
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

read_api_config() {
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        config = json.load(f)
    api = config.get('api', {})
    print(f"{api.get('base_url', '')}|{api.get('model', '')}|{api.get('key', '')}")
except:
    print("|||")
PYEOF
}

# ========== 1. Git + GitHub ==========
setup_git_github() {
    section "Git + GitHub"

    # git 检查
    info "检查 git..."
    if ! command -v git &>/dev/null; then
        error "git 未安装，请先: sudo apt install git"
        exit 1
    fi
    success "git 已安装: $(git --version | cut -d' ' -f3)"

    # Git 用户身份
    info "检查 Git 用户身份..."
    CONFIG_DATA=$(read_git_config || "|||")
    IFS='|' read -r REPO TARGET_DIR CONFIG_EMAIL CONFIG_USERNAME <<< "$CONFIG_DATA"

    if [[ -n "$CONFIG_EMAIL" ]]; then
        git config --global user.email "$CONFIG_EMAIL" 2>/dev/null || true
    fi
    if [[ -n "$CONFIG_USERNAME" ]]; then
        git config --global user.name "$CONFIG_USERNAME" 2>/dev/null || true
    fi
    success "Git 用户: $(git config --global user.email) ($(git config --global user.name))"

    # gh 安装
    info "检查 GitHub CLI (gh)..."
    export PATH="$LOCAL_BIN:$PATH"
    if ! command -v gh &>/dev/null; then
        warn "gh 未安装，正在下载..."
        mkdir -p "$LOCAL_BIN"
        GH_VERSION="2.63.2"
        curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz
        tar -xzf /tmp/gh.tar.gz -C /tmp
        mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh "$LOCAL_BIN/gh"
        chmod +x "$LOCAL_BIN/gh"
        rm -rf /tmp/gh.tar.gz /tmp/gh_${GH_VERSION}_linux_amd64
        success "gh 已安装"
    else
        success "gh 已安装"
    fi

    # gh 登录
    if gh auth status &>/dev/null; then
        success "GitHub 已登录: $(gh api user --jq '.login' 2>/dev/null)"
    else
        echo ""
        echo "请在浏览器中授权 GitHub:"
        gh auth login --git-protocol https --skip-ssh-key --hostname github.com
    fi

    # 克隆/更新仓库
    TARGET_DIR=$(eval echo "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")
    PARENT_DIR=$(dirname "$TARGET_DIR")
    mkdir -p "$PARENT_DIR"

    if [[ -d "$TARGET_DIR/.git" ]]; then
        cd "$TARGET_DIR"
        info "仓库已存在，更新中..."
        git pull origin main 2>/dev/null && success "仓库已更新" || warn "更新失败"
    elif [[ -d "$TARGET_DIR" ]]; then
        warn "目标目录已存在但不是 git 仓库"
    else
        info "克隆仓库: $REPO → $TARGET_DIR"
        if gh repo clone "$REPO" "$TARGET_DIR"; then
            success "仓库克隆完成"
        else
            error "克隆失败"
            exit 1
        fi
    fi
}

# ========== 2. Node.js ==========
setup_nodejs() {
    section "Node.js"

    export PATH="$LOCAL_BIN:$PATH"

    if command -v node &>/dev/null; then
        success "Node.js 已安装: $(node --version)"
        info "npm: $(npm --version)"
    else
        warn "Node.js 未安装，正在安装..."
        local url="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz"
        info "下载: $url"
        curl -fsSL "$url" -o /tmp/node.tar.gz
        tar -xzf /tmp/node.tar.gz -C "$HOME/.local/"
        mkdir -p "$LOCAL_BIN"
        ln -sf "$HOME/.local/node-v${NODE_VERSION}-linux-x64/bin/node" "$LOCAL_BIN/node"
        ln -sf "$HOME/.local/node-v${NODE_VERSION}-linux-x64/bin/npm" "$LOCAL_BIN/npm"
        ln -sf "$HOME/.local/node-v${NODE_VERSION}-linux-x64/bin/npx" "$LOCAL_BIN/npx"
        rm -f /tmp/node.tar.gz
        success "Node.js 安装完成: $(node --version)"
    fi
}

# ========== 3. uv ==========
setup_uv() {
    section "uv (Python)"

    export PATH="$LOCAL_BIN:$PATH"

    if command -v uv &>/dev/null || command -v uvx &>/dev/null; then
        success "uv 已安装: $(uv --version 2>/dev/null || uvx --version 2>/dev/null)"
    else
        warn "uv 未安装，正在安装..."
        if curl -LsSf https://astral.sh/uv/install.sh | sh; then
            success "uv 安装完成"
        else
            warn "uv 安装失败（不影响 MCP 使用）"
        fi
    fi
}

# ========== 4. Claude Code (npm 方式) ==========
setup_claude_code() {
    section "Claude Code"

    # PATH 必须包含 ~/.local/bin
    export PATH="$LOCAL_BIN:$PATH"

    if command -v claude &>/dev/null; then
        success "Claude Code 已安装: $(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "未知")"
        return 0
    fi

    warn "Claude Code 未安装"

    # 优先 npm 安装（比官方脚本更可靠，不受地区限制）
    info "使用 npm 安装 Claude Code..."
    if npm install -g @anthropic-ai/claude-code 2>&1; then
        success "Claude Code 安装成功!"

        # 验证
        if command -v claude &>/dev/null; then
            info "版本: $(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        fi
    else
        error "npm 安装失败"
        exit 1
    fi
}

# ========== 5. Claude API 配置 ==========
setup_claude_api() {
    section "Claude API 配置"

    mkdir -p "$CLAUDE_DIR"

    API_CONFIG=$(read_api_config)
    IFS='|' read -r BASE_URL MODEL_NAME API_KEY <<< "$API_CONFIG"

    info "API: $BASE_URL"
    info "模型: $MODEL_NAME"

    # Claude Code 读取 ~/.claude.json，不是 settings.json
    # 所以配置必须写入 ~/.claude.json
    CLAUDE_JSON="$HOME/.claude.json"

    python3 << PYEOF
import json
import os

# Claude Code 实际读取的是 ~/.claude.json
config_file = os.path.expanduser("$CLAUDE_JSON")
try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except:
    config = {}

if 'env' not in config:
    config['env'] = {}

config['env'].update({
    "ANTHROPIC_BASE_URL": "$BASE_URL",
    "ANTHROPIC_AUTH_TOKEN": "$API_KEY",
    "ANTHROPIC_MODEL": "$MODEL_NAME",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
})

with open(config_file, 'w') as f:
    json.dump(config, f, indent=4)
print("API 配置已写入 ~/.claude.json")
PYEOF

    success "API 配置完成"
}


# ========== 7. 中文字体 ==========
setup_fonts() {
    section "中文字体"

    # 检查是否已有中文字体
    if fc-list :lang=zh 2>/dev/null | grep -q .; then
        info "中文字体已安装"
        return 0
    fi

    # sudo 安装
    info "安装 fonts-wqy-microhei..."
    if sudo apt-get install -y fonts-wqy-microhei fontconfig; then
        success "字体安装成功"
        fc-cache -f 2>/dev/null
    else
        warn "字体安装失败"
    fi
}

# ========== 8. 符号链接 ==========
setup_symlinks() {
    section "符号链接"

    cd "$SCRIPT_DIR"

    setup_link() {
        local link="$1"
        local target="$2"
        local name="$3"

        mkdir -p "$(dirname "$link")"
        if [[ -L "$link" ]]; then
            local existing=$(readlink -f "$link")
            local expected=$(readlink -f "$target" 2>/dev/null)
            if [[ "$existing" = "$expected" ]]; then
                info "$name: 已链接，跳过"
                return 0
            fi
            rm -f "$link"
        elif [[ -e "$link" ]]; then
            rm -f "$link"
        fi
        ln -sf "$target" "$link"
        success "$name: 已链接"
    }

    setup_link "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/link/settings.json" "settings.json"
    setup_link "$CLAUDE_DIR/.config.json" "$SCRIPT_DIR/link/.config.json" ".config.json"
    setup_link "$HOME/CLAUDE.md" "$SCRIPT_DIR/link/CLAUDE.md" "CLAUDE.md"

    # MEMORY.md
    REPO_MEMORY_NAME="$(echo "$SCRIPT_DIR" | sed 's/\//-/g' | sed 's/^-//')"
    MEMORY_DIR="$CLAUDE_DIR/projects/$REPO_MEMORY_NAME/memory"
    MEMORY_REPO_PATH="$SCRIPT_DIR/link/$REPO_MEMORY_NAME/MEMORY.md"

    if [[ -d "$SCRIPT_DIR/link/$REPO_MEMORY_NAME" ]]; then
        mkdir -p "$MEMORY_DIR"
        setup_link "$MEMORY_DIR/MEMORY.md" "$MEMORY_REPO_PATH" "MEMORY.md"
    fi
}

# ========== 9. auto-sync ==========
setup_autosync() {
    section "auto-sync"

    # 安装 inotifywait
    if ! command -v inotifywait &>/dev/null; then
        info "安装 inotify-tools..."
        if sudo apt-get install -y inotify-tools; then
            success "inotify-tools 安装成功"
        else
            warn "inotify-tools 安装失败，auto-sync 可能无法工作"
        fi
    fi

    # 启动 auto-sync
    if bash "$SCRIPT_DIR/init-auto-sync.sh" start 2>/dev/null; then
        success "auto-sync 已启动"
    else
        warn "auto-sync 已在运行或启动失败"
    fi

    # 启用 auto-sync 自启动
    if bash "$SCRIPT_DIR/init-enable-autostart.sh" enable 2>/dev/null; then
        success "auto-sync 自启动已启用"
    else
        warn "auto-sync 自启动启用失败"
    fi
}

# ========== 10. SessionStart Hook ==========
setup_hook() {
    section "SessionStart Hook"

    # Claude Code 读取 ~/.claude.json，不是 settings.json
    # 所以 hooks 必须写入 ~/.claude.json
    CLAUDE_JSON="$HOME/.claude.json"
    HOOK_CMD="bash $SCRIPT_DIR/hook-status.sh"

    python3 << PYEOF
import json
import os

# Claude Code 实际读取的是 ~/.claude.json
config_file = os.path.expanduser("$CLAUDE_JSON")
try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except:
    config = {}

if 'hooks' not in config:
    config['hooks'] = {}

config['hooks']['SessionStart'] = [{
    "matcher": "",
    "hooks": [{
        "type": "command",
        "command": "$HOOK_CMD"
    }]
}]

with open(config_file, 'w') as f:
    json.dump(config, f, indent=4)
print("Hook 已写入 ~/.claude.json")
PYEOF

    success "SessionStart hook 已配置"
}

# ========== 主流程 ==========
main() {
    echo "Ubuntu 初始化 - $(date '+%Y-%m-%d')"
    echo ""

    # 确保 ~/.local/bin 在 PATH 中
    export PATH="$LOCAL_BIN:$PATH"
    if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    setup_git_github
    setup_nodejs
    setup_uv
    setup_claude_code
    setup_claude_api
    setup_fonts
    setup_symlinks
    setup_autosync
    setup_hook

    echo ""
    success "初始化完成！"
    echo ""
    echo "下一步（在 Claude 中执行）:"
    echo "  bash ccconfig/claudeinit.sh"
    echo ""
}

main "$@"
