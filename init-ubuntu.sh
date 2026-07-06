#!/bin/bash
# ==============================================
# Ubuntu 环境初始化脚本（合并版）
# 功能：一次性完成所有环境配置
#
# 合并了：
#   - init01git.sh (git/gh + 克隆仓库)
#   - init02claude.sh (Claude Code + API 配置 + Hook)
#   - init03env.sh (Node.js/uv/字体/符号链接/auto-sync)
#   - ppt-master (Python deps + 克隆 hugohe3/ppt-master)
#
# 使用：
#   bash ccconfig/init-ubuntu.sh
#
# 注意：MCP 服务器安装需要在进入 Claude 后手动执行：
#   bash ccconfig/init-mcp.sh
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/conf/ubuntu.json"
CLAUDE_DIR="$HOME/.claude"
LOCAL_BIN="$HOME/.local/bin"

# 动态路径解析（替代硬编码版本号）
source "$SCRIPT_DIR/lib/path-helper.sh"

# 检查配置文件（首次使用时从 .example 复制）
ensure_config "$CONFIG_FILE" "conf/ubuntu.json" || exit 1
ensure_config "$SCRIPT_DIR/conf/llm.json" "conf/llm.json" || exit 1

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

# ========== 读取 git 配置 ==========
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
    CONFIG_DATA=$(read_git_config || echo "|||")
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
        local gh_ver=$(get_gh_version)
        curl -fsSL "https://github.com/cli/cli/releases/download/v${gh_ver}/gh_${gh_ver}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz
        tar -xzf /tmp/gh.tar.gz -C /tmp
        mv /tmp/gh_${gh_ver}_linux_amd64/bin/gh "$LOCAL_BIN/gh"
        chmod +x "$LOCAL_BIN/gh"
        rm -rf /tmp/gh.tar.gz /tmp/gh_${gh_ver}_linux_amd64
        success "gh 已安装"
    else
        success "gh 已安装"
    fi

    # gh 登录（如 SSH 密钥已存在则跳过交互式认证）
    if gh auth status &>/dev/null; then
        success "GitHub 已登录: $(gh api user --jq '.login' 2>/dev/null)"
    elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
        info "gh 未登录，但 SSH 密钥已存在，跳过 gh 认证"
    else
        echo ""
        echo "请在浏览器中授权 GitHub:"
        gh auth login --git-protocol https --skip-ssh-key --hostname github.com
    fi

    # 配置 git credential helper（幂等 — 已配则 no-op，gh 未登录则跳过）
    if gh auth status &>/dev/null; then
        gh auth setup-git >/dev/null 2>&1 || true
        success "git credential helper → gh auth git-credential"
    fi

    # SSH 是推荐的 git 协议，HTTPS→SSH 转换由 setup_ssh_github() 统一处理
    # 不在此处全局强制 HTTPS

    # 克隆/更新仓库
    # 处理 ~ 展开（bash 内置参数展开，不使用 eval 避免命令注入）
    TARGET_DIR="${TARGET_DIR/\~/$HOME}"
    PARENT_DIR=$(dirname "$TARGET_DIR")
    mkdir -p "$PARENT_DIR"

    if [[ -d "$TARGET_DIR/.git" ]]; then
        info "仓库已存在，更新中..."
        local old_commit=$(git -C "$TARGET_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")

        # 先 fetch 远程
        git -C "$TARGET_DIR" fetch origin main 2>/dev/null || true

        # 检查是否有分歧
        local local_commit=$(git -C "$TARGET_DIR" rev-parse --short HEAD)
        local remote_commit=$(git -C "$TARGET_DIR" rev-parse --short origin/main)

        if [[ "$local_commit" == "$remote_commit" ]]; then
            info "已是最新版本: $local_commit"
        else
            # 有分歧，尝试合并
            if git -C "$TARGET_DIR" pull --ff-only origin main 2>&1 | grep -q "Already up to date\|Fast-forward"; then
                local new_commit=$(git -C "$TARGET_DIR" rev-parse --short HEAD)
                success "仓库已更新: $old_commit → $new_commit"
            else
                warn "本地有提交未推送，尝试推送..."
                git -C "$TARGET_DIR" push origin main 2>&1 | tail -2 || true
                local new_commit=$(git -C "$TARGET_DIR" rev-parse --short HEAD)
                info "已同步到: $new_commit"
            fi
        fi
    elif [[ -d "$TARGET_DIR" ]]; then
        warn "目标目录已存在但不是 git 仓库"
    else
        info "克隆仓库: $REPO → $TARGET_DIR"
        # 优先用 SSH，其次 gh
        if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
            git clone "git@github.com:${REPO}.git" "$TARGET_DIR" || {
                error "SSH 克隆失败，尝试 gh..."
                gh repo clone "$REPO" "$TARGET_DIR"
            }
        elif gh repo clone "$REPO" "$TARGET_DIR"; then
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
        local node_ver=$(get_node_version)
        local url="https://nodejs.org/dist/v${node_ver}/node-v${node_ver}-linux-x64.tar.gz"
        info "下载: $url"
        curl -fsSL "$url" -o /tmp/node.tar.gz
        tar -xzf /tmp/node.tar.gz -C "$HOME/.local/"
        mkdir -p "$LOCAL_BIN"
        recreate_node_symlinks "$HOME/.local/node-v${node_ver}-linux-x64/bin"
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

# ========== 4. Claude Code (原生方式) ==========
setup_claude_code() {
    section "Claude Code"

    # 干净的 PATH（避免 WSL 继承污染）
    export PATH="$LOCAL_BIN:$PATH"

    # 检查是否已安装（优先原生安装）
    if command -v claude &>/dev/null; then
        local current_version=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "未知")
        # 检查是否是 npm 版本（符号链接到 node_modules）
        if [[ -L "$(command -v claude)" ]] && [[ "$(readlink -f "$(command -v claude)")" == *"node_modules"* ]]; then
            warn "检测到 npm 版本，切换到原生安装..."
            if claude install --force 2>&1 | tail -5; then
                success "Claude Code 已切换到原生: $(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
            else
                warn "切换失败，保留 npm 版本"
            fi
        else
            success "Claude Code 已安装: $current_version（原生）"
        fi
        return 0
    fi

    warn "Claude Code 未安装，尝试安装..."

    # 方式一：npm 安装 bootstrap（claude.ai 在国内被屏蔽，先用 npm 安装 CLI 主程序）
    local _node_ver=$(get_node_version)
    NPM_GLOBAL_BIN="$HOME/.local/node-v${_node_ver}-linux-x64/bin"
    export PATH="$NPM_GLOBAL_BIN:$LOCAL_BIN:$PATH"
    mkdir -p "$LOCAL_BIN"

    info "安装 Claude Code npm 包（国内可访问）..."
    local _claude_ver=$(get_version "claude_code")
    local _claude_pkg="@anthropic-ai/claude-code"
    [[ -n "$_claude_ver" ]] && _claude_pkg="${_claude_pkg}@${_claude_ver}"
    if ! npm install -g "$_claude_pkg" 2>&1 | tail -3; then
        error "npm 安装失败"
        return 1
    fi

    # 方式二：用 claude install 下载原生二进制（npm 包内置此命令，可在国内下载二进制）
    info "下载 Claude Code 原生二进制..."
    if claude install 2>&1 | tail -5; then
        if command -v claude &>/dev/null; then
            success "Claude Code 原生安装成功: $(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        fi
    else
        warn "原生二进制下载失败（保留 npm 版本）"
        ln -sf "$NPM_GLOBAL_BIN/claude" "$LOCAL_BIN/claude" 2>/dev/null || true
    fi
}

# ========== 5. LLM 配置（调用 llminit.sh） ==========
setup_claude_api() {
    section "LLM 配置"

    if [[ ! -f "$SCRIPT_DIR/init-llm.sh" ]]; then
        error "init-llm.sh 未找到，跳过 LLM 配置"
        return 1
    fi

    # 直接切换到 conf-llm.json 中指定的 current LLM（不交互）
    local current_llm=$(python3 -c "import json; f=open('$SCRIPT_DIR/conf/llm.json'); print(json.load(f).get('current',''))" 2>/dev/null || echo "")

    if [[ -n "$current_llm" ]]; then
        info "配置 LLM: $current_llm"
        bash "$SCRIPT_DIR/init-llm.sh" "$current_llm"
    else
        info "当前无默认 LLM，运行交互式选择..."
        bash "$SCRIPT_DIR/init-llm.sh"
    fi
}


# ========== 5.5 MiniMax CLI（mmx，全模态官方 CLI） ==========
# Token Plan 用户的官方 CLI，覆盖 text/image/video/speech/music/vision/search
# 自动安装 + symlink 到 ~/.local/bin/mmx；认证由用户主动跑 mmx auth login
setup_mmx_cli() {
    section "MiniMax CLI (mmx)"

    local npm_global_bin
    npm_global_bin="$(npm prefix -g 2>/dev/null)/bin"

    if [[ ! -d "$npm_global_bin" ]]; then
        warn "npm 全局目录未找到，跳过 mmx 安装"
        return 0
    fi

    if command -v mmx &>/dev/null; then
        success "mmx CLI 已安装: $(mmx --version 2>/dev/null | head -1)"
    else
        info "安装 mmx CLI..."
        local _mmx_ver=$(get_version "mmx_cli")
        local _mmx_pkg="mmx-cli"
        [[ -n "$_mmx_ver" ]] && _mmx_pkg="${_mmx_pkg}@${_mmx_ver}"
        if ! npm install -g "$_mmx_pkg" 2>&1 | tail -3; then
            warn "mmx CLI 安装失败（可手动重试: npm install -g mmx-cli）"
            return 0
        fi
    fi

    # symlink 到 ~/.local/bin（跟 node/npm/npx/lark-cli 一致，PATH 首位）
    mkdir -p "$LOCAL_BIN"
    if [[ -x "$npm_global_bin/mmx" ]]; then
        ln -sf "$npm_global_bin/mmx" "$LOCAL_BIN/mmx"
    fi

    if command -v mmx &>/dev/null; then
        success "mmx CLI 可用: $(mmx --version 2>/dev/null | head -1)"
        local mmx_ver
        mmx_ver=$(mmx --version 2>/dev/null | awk '{print $2}')
        [[ -n "$mmx_ver" ]] && save_version "mmx_cli" "$mmx_ver"
        info "认证步骤（首次使用必跑）: mmx auth login"
    else
        warn "mmx CLI 装好但 PATH 未生效（请运行: hash -r 或新开终端）"
    fi
}


# ========== 6. GitHub SSH 密钥（多 WSL 共享） ==========
# 策略：
#   - 同机多 WSL：密钥放 Windows 宿主目录 (/mnt/c/Users/<用户名>/.ssh/)，各 WSL 复制到本地
#   - 不同机器：各自生成独立密钥，公钥都加到 github.com/settings/keys
setup_ssh_github() {
    section "GitHub SSH 密钥"

    local SSH_DIR="$HOME/.ssh"
    local WIN_USER
    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "")
    local WIN_SSH_DIR="/mnt/c/Users/${WIN_USER}/.ssh"
    local KEY_NAME="id_ed25519"
    local GITHUB_EMAIL="${CONFIG_EMAIL:-you@example.com}"

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    # === 1. 获取或生成密钥 ===
    if [[ -f "$SSH_DIR/$KEY_NAME" ]]; then
        info "SSH 密钥已存在: $SSH_DIR/$KEY_NAME"
    elif [[ -f "$WIN_SSH_DIR/$KEY_NAME" ]]; then
        info "从 Windows 宿主目录复制密钥..."
        cp "$WIN_SSH_DIR/$KEY_NAME" "$WIN_SSH_DIR/${KEY_NAME}.pub" "$SSH_DIR/"
        chmod 600 "$SSH_DIR/$KEY_NAME"
        chmod 644 "$SSH_DIR/${KEY_NAME}.pub"
        success "SSH 密钥已从 Windows 宿主复制"
    else
        info "生成新的 SSH 密钥..."
        ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$SSH_DIR/$KEY_NAME" -N ""
        chmod 600 "$SSH_DIR/$KEY_NAME"
        chmod 644 "$SSH_DIR/${KEY_NAME}.pub"
        success "SSH 密钥已生成"

        # 同步到 Windows 宿主目录（供同机其他 WSL 共享）
        if mkdir -p "$WIN_SSH_DIR" 2>/dev/null; then
            cp "$SSH_DIR/$KEY_NAME" "$SSH_DIR/${KEY_NAME}.pub" "$WIN_SSH_DIR/" 2>/dev/null || true
            info "已同步到 Windows 宿主目录（供其他 WSL 使用）"
        fi

        # 显示公钥，提示用户添加到 GitHub
        echo ""
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warn "⚠ 请将以下公钥添加到 GitHub："
        warn ""
        echo "   https://github.com/settings/keys"
        warn ""
        cat "$SSH_DIR/${KEY_NAME}.pub"
        warn ""
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        info "添加完成后，SSH 即可免密推送"
    fi

    # === 2. 配置 ~/.ssh/config ===
    if ! grep -q "Host github.com" "$SSH_DIR/config" 2>/dev/null; then
        cat >> "$SSH_DIR/config" << 'SSHEOF'

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
SSHEOF
        chmod 644 "$SSH_DIR/config"
        info "SSH config 已配置 GitHub"
    else
        info "SSH config GitHub 已存在"
    fi

    # === 2.5. 预添加 GitHub 主机密钥（避免首次连接 yes/no 交互） ===
    if ! grep -q "github.com" "$SSH_DIR/known_hosts" 2>/dev/null; then
        ssh-keyscan github.com >> "$SSH_DIR/known_hosts" 2>/dev/null || true
        chmod 644 "$SSH_DIR/known_hosts"
        info "GitHub 主机密钥已添加"
    fi

    # === 3. 扫描 ~/git/ 下所有仓库，HTTPS → SSH ===
    if [[ -d "$HOME/git" ]]; then
        while IFS= read -r -d '' gitdir; do
            local repo_dir=$(dirname "$gitdir")
            local current_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo "")
            if [[ "$current_url" == https://github.com/* ]]; then
                local repo_path="${current_url#https://github.com/}"
                git -C "$repo_dir" remote set-url origin "git@github.com:${repo_path}"
                success "$(basename "$repo_dir"): HTTPS → SSH"
            elif [[ "$current_url" == git@github.com:* ]]; then
                info "$(basename "$repo_dir"): 已是 SSH"
            fi
        done < <(find "$HOME/git" -maxdepth 3 -name .git -type d -print0 2>/dev/null)
    fi

    # === 4. 测试连接 ===
    info "测试 GitHub SSH 连接..."
    if ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | grep -q "successfully authenticated"; then
        success "GitHub SSH 连接成功"

        # SSH 通了，设置全局规则让以后所有 GitHub 仓库自动走 SSH
        if [[ "$(git config --global url.'git@github.com:'.insteadOf 2>/dev/null)" != "https://github.com/" ]]; then
            git config --global url."git@github.com:".insteadOf "https://github.com/"
            success "全局 Git 已配置: HTTPS 自动替换为 SSH"
        fi
    else
        warn "GitHub SSH 连接测试未通过（可能需先添加公钥到 github.com/settings/keys）"
    fi
}

# ========== 8. 符号链接 ==========
setup_symlinks() {
    bash "$SCRIPT_DIR/setup-links.sh"
}

# ========== 9. auto-sync ==========
setup_autosync() {
    section "auto-sync"

    # 安装 inotifywait（免 sudo：从 deb 提取）
    if ! command -v inotifywait &>/dev/null; then
        info "安装 inotify-tools（免 sudo）..."
        local tmp_dir="/tmp/inotify-install-$$"
        mkdir -p "$tmp_dir"

        # 用 subshell 隔离 cd，避免影响外部 cwd
        (
            cd "$tmp_dir" || exit 1
            # 下载并提取主包
            curl -sL "http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools/inotify-tools_3.22.6.0-4_amd64.deb" -o pkg.deb
            dpkg-deb -x pkg.deb . 2>/dev/null

            # 下载并提取依赖库
            curl -sL "http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools/libinotifytools0_3.22.6.0-4_amd64.deb" -o lib.deb
            dpkg-deb -x lib.deb . 2>/dev/null

            # 安装到用户目录
            mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
            cp usr/bin/inotify* "$HOME/.local/bin/"
            chmod +x "$HOME/.local/bin/inotify"*
            cp usr/lib/x86_64-linux-gnu/libinotifytools.so.0 "$HOME/.local/lib/"
        ) || warn "inotify-tools 解包失败"

        rm -rf "$tmp_dir"

        if command -v inotifywait &>/dev/null; then
            success "inotify-tools 安装成功"
        else
            warn "inotify-tools 安装失败"
            warn "auto-sync 将无法工作"
        fi
    fi

    # 启动 auto-sync
    if bash "$SCRIPT_DIR/monitor.sh" start 2>/dev/null; then
        success "auto-sync 已启动"
    else
        warn "auto-sync 已在运行或启动失败"
    fi

    # 启用 auto-sync 自启动
    if bash "$SCRIPT_DIR/init-autostart.sh" enable 2>/dev/null; then
        success "auto-sync 自启动已启用"
    else
        warn "auto-sync 自启动启用失败"
    fi
}

# ========== 11. SessionStart Hook ==========
setup_hook() {
    section "SessionStart Hook"

    # Claude Code 读取 ~/.claude.json，不是 settings.json
    # 所以 hooks 必须写入 ~/.claude.json
    CLAUDE_JSON="$HOME/.claude.json"
    HOOK_CMD="bash $SCRIPT_DIR/status.sh"

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


# ========== 12. CLI 工具 ==========
setup_cli_tools() {
    section "CLI 工具 (bat/glow/nano)"

    # bat (Ubuntu 包名为 bat，命令为 batcat — 避免与 bacula-console-qt 冲突)
    if command -v batcat &>/dev/null; then
        success "bat (batcat) 已安装: $(batcat --version | head -1)"
    elif command -v bat &>/dev/null; then
        success "bat 已安装: $(bat --version | head -1)"
    else
        warn "bat 未安装，正在安装..."
        if sudo apt-get install -y bat; then
            success "bat 安装完成（命令: batcat）"
        else
            warn "bat 安装失败（sudo apt install bat）"
        fi
    fi

    # glow — Markdown 渲染阅读器
    if command -v glow &>/dev/null; then
        success "glow 已安装: $(glow --version)"
    else
        warn "glow 未安装，正在安装..."
        if sudo apt-get install -y glow; then
            success "glow 安装完成: $(glow --version)"
        else
            warn "glow 安装失败（sudo apt install glow）"
        fi
    fi

    # nano — 编辑器（Ubuntu 预装，确认存在）
    if command -v nano &>/dev/null; then
        success "nano 已安装: $(nano --version | head -1)"
    else
        warn "nano 未安装，正在安装..."
        if sudo apt-get install -y nano; then
            success "nano 安装完成"
        else
            warn "nano 安装失败（sudo apt install nano）"
        fi
    fi
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

    # shell 别名同步（cconfig/setup-links.sh 维护符号链接）
    if ! grep -q "shell_aliases.sh" "$HOME/.bashrc" 2>/dev/null; then
        echo '[ -f ~/.claude/shell_aliases.sh ] && source ~/.claude/shell_aliases.sh' >> "$HOME/.bashrc"
    fi

    setup_git_github
    setup_nodejs
    setup_uv
    setup_claude_code
    setup_symlinks
    setup_claude_api
    setup_mmx_cli
    setup_ssh_github
    # 中文字体可选，有需要再手动装: sudo apt-get install fonts-noto-cjk
    setup_autosync
    setup_hook
    setup_cli_tools

    echo ""
    success "初始化完成！"
    echo ""
    echo "CLI 工具（已自动安装）："
    echo "  bat (batcat) — 代码语法高亮   sudo apt install bat"
    echo "  glow         — Markdown 渲染   sudo apt install glow"
    echo "  nano         — 终端编辑器     sudo apt install nano（通常预装）"
    echo ""
    echo "可选组件（按需安装）："
    echo "  bash ccconfig/option-ppt-master/init.sh   # ppt-master (PPT 生成)"
    echo "  bash ccconfig/option-officecli/init.sh   # OfficeCLI（AI-native Office 工具）"
    echo "  bash ccconfig/option-bridge/init.sh      # cc-connect（飞书 Bridge）"
    echo ""
    echo "下一步:"
    echo "  bash ccconfig/init-mcp.sh   # 安装 MCP 服务器"
    echo ""
}

main "$@"
