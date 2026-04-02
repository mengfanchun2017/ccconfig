#!/bin/bash
# Claude Code 环境准备脚本
# 用途：安装运行时环境依赖 + 建立符号链接
#
# 使用方法：
#   bash ccconfig/init03env.sh
#
# 此脚本会：
#   1. 安装 MCP 服务器所需的运行时环境
#      - Node.js (用于 npm/npx-based MCP 服务器)
#      - uv (用于 Python-based MCP 服务器)
#      - Playwright (浏览器自动化)
#      - 中文字体
#   2. 建立符号链接实现配置双向同步
#      - link/settings.json → ~/.claude/settings.json
#      - link/CLAUDE.md → ~/CLAUDE.md
#      - link/-home-francis-git/MEMORY.md → ~/.claude/projects/.../memory/MEMORY.md
#
# 安装完成后，请运行 claudeinit.sh 安装具体的 MCP 服务器：
#   bash ccconfig/claudeinit.sh

set -e

# 版本
NODE_VERSION="20.11.0"
UV_VERSION="0.10.12"

# 目录
LOCAL_DIR="$HOME/.local"
BIN_DIR="${LOCAL_DIR}/bin"
NODE_DIR="${LOCAL_DIR}/node-v${NODE_VERSION}-linux-x64"
UV_DIR="${LOCAL_DIR}/uv-${UV_VERSION}-x86_64-unknown-linux-gnu"
TARBALL="/tmp/node.tar.gz"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
good() { echo -e "${GREEN}[ OK ]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
section() { echo -e "${CYAN}=== $1 ===${NC}"; }

# 简单的 read 函数，用于需要默认值的场景
read_input() {
    local prompt="$1"
    local default="$2"
    local input=""
    read -p "$prompt" input
    echo "${input:-$default}"
}

# 检查命令是否存在
check_command() {
    command -v "$1" &> /dev/null
}

# ========== Node.js ==========
check_node_installed() {
    if check_command node; then
        local current_version=$(node --version 2>/dev/null || echo "unknown")
        info "Node.js 已安装: $current_version"
        return 0
    fi
    return 1
}

install_nodejs() {
    section "安装 Node.js"

    local url="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz"
    info "下载 Node.js v${NODE_VERSION}..."
    info "URL: $url"

    if ! curl -fsSL "$url" -o "$TARBALL"; then
        error "Node.js 下载失败"
        return 1
    fi
    info "下载完成"

    info "解压到 ~/.local/..."
    tar -xzf "$TARBALL" -C "$LOCAL_DIR/"

    mkdir -p "$BIN_DIR"

    info "创建符号链接..."
    ln -sf "${NODE_DIR}/bin/node" "${BIN_DIR}/node"
    ln -sf "${NODE_DIR}/bin/npm" "${BIN_DIR}/npm"
    ln -sf "${NODE_DIR}/bin/npx" "${BIN_DIR}/npx"

    rm -f "$TARBALL"
    info "Node.js 安装完成"
}

verify_nodejs() {
    echo ""
    info "Node.js 验证:"
    echo "  node: $(node --version)"
    echo "  npm:  $(npm --version)"
    echo "  npx:  $(npx --version 2>/dev/null || echo 'not found')"
    echo ""
}

setup_path() {
    # 确保 ~/.local/bin 在 PATH 中
    local local_bin="$HOME/.local/bin"
    if [[ ":$PATH:" != *":$local_bin:"* ]]; then
        info "添加 $local_bin 到 PATH..."
        if ! grep -q "\.local/bin" "$HOME/.bashrc" 2>/dev/null; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        fi
        export PATH="$local_bin:$PATH"
        good "PATH 已更新"
    else
        info "PATH 已包含 $local_bin"
    fi
}

# ========== Sudo NOPASSWD 配置 ==========
configure_sudo_nopasswd() {
    section "配置 sudo 免密 (apt-get)"

    # 检查是否已有 apt-get 的 NOPASSWD 配置
    if sudo -n apt-get --version >/dev/null 2>&1; then
        info "sudo apt-get 已可免密使用，跳过"
        return 0
    fi

    local sudoers_file="/etc/sudoers.d/wsl-apt"
    local config="francis ALL=(ALL) NOPASSWD: /usr/bin/apt-get"

    # 检查文件是否已存在且配置正确
    if [[ -f "$sudoers_file" ]] && grep -q "NOPASSWD.*apt-get" "$sudoers_file" 2>/dev/null; then
        info "sudoers 配置已存在，跳过"
        return 0
    fi

    info "配置 sudoers 免密 (仅 apt-get)..."
    echo "$config" | sudo tee "$sudoers_file" >/dev/null 2>&1
    sudo chmod 440 "$sudoers_file" 2>/dev/null

    if sudo -n apt-get --version >/dev/null 2>&1; then
        good "sudo apt-get 免密配置成功"
    else
        warn "sudo 免密配置失败"
    fi
}

# ========== uv (Python 包管理器) ==========
check_uv_installed() {
    if check_command uvx || check_command uv; then
        local version=$(uvx --version 2>/dev/null || uv --version 2>/dev/null || echo "unknown")
        info "uv 已安装: $version"
        return 0
    fi
    return 1
}

install_uv() {
    section "安装 uv"

    info "使用官方安装脚本安装 uv..."
    if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
        error "uv 安装失败"
        return 1
    fi

    info "uv 安装完成"
}

verify_uv() {
    echo ""
    info "uv 验证:"
    echo "  uv:  $(uv --version)"
    echo "  uvx: $(uvx --version)"
    echo ""
}

# ========== Playwright 浏览器 ==========
check_playwright_installed() {
    if check_command npx; then
        # 使用 timeout 避免 npx 长时间卡住（最多 10 秒）
        local version=$(timeout 10 npx playwright --version 2>/dev/null || echo "")
        if [[ -n "$version" ]]; then
            info "Playwright 已安装: $version"
            return 0
        fi
    fi
    return 1
}

install_playwright_browsers() {
    section "安装 Playwright 浏览器"

    if ! check_command npx; then
        error "npx 未安装，请先安装 Node.js"
        return 1
    fi

    info "安装 Playwright chromium (官方推荐)..."

    # 先在临时目录安装 playwright（避免项目目录未初始化导致的警告）
    local tmp_dir="/tmp/pw-install-$$"
    mkdir -p "$tmp_dir"
    cd "$tmp_dir"
    npm init -y > /dev/null 2>&1
    npm install playwright > /dev/null 2>&1

    # 使用临时目录的 playwright 安装 chromium，添加超时
    # 如果下载失败会重试3次，每次超时2分钟
    local max_attempts=3
    local attempt=1
    local success=false

    while [[ $attempt -le $max_attempts ]] && [[ "$success" == "false" ]]; do
        echo ""
        info "尝试 $attempt/$max_attempts..."

        # 设置超时 120 秒，如果超时或失败则重试
        if timeout 180 ./node_modules/.bin/playwright install chromium 2>&1; then
            success=true
            good "Chromium 安装成功"
        else
            if [[ $attempt -lt $max_attempts ]]; then
                warn "下载失败，10秒后重试..."
                sleep 10
            fi
            attempt=$((attempt + 1))
        fi
    done

    if [[ "$success" == "false" ]]; then
        warn "Chromium 下载失败，将跳过安装"
        warn "可以稍后手动运行: npx playwright install chromium"
    fi

    # 清理临时目录
    cd - > /dev/null
    rm -rf "$tmp_dir"
}

# ========== Playwright 系统依赖 ==========

# 获取 Playwright 在当前 Ubuntu 版本所需的依赖包列表
# Ubuntu 24.04 使用 t64 后缀的包名
get_playwright_deps() {
    local version=$(lsb_release -rs 2>/dev/null || echo "22.04")
    if [[ "$version" == "24.04" ]]; then
        # Ubuntu 24.04 (Noble) 使用 t64 后缀的包
        echo "libnspr4 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2t64"
    else
        # Ubuntu 22.04 及更早版本使用旧包名
        echo "libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2"
    fi
}

install_playwright_deps() {
    section "安装 Playwright 系统依赖"

    # 检查依赖是否已存在（检查关键库）
    if ldconfig -p 2>/dev/null | grep -q libnspr4.so && \
       ldconfig -p 2>/dev/null | grep -q libasound.so.2; then
        info "Playwright 系统依赖已存在，跳过"
        return 0
    fi

    if ! command -v apt-get &>/dev/null; then
        warn "未检测到 apt-get，无法安装系统依赖"
        return 0
    fi

    local deps=$(get_playwright_deps)
    info "检测到 Ubuntu 版本: $(lsb_release -rs 2>/dev/null || echo 'unknown')"
    info "将安装依赖: $deps"

    # 先尝试 sudo -n（无交互式，适合已配置 NOPASSWD 的环境）
    if echo "$deps" | xargs sudo -n apt-get install -y 2>/dev/null; then
        good "系统依赖安装成功（sudo -n）"
        return 0
    fi

    # sudo -n 失败，尝试 playwright install-deps（它会自己处理依赖）
    info "尝试 playwright install-deps..."
    local tmp_dir="/tmp/pw-install-deps-$$"
    mkdir -p "$tmp_dir"
    cd "$tmp_dir"
    npm init -y > /dev/null 2>&1
    npm install playwright > /dev/null 2>&1

    # 先运行命令，捕获退出码
    set +e
    timeout 180 ./node_modules/.bin/playwright install-deps chromium > /tmp/pw-deps-install.log 2>&1
    local pw_exit=$?
    set -e

    if [[ $pw_exit -eq 0 ]]; then
        good "系统依赖安装成功（playwright install-deps）"
        cd - > /dev/null
        rm -rf "$tmp_dir"
        return 0
    fi

    warn "playwright install-deps 失败，日志:"
    cat /tmp/pw-deps-install.log | sed 's/^/  /'
    cd - > /dev/null
    rm -rf "$tmp_dir"

    # playwright install-deps 也失败了，尝试直接 apt-get 安装
    warn "自动安装失败，将尝试手动 apt-get 安装..."
    echo ""
    echo "请输入密码以安装系统依赖:"
    echo "  sudo apt-get update && sudo apt-get install -y $deps"
    echo ""

    if sudo apt-get update && sudo apt-get install -y $deps; then
        good "系统依赖安装成功"
        return 0
    fi

    warn "系统依赖安装失败，浏览器可能无法运行"
    warn "请稍后手动运行: sudo apt-get install -y $deps"
    return 1
}

# ========== Playwright MCP 配置修复 ==========
configure_playwright_mcp() {
    section "配置 Playwright MCP"

    local claude_json="$HOME/.claude.json"
    if [[ ! -f "$claude_json" ]]; then
        warn "~/.claude.json 不存在，跳过 MCP 配置"
        return 0
    fi

    # 检查当前配置是否正确
    # 问题：MCP 默认使用 channel='chrome'，在 Linux 上指向 /opt/google/chrome/chrome
    # 解决：使用 'chromium' channel，让 playwright 使用自己安装的浏览器
    local result=$(python3 << 'PYEOF'
import json
import os
import sys

file = os.path.expanduser("~/.claude.json")
browser_path = os.path.expanduser("~/.cache/ms-playwright")

try:
    with open(file, 'r') as f:
        data = json.load(f)

    mcp = data.get('mcpServers', {})
    pw = mcp.get('playwright', {})

    # 检查是否需要更新
    args = pw.get('args', [])
    env = pw.get('env', {})

    needs_update = False

    # 1. 确保 env 中有 PLAYWRIGHT_BROWSERS_PATH
    if env.get('PLAYWRIGHT_BROWSERS_PATH') != browser_path:
        env['PLAYWRIGHT_BROWSERS_PATH'] = browser_path
        needs_update = True

    # 2. 检查 args 中是否已经有 --browser chrome 参数
    if any('@playwright/mcp' in str(a) for a in args):
        has_browser_arg = any('--browser' in str(a) for a in args)
        if not has_browser_arg:
            # 在 @playwright/mcp 后添加 --browser chrome
            # 注意：@playwright/mcp 只支持 chrome/firefox/webkit/msedge，不支持 chromium
            new_args = []
            for a in args:
                new_args.append(a)
                if '@playwright/mcp' in str(a):
                    new_args.append('--browser')
                    new_args.append('chrome')
            args = new_args
            needs_update = True

    if not needs_update:
        print("MCP_CONFIG_OK")
        sys.exit(0)

    # 更新配置
    pw['args'] = args
    pw['env'] = env
    mcp['playwright'] = pw
    data['mcpServers'] = mcp

    with open(file, 'w') as f:
        json.dump(data, f, indent=4)

    print("MCP_CONFIG_UPDATED")
    sys.exit(0)
except Exception as e:
    print(f"MCP_CONFIG_ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)

    if [[ "$result" == "MCP_CONFIG_OK" ]]; then
        info "MCP 配置已正确，跳过"
    elif [[ "$result" == "MCP_CONFIG_UPDATED" ]]; then
        good "MCP 配置已更新：使用 chrome channel + PLAYWRIGHT_BROWSERS_PATH"
    else
        warn "MCP 配置检查失败: $result"
    fi
}

verify_playwright() {
    echo ""
    info "Playwright 验证:"
    if check_command npx; then
        echo "  npx playwright: $(timeout 10 npx playwright --version 2>/dev/null || echo '未安装')"
        echo "  浏览器缓存: $(ls ~/.cache/ms-playwright/ 2>/dev/null | wc -l) 个"
        echo "  libnspr4.so: $(ldconfig -p 2>/dev/null | grep -q libnspr4.so && echo '已找到' || echo '未找到')"
    fi
    echo ""
}

# ========== 中文字体 ==========
check_chinese_fonts() {
    if fc-list :lang=zh 2>/dev/null | grep -q .; then
        info "中文字体已安装"
        return 0
    fi
    return 1
}

install_chinese_fonts() {
    section "安装中文字体"

    # 优先使用用户级字体安装（无需 sudo）
    USER_FONTS_DIR="$HOME/.local/share/fonts"
    FONT_URL="https://github.com/anthtype/wqy/raw/main/fonts/wqy-microhei.ttc"

    mkdir -p "$USER_FONTS_DIR"

    if command -v apt-get &>/dev/null; then
        local fonts_pkg="fonts-wqy-microhei"

        # 1. 先尝试用户级安装（下载字体到用户目录）
        if command -v curl &>/dev/null; then
            info "尝试用户级安装中文字体（无需 sudo）..."
            if curl -fsSL "$FONT_URL" -o "$USER_FONTS_DIR/wqy-microhei.ttc" 2>/dev/null; then
                if fc-cache -f "$USER_FONTS_DIR" 2>/dev/null; then
                    good "字体已安装到 $USER_FONTS_DIR"
                    return 0
                else
                    warn "fc-cache 失败，但字体文件已下载"
                    return 0
                fi
            else
                warn "用户级下载失败"
            fi
        fi

        # 2. 尝试 sudo -n（非交互模式，免密）
        info "尝试免密 sudo 安装..."
        if sudo -n apt-get install -y $fonts_pkg fontconfig 2>/dev/null; then
            good "系统字体安装成功"
            fc-cache -f 2>/dev/null
            return 0
        fi

        # 3. 都失败了，提示用户手动输入密码安装
        warn "自动安装失败，需要 sudo 权限"
        echo ""
        echo "请选择："
        echo "  1) 输入密码安装系统字体（推荐）"
        echo "  2) 跳过字体安装"
        echo ""
        font_choice=$(read_input "请输入选项 [1]: " "1")

        if [[ "$font_choice" == "1" ]]; then
            if sudo apt-get install -y $fonts_pkg fontconfig 2>&1; then
                good "系统字体安装成功"
                fc-cache -f 2>/dev/null
            else
                error "字体安装失败，请稍后手动执行:"
                echo "  sudo apt-get install fonts-wqy-microhei fontconfig"
            fi
        else
            info "跳过字体安装"
        fi
    else
        warn "未检测到 apt-get，请手动安装中文字体"
    fi
}

verify_fonts() {
    echo ""
    info "字体验证:"
    echo "  中文字体数量: $(fc-list :lang=zh 2>/dev/null | grep -c . || echo 0)"
    echo ""
}

# ========== 主流程 ==========
main() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CLAUDE_DIR="$HOME/.claude"

    echo "========================================"
    echo "  Claude Code 环境准备脚本"
    echo "========================================"
    echo ""

    echo "此脚本将："
    echo "  1. 安装 MCP 服务器所需的运行时环境"
    echo "     - Node.js - npm/npx-based MCP 服务器"
    echo "     - uv - Python-based MCP 服务器"
    echo "     - Playwright - 浏览器自动化"
    echo "     - 中文字体"
    echo "  2. 建立符号链接实现配置双向同步"
    echo ""
    echo "安装完成后请运行 claudeinit.sh 安装具体的 MCP 服务器"
    echo ""

    # 确保 PATH 包含 ~/.local/bin（必须在检查/安装任何工具之前）
    setup_path

    # 配置 sudo 免密（仅针对 apt-get，避免 playwright install-deps 需要密码）
    configure_sudo_nopasswd

    # Node.js
    section "检测 Node.js"
    if check_node_installed; then
        warn "跳过 Node.js 安装（已存在）"
        verify_nodejs
    else
        install_nodejs
        verify_nodejs
    fi

    # uv
    section "检测 uv"
    if check_uv_installed; then
        warn "跳过 uv 安装（已存在）"
        verify_uv
    else
        install_uv
        verify_uv
    fi

    # Playwright
    section "检测 Playwright"
    if check_playwright_installed; then
        warn "跳过 Playwright 安装（已存在）"
        verify_playwright
    else
        info "安装 Playwright CLI..."
        if npm install -g playwright &>/dev/null; then
            info "Playwright CLI 安装成功"
        else
            warn "Playwright CLI 安装失败，但可通过 npx 使用"
        fi
        verify_playwright
    fi

    # Playwright 浏览器
    section "检测 Playwright 浏览器"
    if ls ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome &>/dev/null || \
       ls ~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux64/chrome &>/dev/null; then
        warn "跳过浏览器安装（已存在）"
    else
        install_playwright_browsers
    fi

    # Playwright 系统依赖
    install_playwright_deps

    # Playwright MCP 配置
    configure_playwright_mcp

    verify_playwright

    # 中文字体
    section "检测中文字体"
    if check_chinese_fonts; then
        warn "跳过中文字体安装（已存在）"
    else
        install_chinese_fonts
    fi
    verify_fonts

    # ========== 建立符号链接 ==========
    section "建立符号链接"

    # 获取当前项目路径
    CLAUDE_PROJECT_PATH="$(pwd)"
    CURRENT_PROJECT=$(basename "$CLAUDE_PROJECT_PATH")

    # 如果是 ccconfig 仓库，使用父目录
    if [ "$CURRENT_PROJECT" = "ccconfig" ]; then
        ACTUAL_PROJECT_PATH="$(dirname "$CLAUDE_PROJECT_PATH")"
    else
        ACTUAL_PROJECT_PATH="$CLAUDE_PROJECT_PATH"
    fi

    # Claude Code 项目名计算规则：将 / 替换为 -，前面加 -
    # /home/francis/git → -home-francis-git
    REPO_MEMORY_NAME="$(echo "$ACTUAL_PROJECT_PATH" | sed 's/\//-/g')"
    MEMORY_DIR="$CLAUDE_DIR/projects/$REPO_MEMORY_NAME/memory"
    MEMORY_REPO_PATH="$SCRIPT_DIR/link/$REPO_MEMORY_NAME/MEMORY.md"

    # 符号链接检查函数
    setup_symlink() {
        local link="$1"
        local target="$2"
        local name="$3"

        if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$(readlink -f "$target")" ]; then
            info "$name: 已链接，跳过"
            return 0
        elif [ -L "$link" ] || [ -e "$link" ]; then
            rm -f "$link"
        fi

        mkdir -p "$(dirname "$link")"
        ln -sf "$target" "$link"
        good "$name: 已建立链接"
        return 0
    }

    # settings.json
    setup_symlink "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/link/settings.json" "settings.json"

    # CLAUDE.md
    setup_symlink "$HOME/CLAUDE.md" "$SCRIPT_DIR/link/CLAUDE.md" "CLAUDE.md"

    # MEMORY.md
    if [ -d "$SCRIPT_DIR/link/$REPO_MEMORY_NAME" ]; then
        mkdir -p "$MEMORY_DIR"
        setup_symlink "$MEMORY_DIR/MEMORY.md" "$MEMORY_REPO_PATH" "MEMORY.md"
    else
        info "MEMORY.md: 仓库中未找到对应目录，跳过"
    fi

    echo ""

    section "安装完成"
    echo ""
    info "环境准备就绪，符号链接已建立"
    echo ""
    echo "========================================"
    echo "  📋 下一步操作"
    echo "========================================"
    echo ""
    echo "  运行 claudeinit.sh 安装 MCP 服务器："
    echo "  bash ccconfig/claudeinit.sh"
    echo ""
    echo "  或直接启动 Claude Code："
    echo "  claude"
    echo ""
}

main "$@"
