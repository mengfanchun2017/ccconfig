#!/bin/bash
# init-bootstrap.sh — ccconfig 新机器起步：gh auth + ccprivate 一体化
#
# 合并 bootstrap-gh-auth.sh（装 gh + GitHub 认证 + git 身份）
# 和 init-ccprivate-repo.sh（创建 ccprivate 私有配置仓库 + 符号链接）
# 为一个脚本，PAT 认证一次，ccprivate 操作复用同一认证。
#
# 用法：
#   bash init-bootstrap.sh                   # 交互式新建（默认）
#   bash init-bootstrap.sh --clone           # 克隆已有 ccprivate
#   bash init-bootstrap.sh --non-interactive # CI 模式（env 旁路所有 read）
#   bash init-bootstrap.sh --dry-run         # 预览
#
# 输出：~/git/ccprivate/ + 符号链接已建立
# 全链：init-bootstrap → init-base.sh all → init-option（可选）→ maintain.sh（1A 全量检查）
#
# 环境变量：
#   GH_TOKEN                    GitHub PAT（跳过 gh auth 交互）
#   CCP_NONINTERACTIVE=1        非交互模式
#   CCP_GH_USER                 GitHub 用户名
#   CCP_GIT_EMAIL               Git 邮箱
#   CCP_DEFAULT_LLM             deepseek | minimax | claude
#   CCP_LLM_DEEPSEEK_KEY        DeepSeek API key
#   CCP_LLM_MINIMAX_KEY         MiniMax API key
#   CCP_SKIP_FEISHU=1           跳过飞书占位符引导

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$SCRIPT_DIR"
CCPRIVATE_DIR="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
LOCAL_BIN="$HOME/.local/bin"
export PATH="$LOCAL_BIN:$PATH"

source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/interact.sh"
source "$SCRIPT_DIR/lib/dry-run.sh"

NONINTERACTIVE=false
[[ "${CCP_NONINTERACTIVE:-}" == "1" ]] && NONINTERACTIVE=true
CLONE_MODE=false
DRY_RUN=false

# ── 标题 ──
banner() {
    echo ""
    echo -e "${CYAN}ccconfig 起步 — gh auth + ccprivate 一体化${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
}

# ============================================================
# 模块 1: 装 gh
# ============================================================
install_gh() {
    if command -v gh &>/dev/null; then
        ok "gh 已装: $(gh --version | head -1)"
        return 0
    fi

    warn "gh 命令未找到，binary 安装到 ~/.local/bin/gh"

    local gh_ver
    gh_ver=$(CCCONFIG_DIR="$CCCONFIG_DIR" python3 -c '
import json, os
try:
    p = os.path.join(os.environ["CCCONFIG_DIR"], "conf", "versions.json")
    print(json.load(open(p)).get("components", {}).get("gh", {}).get("version", "2.97.0"))
except Exception:
    print("2.97.0")
' 2>/dev/null || echo "2.97.0")
    mkdir -p "$LOCAL_BIN"
    local tmp="/tmp/gh-install-$$"
    mkdir -p "$tmp"
    curl -fsSL "https://github.com/cli/cli/releases/download/v${gh_ver}/gh_${gh_ver}_linux_amd64.tar.gz" \
        -o "$tmp/gh.tar.gz" || { err "下载失败（GitHub 可能被墙，设 http_proxy 重试）"; rm -rf "$tmp"; return 1; }
    tar -xzf "$tmp/gh.tar.gz" -C "$tmp"
    mv "$tmp/gh_${gh_ver}_linux_amd64/bin/gh" "$LOCAL_BIN/gh"
    chmod +x "$LOCAL_BIN/gh"
    rm -rf "$tmp"

    if command -v gh &>/dev/null; then
        ok "gh 已装: $(gh --version | head -1)"
        return 0
    fi
    err "gh 安装后 PATH 找不到"
    return 1
}

# ============================================================
# 模块 2: GitHub 认证（一次 PAT，全部复用）
# ============================================================
gh_auth() {
    # 已登录 → 跳过
    if gh auth status &>/dev/null; then
        info "GitHub: ${GREEN}已登录${NC} ($(gh api user --jq '.login' 2>/dev/null))"
        return 0
    fi

    # GH_TOKEN 环境变量
    local env_token=""
    if [[ -n "${GH_TOKEN:-}" ]]; then
        env_token="$GH_TOKEN"
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        env_token="$GITHUB_TOKEN"
    fi
    if [[ -n "$env_token" ]]; then
        info "检测到 \$GH_TOKEN/\$GITHUB_TOKEN，自动登录"
        printf '%s' "$env_token" | gh auth login --hostname github.com --with-token >/dev/null 2>&1 || true
        if gh auth status &>/dev/null; then
            ok "GitHub 认证完成（env token）: $(gh api user --jq '.login' 2>/dev/null)"
            return 0
        fi
        warn "env token 注入失败"
        if $NONINTERACTIVE; then
            err "非交互模式且 env token 失败，终止"
            return 1
        fi
    fi

    # SSH key 已存在 → 跳过 gh 认证（git 走 SSH）
    if [[ -f "$HOME/.ssh/id_ed25519" ]] || [[ -f "$HOME/.ssh/id_rsa" ]]; then
        if $NONINTERACTIVE; then
            info "SSH key 已存在，跳过 gh 认证"
            return 0
        fi
        warn "gh 未登录，但 SSH key 已存在"
        if confirm "SSH 已够用，跳过 gh 登录？" y; then
            return 0
        fi
    fi

    if $NONINTERACTIVE; then
        err "非交互模式：gh 未登录且 GH_TOKEN 未设"
        return 1
    fi

    # 交互：PAT 或 Web OAuth
    local method
    method=$(menu_select "认证方式" "PAT 粘贴" "Web OAuth")
    case "$method" in
        2)
            gh auth login --web --git-protocol https --hostname github.com || true
            ;;
        0)
            err "跳过 GitHub 认证"
            return 1
            ;;
        *)
            echo ""
            echo "  浏览器打开（Fine-grained PAT）:"
            echo -e "    ${BOLD}https://github.com/settings/personal-access-tokens/new${NC}"
            echo ""
            echo "  按以下填："
            echo "    Token name        : ccconfig-push"
            echo "    Expiration        : No expiration（推荐；GitHub 过期前会邮件提醒）"
            echo "    Repository access : All repositories"
            echo "    Repository permissions →"
            echo "      Contents  : Read and write  ☑"
            echo "      Metadata  : Read-only       ☑"
            echo "    Account permissions : 全部 No access"
            echo ""
            echo -e "  ${GRAY}Token 仅存本地 ~/.config/gh/hosts.yml（600），不同步 ccprivate${NC}"
            echo ""
            local token
            token=$(prompt_key "PAT（粘贴，输入后显示末 4 位）")
            if [[ -z "$token" ]]; then
                err "Token 为空"
                return 1
            fi
            token=$(printf '%s' "$token" | tr -d '\r\n')
            echo "$token" | gh auth login --hostname github.com --with-token || true
            ;;
    esac

    if gh auth status &>/dev/null; then
        ok "GitHub 认证完成: $(gh api user --jq '.login' 2>/dev/null)"
        return 0
    fi
    err "GitHub 认证失败"
    return 1
}

# ============================================================
# 模块 3: git 身份 + credential helper
# ============================================================
setup_git_ident() {
    local cur_name cur_email
    cur_name=$(git config --global user.name 2>/dev/null || echo "")
    cur_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -n "$cur_name" && -n "$cur_email" ]]; then
        info "Git 身份: ${GREEN}$cur_name <$cur_email>${NC}（global）"
        return 0
    fi

    # 从 gh api 取
    if gh auth status &>/dev/null; then
        local gh_email gh_name
        gh_email=$(gh api user --jq '.email // empty' 2>/dev/null)
        gh_name=$(gh api user --jq '.name // .login' 2>/dev/null)
        [[ -n "$gh_email" ]] && git config --global user.email "$gh_email"
        [[ -n "$gh_name" ]]  && git config --global user.name  "$gh_name"
        if [[ -n "$(git config --global user.name)" && -n "$(git config --global user.email)" ]]; then
            ok "Git 身份: $(git config --global user.name) <$(git config --global user.email)>"
            return 0
        fi
    fi

    # 非交互模式 → 报错
    if $NONINTERACTIVE; then
        err "git 身份缺失（设 CCP_GH_USER + CCP_GIT_EMAIL，或 git config --global user.{name,email}）"
        return 1
    fi

    [[ -z "$cur_name" ]] && cur_name=$(prompt "Git user.name（GitHub 用户名）")
    [[ -z "$cur_email" ]] && cur_email=$(prompt "Git user.email（GitHub 注册邮箱）")
    [[ -z "$cur_name" ]] && { err "user.name 不能为空"; return 1; }
    [[ -z "$cur_email" ]] && { err "user.email 不能为空"; return 1; }
    git config --global user.name "$cur_name"
    git config --global user.email "$cur_email"
    ok "Git 身份已设: $cur_name <$cur_email>"

    # 配 credential helper
    gh auth setup-git >/dev/null 2>&1 || true
    ok "git credential helper → gh"
}

# ============================================================
# 模块 4: 收集用户信息（LLM key 等）
# ============================================================
detect_gh_user() {
    gh api user --jq '.login' 2>/dev/null || echo ""
}

detect_git_email() {
    local e
    e=$(git config --global user.email 2>/dev/null || echo "")
    [[ -n "$e" ]] && echo "$e" && return
    gh api user --jq '.email' 2>/dev/null || echo ""
}

probe_repo() {
    local err_out
    err_out=$(gh repo view "$1" 2>&1 >/dev/null)
    if [[ $? -eq 0 ]]; then
        return 0
    fi
    grep -qiE 'Could not resolve to a Repository|HTTP 404|Not Found|repository not found' <<<"$err_out" && return 1
    return 2
}

collect_info() {
    section "GitHub 信息"

    GH_USER="${CCP_GH_USER:-$(detect_gh_user)}"
    if [[ -n "$GH_USER" ]]; then
        info "GitHub 账号: ${GREEN}$GH_USER${NC}"
    elif $NONINTERACTIVE; then
        err "GH_USER 缺失（设 CCP_GH_USER 或保持 gh 已登录）"
        return 1
    else
        while [[ -z "$GH_USER" ]]; do
            GH_USER=$(prompt "GitHub 用户名")
            [[ -z "$GH_USER" ]] && err "不能为空"
        done
    fi

    GIT_EMAIL="${CCP_GIT_EMAIL:-$(detect_git_email)}"
    if [[ -n "$GIT_EMAIL" ]]; then
        info "Git 邮箱: ${GREEN}$GIT_EMAIL${NC}"
    elif $NONINTERACTIVE; then
        err "GIT_EMAIL 缺失（设 CCP_GIT_EMAIL 或 git config --global user.email）"
        return 1
    else
        while [[ -z "$GIT_EMAIL" ]]; do
            GIT_EMAIL=$(prompt "Git 邮箱")
            [[ -z "$GIT_EMAIL" ]] && err "不能为空"
        done
    fi

    section "LLM API Key（至少填一个）"

    DEEPSEEK_KEY="${CCP_LLM_DEEPSEEK_KEY:-}"
    MINIMAX_KEY="${CCP_LLM_MINIMAX_KEY:-}"

    if $NONINTERACTIVE; then
        case "${CCP_DEFAULT_LLM:-deepseek}" in
            deepseek|1) DEFAULT_LLM=deepseek ;;
            minimax|2)  DEFAULT_LLM=minimax ;;
            *) err "CCP_DEFAULT_LLM 必须是 deepseek|minimax"; return 1 ;;
        esac
        info "默认 LLM: ${GREEN}$DEFAULT_LLM${NC}"
        local key_var="${DEFAULT_LLM}_KEY"
        local key_name="${DEFAULT_LLM^^}_KEY"
        if [[ -z "${!key_var}" ]]; then
            err "DEFAULT_LLM=$DEFAULT_LLM 但 CCP_${key_name} 未设"
            return 1
        fi
    else
        local llm_choice
        llm_choice=$(menu_select "默认 LLM" "DeepSeek" "MiniMax")
        case "$llm_choice" in
            1) DEFAULT_LLM=deepseek; [[ -z "$DEEPSEEK_KEY" ]] && DEEPSEEK_KEY=$(prompt_key "DeepSeek API Key") ;;
            2) DEFAULT_LLM=minimax;  [[ -z "$MINIMAX_KEY" ]] && MINIMAX_KEY=$(prompt_key "MiniMax API Key") ;;
            0) warn "取消 LLM 选择"; DEFAULT_LLM="${DEFAULT_LLM:-deepseek}" ;;
        esac

        # 收集其他 LLM key（可选）
        [[ "$llm_choice" != "1" && -z "$DEEPSEEK_KEY" ]] && DEEPSEEK_KEY=$(prompt "DeepSeek Key？(回车跳过)")
        [[ "$llm_choice" != "2" && -z "$MINIMAX_KEY" ]]  && MINIMAX_KEY=$(prompt "MiniMax Key？(回车跳过)")
    fi

    export GH_USER GIT_EMAIL DEFAULT_LLM DEEPSEEK_KEY MINIMAX_KEY
}

# ============================================================
# 模块 5: 生成 ccprivate 配置文件
# ============================================================
gen_llm_json() {
    local f="$CCPRIVATE_DIR/conf/llm.json"
    DEEPSEEK_KEY="${DEEPSEEK_KEY:-}" MINIMAX_KEY="${MINIMAX_KEY:-}" \
    DEFAULT_LLM="$DEFAULT_LLM" OUT="$f" python3 << 'PYEOF'
import json, os
llms = {}
for k, v in [("deepseek","DEEPSEEK_KEY"),("minimax","MINIMAX_KEY")]:
    key = os.environ.get(v, "")
    if not key:
        continue
    if k == "deepseek":
        llms[k] = {"name":"DeepSeek","base_url":"https://api.deepseek.com/anthropic","model":"deepseek-v4-pro","key":key,"small_model":"deepseek-v4-pro"}
    elif k == "minimax":
        llms[k] = {"name":"MiniMax","base_url":"https://api.minimaxi.com/anthropic","model":"MiniMax-M3","key":key,"small_model":"MiniMax-M3"}
d = {"llms": llms, "current": os.environ["DEFAULT_LLM"]}
with open(os.environ["OUT"], "w") as fh:
    json.dump(d, fh, indent=4, ensure_ascii=False)
    fh.write("\n")
PYEOF
    ok "conf/llm.json"
}

gen_mcp_servers_json() {
    local f="$CCPRIVATE_DIR/conf/mcp-servers.json"
    local template="$CCCONFIG_DIR/conf/mcp-servers.json.example"
    if [[ -f "$template" ]]; then
        cp "$template" "$f"
    else
        python3 -c "import json; d={'env':{'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC':'1'},'mcp_servers':[]}; json.dump(d,open('$f','w'),indent=2); print('')"
    fi
    ok "conf/mcp-servers.json（模板，Key 占位，稍后用 init-mcp.sh keys 填写）"
}

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
- 配置维护 → `cd ${CCCONFIG_HOME:-~/git/ccconfig} && claude`
- 项目开发 → `cd ~/git/<project> && claude`
EOF
    ok "link/CLAUDE.md"
}

gen_settings_json() {
    cat > "$CCPRIVATE_DIR/link/settings.json" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Edit(**/*)",
      "Read(**/*)",
      "WebSearch",
      "WebFetch",
      "Skill(*)",
      "Agent"
    ],
    "defaultMode": "auto"
  }
}
EOF
    ok "link/settings.json"
}

gen_dot_config_json() {
    echo "{}" > "$CCPRIVATE_DIR/link/.config.json"
    ok "link/.config.json"
}

gen_setup_sh() {
    cat > "$CCPRIVATE_DIR/setup.sh" << 'SETUPEOF'
#!/bin/bash
# ccprivate — 私有配置注入脚本
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="${CCCONFIG_DIR:-$HOME/git/ccconfig}"
CLAUDE_DIR="$HOME/.claude"
source "$CCCONFIG_DIR/lib/colors.sh" 2>/dev/null || {
    GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; YELLOW='\033[0;33m'; NC='\033[0m'
    section(){ echo -e "\n${CYAN}=== $1 ===${NC}"; }
    info(){ echo -e "${BLUE}ℹ️  $1${NC}"; }
    ok(){ echo -e "${GREEN}✅ $1${NC}"; }
    warn(){ echo -e "${YELLOW}⚠️  $1${NC}"; }
}
setup_link() {
    local link="$1" target="$2" label="$3"
    mkdir -p "$(dirname "$link")"
    if [ -L "$link" ]; then
        local existing expected
        existing=$(readlink -f "$link" 2>/dev/null || true)
        expected=$(readlink -f "$target" 2>/dev/null || true)
        if [ "$existing" = "$expected" ] && [ -n "$existing" ]; then
            info "$label: 已链接"
            return 0
        fi
        rm -f "$link"
    elif [ -e "$link" ]; then
        rm -rf "$link"
    fi
    ln -s "$target" "$link"
    ok "$label"
}
section "用户级链接"
setup_link "$HOME/CLAUDE.md"           "$SCRIPT_DIR/link/CLAUDE.md"     "~/CLAUDE.md"
setup_link "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/link/settings.json" "~/.claude/settings.json"
setup_link "$CLAUDE_DIR/.config.json"  "$SCRIPT_DIR/link/.config.json"  "~/.claude/.config.json"
setup_link "$HOME/.lark-default-account" "$SCRIPT_DIR/link/.lark-default-account" ".lark-default-account"
setup_link "$CLAUDE_DIR/.claudeignore"  "$SCRIPT_DIR/link/.claudeignore"  "~/.claude/.claudeignore"
setup_link "$CLAUDE_DIR/commands/should-compact.md" "$CCCONFIG_DIR/commands/should-compact.md" "~/.claude/commands/should-compact.md"
setup_link "$HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json" "$SCRIPT_DIR/conf/llmswitch.json" "llmswitch.json"
mkdir -p "$SCRIPT_DIR/skill-local"
[ -f "$SCRIPT_DIR/skill-local/.gitkeep" ] || touch "$SCRIPT_DIR/skill-local/.gitkeep"
section "用户级记忆"
_cconfig_id="$(echo "$HOME/git/ccconfig" | tr '/' '-')"
mkdir -p "$SCRIPT_DIR/link/memory"
[ -f "$SCRIPT_DIR/link/memory/.gitkeep" ] || touch "$SCRIPT_DIR/link/memory/.gitkeep"
setup_link "$CLAUDE_DIR/projects/$_cconfig_id/memory" "$SCRIPT_DIR/link/memory" "memory → ccprivate/link/memory"
unset _cconfig_id
section "运行时链接"
[ -d "$SCRIPT_DIR/rules" ] && setup_link "$CLAUDE_DIR/rules" "$SCRIPT_DIR/rules" "rules → ccprivate/rules"
[ -d "$SCRIPT_DIR/agents" ] && setup_link "$CLAUDE_DIR/agents" "$SCRIPT_DIR/agents" "agents → ccprivate/agents"
[ -d "$SCRIPT_DIR/commands" ] && setup_link "$CLAUDE_DIR/commands" "$SCRIPT_DIR/commands" "commands → ccprivate/commands"
section "ccconfig 公开链接"
[ -x "$CCCONFIG_DIR/lib/setup-links.sh" ] && bash "$CCCONFIG_DIR/lib/setup-links.sh" || warn "ccconfig/lib/setup-links.sh 不存在"
echo ""
ok "ccprivate setup 完成"
SETUPEOF
    chmod +x "$CCPRIVATE_DIR/setup.sh"
    ok "setup.sh"
}

# ============================================================
# 模块 6: 飞书配置引导
# ============================================================
prompt_feishu_config() {
    local f="$CCPRIVATE_DIR/conf/feishu.json"
    [[ -f "$f" ]] || return 0
    if $NONINTERACTIVE || [[ "${CCP_SKIP_FEISHU:-}" == "1" ]]; then
        info "跳过飞书占位符引导（稍后 vim $f）"
        return 0
    fi
    grep -qE '请填入|your-app-name|你的应用' "$f" 2>/dev/null || return 0

    warn "conf/feishu.json 还是模板（含占位符）"
    local choice
    choice=$(menu_select "配置飞书" "现在配置" "跳过")
    [[ "$choice" != "1" ]] && { info "跳过。后续: vim $f"; return 0; }

    echo ""
    info "在 https://open.feishu.cn/app 创建企业自建应用"
    local app_id app_secret app_name
    while [[ -z "$app_id" ]]; do app_id=$(prompt "App ID (cli_xxxxx)"); done
    read -r -s -p "  App Secret: " app_secret; echo ""
    app_name=$(prompt "应用名称" "default")
    app_name="${app_name:-default}"

    APP_ID="$app_id" APP_SECRET="$app_secret" APP_NAME="$app_name" FILE="$f" python3 << 'PYEOF'
import json, os
with open(os.environ["FILE"]) as fh: d = json.load(fh)
apps = d.get("apps", [{}])
apps[0]["name"] = os.environ.get("APP_NAME","default")
apps[0]["appId"] = os.environ["APP_ID"]
apps[0]["appSecret"] = os.environ["APP_SECRET"]
apps[0]["description"] = apps[0].get("description","filled by init-bootstrap")
apps[0]["brand"] = "feishu"
apps[0]["workDir"] = os.path.expanduser("~/git")
apps[0]["claudeConfigDir"] = os.path.expanduser("~/.claude")
apps[0].setdefault("larkCli", {"enabled":True,"configDir":"~/.lark-cli","description":""})
apps[0]["larkCli"]["enabled"] = True
d["apps"] = apps
with open(os.environ["FILE"],"w") as fh: json.dump(d,fh,indent=2,ensure_ascii=False); fh.write("\n")
PYEOF
    ok "conf/feishu.json 已填好"
}

# ============================================================
# 模块 7: 创建 GitHub 私有仓库 + push
# ============================================================
create_and_push() {
    section "推送到 GitHub 私有仓库"
    pushd "$CCPRIVATE_DIR" >/dev/null || return 1

    local _rc=0 _repo_found=false

    if git remote get-url origin &>/dev/null; then
        info "remote 已存在，跳过创建"
    elif ! gh auth status &>/dev/null 2>&1; then
        warn "gh 未认证，无法自动创建仓库"
        info "  手动建仓: https://github.com/new?name=ccprivate&visibility=private"
        info "  git remote add origin git@github.com:$GH_USER/ccprivate.git"
        _rc=1
    else
        probe_repo "$GH_USER/ccprivate"; local _p=$?
        if [[ $_p -eq 0 ]]; then
            _repo_found=true
        elif git ls-remote "https://github.com/$GH_USER/ccprivate.git" &>/dev/null 2>&1; then
            info "git ls-remote 验证通过"
            _repo_found=true
        elif [[ $_p -eq 1 ]]; then
            warn "仓库 $GH_USER/ccprivate 不存在（404），需先在 GitHub 建仓"
            if confirm "仓库 $GH_USER/ccprivate 已创建？尝试 push 到远程？" y; then
                _repo_found=true
            fi
        else
            warn "仓库检测失败（网络瞬断或 API 阻断，非 404）"
            if confirm "仓库 $GH_USER/ccprivate 已创建？尝试 push 到远程？" y; then
                _repo_found=true
            fi
        fi
    fi

    if $_repo_found; then
        info "GitHub 仓库已存在: $GH_USER/ccprivate"
        git remote add origin "https://github.com/$GH_USER/ccprivate.git" 2>/dev/null || true
        git push -u origin main 2>&1 | tail -2
        ok "已推送"
    else
        err "GitHub 仓库 $GH_USER/ccprivate 不可达"
        err "  请手动建仓: https://github.com/new?name=ccprivate&visibility=private"
        err "  然后重跑: bash init-bootstrap.sh"
        _rc=1
    fi

    popd >/dev/null
    return $_rc
}

# ============================================================
# 模块 8: 创建 ccprivate（新建模式）
# ============================================================
do_create() {
    banner

    # 本地已有完整 ccprivate → 刷新
    if [[ -d "$CCPRIVATE_DIR/.git" ]]; then
        info "ccprivate 已存在，刷新符号链接"
        bash "$CCPRIVATE_DIR/setup.sh"
        return 0
    fi
    if [[ -d "$CCPRIVATE_DIR" ]] && [[ -n "$(ls -A "$CCPRIVATE_DIR" 2>/dev/null)" ]]; then
        err "$CCPRIVATE_DIR 非空但无 .git，请手动清理后重试"
        return 1
    fi

    # GitHub 已有 ccprivate → 引导 clone
    local gh_user
    gh_user=$(detect_gh_user)
    if [[ -n "$gh_user" ]]; then
        if gh repo view "$gh_user/ccprivate" &>/dev/null 2>&1; then
            info "GitHub 已有 ccprivate: $gh_user/ccprivate，直接 clone"
            do_clone
            return $?
        fi
        if git ls-remote "https://github.com/$gh_user/ccprivate.git" &>/dev/null 2>&1; then
            info "GitHub 已有 ccprivate（ls-remote 验证），直接 clone"
            do_clone
            return $?
        fi
    fi

    # 收集信息
    collect_info || return 1

    # 手动建仓引导：仅当 404（真不存在）才提示建仓，网络瞬断不误导
    if [[ -n "$GH_USER" ]]; then
        probe_repo "$GH_USER/ccprivate"; local _pr=$?
        if [[ $_pr -eq 2 ]]; then
            warn "$GH_USER/ccprivate 探测失败（网络瞬断或 API 阻断，非 404）"
            info "跳过建仓引导——若仓库已存在，push 阶段会重试"
        elif [[ $_pr -ne 0 ]]; then
            section "需要先建 GitHub 私有仓库"
            cat <<'EOF'
  打开: https://github.com/new?name=ccprivate&visibility=private&description=Personal+Claude+Code+config
  • Repository name : ccprivate
  • Description     : Personal Claude Code config
  • Visibility      : Private
  • ❌ 不要勾 Add README / .gitignore / license
  • 点 Create repository

  建好后按回车继续（或 Ctrl+C 取消）。
EOF
            read -p "建好了？按回车继续..." _ < /dev/tty || true

            local _repo_ok=false _pr2
            probe_repo "$GH_USER/ccprivate"; _pr2=$?
            if [[ $_pr2 -eq 0 ]]; then
                _repo_ok=true
            elif git ls-remote "https://github.com/$GH_USER/ccprivate.git" &>/dev/null 2>&1; then
                _repo_ok=true
            elif [[ $_pr2 -eq 1 ]]; then
                warn "仓库仍 404——确认已在 GitHub 建仓"
                confirm "仓库确实已创建？继续推送？" y && _repo_ok=true
            else
                warn "探测仍失败（网络瞬断），手动确认"
                confirm "仓库确实已创建？继续推送？" y && _repo_ok=true
            fi
            if ! $_repo_ok; then
                err "仓库未就绪，请确认 $GH_USER/ccprivate 存在后重跑"
                return 1
            fi
            ok "GitHub 仓库已就绪: $GH_USER/ccprivate"
        fi
    fi

    section "创建目录结构"
    mkdir -p "$CCPRIVATE_DIR/conf"
    mkdir -p "$CCPRIVATE_DIR/skill-config"
    mkdir -p "$CCPRIVATE_DIR/rules"
    mkdir -p "$CCPRIVATE_DIR/agents"
    mkdir -p "$CCPRIVATE_DIR/commands"
    mkdir -p "$CCPRIVATE_DIR/link/projects"
    mkdir -p "$CCPRIVATE_DIR/link/memory"
    touch "$CCPRIVATE_DIR/link/memory/.gitkeep"

    section "生成配置文件"
    gen_llm_json
    gen_mcp_servers_json
    gen_claude_md
    gen_settings_json
    gen_dot_config_json
    gen_setup_sh

    # 复制 .example 模板到 ccprivate（死模板/可选场景不注入新用户）
    for example in "$CCCONFIG_DIR"/conf/*.example; do
        [[ -f "$example" ]] || continue
        local name; name=$(basename "$example" .example)
        case "$name" in
            claude.json|ubuntu.json|supabase.json) continue ;;
        esac
        if [[ ! -f "$CCPRIVATE_DIR/conf/$name" ]]; then
            cp "$example" "$CCPRIVATE_DIR/conf/$name"
            if grep -qE '请填入|请替换|your.key|placeholder|changeme' "$CCPRIVATE_DIR/conf/$name" 2>/dev/null; then
                warn "conf/$name 含占位符，请编辑: vim $CCPRIVATE_DIR/conf/$name"
            else
                info "conf/$name (从模板复制)"
            fi
        fi
    done

    # 复制 agents 模板
    for example in "$CCCONFIG_DIR"/templates/agents/*.md.example; do
        [[ -f "$example" ]] || continue
        local base; base=$(basename "$example" .md.example)
        local target="$CCPRIVATE_DIR/agents/$base.md"
        [[ ! -f "$target" ]] && cp "$example" "$target" && info "agents/$base.md (从模板)"
    done

    prompt_feishu_config

    section "初始化 Git"
    # 确保 git 身份已配
    setup_git_ident

    pushd "$CCPRIVATE_DIR" >/dev/null
    git init -b main
    git add -A
    git commit -m "init: ccprivate 个人配置

Co-Authored-By: Claude <noreply@anthropic.com>" 2>&1 | tail -1
    popd >/dev/null

    create_and_push || return 1

    section "建立符号链接"
    bash "$CCPRIVATE_DIR/setup.sh"

    echo ""
    ok "ccprivate 创建完成 🎉"
    echo ""
    echo -e "  ${GREEN}下一步:${NC} bash $CCCONFIG_DIR/init-base.sh all"
    echo -e "  ${GRAY}（Ubuntu 环境 → LLM 写入 → 收尾链接/服务，3 步）${NC}"
    echo -e "  ${GRAY}完成后: bash init-option.sh（可选装附加组件）→ bash maintain.sh（1A 全量检查）${NC}"
    echo ""
    echo -e "  ${CYAN}权限配置已写入 settings.json:${NC}"
    echo -e "    defaultMode=auto + allow 全工具（Bash/Edit/Read/Agent，spawn agent 跳分类器）"
    echo -e "  ${CYAN}bypass 模式:${NC} init-base.sh all 后终端输 ${GREEN}claudeby${NC} = claude --dangerously-skip-permissions"
    echo -e "    ${GRAY}日常用 claude（auto+allow 足够），需跳分类器/无人值守用 claudeby${NC}"
    echo ""
}

# ============================================================
# 模块 9: 克隆 ccprivate（克隆模式）
# ============================================================
do_clone() {
    banner

    GH_USER=$(detect_gh_user)
    if [[ -z "$GH_USER" ]]; then
        if $NONINTERACTIVE; then
            GH_USER="${CCP_GH_USER:-}"
            [[ -z "$GH_USER" ]] && { err "CCP_GH_USER 未设"; return 1; }
        else
            GH_USER=$(prompt "GitHub 用户名")
        fi
    fi

    if [[ -d "$CCPRIVATE_DIR/.git" ]] && git -C "$CCPRIVATE_DIR" remote get-url origin &>/dev/null; then
        info "ccprivate 已存在，拉取最新"
        git -C "$CCPRIVATE_DIR" pull origin main 2>&1 | tail -2
    else
        if [[ -d "$CCPRIVATE_DIR" ]]; then
            local bak="${CCPRIVATE_DIR}.bak.$(date +%s)"
            warn "旧 ccprivate 备份到 $bak 后重新 clone"
            mv "$CCPRIVATE_DIR" "$bak"
        fi
        section "克隆 ccprivate"
        gh repo clone "$GH_USER/ccprivate" "$CCPRIVATE_DIR"
    fi

    section "建立符号链接"
    bash "$CCPRIVATE_DIR/setup.sh"

    ok "ccprivate 就绪"
    echo ""
    echo -e "  ${GREEN}下一步:${NC} bash $CCCONFIG_DIR/init-base.sh all"
    echo -e "  ${GRAY}（Ubuntu 环境 → LLM 写入 → 收尾链接/服务，3 步）${NC}"
    echo -e "  ${GRAY}完成后: bash init-option.sh（可选装附加组件）→ bash maintain.sh（1A 全量检查）${NC}"
}

# ============================================================
# 模块 10: 更新 ccprivate
# ============================================================
do_update() {
    banner

    if [[ ! -d "$CCPRIVATE_DIR/.git" ]]; then
        err "$CCPRIVATE_DIR 不是 git 仓库，无法更新"
        err "  请先: bash init-bootstrap.sh --clone"
        return 1
    fi

    section "拉取最新 ccprivate"
    git -C "$CCPRIVATE_DIR" pull origin main 2>&1 | tail -3

    section "刷新生成配置"
    local llm_src="$CCPRIVATE_DIR/conf/llm.json"
    if [[ -f "$llm_src" ]]; then
        eval "$(LLM_SRC="$llm_src" python3 << 'PYEOF'
import json, os, shlex
d = json.load(open(os.environ["LLM_SRC"]))
llms = d.get("llms", {})
for k,v in [("deepseek","DEEPSEEK_KEY"),("minimax","MINIMAX_KEY"),("claude","CLAUDE_KEY")]:
    print(f'{v}={shlex.quote(llms.get(k,{}).get("key",""))}')
print(f'DEFAULT_LLM={shlex.quote(d.get("current","deepseek"))}')
PYEOF
        )"
        if [[ -n "$DEEPSEEK_KEY" || -n "$MINIMAX_KEY" || -n "$CLAUDE_KEY" ]]; then
            gen_llm_json
            gen_mcp_servers_json
        fi
    fi

    section "建立符号链接"
    bash "$CCPRIVATE_DIR/setup.sh"

    ok "ccprivate 更新完成"
}

# ============================================================
# 入口
# ============================================================
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # source 时不执行
    return 0
fi

# dry-run 处理
for arg in "$@"; do
    [[ "$arg" == "--dry-run" || "$arg" == "--preview" || "$arg" == "--what" ]] && DRY_RUN=true
done
if $DRY_RUN; then
    echo ""
    echo -e "${CYAN}init-bootstrap — DRY-RUN${NC}"
    echo -e "${CYAN}══════════════════════${NC}"
    echo ""
    echo "  1. 装 gh（如缺失）"
    echo "  2. GitHub 认证（PAT/Web OAuth）"
    echo "  3. 配置 git 身份 + credential helper"
    echo "  4. 创建 ~/git/ccprivate/ 目录结构 + 配置文件"
    echo "  5. 推送到 GitHub 私有仓库"
    echo "  6. 建立符号链接（setup.sh）"
    echo ""
    echo "  下一步: bash init-base.sh all → init-option（可选）→ maintain.sh（1A 全量检查）"
    echo ""
    echo "  === dry-run: no changes applied ==="
    exit 0
fi

# 非交互模式
if [[ "$*" =~ (--non-interactive|--ni|-y|--yes) ]]; then
    NONINTERACTIVE=true
fi
if [[ "$*" =~ --clone ]]; then
    CLONE_MODE=true
fi
if [[ "$*" =~ --update ]]; then
    do_update
    exit $?
fi

# 主流程
if $CLONE_MODE; then
    install_gh || exit 1
    gh_auth || exit 1
    do_clone
    exit $?
fi

install_gh || exit 1
gh_auth || exit 1
setup_git_ident
do_create