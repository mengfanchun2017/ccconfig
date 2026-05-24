#!/bin/bash
# ccconfig share/setup.sh — 新用户引导式配置向导
#
# 克隆 cccshare 后运行此脚本完成个人配置。
# 支持：交互式引导、外部私有配置仓库、依赖检查。
#
# 用法:
#   bash share/setup.sh                        # 交互式引导
#   bash share/setup.sh --quick                 # 快速模式（仅基础配置）
#   bash share/setup.sh --config-repo <url>     # 从私有配置仓库导入

set -e

SHARE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SHARE_DIR/.." && pwd)"
CONF_DIR="$CCCONFIG_DIR/conf"
LOCAL_BIN="$HOME/.local/bin"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; GRAY='\033[0;90m'; NC='\033[0m'

CONFIG_REPO=""
QUICK_MODE=false

for arg in "$@"; do
    case "$arg" in
        --quick) QUICK_MODE=true ;;
        --config-repo) CONFIG_REPO="${2:-}"; shift ;;
        --config-repo=*) CONFIG_REPO="${arg#*=}" ;;
    esac
done

banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     ccconfig — Claude Code 配置中枢              ║${NC}"
    echo -e "${CYAN}║     新用户配置向导                                ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

section() {
    echo ""
    echo -e "${BOLD}$1${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ========== Step 1: 欢迎 ==========
step_welcome() {
    banner
    echo "  此向导将帮你完成 ccconfig 的个人配置。"
    echo ""
    echo "  预计时间: 3-5 分钟"
    echo "  涉及内容:"
    echo "    • Git 用户信息配置"
    echo "    • LLM API Key 配置"
    echo "    • (可选) 飞书集成"
    echo "    • (可选) 私有配置仓库关联"
    echo ""

    if ! $QUICK_MODE; then
        read -p "  按回车开始配置... " _
    fi
}

# ========== Step 2: 依赖检查 ==========
step_deps() {
    section "Step 1/5: 依赖检查"

    local missing=0

    check() {
        if command -v "$1" &>/dev/null; then
            local v="$($1 $2 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo '?')"
            echo -e "  ${GREEN}✅${NC} $1 ${GRAY}$v${NC}"
        else
            echo -e "  ${RED}❌${NC} $1 ${GRAY}$3 — $4${NC}"
            missing=$((missing + 1))
        fi
    }

    check "git" "--version" "版本控制" "sudo apt install git"
    check "node" "--version" "Node.js" "https://nodejs.org"
    check "python3" "--version" "Python 3" "sudo apt install python3"
    check "curl" "--version" "HTTP 客户端" "sudo apt install curl"
    check "gh" "--version" "GitHub CLI" "https://cli.github.com"
    check "claude" "--version" "Claude Code" "npm install -g @anthropic-ai/claude-code"

    if [ $missing -gt 0 ]; then
        echo ""
        echo -e "  ${RED}$missing 个依赖缺失，请先安装后重试${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}依赖完整${NC}"
}

# ========== Step 3: Git 配置 ==========
step_git_config() {
    section "Step 2/5: Git 用户信息"

    local git_name git_email

    if [ -f "$CONF_DIR/ubuntu.json" ]; then
        git_name=$(python3 -c "import json; print(json.load(open('$CONF_DIR/ubuntu.json')).get('git_name',''))" 2>/dev/null || echo "")
        git_email=$(python3 -c "import json; print(json.load(open('$CONF_DIR/ubuntu.json')).get('git_email',''))" 2>/dev/null || echo "")
    fi

    if [ -n "$git_name" ] && [ -n "$git_email" ]; then
        echo -e "  当前配置: ${GREEN}$git_name${NC} <${GRAY}$git_email${NC}>"
        if ! $QUICK_MODE; then
            read -p "  保持不变? [Y/n]: " keep
            keep="${keep:-y}"
            if [[ "$keep" =~ ^[Yy]$ ]]; then
                return 0
            fi
        else
            return 0
        fi
    fi

    read -p "  Git 用户名: " git_name
    read -p "  Git 邮箱: " git_email

    if [ -z "$git_name" ] || [ -z "$git_email" ]; then
        echo -e "  ${RED}用户名和邮箱不能为空${NC}"
        step_git_config
        return
    fi

    # 保存到 ubuntu.json
    if [ -f "$CONF_DIR/ubuntu.json" ]; then
        python3 -c "
import json
with open('$CONF_DIR/ubuntu.json') as f:
    d = json.load(f)
d['git_name'] = '$git_name'
d['git_email'] = '$git_email'
with open('$CONF_DIR/ubuntu.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write('\n')
"
    else
        python3 -c "
import json
with open('$CONF_DIR/ubuntu.json', 'w') as f:
    json.dump({'git_name':'$git_name','git_email':'$git_email'}, f, indent=2, ensure_ascii=False)
    f.write('\n')
"
    fi

    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    echo -e "  ${GREEN}Git 配置完成${NC}"
}

# ========== Step 4: LLM 配置 ==========
step_llm_config() {
    section "Step 3/5: LLM API Key"

    if [ -f "$CONF_DIR/llm.json" ]; then
        local current=$(python3 -c "import json; d=json.load(open('$CONF_DIR/llm.json')); print(d.get('current',''))" 2>/dev/null || echo "")
        if [ -n "$current" ]; then
            echo -e "  当前 LLM: ${GREEN}$current${NC}"
        fi
    fi

    echo ""
    echo "  Claude Code 支持多 LLM 后端："
    echo "    1) Claude (Anthropic 官方)"
    echo "    2) DeepSeek"
    echo "    3) MiniMax"
    echo ""

    if ! $QUICK_MODE; then
        read -p "  选择默认后端 [1-3, 默认 2]: " llm_choice
        llm_choice="${llm_choice:-2}"

        case "$llm_choice" in
            1)
                read -p "  Anthropic API Key: " api_key
                python3 -c "
import json
d = {'current': 'claude', 'backends': {}}
d['backends']['claude'] = {'api_key': '$api_key', 'base_url': 'https://api.anthropic.com'}
with open('$CONF_DIR/llm.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write('\n')
" 2>/dev/null || echo -e "  ${YELLOW}配置保存失败${NC}"
                ;;
            2)
                read -p "  DeepSeek API Key: " api_key
                python3 -c "
import json
d = {'current': 'deepseek', 'backends': {'deepseek': {'api_key': '$api_key', 'base_url': 'https://api.deepseek.com'}}}
with open('$CONF_DIR/llm.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write('\n')
" 2>/dev/null || echo -e "  ${YELLOW}配置保存失败${NC}"
                ;;
            3)
                read -p "  MiniMax API Key: " api_key
                read -p "  MiniMax Group ID: " group_id
                python3 -c "
import json
d = {'current': 'minimax', 'backends': {'minimax': {'api_key': '$api_key', 'group_id': '$group_id', 'base_url': 'https://api.minimax.chat'}}}
with open('$CONF_DIR/llm.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write('\n')
" 2>/dev/null || echo -e "  ${YELLOW}配置保存失败${NC}"
                ;;
        esac
        echo -e "  ${GREEN}LLM 配置完成${NC}"
    else
        echo -e "  ${YELLOW}快速模式: 跳过 LLM 配置，手动编辑 conf/llm.json${NC}"
    fi
}

# ========== Step 5: 私有配置仓库 ==========
step_config_repo() {
    section "Step 4/5: 私有配置仓库"

    echo "  你可以使用自己的私有 Git 仓库存储个人配置，"
    echo "  这样 API Key、Token 等不会进入公开仓库。"
    echo ""

    if [ -n "$CONFIG_REPO" ]; then
        echo -e "  配置仓库: ${GREEN}$CONFIG_REPO${NC}"
    fi

    if ! $QUICK_MODE; then
        read -p "  设置私有配置仓库? [y/N]: " use_repo
        if [[ "$use_repo" =~ ^[Yy]$ ]]; then
            if [ -z "$CONFIG_REPO" ]; then
                read -p "  仓库 URL (如 git@github.com:you/ccconfig-private.git): " CONFIG_REPO
            fi
            if [ -n "$CONFIG_REPO" ]; then
                local private_dir="$HOME/git/ccconfig-private"
                if [ ! -d "$private_dir" ]; then
                    git clone "$CONFIG_REPO" "$private_dir" 2>/dev/null || {
                        echo -e "  ${YELLOW}克隆失败，将创建新仓库${NC}"
                        mkdir -p "$private_dir"
                        git -C "$private_dir" init -b main
                    }
                fi
                # 从私有仓库复制配置文件
                for f in claude.json llm.json ubuntu.json feishu.json; do
                    if [ -f "$private_dir/conf/$f" ]; then
                        cp "$private_dir/conf/$f" "$CONF_DIR/"
                        echo -e "  ${GREEN}✅${NC} 导入 conf/$f"
                    fi
                done
                echo -e "  ${GREEN}私有配置仓库已关联: $CONFIG_REPO${NC}"
                echo -e "  ${GRAY}更新: cd $private_dir && git pull${NC}"
            fi
        fi
    fi
}

# ========== Step 6: 建立符号链接 ==========
step_symlinks() {
    section "Step 5/5: 建立符号链接"

    if [ -f "$CCCONFIG_DIR/setup-links.sh" ]; then
        bash "$CCCONFIG_DIR/setup-links.sh"
        echo -e "  ${GREEN}符号链接建立完成${NC}"
    else
        echo -e "  ${RED}未找到 setup-links.sh${NC}"
    fi
}

# ========== Step 7: 完成 ==========
step_done() {
    section "配置完成"
    echo ""
    echo -e "  ${GREEN}✅ ccconfig 个人配置已完成${NC}"
    echo ""
    echo "  后续操作:"
    echo "    bash ccconfig/init.sh              # 交互式菜单"
    echo "    bash ccconfig/init.sh all          # 一键初始化全部"
    echo "    bash ccconfig/status.sh            # 状态检查"
    echo "    bash ccconfig/deps-check.sh        # 依赖检查"
    echo ""
    echo "  可选组件:"
    echo "    bash ccconfig/option-bridge/init.sh     # 飞书 Bridge"
    echo "    bash ccconfig/option-officecli/init.sh  # OfficeCLI"
    echo "    bash ccconfig/option-ppt-master/init.sh # PPT 生成"
    echo ""
    echo "  auto-sync (文件监控+自动提交推送):"
    echo "    bash ccconfig/monitor.sh start"
    echo ""
    echo -e "  ${GRAY}更多: bash ccconfig/init.sh${NC}"
    echo ""
}

# ========== 主流程 ==========
main() {
    step_welcome
    step_deps
    step_git_config
    step_llm_config
    step_config_repo
    step_symlinks
    step_done
}

main
