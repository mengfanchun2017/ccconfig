#!/bin/bash
# ==============================================
# Ubuntu 环境初始化脚本（合并版）
# 功能：一次性完成所有环境配置
#
# 合并了：
#   - init01git.sh (git/gh + 克隆仓库)
#   - init02claude.sh (Claude Code + API 配置 + Hook)
#   - init03env.sh (Node.js/字体/符号链接/auto-sync)
#   - OfficeCLI (curl 安装)
#
# 使用：
#   bash ccconfig/init-ubuntu.sh
#
# 注意：MCP 服务器安装需要在进入 Claude 后手动执行：
#   bash ccconfig/init-mcp.sh
# ==============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
CLAUDE_DIR="$HOME/.claude"
LOCAL_BIN="$HOME/.local/bin"

# 动态路径解析（resolve_conf 在其中定义，必须优先 source）
source "$SCRIPT_DIR/path-helper.sh"
source "$SCRIPT_DIR/dry-run.sh"

# ubuntu.json 已移除（git config + gh api 替代）
# llm.json 由 init-llm.sh 管理

# 颜色（colors.sh 可选 source，缺失时 fallback）
source "$SCRIPT_DIR/colors.sh"

# libicu 确保（.NET 二进制运行时依赖，officecli/fpptx/fdocx/fxlsx 共用）
source "$SCRIPT_DIR/ensure-libicu.sh"

# ========== 读取 git 配置 ==========
# 从 git config / gh api 读取（不再依赖 ubuntu.json）
read_git_config() {
    local email
    email=$(git config --global user.email 2>/dev/null || echo "")
    local username
    username=$(gh api user --jq '.login' 2>/dev/null || echo "")
    echo "|||${email}|${username}"  # 兼容原格式：repo|target_dir|email|username
}

# ========== 1. ccprivate 私有仓库 clone ==========
# 已由 init-ccprivate-repo.sh 在 Step 3 处理；此处仅做幂等补刀
setup_ccprivate() {
    section "ccprivate 私有仓库"

    export PATH="$LOCAL_BIN:$PATH"

    local CCPRIVATE_DIR="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    # 已 clone → 跳过（init-ccprivate-repo.sh 在 4 步流程 Step 3 已处理）
    if [[ -d "$CCPRIVATE_DIR/.git" ]]; then
        info "ccprivate 已存在，pull 最新"
        git -C "$CCPRIVATE_DIR" pull --ff-only 2>&1 | tail -2 || warn "pull 失败（本地有改动），继续"
        success "ccprivate 已更新"
        return 0
    fi

    # git 必须已装（bootstrap-gh-auth.sh 装）
    if ! command -v git &>/dev/null; then
        error "git 未安装，请先跑 bootstrap-gh-auth.sh"
        exit 1
    fi

    local REPO_USERNAME
    REPO_USERNAME=$(gh api user --jq '.login' 2>/dev/null || echo "")
    local CCPRIVATE_REPO="${REPO_USERNAME}/ccprivate"

    if [[ -z "$REPO_USERNAME" ]] || [[ "$CCPRIVATE_REPO" == "/ccprivate" ]]; then
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
            warn "  手动: bash init-ccprivate-repo.sh"
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
        curl -fsSL --retry 3 --retry-delay 2 "$url" -o /tmp/node.tar.gz || \
            curl -fsSL --retry 3 --retry-delay 2 --http1.1 "$url" -o /tmp/node.tar.gz || {
                error "Node.js 下载失败（网络问题）"
                warn "  重试: bash ccconfig/lib/init-ubuntu.sh"
                warn "  代理: export HTTPS_PROXY=http://127.0.0.1:7890 && bash ccconfig/lib/init-ubuntu.sh"
                return 1
            }
        tar -xzf /tmp/node.tar.gz -C "$HOME/.local/"
        mkdir -p "$LOCAL_BIN"
        recreate_node_symlinks "$HOME/.local/node-v${node_ver}-linux-x64/bin"
        rm -f /tmp/node.tar.gz
        success "Node.js 安装完成: $(node --version)"
    fi
}


# ========== 3.5 Python pip（Ubuntu 24 默认无 pip3） ==========
ensure_pip() {
    section "Python pip"
    if command -v pip3 &>/dev/null || python3 -m pip --version &>/dev/null 2>&1; then
        success "pip 可用: $(pip3 --version 2>/dev/null || python3 -m pip --version 2>/dev/null | head -1)"
        return 0
    fi
    warn "pip3 未安装，尝试安装..."
    if [[ -z "${BOOTSTRAP_NOSUDO:-}" ]] && command -v sudo &>/dev/null; then
        sudo apt-get install -y -qq --no-install-recommends python3-pip &>/dev/null && success "pip3 已安装" && return 0
    fi
    python3 -m ensurepip --user 2>/dev/null && success "pip (ensurepip)" && return 0
    warn "pip 安装失败，Python 包管理功能不可用"
}

# ========== 3.6 Python pip 包（init 时安装，update 时升级） ==========
setup_python_packages() {
    section "Python pip 包"

    local req_file="$CCCONFIG_ROOT/conf/python-requirements.txt"  # 公开文件，不走 resolve_conf

    if [ ! -f "$req_file" ]; then
        info "未找到 $req_file，跳过"
        return 0
    fi

    # 确保 pip3 可用（WSL Ubuntu 默认无 python3-pip）
    if ! command -v pip3 &>/dev/null; then
        if [[ -z "${BOOTSTRAP_NOSUDO:-}" ]] && command -v sudo &>/dev/null; then
            info "安装 python3-pip（apt）..."
            sudo apt-get install -y -qq --no-install-recommends python3-pip &>/dev/null || {
                warn "apt 安装失败，尝试 ensurepip..."
                python3 -m ensurepip --user 2>/dev/null || true
            }
        else
            info "尝试 python3 -m ensurepip..."
            python3 -m ensurepip --user 2>/dev/null || true
        fi
    fi

    if ! command -v pip3 &>/dev/null; then
        warn "pip3 仍不可用，跳过 Python 包安装"
        warn "  手动: sudo apt install python3-pip && pip3 install --user -r $req_file"
        return 0
    fi

        # 优先安装有 apt 包的 Python 库
    info "安装 apt 版 Python 包（python3-xxx）..."
    local apt_pkgs=""
    while IFS= read -r line; do
        # 跳过注释和空行，检查是否有 apt 替代
        local pkg_name
        pkg_name=$(echo "$line" | sed 's/==.*//' | xargs)
        case "$pkg_name" in
            python-docx) apt_pkgs="$apt_pkgs python3-docx" ;;
            # 后续有更多 apt 包的 python 库在这里加
        esac
    done < "$req_file"
    if [ -n "$apt_pkgs" ]; then
        sudo apt-get install -y -qq --no-install-recommends $apt_pkgs 2>/dev/null || {
            warn "apt 安装失败，跳回 pip 安装"
        }
    fi

    # pip 安装剩余包（排除已有 apt 包的）
    info "安装 pip 依赖..."
    local out
    out=$(pip3 install --user -r "$req_file" 2>&1) || true
    if echo "$out" | grep -q "externally-managed-environment"; then
        info "PEP 668 环境，使用 --break-system-packages..."
        out=$(pip3 install --break-system-packages --user -r "$req_file" 2>&1) || {
            warn "部分包安装失败（需手动安装）"
            echo "$out" | tail -5
            return 0
        }
    fi
    success "Python 依赖已安装"
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
        hash -r 2>/dev/null || true
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
    if ! npm install -g "$_claude_pkg" 2>&1 | tail -5; then
        error "npm 安装失败"
        warn "  重试: npm install -g $_claude_pkg"
        warn "  国内网络: 配置 npm 镜像或挂代理"
        warn "  手动: npm install -g @anthropic-ai/claude-code && claude install"
        hash -r 2>/dev/null || true
        return 1
    fi

    # npm install 成功但 node_modules 刷新可能影响 PATH，hash -r 刷新 shell hash
    hash -r 2>/dev/null || true

    # npm install -g 后，找 claude 可执行文件路径
    local claude_src=""
    local npm_bin="$(npm prefix -g 2>/dev/null)/bin"
    if [[ -x "$npm_bin/claude" ]]; then
        claude_src="$npm_bin/claude"
    else
        # 回退：find_node_bin 扫描 node_modules/.bin 等位置
        claude_src="$(find_node_bin claude 2>/dev/null || true)"
    fi
    if [[ -n "$claude_src" ]] && [[ -x "$claude_src" ]]; then
        ln -sf "$claude_src" "$LOCAL_BIN/claude"
        export PATH="$LOCAL_BIN:$PATH"
        info "npm 版本已安装: $(claude --version 2>/dev/null | head -1)"
    else
        warn "claude 可执行文件未找到，尝试 which/find 自动搜索..."
        local found
        found=$(find "$HOME" -maxdepth 5 -name claude -type f -executable 2>/dev/null | head -1)
        if [[ -n "$found" ]]; then
            ln -sf "$found" "$LOCAL_BIN/claude"
            info "claude 已链接: $found"
        else
            warn "claude 未在标准位置找到，运行 claude install 后重试"
        fi
    fi

    # 方式二：用 claude install 下载原生二进制（npm 包内置此命令）
    if command -v claude &>/dev/null; then
        info "下载 Claude Code 原生二进制..."
        if claude install --force 2>&1 | tail -5; then
            success "Claude Code 原生安装成功"
        else
            warn "原生二进制下载失败（保留 npm 版本）"
            warn "  重试: claude install --force"
            warn "  走代理: export HTTPS_PROXY=http://127.0.0.1:7890 && claude install --force"
        fi
    else
        error "Claude Code 安装失败 — npm 和原生均不可用"
        error "  手动: npm install -g @anthropic-ai/claude-code && claude install"
        error "  代理: export HTTPS_PROXY=http://127.0.0.1:7890 && npm install -g @anthropic-ai/claude-code"
        hash -r 2>/dev/null || true
        return 1
    fi
    hash -r 2>/dev/null || true
}

# ========== 5. LLM 配置（调用 llminit.sh） ==========
# init-base.sh all 流程中 LLM 配置是独立步骤（Step 2），此处跳过避免重复
setup_llm_backend() {
    if [[ "${INIT_ALL_FLOW:-}" == "1" ]]; then
        info "LLM 配置由 init.sh Step 2 处理，跳过"
        return 0
    fi

    section "LLM 配置"

    if [[ ! -f "$CCCONFIG_ROOT/lib/init-llm.sh" ]]; then
        error "init-llm.sh 未找到，跳过 LLM 配置"
        return 1
    fi

    # 直接切换到 conf-llm.json 中指定的 current LLM（不交互）
    local llm_conf=$(resolve_conf llm.json) || return 1
    local current_llm=$(python3 -c "import json; f=open('$llm_conf'); print(json.load(f).get('current',''))" 2>/dev/null || echo "")

    if [[ -n "$current_llm" ]]; then
        info "配置 LLM: $current_llm"
        bash "$CCCONFIG_ROOT/lib/init-llm.sh" "$current_llm"
    else
        info "当前无默认 LLM，运行交互式选择..."
        bash "$CCCONFIG_ROOT/lib/init-llm.sh"
    fi
}




# ========== 6. GitHub SSH 密钥（多 WSL 共享） — 可选加速 ==========
# 策略：
#   - gh auth（bootstrap-gh-auth.sh 已做）= 认证主路径，PAT 已够 push/clone
#   - SSH 密钥（本段）= 可选加速，push 更快（2-3s vs 5-15s）
#   - 同机多 WSL：密钥放 Windows 宿主目录，各 WSL 复制到本地
#   - 不同机器：各自生成独立密钥，公钥都加到 github.com/settings/keys
#   - caller 逻辑：gh auth 已配 → 跳过 SSH；gh 未配 → 跑 SSH 作为 fallback
setup_ssh_github() {
    section "GitHub SSH 密钥（可选加速）"

    echo -e "  ${GRAY}PAT 已够用, 这是可选的 push 加速。${NC}"
    echo -e "  ${GRAY}不配 SSH 也能正常 push, 只是慢一点。${NC}"
    echo ""

    local SSH_DIR="$HOME/.ssh"
    local WIN_USER
    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "")
    local WIN_SSH_DIR="/mnt/c/Users/${WIN_USER}/.ssh"
    local KEY_NAME="id_ed25519"
    local GITHUB_EMAIL
    GITHUB_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
    GITHUB_EMAIL="${GITHUB_EMAIL:-you@example.com}"

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    # === 1. 获取或生成密钥 ===
    if [[ -f "$SSH_DIR/$KEY_NAME" ]]; then
        info "SSH 密钥已存在"
    elif [[ -f "$WIN_SSH_DIR/$KEY_NAME" ]]; then
        info "从 Windows 宿主复制密钥..."
        cp "$WIN_SSH_DIR/$KEY_NAME" "$WIN_SSH_DIR/${KEY_NAME}.pub" "$SSH_DIR/"
        chmod 600 "$SSH_DIR/$KEY_NAME"
        chmod 644 "$SSH_DIR/${KEY_NAME}.pub"
        success "SSH 密钥已复制"
    else
        info "生成新的 SSH 密钥..."
        ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$SSH_DIR/$KEY_NAME" -N ""
        chmod 600 "$SSH_DIR/$KEY_NAME"
        chmod 644 "$SSH_DIR/${KEY_NAME}.pub"
        success "SSH 密钥已生成"

        # 同步到 Windows 宿主目录（供同机其他 WSL 共享）
        if mkdir -p "$WIN_SSH_DIR" 2>/dev/null; then
            cp "$SSH_DIR/$KEY_NAME" "$SSH_DIR/${KEY_NAME}.pub" "$WIN_SSH_DIR/" 2>/dev/null || true
        fi
    fi

    # 显示公钥指纹（一行，不占版面）
    local _fp
    _fp=$(ssh-keygen -lf "$SSH_DIR/$KEY_NAME" 2>/dev/null | awk '{print $2}')
    info "公钥指纹: $_fp"

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
    fi

    # === 3. 预添加 GitHub 主机密钥 ===
    if ! grep -q "github.com" "$SSH_DIR/known_hosts" 2>/dev/null; then
        timeout 10 ssh-keyscan github.com >> "$SSH_DIR/known_hosts" 2>/dev/null || true
        chmod 644 "$SSH_DIR/known_hosts"
    fi

    # === 4. 测试连接 ===
    if { ssh -T -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 git@github.com 2>&1 || true; } | grep -q "successfully authenticated"; then
        success "GitHub SSH 连接成功"

        # SSH 通了，扫描仓库转 HTTPS → SSH
        if [[ -d "$HOME/git" ]]; then
            while IFS= read -r -d '' gitdir; do
                local repo_dir=$(dirname "$gitdir")
                local current_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo "")
                if [[ "$current_url" == https://github.com/* ]]; then
                    local repo_path="${current_url#https://github.com/}"
                    git -C "$repo_dir" remote set-url origin "git@github.com:${repo_path}"
                fi
            done < <(find "$HOME/git" -maxdepth 3 -name .git -type d -print0 2>/dev/null)
        fi

        if [[ "$(git config --global url.'git@github.com:'.insteadOf 2>/dev/null)" != "https://github.com/" ]]; then
            git config --global url."git@github.com:".insteadOf "https://github.com/"
        fi
    else
        echo ""
        echo -e "  ${YELLOW}⚠ SSH 连接测试未通过${NC}"
        echo -e "  ${GRAY}公钥需先添加到 GitHub: https://github.com/settings/keys${NC}"
        echo ""
        cat "$SSH_DIR/${KEY_NAME}.pub"
        echo ""
        echo -e "  ${GRAY}添加后验证: ssh -T git@github.com${NC}"
        echo -e "  ${GRAY}然后转换仓库: bash maintain.sh fix${NC}"
    fi
}

# ========== 8. 符号链接 ==========
setup_symlinks() {
    bash "$SCRIPT_DIR/setup-links.sh" || warn "符号链接/skills 部分失败（首次初始化正常，ccprivate 就绪后重跑即可）"
}

# ========== 9. auto-sync ==========
setup_autosync() {
    section "auto-sync"

    # 安装 inotifywait（apt 优先 / 免 sudo deb 提取 — lib/install-inotify.sh）
    source "$SCRIPT_DIR/install-inotify.sh"
    install_inotify || warn "auto-sync 将无法工作 — 手动: sudo apt install inotify-tools"

    # 启动 auto-sync
    if bash "$SCRIPT_DIR/monitor.sh" start 2>/dev/null; then
        success "auto-sync 已启动"
    else
        warn "auto-sync 已在运行或启动失败"
    fi

    # 启用 auto-sync 自启动
    if bash "$CCCONFIG_ROOT/lib/init-autostart.sh" enable; then
        success "auto-sync 自启动已启用"
    else
        warn "auto-sync 自启动启用失败（非致命，可手动: sudo systemctl enable --now claude-auto-sync）"
    fi
}

# ========== 11. SessionStart Hook ==========
setup_hook() {
    section "SessionStart Hook"

    # Claude Code 读取 settings.json（.claude.json 已移除，由 settings.json 统一承载）
    CLAUDE_JSON="$HOME/.claude/settings.json"
    HOOK_CMD="bash \$HOME/git/ccconfig/lib/status.sh"

    python3 << PYEOF
import json
import os

# Claude Code 实际读取的是 settings.json
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


# ========== 12. CLI 工具（已移至 init-option.sh） ==========
setup_cli_tools() {
    # 交给 init-option.sh 统一管理
    true
}

# ========== 主流程 ==========
main() {
    echo "Ubuntu 初始化 - $(date '+%Y-%m-%d')"
    echo ""

    # 确保 ~/.local/bin 在 PATH 中（先写 bashrc，再 export 给当前进程）
    if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$LOCAL_BIN:$PATH"

    # shell 别名同步（cconfig/setup-links.sh 维护符号链接）
    # bashrc 加载行 + symlink 同步到位：claudeby 等 alias 在 step1 即就绪
    if ! grep -q "shell_init.sh" "$HOME/.bashrc" 2>/dev/null; then
        echo '[ -f ~/.claude/shell_init.sh ] && source ~/.claude/shell_init.sh' >> "$HOME/.bashrc"
    fi
    setup_symlinks

    # git 传输：gh auth + credential helper 已就绪则跳过 SSH
    # bootstrap-gh-auth.sh 已配好，SSH 是可选加速（push 2-3s vs 5-15s）
    if gh auth status &>/dev/null 2>&1; then
        info "git: HTTPS + gh credential helper（PAT 已配，SSH 跳过）"
        info "  可选加速: 重跑本脚本 + 设 SETUP_SSH=1 强制配 SSH"
    elif [[ "${SETUP_SSH:-}" == "1" ]]; then
        info "SETUP_SSH=1 强制配 SSH（即使 PAT 已配）"
        setup_ssh_github
    else
        setup_ssh_github
    fi
    setup_ccprivate
    setup_nodejs
    ensure_pip
    setup_python_packages
    ensure_libicu
    setup_claude_code || CLAUDE_CLI_NOT_READY=1

    # ccprivate 私有链接（MEMORY.md, CLAUDE.md, settings.json 等）
    # init-base.sh all 流程中 maintain.sh finalize 统一处理，此处跳过避免重复
    if [[ "${INIT_ALL_FLOW:-}" != "1" ]]; then
        local ccprivate_setup="${CCPRIVATE_HOME:-$HOME/git/ccprivate}/setup.sh"
        if [[ -x "$ccprivate_setup" ]]; then
            section "ccprivate 私有链接"
            if bash "$ccprivate_setup" 2>/dev/null; then
                success "ccprivate 链接已建立"
            else
                warn "ccprivate 链接部分失败（首次初始化正常，后续会自愈）"
            fi
        else
            info "ccprivate/setup.sh 不可执行，跳过私有链接（ccprivate 就绪后重跑 init-ubuntu.sh）"
        fi
    fi

    setup_llm_backend
    # 中文字体可选，有需要再手动装: sudo apt-get install fonts-noto-cjk
    setup_autosync
    setup_hook
    setup_cli_tools

    echo ""
    success "初始化完成！"
    echo ""

    if [[ "${INIT_ALL_FLOW:-}" != "1" ]]; then
        echo -e "  ${BOLD}继续初始化:${NC}"
        echo -e "    全部自动: ${GREEN}bash ccconfig/init-base.sh all${NC}"
        echo -e "    分步: LLM → MCP → Skills → 验证"
        echo ""
    fi

    echo "可选组件（按需: bash ccconfig/init-option.sh）："
    echo "  bat/glow/nano    # CLI 工具"
    echo "  OfficeCLI        # 命令行 Office 文档创建"
    echo "  Bridge           # 飞书集成"
    echo "  Cloudflare       # Workers/R2/D1 开发"
    echo "  Remote           # SSH + Tailscale 远程连接"
    echo ""
}

# TEST_MODE=1 时 source 不执行 main（供单元测试加载函数）
[[ "${TEST_MODE:-0}" == "1" ]] || main "$@"
