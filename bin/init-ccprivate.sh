#!/bin/bash
# init-ccprivate.sh — 一键创建 ccprivate 私有配置仓库
#
# 用法：
#   bash ccconfig/bin/init-ccprivate.sh           # 交互式新建
#   bash ccconfig/bin/init-ccprivate.sh --clone    # 从已有 GitHub 仓库克隆
#   bash ccconfig/bin/init-ccprivate.sh --update   # 更新已有 ccprivate（pull + setup + 刷新配置）
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

# ── gh auth 预检 ──
check_gh_auth() {
    if gh auth status &>/dev/null; then
        info "GitHub 认证: ${GREEN}已登录${NC}"
        return 0
    fi
    warn "GitHub 未认证，需要先登录"
    echo ""
    read -p "  现在登录? [Y/n]: " do_login
    do_login="${do_login:-y}"
    if [[ "$do_login" =~ ^[Yy]$ ]]; then
        gh auth login
        if gh auth status &>/dev/null; then
            ok "GitHub 认证完成"
            return 0
        fi
        err "GitHub 认证失败"
        return 1
    fi
    return 1
}

# ── 自动检测 GitHub username ──
detect_gh_user() {
    local user
    user=$(gh api user --jq '.login' 2>/dev/null) || true
    if echo "$user" | grep -qE '^[a-zA-Z0-9](-?[a-zA-Z0-9])*$'; then
        echo "$user"
    else
        echo ""
    fi
}

# ── 自动检测 git email ──
detect_git_email() {
    local e
    e=$(git config --global user.email 2>/dev/null || echo "")
    [ -n "$e" ] && echo "$e" && return
    e=$(gh api user --jq '.email' 2>/dev/null) || true
    if echo "$e" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        echo "$e"
    else
        echo ""
    fi
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
        while [ -z "$GH_USER" ]; do
            read -p "  GitHub 用户名: " GH_USER
            [ -z "$GH_USER" ] && err "GitHub 用户名不能为空"
        done
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
        while [ -z "$GIT_EMAIL" ]; do
            read -p "  Git 邮箱: " GIT_EMAIL
            [ -z "$GIT_EMAIL" ] && err "Git 邮箱不能为空"
        done
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
    local f="$CCPRIVATE_DIR/conf/llm.json"
    DEEPSEEK_KEY="${DEEPSEEK_KEY:-}" MINIMAX_KEY="${MINIMAX_KEY:-}" CLAUDE_KEY="${CLAUDE_KEY:-}" DEFAULT_LLM="$DEFAULT_LLM" OUT="$f" python3 << 'PYEOF'
import json, os

llms = {}
dk = os.environ.get("DEEPSEEK_KEY", "")
mk = os.environ.get("MINIMAX_KEY", "")
ck = os.environ.get("CLAUDE_KEY", "")
if dk:
    llms["deepseek"] = {
        "name": "DeepSeek",
        "base_url": "https://api.deepseek.com/anthropic",
        "model": "deepseek-v4-pro",
        "key": dk,
        "small_model": "deepseek-v4-pro"
    }
if mk:
    llms["minimax"] = {
        "name": "MiniMax",
        "base_url": "https://api.minimaxi.com/anthropic",
        "model": "MiniMax-M3",
        "key": mk,
        "small_model": "MiniMax-M3"
    }
if ck:
    llms["claude"] = {
        "name": "Claude",
        "base_url": "https://api.anthropic.com",
        "model": "claude-sonnet-4-6",
        "key": ck,
        "small_model": "claude-haiku-4-5"
    }

d = {"llms": llms, "current": os.environ["DEFAULT_LLM"]}
with open(os.environ["OUT"], "w") as fh:
    json.dump(d, fh, indent=4, ensure_ascii=False)
    fh.write("\n")
PYEOF
    ok "conf/llm.json"
}

# ── 生成 conf/claude.json ──
# LLM env (ANTHROPIC_BASE_URL/MODEL/AUTH_TOKEN) 由 init-llm.sh 独占管理
# 这里只放 Claude Code 行为开关 + MCP 配置占位
gen_claude_json() {
    local f="$CCPRIVATE_DIR/conf/claude.json"

    python3 - <<PYEOF
import json
d = {
    "env": {
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
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
    local f="$CCPRIVATE_DIR/conf/ubuntu.json"
    GH_USER="$GH_USER" GIT_EMAIL="$GIT_EMAIL" OUT="$f" python3 << 'PYEOF'
import json, os
d = {
    "git": {
        "repo": os.environ["GH_USER"] + "/cconfig",
        "target_dir": os.path.expanduser("~/git/cconfig"),
        "email": os.environ["GIT_EMAIL"],
        "username": os.environ["GH_USER"]
    }
}
with open(os.environ["OUT"], "w") as fh:
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

# ── 生成 link/.config.json ──
gen_dot_config_json() {
    cat > "$CCPRIVATE_DIR/link/.config.json" << 'EOF'
{}
EOF
    ok "link/.config.json"
}

# ── 生成 setup.sh ──
gen_setup_sh() {
    cat > "$CCPRIVATE_DIR/setup.sh" << 'SETUPEOF'
#!/bin/bash
# ccprivate setup.sh — 私有链接一步到位（不含 skills，skills 由 init.sh all 统一管理）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCCONFIG_DIR="${CCCONFIG_DIR:-$HOME/git/ccconfig}"
CLAUDE_DIR="$HOME/.claude"

echo "=== ccprivate setup ==="

setup_link() {
    local link="$1" target="$2" label="$3"
    mkdir -p "$(dirname "$link")"
    if [ -L "$link" ]; then
        local existing=$(readlink -f "$link" 2>/dev/null)
        local expected=$(readlink -f "$target" 2>/dev/null)
        if [ "$existing" = "$expected" ]; then
            echo "  $label: 已链接，跳过"
            return 0
        fi
        rm -f "$link"
    elif [ -e "$link" ]; then
        rm -rf "$link"
    fi
    ln -s "$target" "$link"
    echo "  $label"
}

# --- 用户级链接 ---
echo "--- 用户级链接 ---"
setup_link "$HOME/CLAUDE.md"           "$SCRIPT_DIR/link/CLAUDE.md"     "~/CLAUDE.md"
setup_link "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/link/settings.json" "~/.claude/settings.json"
setup_link "$CLAUDE_DIR/.config.json"  "$SCRIPT_DIR/link/.config.json"  "~/.claude/.config.json"

# --- Memory 链接 ---
echo "--- Memory 链接 ---"
for proj_dir in "$SCRIPT_DIR/link/projects"/-home-*-*/; do
    [ -d "$proj_dir" ] || continue
    PROJ_NAME=$(basename "$proj_dir")
    if [ -d "${proj_dir}memory" ]; then
        setup_link "$CLAUDE_DIR/projects/$PROJ_NAME/memory" "${proj_dir}memory" "memory/$PROJ_NAME"
    fi
done

# --- 项目 CLAUDE.md ---
echo "--- 项目 CLAUDE.md ---"
for proj_dir in "$SCRIPT_DIR/link/projects"/-home-*-*/; do
    [ -d "$proj_dir" ] || continue
    PROJ_NAME=$(basename "$proj_dir")
    if [ "$PROJ_NAME" = "-home-${USER}-git" ]; then continue; fi
    PROJ_PATH="/$(echo "$PROJ_NAME" | sed 's/^-//' | sed 's/-/\//g')"
    if [ -f "${proj_dir}CLAUDE.md" ] && [ -d "$PROJ_PATH" ]; then
        setup_link "$PROJ_PATH/CLAUDE.md" "${proj_dir}CLAUDE.md" "$PROJ_NAME/CLAUDE.md"
    fi
done

# --- Conf 链接（cconfig/conf/ → ccprivate/conf/） ---
echo "--- Conf 链接 ---"
for src in "$SCRIPT_DIR/conf/"*.json; do
    [ -f "$src" ] || continue
    name=$(basename "$src")
    dst="$CCCONFIG_DIR/conf/$name"
    [ -L "$dst" ] && rm -f "$dst"
    [ -f "$dst" ] && rm -f "$dst"
    ln -s "$src" "$dst"
    echo "  conf/$name → ccprivate"
done
# 旧格式回退（兼容 1.3.7 及更早的 ccprivate）
if [ -d "$SCRIPT_DIR/conf/.generated" ]; then
    for src in "$SCRIPT_DIR/conf/.generated/"*.json; do
        [ -f "$src" ] || continue
        name=$(basename "$src")
        [ -f "$SCRIPT_DIR/conf/$name" ] && continue
        dst="$CCCONFIG_DIR/conf/$name"
        [ -L "$dst" ] && rm -f "$dst"
        [ -f "$dst" ] && rm -f "$dst"
        ln -s "$src" "$dst"
        echo "  conf/$name → ccprivate (.generated)"
    done
fi

# --- ccconfig link/projects overlay ---
echo "--- ccconfig link overlay ---"
for old in "$CCCONFIG_DIR/link/CLAUDE.md" "$CCCONFIG_DIR/link/settings.json" "$CCCONFIG_DIR/link/.config.json"; do
    if [ -f "$old" ] && [ ! -L "$old" ]; then rm -f "$old"; fi
done
setup_link "$CCCONFIG_DIR/link/projects" "$SCRIPT_DIR/link/projects" "ccconfig/link/projects"

# --- ccconfig 公开链接（agents/rules/commands/skills） ---
if [ -x "$CCCONFIG_DIR/setup-links.sh" ]; then
    echo "--- 调 ccconfig/setup-links.sh（公开部分）---"
    bash "$CCCONFIG_DIR/setup-links.sh"
fi

echo ""
echo "=== ccprivate setup 完成 ==="
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

    # 本地已有 ccprivate → 直接跑 setup.sh，不啰嗦
    if [ -d "$CCPRIVATE_DIR" ] && [ -n "$(ls -A "$CCPRIVATE_DIR" 2>/dev/null)" ]; then
        info "$CCPRIVATE_DIR 已存在，刷新符号链接"
        bash "$CCPRIVATE_DIR/setup.sh"
        return 0
    fi

    # GitHub 已有 ccprivate → 引导 clone，不新建
    local gh_user=$(detect_gh_user)
    if [ -n "$gh_user" ] && gh repo view "$gh_user/ccprivate" &>/dev/null 2>&1; then
        info "GitHub 已有 ccprivate 仓库: $gh_user/ccprivate"
        echo ""
        echo -e "  ${GREEN}已有配置，直接 clone 即可，无需重新创建。${NC}"
        echo ""
        do_clone
        return $?
    fi

    # 完全新建
    collect_info

    section "创建目录结构"
    mkdir -p "$CCPRIVATE_DIR/conf"
    mkdir -p "$CCPRIVATE_DIR/skill-config"
    mkdir -p "$CCPRIVATE_DIR/link/projects"

    section "生成配置文件"
    gen_llm_json
    gen_claude_json
    gen_ubuntu_json
    gen_claude_md
    gen_settings_json
    gen_dot_config_json
    gen_setup_sh

    # 复制可选 .example 到 ccprivate（用户以后可按需编辑）
    for example in "$CCCONFIG_DIR"/conf/*.example; do
        [ -f "$example" ] || continue
        local name=$(basename "$example" .example)
        if [ ! -f "$CCPRIVATE_DIR/conf/$name" ]; then
            cp "$example" "$CCPRIVATE_DIR/conf/$name"
            if grep -qE '请填入|请替换|your.key|placeholder|changeme' "$CCPRIVATE_DIR/conf/$name" 2>/dev/null; then
                warn "conf/$name 含占位符值，请编辑填入真实信息: vim $CCPRIVATE_DIR/conf/$name"
            else
                info "conf/$name (从模板复制，按需编辑)"
            fi
        fi
    done

    section "初始化 Git"
    cd "$CCPRIVATE_DIR"
    git init -b main
    git add -A
    git commit -m "init: ccprivate 个人配置

Co-Authored-By: Claude <noreply@anthropic.com>" 2>&1 | tail -1

    check_gh_auth || return 1

    create_and_push

    section "建立符号链接"
    bash "$CCPRIVATE_DIR/setup.sh"

    echo ""
    ok "ccprivate 创建完成"
    echo ""
    echo -e "  ${YELLOW}⚠️  下一步必须先 cd 到 ccconfig 目录${NC}"
    echo -e "    ${GREEN}cd $CCCONFIG_DIR && bash init.sh all${NC}"
    echo -e "  ${GRAY}(5 步: Ubuntu → LLM → MCP → Skills → 验证)${NC}"
    echo ""
}

# ── 主流程：更新已有 ──
do_update() {
    banner

    if [ ! -d "$CCPRIVATE_DIR/.git" ]; then
        err "$CCPRIVATE_DIR 不是 git 仓库，无法更新"
        echo "  请先运行: bash $CCCONFIG_DIR/bin/init-ccprivate.sh --clone"
        return 1
    fi

    check_gh_auth || return 1

    section "拉取最新 ccprivate"
    cd "$CCPRIVATE_DIR"
    git pull origin main 2>&1 | tail -3

    section "刷新生成配置"
    local llm_src=""
    if [ -f "$CCPRIVATE_DIR/conf/llm.json" ]; then
        llm_src="$CCPRIVATE_DIR/conf/llm.json"
    elif [ -f "$CCPRIVATE_DIR/conf/.generated/llm.json" ]; then
        llm_src="$CCPRIVATE_DIR/conf/.generated/llm.json"
        info "从旧路径迁移: conf/.generated/ → conf/"
    fi
    if [ -n "$llm_src" ]; then
        eval "$(LLM_SRC="$llm_src" python3 << 'PYEOF'
import json, os
d = json.load(open(os.environ["LLM_SRC"]))
llms = d.get("llms", {})
for key, var in [("deepseek","DEEPSEEK_KEY"), ("minimax","MINIMAX_KEY"), ("claude","CLAUDE_KEY")]:
    print(f'{var}={llms.get(key,{}).get("key","")}')
print(f'DEFAULT_LLM={d.get("current","deepseek")}')
PYEOF
        )"
        if [ -n "$DEEPSEEK_KEY" ] || [ -n "$MINIMAX_KEY" ] || [ -n "$CLAUDE_KEY" ]; then
            gen_llm_json
            gen_claude_json
        fi
    fi

    local ubuntu_src=""
    if [ -f "$CCPRIVATE_DIR/conf/ubuntu.json" ]; then
        ubuntu_src="$CCPRIVATE_DIR/conf/ubuntu.json"
    elif [ -f "$CCPRIVATE_DIR/conf/.generated/ubuntu.json" ]; then
        ubuntu_src="$CCPRIVATE_DIR/conf/.generated/ubuntu.json"
        info "从旧路径迁移: conf/.generated/ → conf/"
    fi
    if [ -n "$ubuntu_src" ]; then
        eval "$(UBUNTU_SRC="$ubuntu_src" python3 << 'PYEOF'
import json, os
d = json.load(open(os.environ["UBUNTU_SRC"]))
g = d.get("git", {})
print(f'GH_USER={g.get("username","")}')
print(f'GIT_EMAIL={g.get("email","")}')
PYEOF
        )"
        if [ -n "$GH_USER" ]; then
            gen_ubuntu_json
        fi
    fi

    section "建立符号链接"
    bash "$CCPRIVATE_DIR/setup.sh"

    echo ""
    ok "ccprivate 更新完成"
    echo -e "  ${GRAY}配置已刷新。如需重跑系统初始化: bash $CCCONFIG_DIR/init.sh all${NC}"
}

# ── 主流程：克隆已有 ──
do_clone() {
    banner

    GH_USER=$(detect_gh_user)
    if [ -z "$GH_USER" ]; then
        read -p "  GitHub 用户名: " GH_USER
    fi

    check_gh_auth || return 1

    if [ -d "$CCPRIVATE_DIR/.git" ] && git -C "$CCPRIVATE_DIR" remote get-url origin &>/dev/null; then
        info "ccprivate 已存在，拉取最新"
        git -C "$CCPRIVATE_DIR" pull origin main 2>&1 | tail -2
    else
        # 无 remote（失败的 do_create 残留）或非 git 目录 → 直接 clone
        if [ -d "$CCPRIVATE_DIR" ]; then
            info "移除旧 ccprivate（无 remote 或非 git 仓库）"
            rm -rf "$CCPRIVATE_DIR"
        fi
        section "克隆 ccprivate"
        gh repo clone "$GH_USER/ccprivate" "$CCPRIVATE_DIR"
    fi
    git -C "$CCPRIVATE_DIR" remote set-url origin "git@github.com:$GH_USER/ccprivate.git" 2>/dev/null || true

    section "建立符号链接"
    bash "$CCPRIVATE_DIR/setup.sh"

    ok "ccprivate 就绪"
    echo ""
    echo -e "  ${YELLOW}⚠️  下一步必须先 cd 到 ccconfig 目录${NC}"
    echo -e "    ${GREEN}cd $CCCONFIG_DIR && bash init.sh all${NC}"
    echo -e "  ${GRAY}(5 步: Ubuntu → LLM → MCP → Skills → 验证)${NC}"
}

# ── 入口 ──
case "${1:-}" in
    --clone|-c)
        do_clone
        ;;
    --update|-u)
        do_update
        ;;
    *)
        do_create
        ;;
esac
