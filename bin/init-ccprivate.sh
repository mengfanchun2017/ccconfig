#!/bin/bash
# init-ccprivate.sh — 一键创建 ccprivate 私有配置仓库
#
# 用法：
#   bash ccconfig/bin/init-ccprivate.sh           # 交互式新建
#   bash ccconfig/bin/init-ccprivate.sh --clone    # 从已有 GitHub 仓库克隆
#
# 前置条件：SSH key 已添加到 GitHub（推荐），或 gh auth login 已完成（HTTPS 备选）
# 输出：~/git/ccprivate/ 完整目录结构 + GitHub 私有仓库 + symlink 已建立

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CCPRIVATE_DIR="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; GRAY='\033[0;90m'; NC='\033[0m'

banner() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   ccprivate 私有配置仓库 — 一键创建       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""
}

section() { echo -e "\n${BOLD}$1${NC}"; }
info()   { echo -e "  ${GRAY}$1${NC}"; }
ok()     { echo -e "  ${GREEN}✅ $1${NC}"; }
warn()   { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
err()    { echo -e "  ${RED}❌ $1${NC}"; }

# ── 自动检测 GitHub username ──
detect_gh_user() {
    gh api user --jq '.login' 2>/dev/null || echo ""
}

# ── 自动检测 git email ──
detect_git_email() {
    local e
    e=$(git config --global user.email 2>/dev/null || echo "")
    [ -n "$e" ] && echo "$e" && return
    e=$(gh api user --jq '.email' 2>/dev/null || echo "")
    [ -n "$e" ] && echo "$e" && return
    echo ""
}

# ── 收集用户信息 ──
collect_info() {
    section "GitHub 信息"

    GH_USER=$(detect_gh_user)
    if [ -n "$GH_USER" ]; then
        info "GitHub 账号: ${GREEN}$GH_USER${NC}"
        read -p "  确认? [Y/n]: " confirm
        confirm="${confirm:-y}"
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            read -p "  输入 GitHub 用户名: " GH_USER
        fi
    else
        read -p "  GitHub 用户名: " GH_USER
    fi

    GIT_EMAIL=$(detect_git_email)
    if [ -n "$GIT_EMAIL" ]; then
        info "Git 邮箱: ${GREEN}$GIT_EMAIL${NC}"
        read -p "  确认? [Y/n]: " confirm
        confirm="${confirm:-y}"
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            read -p "  输入邮箱: " GIT_EMAIL
        fi
    else
        read -p "  Git 邮箱: " GIT_EMAIL
    fi

    section "LLM API Key（至少填一个）"

    echo ""
    echo "  1) DeepSeek"
    echo "  2) MiniMax"
    echo "  3) Claude (Anthropic 官方)"
    echo ""
    read -p "  选择默认后端 [1]: " LLM_CHOICE
    LLM_CHOICE="${LLM_CHOICE:-1}"

    case "$LLM_CHOICE" in
        1)
            DEFAULT_LLM="deepseek"
            read -p "  DeepSeek API Key: " DEEPSEEK_KEY
            ;;
        2)
            DEFAULT_LLM="minimax"
            read -p "  MiniMax API Key: " MINIMAX_KEY
            ;;
        3)
            DEFAULT_LLM="claude"
            read -p "  Anthropic API Key: " CLAUDE_KEY
            ;;
    esac

    # 如果用户有多个 key，问要不要填其他的
    echo ""
    if [ "$LLM_CHOICE" != "1" ]; then
        read -p "  还有 DeepSeek Key? 直接回车跳过: " DEEPSEEK_KEY
    fi
    if [ "$LLM_CHOICE" != "2" ]; then
        read -p "  还有 MiniMax Key? 直接回车跳过: " MINIMAX_KEY
    fi
    if [ "$LLM_CHOICE" != "3" ]; then
        read -p "  还有 Anthropic Key? 直接回车跳过: " CLAUDE_KEY
    fi
}

# ── 生成 conf/llm.json ──
gen_llm_json() {
    local f="$CCPRIVATE_DIR/conf/.generated/llm.json"
    python3 << PYEOF
import json

llms = {}
if "${DEEPSEEK_KEY:-}":
    llms["deepseek"] = {
        "name": "DeepSeek",
        "base_url": "https://api.deepseek.com/anthropic",
        "model": "deepseek-v4-pro",
        "key": "${DEEPSEEK_KEY}",
        "small_model": "deepseek-v4-pro"
    }
if "${MINIMAX_KEY:-}":
    llms["minimax"] = {
        "name": "MiniMax",
        "base_url": "https://api.minimaxi.com/anthropic",
        "model": "MiniMax-M3",
        "key": "${MINIMAX_KEY}",
        "small_model": "MiniMax-M3"
    }
if "${CLAUDE_KEY:-}":
    llms["claude"] = {
        "name": "Claude",
        "base_url": "https://api.anthropic.com",
        "model": "claude-sonnet-4-6",
        "key": "${CLAUDE_KEY}",
        "small_model": "claude-haiku-4-5"
    }

d = {"llms": llms, "current": "$DEFAULT_LLM"}
with open("$f", "w") as fh:
    json.dump(d, fh, indent=4, ensure_ascii=False)
    fh.write("\n")
PYEOF
    ok "conf/llm.json"
}

# ── 生成 conf/claude.json ──
gen_claude_json() {
    local f="$CCPRIVATE_DIR/conf/.generated/claude.json"
    local auth_token="${DEEPSEEK_KEY:-${MINIMAX_KEY:-${CLAUDE_KEY:-}}}"
    local base_url="https://api.deepseek.com/anthropic"
    local model="deepseek-v4-pro"
    case "$DEFAULT_LLM" in
        minimax) base_url="https://api.minimaxi.com/anthropic"; model="MiniMax-M3" ;;
        claude)  base_url="https://api.anthropic.com"; model="claude-sonnet-4-6" ;;
    esac

    python3 << PYEOF
import json
d = {
    "env": {
        "ANTHROPIC_BASE_URL": "$base_url",
        "ANTHROPIC_MODEL": "$model",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        "ANTHROPIC_AUTH_TOKEN": "$auth_token"
    },
    "settings": {"default_action": "sync", "auto_config_keys": True},
    "mcp_servers": []
}
with open("$f", "w") as fh:
    json.dump(d, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PYEOF
    ok "conf/claude.json"
}

# ── 生成 conf/ubuntu.json ──
gen_ubuntu_json() {
    local f="$CCPRIVATE_DIR/conf/.generated/ubuntu.json"
    python3 << PYEOF
import json
d = {
    "git": {
        "repo": "$GH_USER/ccconfig",
        "target_dir": "\$HOME/git/ccconfig",
        "email": "$GIT_EMAIL",
        "username": "$GH_USER"
    }
}
with open("$f", "w") as fh:
    json.dump(d, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PYEOF
    ok "conf/ubuntu.json"
}

# ── 生成 link/CLAUDE.md ──
gen_claude_md() {
    cat > "$CCPRIVATE_DIR/link/CLAUDE.md" << 'EOF'
# Claude Code 用户配置

> 全局 AI 行为指南。所有项目通用。

## 核心约定
- 中文回复
- 简洁输出，不啰嗦

## 权限
- Bash(*) Read(*) Write(*) Edit(*) Glob(*) Grep(*)
- WebSearch WebFetch Skill(*)

## 工作目录
- 配置维护 → `cd ~/git/ccconfig && claude`
- 项目开发 → `cd ~/git/<project> && claude`
EOF
    ok "link/CLAUDE.md"
}

# ── 生成 link/settings.json ──
gen_settings_json() {
    cat > "$CCPRIVATE_DIR/link/settings.json" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Glob(*)",
      "Grep(*)",
      "WebSearch",
      "WebFetch",
      "Skill(*)"
    ]
  }
}
EOF
    ok "link/settings.json"
}

# ── 生成 setup.sh ──
gen_setup_sh() {
    cat > "$CCPRIVATE_DIR/setup.sh" << 'SETUPEOF'
#!/bin/bash
# ccprivate setup.sh — 私有 + 公开链接一步到位
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="${CCCONFIG_HOME:-$HOME/git/ccconfig}"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
ok() { echo -e "${GREEN}✅ $1${NC}"; }

link_file() {
    local src="$1" dst="$2" name="$3"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        info "$name: 已链接"
        return 0
    fi
    [ -e "$dst" ] || [ -L "$dst" ] && rm -f "$dst"
    ln -sf "$src" "$dst"
    ok "$name: 已链接"
}

echo "=== ccprivate → ccconfig 私有链接 ==="

for f in "$SCRIPT_DIR"/conf/*.json; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    link_file "$f" "$CCCONFIG_DIR/conf/$name" "conf/$name"
done

if [ -f "$SCRIPT_DIR/link/CLAUDE.md" ]; then
    link_file "$SCRIPT_DIR/link/CLAUDE.md" "$HOME/CLAUDE.md" "~/CLAUDE.md"
fi
if [ -f "$SCRIPT_DIR/link/settings.json" ]; then
    link_file "$SCRIPT_DIR/link/settings.json" "$HOME/.claude/settings.json" "settings.json"
fi
if [ -f "$SCRIPT_DIR/link/.config.json" ]; then
    link_file "$SCRIPT_DIR/link/.config.json" "$HOME/.claude/.config.json" ".config.json"
fi
if [ -d "$SCRIPT_DIR/link/projects" ]; then
    link_file "$SCRIPT_DIR/link/projects" "$CCCONFIG_DIR/link/projects" "link/projects"
fi

echo ""
echo "=== ccconfig 公开链接 ==="
if [ -f "$CCCONFIG_DIR/setup-links.sh" ]; then
    bash "$CCCONFIG_DIR/setup-links.sh"
fi

echo ""
ok "全部链接完成"
echo "下一步: bash $CCCONFIG_DIR/init.sh all"
SETUPEOF
    chmod +x "$CCPRIVATE_DIR/setup.sh"
    ok "setup.sh"
}

# ── 创建 GitHub 私有仓库并推送 ──
create_and_push() {
    section "创建 GitHub 私有仓库"

    cd "$CCPRIVATE_DIR"

    # 检查是否已有 remote
    if git remote get-url origin &>/dev/null; then
        info "remote 已存在，跳过创建"
        return 0
    fi

    if gh repo view "$GH_USER/ccprivate" &>/dev/null 2>&1; then
        info "GitHub 仓库已存在: $GH_USER/ccprivate"
        git remote add origin "git@github.com:$GH_USER/ccprivate.git"
    else
        info "创建私有仓库: $GH_USER/ccprivate"
        gh repo create "$GH_USER/ccprivate" --private --source=. --remote=origin --push 2>&1 | tail -3
        git remote set-url origin "git@github.com:$GH_USER/ccprivate.git"
        ok "仓库已创建并推送（SSH）"
        return 0
    fi

    git push -u origin main 2>&1 | tail -2
    ok "已推送"
}

# ── 主流程：新建 ──
do_create() {
    banner

    if [ -d "$CCPRIVATE_DIR" ] && [ -n "$(ls -A "$CCPRIVATE_DIR" 2>/dev/null)" ]; then
        warn "$CCPRIVATE_DIR 已存在且非空"
        read -p "  覆盖? [y/N]: " overwrite
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            rm -rf "$CCPRIVATE_DIR"
        else
            info "跳过创建，直接跑 setup.sh"
            bash "$CCPRIVATE_DIR/setup.sh"
            return 0
        fi
    fi

    collect_info

    section "创建目录结构"
    mkdir -p "$CCPRIVATE_DIR/conf/.generated"
    mkdir -p "$CCPRIVATE_DIR/skill-config"
    mkdir -p "$CCPRIVATE_DIR/link/projects"

    section "生成配置文件"
    gen_llm_json
    gen_claude_json
    gen_ubuntu_json
    gen_claude_md
    gen_settings_json
    gen_setup_sh

    # 复制可选 .example 到 ccprivate（用户以后可按需编辑）
    for example in "$CCCONFIG_DIR"/conf/*.example; do
        [ -f "$example" ] || continue
        local name=$(basename "$example" .example)
        if [ ! -f "$CCPRIVATE_DIR/conf/$name" ]; then
            cp "$example" "$CCPRIVATE_DIR/conf/$name"
            info "conf/$name (从模板复制，按需编辑)"
        fi
    done

    section "初始化 Git"
    cd "$CCPRIVATE_DIR"
    git init -b main
    git add -A
    git commit -m "init: ccprivate 个人配置

Co-Authored-By: Claude <noreply@anthropic.com>" 2>&1 | tail -1

    create_and_push

    section "建立符号链接"
    bash "$CCPRIVATE_DIR/setup.sh"

    echo ""
    ok "ccprivate 创建完成"
    echo ""
    echo "  下一步:"
    echo "    bash $CCCONFIG_DIR/init.sh all"
    echo ""
}

# ── 主流程：克隆已有 ──
do_clone() {
    banner

    GH_USER=$(detect_gh_user)
    if [ -z "$GH_USER" ]; then
        read -p "  GitHub 用户名: " GH_USER
    fi

    if [ -d "$CCPRIVATE_DIR" ]; then
        warn "$CCPRIVATE_DIR 已存在"
        read -p "  删除后重新克隆? [y/N]: " reclone
        if [[ "$reclone" =~ ^[Yy]$ ]]; then
            rm -rf "$CCPRIVATE_DIR"
        else
            info "跳过克隆"
            bash "$CCPRIVATE_DIR/setup.sh"
            return 0
        fi
    fi

    section "克隆 ccprivate"
    gh repo clone "$GH_USER/ccprivate" "$CCPRIVATE_DIR"
    git -C "$CCPRIVATE_DIR" remote set-url origin "git@github.com:$GH_USER/ccprivate.git"

    section "建立符号链接"
    bash "$CCPRIVATE_DIR/setup.sh"

    ok "ccprivate 克隆完成"
}

# ── 入口 ──
case "${1:-}" in
    --clone|-c)
        do_clone
        ;;
    *)
        do_create
        ;;
esac
