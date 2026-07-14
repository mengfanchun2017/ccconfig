#!/bin/bash
# ==============================================
# Ubuntu 环境初始化脚本（合并版）
# 功能：一次性完成所有环境配置
#
# 合并了：
#   - init01git.sh (git/gh + 克隆仓库)
#   - init02claude.sh (Claude Code + API 配置 + Hook)
#   - init03env.sh (Node.js/uv/字体/符号链接/auto-sync)
#   - OfficeCLI (curl 安装)
#
# 使用：
#   bash ccconfig/init-ubuntu.sh
#
# 注意：MCP 服务器安装需要在进入 Claude 后手动执行：
#   bash ccconfig/init-mcp.sh
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$CCCONFIG_ROOT/conftemp/ubuntu.json"
CLAUDE_DIR="$HOME/.claude"
LOCAL_BIN="$HOME/.local/bin"

# 动态路径解析（替代硬编码版本号）
source "$SCRIPT_DIR/path-helper.sh"

# 检查配置文件（首次使用时从 .example 复制）
ensure_config "$CONFIG_FILE" "conftemp/ubuntu.json" || exit 1
ensure_config "$CCCONFIG_ROOT/conftemp/llm.json" "conftemp/llm.json" || exit 1

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

# ========== 1. ccprivate 私有仓库 clone ==========
# 已由 bin/init-ccprivate.sh 在 Step 3 处理；此处仅做幂等补刀
setup_ccprivate() {
    section "ccprivate 私有仓库"

    export PATH="$LOCAL_BIN:$PATH"

    local CCPRIVATE_DIR="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    # 已 clone → 跳过（bin/init-ccprivate.sh 在 4 步流程 Step 3 已处理）
    if [[ -d "$CCPRIVATE_DIR/.git" ]]; then
        info "ccprivate 已存在，pull 最新"
        git -C "$CCPRIVATE_DIR" pull --ff-only 2>&1 | tail -2 || warn "pull 失败（本地有改动），继续"
        success "ccprivate 已更新"
        return 0
    fi

    # git 必须已装（bootstrap.sh 装）
    if ! command -v git &>/dev/null; then
        error "git 未安装，请先跑 bootstrap.sh"
        exit 1
    fi

    # 从 conf/ubuntu.json 读 GitHub 用户名，推导 ccprivate 仓库名
    local REPO_USERNAME
    REPO_USERNAME=$(python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE') as f:
        d = json.load(f)
    print(d.get('git', {}).get('username', ''))
except: pass
" 2>/dev/null)
    local CCPRIVATE_REPO="${REPO_USERNAME:-$(gh api user --jq '.login' 2>/dev/null || echo '')}/ccprivate"

    if [[ -z "${REPO_USERNAME:-}" ]] || [[ "$CCPRIVATE_REPO" == "/ccprivate" ]]; then
        warn "无法确定 ccprivate 仓库名，跳过 clone"
        warn "  手动: gh repo clone <your-username>/ccprivate $CCPRIVATE_DIR"
        return 0
    fi

    local PARENT_DIR
    PARENT_DIR=$(dirname "$CCPRIVATE_DIR")
    mkdir -p "$PARENT_DIR" 2>/dev/null || { warn "无法创建 $PARENT_DIR，跳过 ccprivate clone"; return 0; }

    info "克隆 ccprivate: $CCPRIVATE_REPO → $CCPRIVATE_DIR"
    if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
        git clone "git@github.com:${CCPRIVATE_REPO}.git" "$CCPRIVATE_DIR" || {
            error "SSH 克隆失败，尝试 gh..."
            gh repo clone "$CCPRIVATE_REPO" "$CCPRIVATE_DIR" 2>/dev/null || warn "gh clone 也失败"
        }
    elif gh auth status &>/dev/null 2>&1; then
        gh repo clone "$CCPRIVATE_REPO" "$CCPRIVATE_DIR" 2>/dev/null || warn "gh clone 失败"
    else
        git clone "https://github.com/${CCPRIVATE_REPO}.git" "$CCPRIVATE_DIR" 2>/dev/null || {
            warn "ccprivate clone 失败"
            warn "  手动: bash bin/init-ccprivate.sh"
            return 0
        }
    fi

    if [[ -d "$CCPRIVATE_DIR/.git" ]]; then
        success "ccprivate 已 clone"
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

    # 确保 node/npm/npx 在 PATH 中
    local node_bin
    node_bin=$(find_node_bin 2>/dev/null || echo "$LOCAL_BIN")
    export PATH="$node_bin:$LOCAL_BIN:$PATH"
    mkdir -p "$LOCAL_BIN"

    info "安装 Claude Code npm 包..."
    local _claude_ver=$(get_version "claude_code")
    local _claude_pkg="@anthropic-ai/claude-code"
    [[ -n "$_claude_ver" ]] && _claude_pkg="${_claude_pkg}@${_claude_ver}"
    if ! npm install -g "$_claude_pkg" 2>&1 | tail -3; then
        error "npm 安装失败"
        return 1
    fi

    # npm install -g 后，从 npm 实际 prefix 拿 claude 路径（不用猜测 node-vXX 目录）
    local npm_bin
    npm_bin="$(npm prefix -g 2>/dev/null)/bin"
    if [[ -x "$npm_bin/claude" ]]; then
        ln -sf "$npm_bin/claude" "$LOCAL_BIN/claude"
        export PATH="$LOCAL_BIN:$PATH"
        info "npm 版本已安装: $(claude --version 2>/dev/null | head -1)"
    fi

    # 方式二：用 claude install 下载原生二进制（npm 包内置此命令）
    if command -v claude &>/dev/null; then
        info "下载 Claude Code 原生二进制..."
        if claude install 2>&1 | tail -5; then
            command -v claude &>/dev/null && success "Claude Code 原生安装成功"
        else
            warn "原生二进制下载失败（保留 npm 版本）"
        fi
    else
        error "Claude Code 安装失败 — npm 和原生均不可用"
        error "  手动: npm install -g @anthropic-ai/claude-code && claude install"
        return 1
    fi
}

# ========== 5. LLM 配置（调用 llminit.sh） ==========
setup_llm_backend() {
    section "LLM 配置"

    if [[ ! -f "$CCCONFIG_ROOT/lib/init-llm.sh" ]]; then
        error "init-llm.sh 未找到，跳过 LLM 配置"
        return 1
    fi

    # 直接切换到 conf-llm.json 中指定的 current LLM（不交互）
    local current_llm=$(python3 -c "import json; f=open('$CCCONFIG_ROOT/conftemp/llm.json'); print(json.load(f).get('current',''))" 2>/dev/null || echo "")

    if [[ -n "$current_llm" ]]; then
        info "配置 LLM: $current_llm"
        bash "$CCCONFIG_ROOT/lib/init-llm.sh" "$current_llm"
    else
        info "当前无默认 LLM，运行交互式选择..."
        bash "$CCCONFIG_ROOT/lib/init-llm.sh"
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
    bash "$SCRIPT_DIR/setup-links.sh" || warn "符号链接/skills 部分失败（首次初始化正常，ccprivate 就绪后重跑即可）"
}

# ========== 9. auto-sync ==========
setup_autosync() {
    section "auto-sync"

    # 安装 inotifywait（apt 优先，失败则免 sudo deb 提取）
    if ! command -v inotifywait &>/dev/null; then
        local installed=false

        # 方式 1：apt（有 sudo 且非 NOSUDO 模式）
        if [[ -z "${BOOTSTRAP_NOSUDO:-}" ]] && command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
            info "安装 inotify-tools（apt）..."
            if sudo apt-get install -y inotify-tools 2>/dev/null; then
                success "inotify-tools (apt) 安装成功"
                installed=true
            fi
        fi

        # 方式 2：免 sudo deb 提取
        if ! $installed; then
            info "安装 inotify-tools（免 sudo deb 提取）..."
            local arch
            arch=$(uname -m 2>/dev/null || echo "x86_64")
            [[ "$arch" == "x86_64" ]] && arch="amd64"
            [[ "$arch" == "aarch64" ]] && arch="arm64"

            local tmp_dir="/tmp/inotify-install-$$"
            mkdir -p "$tmp_dir"

            (
                cd "$tmp_dir" || exit 1
                local base="http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools"
                curl -sL "$base/inotify-tools_3.22.6.0-4_${arch}.deb" -o pkg.deb
                curl -sL "$base/libinotifytools0_3.22.6.0-4_${arch}.deb" -o lib.deb
                dpkg-deb -x pkg.deb . 2>/dev/null
                dpkg-deb -x lib.deb . 2>/dev/null

                mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
                cp usr/bin/inotify* "$HOME/.local/bin/" 2>/dev/null || true
                chmod +x "$HOME/.local/bin/inotify"* 2>/dev/null || true
                # lib 路径按架构来
                local libdir
                libdir=$(find usr/lib -name "libinotifytools.so.0" 2>/dev/null | head -1)
                [[ -n "$libdir" ]] && cp "$libdir" "$HOME/.local/lib/"
            ) || warn "inotify-tools 解包失败"

            rm -rf "$tmp_dir"

            if command -v inotifywait &>/dev/null; then
                success "inotify-tools 安装成功"
                installed=true
            fi
        fi

        if ! $installed; then
            warn "inotify-tools 安装失败"
            warn "  auto-sync 将无法工作"
            warn "  手动: sudo apt install inotify-tools"
        fi
    fi

    # 启动 auto-sync
    if bash "$SCRIPT_DIR/monitor.sh" start 2>/dev/null; then
        success "auto-sync 已启动"
    else
        warn "auto-sync 已在运行或启动失败"
    fi

    # 启用 auto-sync 自启动
    if bash "$CCCONFIG_ROOT/lib/init-autostart.sh" enable 2>/dev/null; then
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

_status_cmd = "$HOOK_CMD"
_existing = config['hooks'].get('SessionStart', [])

# Check if status.sh is already registered
_already = False
for entry in _existing:
    for h in entry.get('hooks', []):
        if h.get('command', '') == _status_cmd:
            _already = True
            break

if _already:
    print("SessionStart hook 已存在，跳过")
else:
    _existing.append({
        "matcher": "",
        "hooks": [{
            "type": "command",
            "command": _status_cmd
        }]
    })
    config['hooks']['SessionStart'] = _existing
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=4)
    print("SessionStart hook 已追加")
PYEOF

    success "SessionStart hook 已配置"
}


# ========== 12. CLI 工具（仅检查，不自动安装） ==========
setup_cli_tools() {
    section "CLI 工具（可选，按需手动安装）"

    local bat_ok=false glow_ok=false nano_ok=false
    command -v batcat &>/dev/null && bat_ok=true
    command -v bat &>/dev/null && bat_ok=true
    command -v glow &>/dev/null && glow_ok=true
    command -v nano &>/dev/null && nano_ok=true

    $bat_ok && info "bat  ✓" || info "bat  ✗ (可选: sudo apt install bat)"
    $glow_ok && info "glow ✓" || info "glow ✗ (可选: sudo apt install glow)"
    $nano_ok && info "nano ✓" || info "nano ✗ (可选: sudo apt install nano)"
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

    setup_ccprivate
    setup_nodejs
    setup_uv
    setup_claude_code
    setup_symlinks
    setup_llm_backend
    setup_mmx_cli
    setup_ssh_github
    # 中文字体可选，有需要再手动装: sudo apt-get install fonts-noto-cjk
    setup_autosync
    setup_hook
    setup_cli_tools

    echo ""
    success "初始化完成！"
    echo ""
    echo -e "  ${BOLD}继续初始化:${NC}"
    echo -e "    全部自动: ${GREEN}bash ccconfig/init.sh all${NC}"
    echo -e "    分步: LLM → MCP → Skills → 验证"
    echo ""
    echo "可选组件（按需手动安装）："
    echo "  bash ccconfig/option-officecli/init.sh    # OfficeCLI"
    echo "  bash ccconfig/option-bridge/init.sh       # 飞书 Bridge"
    echo "  bash ccconfig/option-cloudflare/init.sh   # Cloudflare 插件"
    echo "  sudo apt install bat glow                  # CLI 工具"
    echo ""
}

main "$@"
