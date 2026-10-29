#!/bin/bash
# Claude Config - 状态检查
#
# 检查项（与下方 check_*() 调用顺序一致，勿凭印象写）：
# 1. 符号链接 + ccprivate 结构（check_symlinks / check_ccprivate_structure）
#    含 settings 分层双向检查：键放错文件（.config.json 里不生效）+ 基线键缺失
# 2. 核心依赖（check_deps_quick）
# 3. auto-sync 状态（check_autosync）
# 4. GitHub PAT 有效期（check_pat_expiry）
# 5. Git 项目状态 + MEMORY + 最后推送（check_repos）
# 6. 飞书 lark-cli 状态（check_feishu）
# --quick 到此为止，以下仅完整模式 --
# 7. MCP 服务器状态（check_mcp）
# 8. option-* 可选组件，含 SSH/Tailscale（check_option_components）
# 9. Skills 安装/断链（check_skills）
# 10. Example 模板同步（check_example_sync）
#
# 用途：通过 SessionStart hook 在 Claude 启动时运行

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/dry-run.sh"
source "$SCRIPT_DIR/path-helper.sh"
source "$SCRIPT_DIR/git-pull.sh"
REPO_DIR="$CCCONFIG_ROOT"

# --quick: 跳过慢检查（MCP、option 组件、模板对比）
QUICK_MODE=false
[[ "${1:-}" == "--quick" ]] && QUICK_MODE=true

# ========== Git 拉取 ==========
git_pull() {
    if [ ! -d "$REPO_DIR/.git" ]; then
        return 0
    fi
    # 走单点实现（lib/git-pull.sh）：分支自适应 + 代理注入/剥死代理 + 冲突回滚。
    # 旧版写死 origin main，在 master 分支仓上会静默失败。
    local _b; _b=$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || echo main)
    if timeout 30 git -C "$REPO_DIR" fetch origin "$_b" 2>/dev/null; then
        local updates=$(git -C "$REPO_DIR" rev-list --count "HEAD..origin/$_b" 2>/dev/null || echo 0)
        if [ "$updates" -gt 0 ]; then
            echo -e "${CYAN}[Git]${NC} 发现 $updates 个更新，正在拉取..."
            # 失败必须处理：本函数由 SessionStart hook 自动跑，--rebase 撞冲突会
            # 把仓库留在中间态，而 2>/dev/null 让用户完全看不到发生了什么
            local _rc=0
            git_pull_repo "$REPO_DIR" --rebase --quiet 2>/dev/null || _rc=$?
            if [ "$_rc" -eq 2 ]; then
                echo -e "  ${YELLOW}⚠ 拉取冲突，已回滚到拉取前状态${NC}"
            elif [ "$_rc" -ne 0 ]; then
                echo -e "  ${YELLOW}⚠ 拉取失败${NC}"
            fi
            [ "$_rc" -ne 0 ] && echo -e "  ${GRAY}手动: cd $REPO_DIR && git pull --rebase origin $_b${NC}"
        fi
    fi
}

# ========== 1. 检查符号链接 ==========
check_symlinks() {
    echo -e "${CYAN}━━━ 配置文件链接━━━${NC}"

    local issues=0

    # 本机组 —— LLM 选择 / 会话配置 / context 策略，每机独立文件，
    # symlink 回 ccprivate 才是错的（A 机切换会 push 覆盖 B 机）
    local f
    for f in settings.json .config.json .claudeignore; do
        if [ -L "$HOME/.claude/$f" ]; then
            echo -e "  ${YELLOW}○${NC} $f（被 symlink 回 ccprivate，会跨机覆盖）"
            issues=$((issues + 1))
        elif [ -f "$HOME/.claude/$f" ]; then
            echo -e "  ${GREEN}✅${NC} $f（本机）"
        else
            echo -e "  ${RED}❌${NC} $f（缺失，跑 ccprivate/setup.sh）"
            issues=$((issues + 1))
        fi
    done

    # settings 类键必须待在 settings.json —— Claude Code 只把它当 settings 文件读，
    # .config.json 是全局配置/应用状态（官方称 ~/.claude.json），写在那里的
    # permissions/hooks/statusLine 等【完全不读】且静默失效。这条检查就是为了
    # 让这种"配了但没生效"能被看见。
    local misfiled
    misfiled=$(TPL="$CCCONFIG_ROOT/templates/settings.json.example" python3 - <<'PY' 2>/dev/null || true
import json, os
sf = os.path.expanduser("~/.claude/settings.json")
cf = os.path.expanduser("~/.claude/.config.json")
KEYS = {"permissions","hooks","statusLine","enabledPlugins","extraKnownMarketplaces",
        "skillOverrides","autoUpdatesChannel","effortLevel","skipWorkflowUsageWarning",
        "skipDangerousModePermissionPrompt","tui"}
try:
    cd = json.load(open(cf))
except Exception:
    cd = {}
misfiled = [k for k in KEYS if k in cd]

# 反向检查：模板里的基线键在 settings.json 里是否缺失。
# init-ubuntu.sh 的 setup_hook 与 init-llm.sh 都会先于 setup.sh 创建
# settings.json，老逻辑判"已存在即跳过" → permissions/statusLine 永不落盘，
# 而上面的错位检查照样报绿。这条让"配了但没配全"也能被看见。
missing = []
tpl_path = os.environ.get("TPL", "")

def missing_paths(sd, t, prefix=""):
    """下钻一层：permissions 顶层键常在（哪怕空壳），permissions.allow 缺失
    才是"白名单没生效"的真正症状。只比顶层会把这种情况误判为已就绪。"""
    out = []
    for k, v in t.items():
        if k not in sd:
            out.append(prefix + k)
        elif isinstance(v, dict) and isinstance(sd.get(k), dict):
            out.extend(missing_paths(sd[k], v, prefix + k + "."))
        elif isinstance(v, list) and k in ("allow", "deny", "ask") and isinstance(sd.get(k), list):
            if any(x not in sd[k] for x in v):
                out.append(prefix + k)
    return out

try:
    if os.path.isfile(tpl_path):
        t = json.load(open(tpl_path))
        with open(sf) as f:
            sd = json.load(f)
        missing = missing_paths(sd, t)
except Exception:
    pass

if misfiled:
    print("MISFILED:" + ",".join(sorted(misfiled)))
if missing:
    print("MISSING:" + ",".join(sorted(missing)))
PY
)
    local _mis="" _miss=""
    while IFS= read -r _line; do
        case "$_line" in
            MISFILED:*) _mis="${_line#MISFILED:}" ;;
            MISSING:*)  _miss="${_line#MISSING:}" ;;
        esac
    done <<< "$misfiled"
    unset _line

    if [ -n "$_mis" ]; then
        echo -e "  ${YELLOW}○${NC} settings 键放错文件（在 .config.json 里不生效）: $_mis"
        echo -e "  ${GRAY}    修复: bash maintain.sh fix${NC}"
        issues=$((issues + 1))
    fi
    if [ -n "$_miss" ]; then
        echo -e "  ${YELLOW}○${NC} settings.json 缺基线键: $_miss"
        echo -e "  ${GRAY}    （权限白名单/hook/状态栏没生效）修复: bash maintain.sh fix${NC}"
        issues=$((issues + 1))
    fi
    if [ -z "$_mis" ] && [ -z "$_miss" ]; then
        echo -e "  ${GREEN}✅${NC} settings 键都在 settings.json 且基线完整"
    fi

    # CLAUDE.md
    if [ -L "$HOME/CLAUDE.md" ] && [ -e "$HOME/CLAUDE.md" ]; then
        echo -e "  ${GREEN}✅${NC} CLAUDE.md"
    else
        echo -e "  ${RED}❌${NC} CLAUDE.md"
        issues=$((issues + 1))
    fi

    # MEMORY.md — 检查项目级 memory 基础设施
    # memory 内容由 Claude Code 自动管理，这里只检查 symlink 链路是否就绪
    # 实际链路（2026-10-27 核对 setup.sh）：ccprivate/link/memory →
    # ~/.claude/projects/<ccconfig-id>/memory，**不是** 整个 projects 目录。
    # 旧代码查 link/projects（v2 写法，早已不存在）→ 恒判失败，误导排查。
    local mem_ok=false
    local _cid; _cid="$(echo "$HOME/git/ccconfig" | tr '/' '-')"
    if [ -L "$HOME/.claude/projects/$_cid/memory" ] && [ -e "$HOME/.claude/projects/$_cid/memory" ]; then
        mem_ok=true
    elif [ -d "$CCPRIVATE_HOME/link/memory" ] && [ ! -d "$HOME/.claude/projects/$_cid/memory" ]; then
        # ccprivate 侧就绪，但 ~/.claude 侧链接未建（新装 / Claude 未运行过）
        mem_ok=true
    fi
    unset _cid
    if $mem_ok; then
        echo -e "  ${GREEN}✅${NC} MEMORY.md"
    else
        echo -e "  ${YELLOW}○${NC} MEMORY.md (ccprivate 未链接，run setup.sh)"
    fi

    # rules (条件规则)
    if [ -L "$HOME/.claude/rules" ] && [ -d "$HOME/.claude/rules" ]; then
        local rule_count=$(ls "$HOME/.claude/rules/"*.md 2>/dev/null | wc -l)
        # 预算检查：超限报 warning（手写数字必漂移，故实测）。单次调用取全部字段。
        local budget_line=""
        if [ -x "$CCCONFIG_ROOT/bin/check-context-budget.sh" ]; then
            local _bj
            _bj=$(bash "$CCCONFIG_ROOT/bin/check-context-budget.sh" --json 2>/dev/null || true)
            if [ -n "$_bj" ]; then
                read -r _b_ok _b_always _b_total < <(printf '%s' "$_bj" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(int(d['ok']), d['always_kb'], d['total_kb'])
" 2>/dev/null) || true
                if [ "${_b_ok:-0}" = "1" ]; then
                    budget_line=" ${GRAY}[${_b_always}/${_b_total}KB]${NC}"
                else
                    budget_line=" ${YELLOW}⚠ 预算超限${NC}"
                    issues=$((issues + 1))
                fi
            fi
        fi
        echo -e "  ${GREEN}✅${NC} rules ($rule_count 个)${budget_line}"
    else
        echo -e "  ${YELLOW}○${NC} rules (未链接)"
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        echo -e "  ${GREEN}配置链接就绪${NC}"
    else
        echo -e "  ${GRAY}自动修复 symlink 中 (ccprivate/setup.sh)...${NC}"
        local fixed=false
        if [ -x "$CCPRIVATE_HOME/setup.sh" ]; then
            if bash "$CCPRIVATE_HOME/setup.sh" 2>/dev/null; then
                echo -e "  ${GREEN}✅ symlink 已修复 (ccprivate/setup.sh)${NC}"
                fixed=true
            fi
        fi
        if ! $fixed && bash "$REPO_DIR/lib/setup-links.sh" 2>/dev/null; then
            echo -e "  ${GREEN}✅ 公开链接已修复 (setup-links.sh)${NC}"
        elif ! $fixed; then
            echo -e "  ${RED}❌ 自动修复失败${NC}"
            echo -e "  ${GRAY}手动: bash ${CCPRIVATE_HOME}/setup.sh${NC}"
        fi
    fi
}

# ========== 1b. ccprivate 结构 ==========
check_ccprivate_structure() {
    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
    echo -e "${CYAN}━━━ ccprivate 结构━━━${NC}"

    if [ ! -d "$ccpriv" ]; then
        echo -e "  ${RED}❌${NC} ccprivate 目录不存在: $ccpriv"
        echo -e "  ${GRAY}创建: bash ccconfig/init-bootstrap.sh${NC}"
        return
    fi

    local issues=0

    # --- .generated/ 残留 ---
    if [ -d "$ccpriv/conf/.generated" ] && [ -n "$(ls -A "$ccpriv/conf/.generated" 2>/dev/null)" ]; then
        local gen_count=$(ls "$ccpriv/conf/.generated/"*.json 2>/dev/null | wc -l)
        echo -e "  ${YELLOW}⚠${NC}  conf/.generated/ 残留 (${gen_count} 文件) — 需迁移到 conf/"
        issues=$((issues + 1))
    fi

    # --- 目录完整性 ---
    local expected_dirs=("rules" "agents" "commands" "bin")
    local missing_dirs=()
    for d in "${expected_dirs[@]}"; do
        [ -d "$ccpriv/$d" ] || missing_dirs+=("$d")
    done
    if [ ${#missing_dirs[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC}  缺少目录: ${missing_dirs[*]}"
        issues=$((issues + 1))
    fi

    # --- setup.sh 版本 ---
    if [ -f "$ccpriv/setup.sh" ]; then
        if grep -q 'shell_aliases' "$ccpriv/setup.sh" 2>/dev/null; then
            echo -e "  ${RED}❌${NC} setup.sh 为旧版 (v2) — 含 shell_aliases 引用"
            issues=$((issues + 1))
        elif grep -q 'link/projects' "$ccpriv/setup.sh" 2>/dev/null; then
            echo -e "  ${YELLOW}⚠${NC}  setup.sh 使用 link/projects/ 模式 (v2，与模板不同)"
            issues=$((issues + 1))
        fi
    else
        echo -e "  ${RED}❌${NC} setup.sh 缺失"
        issues=$((issues + 1))
    fi

    # --- link/ 内容 ---
    # 只查共享文件。本机三件套（settings.json/.config.json/.claudeignore）**不在本仓**：
    # 模板唯一真相源是 ccconfig/templates/*.example，setup.sh 直接从那里 cp 到 ~/.claude/。
    # 2026-10-27 起 link/*.example 副本已删 —— 此前本检查把那些副本当"必需"，
    # 而 ccprivate-upgrade 把同样的文件当"废弃副本"报警，两处口径直接矛盾（会反复报修不好）。
    local missing_links=()
    for f in "CLAUDE.md"; do
        [ -f "$ccpriv/link/$f" ] || missing_links+=("$f")
    done
    if [ ${#missing_links[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC}  link/ 缺少: ${missing_links[*]}"
        issues=$((issues + 1))
    fi
    # 反向检查：已废弃的模板副本若还在，提示清理（老机器升级后会残留）
    local stale_links=()
    for f in settings.json .config.json .claudeignore; do
        [ -f "$ccpriv/link/$f.example" ] && stale_links+=("$f.example")
    done
    if [ ${#stale_links[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC}  link/ 有已废弃模板副本: ${stale_links[*]}（bash maintain.sh fix 清理）"
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        echo -e "  ${GREEN}✅ ccprivate 结构正常${NC}"
    else
        echo -e "  ${GRAY}修复: bash maintain.sh fix${NC}"
    fi
}

# ========== 3. 检查 auto-sync ==========
check_autosync() {
    echo ""
    echo -e "${CYAN}━━━ auto-sync━━━${NC}"

    if [ -x "$REPO_DIR/lib/monitor.sh" ]; then
        bash "$REPO_DIR/lib/monitor.sh" status 2>/dev/null || true
    else
        echo -e "  ${RED}❌${NC} monitor.sh 不存在"
    fi
}

# ========== 3b. PAT 认证检查（on-failure 设计：失效才提示续期，不巡检过期天数） ==========
check_pat_expiry() {
    echo -e "${CYAN}━━━ GitHub PAT━━━${NC}"

    if ! gh auth status &>/dev/null 2>&1; then
        echo -e "  ${YELLOW}○${NC}  gh 未登录"
        return 0
    fi

    # 网络抖动会偶发 timeout（github.com 直连不稳定），重试 2 次避免误报失效
    local u="?"
    for _ in 1 2 3; do
        u=$(gh api user --jq '.login' 2>/dev/null) && break
        sleep 2
    done
    if [ -n "$u" ] && [ "$u" != "?" ]; then
        echo -e "  ${GREEN}✅${NC} 认证有效（$u）"
    else
        echo -e "  ${RED}❌${NC} 认证失效或网络不通"
        echo -e "  ${YELLOW}续期: bash ~/git/ccconfig/bin/refresh-gh-auth.sh${NC}"
    fi
}

# ========== 4+5+6. 仓库概况（合并最后推送 + MEMORY + Git 项目）==========
# auto-sync monitor 已提供 git dirty 信息，这里只补充 CLI 需要的信息
check_repos() {
    echo -e "${CYAN}━━━ 仓库━━━${NC}"

    # ccconfig 最后推送
    local log=$(git -C "$REPO_DIR" log -1 --format="%ci|%s" 2>/dev/null)
    if [ -n "$log" ]; then
        local date=$(echo "$log" | cut -d'|' -f1 | cut -d' ' -f1)
        local msg=$(echo "$log" | cut -d'|' -f2- | head -c 60)
        echo -e "  ${GRAY}ccconfig 最后推送: $date —${NC} $msg"
    fi

    local found=0
    for git_dir in "$HOME/git"/*/; do
        [ -d "${git_dir}.git" ] || continue
        local name=$(basename "$git_dir")
        [ "$name" = "ccprivate" ] && continue
        found=$((found + 1))

        local issues=""

        # CLAUDE.md 异常
        if [ -L "${git_dir}CLAUDE.md" ] && [ ! -e "${git_dir}CLAUDE.md" ]; then
            issues="${issues}CLAUDE.md断链 "
        fi

        # Memory 问题
        local rel_path="${git_dir#/}"
        rel_path="${rel_path%/}"
        local proj_id="-${rel_path//\//-}"
        local mem="$HOME/.claude/projects/$proj_id/memory"
        if [ -L "$mem" ] && [ ! -d "$mem" ]; then
            issues="${issues}memory断链 "
        elif [ -d "$mem" ] && [ ! -L "$mem" ]; then
            issues="${issues}memory应为symlink "
        fi


        if [ -n "$issues" ]; then
            echo -e "  ${YELLOW}⚠${NC} $name — $issues"
        fi
    done

    [ $found -eq 0 ] && echo -e "  ${GRAY}(~/git/ 下无项目)${NC}"

    # 账号一致性：三仓 remote 属主必须与当前 gh 账号一致。
    # 不一致时 pull/push 会用旧 remote + 旧 PAT，失败常被 || true 吞掉 →
    # 换账号后静默不同步（skill 仓的 remote 换址见 init-skill.sh ensure_claude_skills）。
    _acct=$(gh api user --jq '.login' 2>/dev/null || echo "")
    if [ -n "$_acct" ]; then
        for _r in ccconfig ccprivate skill; do
            _rd="$HOME/git/$_r"
            [ -d "$_rd/.git" ] || continue
            _ro=$(git -C "$_rd" remote get-url origin 2>/dev/null | sed 's#.*github.com[:/]##; s#/.*##')
            if [ -n "$_ro" ] && [ "$_ro" != "$_acct" ]; then
                echo -e "  ${YELLOW}⚠${NC} $_r remote 属主=$_ro ≠ 当前账号=$_acct（换账号残留）"
            fi
        done
        unset _r _rd _ro
    fi
    unset _acct

    # 双端同步状态（多终端自查的唯一入口）。
    # monitor 只在文件事件/心跳时收敛，本机不碰文件时用户无从知道"另一终端推到哪了" ——
    # 这是"看不出两边有没有收敛"的直接原因。此处 fetch 后显式列出 ahead/behind。
    # 只有慢速模式做 fetch：--quick 供 SessionStart 用，不能在这里引入网络等待。
    local _sync_shown=false
    local _s _sd _sb _ah _bh _dirty _line
    for _s in ccconfig ccprivate skill; do
        _sd="$HOME/git/$_s"
        [ -d "$_sd/.git" ] || continue
        _sb=$(git -C "$_sd" branch --show-current 2>/dev/null) || continue
        [ -n "$_sb" ] || continue

        local _ferr=""
        if ! $QUICK_MODE; then
            # 重试一次：monitor 正在同一仓库做 fetch/rebase，并发 fetch 会瞬时失败
            # （实测 ccconfig/ccprivate 各出现过一次，手动复跑即通）→ 单次失败不足以
            # 判定"对端不可达"，报出来只会变成假警报。
            local _fok=false _try
            for _try in 1 2; do
                if _ferr=$(timeout 30 git -C "$_sd" fetch origin "$_sb" 2>&1); then
                    _fok=true; break
                fi
                [ "$_try" -eq 1 ] && sleep 2
            done
            if ! $_fok; then
                $_sync_shown || { echo -e "  ${GRAY}双端同步:${NC}"; _sync_shown=true; }
                echo -e "    ${YELLOW}⚠${NC} $_s — fetch 失败两次（无法判断对端进展）"
                echo -e "      ${GRAY}$(printf '%s' "$_ferr" | tail -2 | tr '\n' ' ')${NC}"
                continue
            fi
        fi

        _ah=$(git -C "$_sd" rev-list --count "origin/$_sb..HEAD" 2>/dev/null || echo 0)
        _bh=$(git -C "$_sd" rev-list --count "HEAD..origin/$_sb" 2>/dev/null || echo 0)
        _dirty=$(git -C "$_sd" status --porcelain 2>/dev/null | wc -l)

        if [ "${_ah:-0}" -eq 0 ] && [ "${_bh:-0}" -eq 0 ] && [ "${_dirty:-0}" -eq 0 ]; then
            continue   # 三绿不占屏
        fi
        $_sync_shown || { echo -e "  ${GRAY}双端同步:${NC}"; _sync_shown=true; }
        _line="    "
        [ "${_ah:-0}" -gt 0 ] && _line="${_line}${YELLOW}未推 $_ah${NC} "
        [ "${_bh:-0}" -gt 0 ] && _line="${_line}${CYAN}落后 $_bh（其他终端）${NC} "
        [ "${_dirty:-0}" -gt 0 ] && _line="${_line}${YELLOW}工作区脏 $_dirty${NC} "
        echo -e "${_line}$_s"
    done
    # 全绿时也要有一行：什么都不显示会让人分不清"查过了没事"与"根本没查"，
    # 这正是用户"看不出两边有没有收敛"的一部分。--quick 不 fetch，故不显示该行。
    if ! $_sync_shown && ! $QUICK_MODE; then
        echo -e "  ${GRAY}双端同步:${NC} ${GREEN}✅${NC} 三仓均已同步（无未推 / 无落后 / 工作区干净）"
    fi
    unset _s _sd _sb _ah _bh _dirty _line

    # memory 概览（只算有 memory 的项目）
    local projects_dir="$HOME/.claude/projects"
    if [[ -d "$projects_dir" ]]; then
        local any=false
        for proj_dir in "$projects_dir"/*/; do
            [[ -d "$proj_dir" ]] || continue
            local pname=$(basename "$proj_dir")
            [[ "$pname" == *"--claude-worktrees-"* ]] && continue
            local mem_dir="${proj_dir}memory"
            if [[ -f "$mem_dir/MEMORY.md" ]]; then
                local count=$(ls -1 "$mem_dir"/*.md 2>/dev/null | grep -v MEMORY | wc -l)
                local display=$(echo "$pname" | sed 's/^-home-[^-]*-//' | tr '-' '/')
                [[ $any == false ]] && { echo -e "  ${GRAY}memory:${NC}"; any=true; }
                echo -e "    $display — ${count} 条"
            fi
        done
        $any || echo -e "  ${GRAY}memory: 无项目有记忆${NC}"
    fi
}


# ========== MCP 服务器状态 ==========
check_mcp() {
    local lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    bash "$lib_dir/mcp-manager.sh" status

    # ── getnote CLI 授权状态（2026-10 从 MCP 迁 CLI+Skill，单账号无切换）──
    local gn_init="$REPO_DIR/option-getnote/init.sh"
    if [ -f "$gn_init" ]; then
        local gn_line
        gn_line=$(bash "$gn_init" --status 2>/dev/null | head -1)
        case "$gn_line" in
            OK*)   echo -e "  getnote: ${GREEN}${gn_line#OK }${NC}" ;;
            WARN*) echo -e "  getnote: ${YELLOW}${gn_line#WARN }${NC}" ;;
            *)     echo -e "  getnote: ${YELLOW}${gn_line:-未安装}${NC}" ;;
        esac
    fi
}

# ========== 7. 飞书 lark-cli 状态（可选） ==========
check_feishu() {
    echo -e "${CYAN}━━━ 飞书 (lark-cli)━━━${NC}"

    export PATH="$HOME/.local/bin:$(find_node_bin):$PATH"

    # 当前账号
    local current_name=""
    local current_dir
    local marker_file="$HOME/.lark-cli-account"
    if [ -f "$marker_file" ]; then
        current_name=$(grep '^name=' "$marker_file" 2>/dev/null | cut -d'=' -f2)
        current_dir=$(grep '^configDir=' "$marker_file" 2>/dev/null | cut -d'=' -f2)
    fi
    current_dir="${current_dir:-${LARKSUITE_CLI_CONFIG_DIR:-$HOME/.lark-cli}}"
    current_dir="${current_dir/#\~/$HOME}"

    # 检查安装
    echo -n "  安装 ... "
    if command -v lark-cli &> /dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${GRAY}－${NC} (未安装)"
    fi

    # 当前账号别名
    if [ -n "$current_name" ]; then
        echo -e "  当前账号: ${GREEN}${current_name}${NC} ${GRAY}(${current_dir})${NC}"
    else
        echo -e "  当前账号: ${YELLOW}未匹配${NC} ${GRAY}(${current_dir})${NC}"
    fi

    # 检查配置（先设有效 config dir，避免默认目录误报未配置）
    local _lark_config_dir="${current_dir:-${LARKSUITE_CLI_CONFIG_DIR:-$HOME/.lark-cli}}"
    if command -v lark-cli &> /dev/null; then
        echo -n "  配置 ... "
        if LARKSUITE_CLI_CONFIG_DIR="$_lark_config_dir" lark-cli config show 2>/dev/null | grep -q "appId"; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${YELLOW}○${NC} 未配置"
        fi

        # 检查授权：config 里残留 users 字段 ≠ token 有效，须查 auth status 的 user.available
        echo -n "  授权 ... "
        local _auth_json
        _auth_json=$(LARKSUITE_CLI_CONFIG_DIR="$_lark_config_dir" lark-cli auth status 2>/dev/null || true)
        if echo "$_auth_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if d.get('identities', {}).get('user', {}).get('available') else 1)
" 2>/dev/null; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${YELLOW}○${NC} 未授权"
        fi
    fi

    # 列出所有已配置账号
    local feishu_json="$(resolve_conf feishu.json)"
    if [ -f "$feishu_json" ]; then
        local accounts_info
        accounts_info=$(python3 - "$feishu_json" "$current_name" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
current = sys.argv[2]
apps = data.get('apps', [])
if not apps:
    sys.exit(0)
for app in apps:
    lark = app.get('larkCli', {})
    if lark.get('enabled'):
        name = app.get('name', '?')
        marker = '▶' if name == current else ' '
        cfg = lark.get('configDir', '~/.lark-cli')
        print(f"    {marker} {name}  {cfg}")
PYEOF
        )
        if [ -n "$accounts_info" ]; then
            echo -e "  账号列表:"
            echo "$accounts_info"
        fi
    fi

    echo -e "  ${GRAY}切换账号: bash ccconfig/option-larkcli/lark-switch.sh <name>${NC}"

    # botmux 状态（飞书 ↔ AI 编程 CLI 桥）
    echo -n "  botmux ... "
    if command -v botmux &> /dev/null; then
        local _bm_line; _bm_line=$(bash "$REPO_DIR/option-botmux/init.sh" --status 2>/dev/null | head -1 | sed 's/\x1b\[[0-9;]*[mK]//g') || true
        case "$_bm_line" in
            OK*)   echo -e "${GREEN}✅${NC} ${_bm_line#OK }" ;;
            WARN*) echo -e "${YELLOW}○${NC} ${_bm_line#WARN }" ;;
            *)     echo -e "${GRAY}－${NC} 未安装" ;;
        esac
    else
        echo -e "${GRAY}－${NC} (未安装)"
    fi
    echo -e "  ${GRAY}配置: bash option-botmux/init.sh setup   启动: bash option-botmux/init.sh start${NC}"
    echo -e "  ${GRAY}飞书发消息无反馈: bash option-botmux/init.sh doctor  （status 只反映 daemon 存活，体检才查会话/队列）${NC}"
}

# ========== 2. 依赖检查 ==========
check_deps_quick() {
    echo -e "${CYAN}━━━ 核心依赖━━━${NC}"

    local deps_script="$REPO_DIR/lib/deps-check.sh"
    if [ -x "$deps_script" ]; then
        bash "$deps_script" --required 2>/dev/null || true
    else
        echo -e "  ${YELLOW}○${NC} deps-check.sh 不存在"
    fi
}

# ========== 10. option-* 可选组件（含远程连接） ==========
check_option_components() {
    echo ""
    echo -e "${CYAN}━━━ 可选组件━━━${NC}"
    echo ""

    local found=0
    local -a shown=()

    # --other-- 组 = 自动发现但没在别的分组里列过的 option；下面的 handled 复用
    # 这一份清单，避免两处各写一份排除名单、改一处忘另一处（曾导致 officecli/
    # remote/cloudflare/getnote 被 --other-- 排除、又漏在 handled 里 → 完全不显示；
    # 且 skill 同时出现在 --claude-- 和 --other-- → 重复显示）。
    local other_list=""
    other_list=$(ls -d "$REPO_DIR"/option-*/ 2>/dev/null | xargs -n1 basename 2>/dev/null \
        | sed 's/^option-//' \
        | grep -vE '^(larkcli|botmux|getnote|officecli|remote|cloudflare|skill)$' | tr '\n' ' ')

    # 分组：与 init-option.sh 保持一致
    local groups=(
        "--os--|bat glow nano"
        "--claude--|mcp skill"
        "--lark--|larkcli botmux"
        "--other--|${other_list}"
        "--key--|feishu_key"
    )

    # 自动发现 option-* 组件
    local auto_opts=()
    while IFS= read -r d; do
        local name="${d#option-}"
        auto_opts+=("$name")
    done < <(ls -d "$REPO_DIR"/option-*/ 2>/dev/null | xargs -n1 basename)

    for group_entry in "${groups[@]}"; do
        local group_title="${group_entry%%|*}"
        local group_items="${group_entry#*|}"
        [ -z "$group_items" ] && continue

        echo -e "  ${BOLD}${group_title}${NC}"

        for name in $group_items; do
            found=$((found + 1))
            shown+=("$name")
            icon="" detail=""
            _check_component "$name"
            _print_option "$name" "$icon" "$detail"

            if [ "$name" = "remote" ]; then
                local out; out=$(bash "$REPO_DIR/option-remote/init.sh" --status 2>&1) || true
                echo "$out" | sed 's/\x1b\[[0-9;]*[mK]//g' | grep -vE '^[[:space:]]*$' | tail -n +2 | while IFS= read -r sub; do
                    echo "      $sub"
                done
            fi
        done
    done

    # 自动发现的 option 不在分组中的也显示。
    # handled 必须覆盖**所有**已在上面分组里出现过的名字，否则会被这里再列一遍；
    # 反之若某个 option 被 --other-- 排除且不在 handled 里，就会一个都不显示。
    # 从"分组里实际列过的 shown"派生，而不是手写名单 —— 手写必然与分组漂移。
    local handled=" feishu_key " _s
    for _s in "${shown[@]}"; do handled+="$_s "; done
    for name in "${auto_opts[@]}"; do
        echo " $handled " | grep -q " $name " && continue
        # 分组里已列过的不再列：--other-- 组由同一份 ls 生成，此前 evalscope/llmswitch
        # 会在 --other-- 和这里各出现一次
        local _dup=false
        for _s in "${shown[@]}"; do [ "$_s" = "$name" ] && { _dup=true; break; }; done
        $_dup && continue
        found=$((found + 1))
        icon="" detail=""
        _check_component "$name"
        _print_option "$name" "$icon" "$detail"
    done

    if [ $found -eq 0 ]; then
        echo -e "  ${GRAY}(无可选组件)${NC}"
    fi
    echo ""
}

# 子函数：检测单个组件状态
_check_component() {
    local name="$1"
    case "$name" in
        mcp)
            local claude_json="$HOME/.claude/.config.json"
            if [ -f "$claude_json" ]; then
                local count=$(python3 -c "import json; d=json.load(open('$claude_json')); print(len(d.get('mcpServers',{})))" 2>/dev/null || echo "0")
                [ "$count" -gt 0 ] && { icon="ok"; detail="$count 个 MCP 服务器"; } || { icon="miss"; detail="MCP 未配置（bash lib/init-mcp.sh sync）"; }
            else
                icon="miss"; detail="mcp-servers.json 未找到"
            fi ;;
        botmux)
            # 飞书 ↔ AI 编程 CLI 桥（option-botmux/）。非交互安全：只读状态，不触发扫码
            local bm_init="$REPO_DIR/option-botmux/init.sh"
            if [ -f "$bm_init" ]; then
                local bm_line; bm_line=$(bash "$bm_init" --status 2>/dev/null | head -1 | sed 's/\x1b\[[0-9;]*[mK]//g') || true
                case "$bm_line" in
                    OK*)   icon="ok";   detail="${bm_line#OK }" ;;
                    WARN*) icon="warn"; detail="${bm_line#WARN }" ;;
                    *)     icon="miss"; detail="${bm_line#MISSING }" ;;
                esac
                # OK 只代表 daemon 活着。会话卡死（worker D 状态/pane 已死）时
                # status 仍报 OK，但飞书里零反馈 —— 补一句指向体检，别让人被误导。
                if [ "$icon" = "ok" ] && command -v botmux >/dev/null 2>&1; then
                    local _q=0 _f
                    for _f in "$HOME"/.botmux/data/queues/*.jsonl; do
                        [ -e "$_f" ] && _q=$((_q + $(wc -l < "$_f" 2>/dev/null || echo 0)))
                    done
                    if [ "$_q" -gt 0 ]; then
                        icon="warn"; detail="$detail（队列积压 ${_q} 条 → 跑 doctor）"
                    fi
                fi
            else icon="miss"; detail="option-botmux 缺失"; fi ;;
        feishu_key)
            local feishu_conf; feishu_conf=$(resolve_conf feishu.json 2>/dev/null) || { icon="miss"; detail="ccprivate/conf/feishu.json 不存在"; return; }
            local fk_out
            fk_out=$(python3 - "$feishu_conf" << 'PYEOF' 2>/dev/null
import json, sys
PLACEHOLDER = ['请填入','请到','请替换','your key','your_key','placeholder','changeme','<your-','your-app-name']
def is_ph(v):
    if not v or not isinstance(v, str): return True
    return any(p in v.lower() for p in PLACEHOLDER)
with open(sys.argv[1]) as f: d = json.load(f)
apps = d.get('apps', [])
ph_lc = [a['name'] for a in apps if a.get('larkCli',{}).get('enabled') and (is_ph(a.get('appId','')) or is_ph(a.get('appSecret','')))]
ph_unfilled = [a['name'] for a in apps if not a.get('appId') or not a.get('appSecret')]
if ph_lc: print("placeholder|larkcli:" + ",".join(ph_lc))
elif ph_unfilled: print("empty|" + ",".join(ph_unfilled))
else: print("ok|所有 appId/appSecret 已配置")
PYEOF
)
            icon="${fk_out%%|*}"; detail="${fk_out#*|}" ;;
        llmswitch)
            # 自包含组件：入口是 lib/init-llm.sh + lib/ensure-bridge.sh，本体是
            # option-llmswitch/openai_bridge.py，本来就没有 init.sh。
            # 此前落进下面的 *) 分支，被当成"init.sh 缺失"误报 ✗。
            # 运行时健康由 monitor.sh status 的 Bridge 行负责（这里不重复探网络）。
            [ -f "$REPO_DIR/option-llmswitch/openai_bridge.py" ] \
                && { icon="ok"; detail="自包含（bridge，入口 lib/init-llm.sh）"; } \
                || { icon="miss"; detail="option-llmswitch/openai_bridge.py 缺失"; } ;;
        bat)
            local ver=$(bat --version 2>/dev/null | head -1 || batcat --version 2>/dev/null | head -1 || echo "")
            [ -n "$ver" ] && { icon="ok"; detail="bat 已安装 ($ver)"; } || { icon="miss"; detail="bat 未安装"; } ;;
        glow)
            local ver=$(glow --version 2>/dev/null | head -1)
            [ -n "$ver" ] && { icon="ok"; detail="glow 已安装 ($ver)"; } || { icon="miss"; detail="glow 未安装"; } ;;
        nano)
            local ver=$(nano --version 2>/dev/null | head -1)
            [ -n "$ver" ] && { icon="ok"; detail="nano 已安装 ($ver)"; } || { icon="miss"; detail="nano 未安装"; } ;;
        *)
            local init_script="$REPO_DIR/option-$name/init.sh"
            if [ -f "$init_script" ]; then
                local out; out=$(bash "$init_script" --status 2>&1) || true
                local line; line=$(echo "$out" | sed 's/\x1b\[[0-9;]*[mK]//g' | grep -vE '^[[:space:]]*$' | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//') || true
                if echo "$line" | grep -qi "^OK"; then icon="ok"; detail="${line#OK }"
                elif echo "$line" | grep -qi "^WARN"; then icon="warn"; detail="${line#WARN }"
                elif echo "$line" | grep -qiE "^(MISSING|FAIL)"; then icon="miss"; detail="${line#MISSING }"; detail="${detail#FAIL }"
                else icon="?"; detail="$line"; fi
            elif [ -d "$REPO_DIR/option-$name" ]; then
                icon="miss"; detail="option-$name 目录存在但 init.sh 缺失"
            else
                icon="miss"; detail="option-$name 未安装（目录不存在）"
            fi ;;
    esac
}

_print_option() {
    local name="$1" icon="$2" detail="$3"
    printf "    %-12s " "$name"
    case "$icon" in
        ok)   echo -e "${GREEN}✅${NC} $detail" ;;
        warn) echo -e "${YELLOW}⚠${NC}  $detail" ;;
        miss|no_conf|empty) echo -e "${GRAY}✗${NC}  ${GRAY}$detail${NC}" ;;
        placeholder) echo -e "${YELLOW}⚠${NC}  ${GRAY}$detail${NC}" ;;
        *)    echo -e "${GRAY}?${NC}  $detail" ;;
    esac
}

# ========== 12. Skills 安装状态 ==========
check_skills() {
    echo -e "${CYAN}── Skills${NC}"

    local skills_dir="$HOME/.claude/skills"
    local skills_src="${SKILL_SRC:-$HOME/git/skill/plugins}"
    local ok=true

    if [[ -d "$skills_src" ]]; then
        local self_count=$(ls "$skills_src" 2>/dev/null | wc -l)
        echo -e "  自建: ${GREEN}${self_count}${NC} 个 (skill/plugins/)"
    else
        echo -e "  自建: ${YELLOW}未找到${NC} skill/plugins/"
        ok=false
    fi

    if [[ -d "$skills_dir" ]]; then
        # 视图条目来自三个源，必须分类显示才能与"自建 N 个"对上账：
        # 只报"已链接"会让总数（含 lark-* 第三方链接 + getnote 实体目录）对不上。
        local broken=0 linked=0 third=0 real=0 total=0 d target
        for d in "$skills_dir"/*; do
            [[ -e "$d" || -L "$d" ]] || continue
            total=$((total + 1))
            if [[ ! -L "$d" ]]; then
                real=$((real + 1))
            elif [[ ! -e "$d" ]]; then
                broken=$((broken + 1))
            else
                target=$(readlink -f "$d")
                case "$target" in
                    "$skills_src"/*) linked=$((linked + 1)) ;;
                    *)               third=$((third + 1)) ;;
                esac
            fi
        done
        echo -e "  视图: ${GREEN}${total}${NC} 个（本仓链接 ${linked} / 第三方链接 ${third} / 实体目录 ${real}）"
        if [[ $broken -gt 0 ]]; then
            echo -e "  ${RED}断链: ${broken}${NC} 个 → bash maintain.sh fix"
            ok=false
        fi
    else
        echo -e "  ${YELLOW}~/.claude/skills/ 不存在${NC} → bash init-skill.sh sync"
        ok=false
    fi

    local third_party="$CCCONFIG_ROOT/conf/third-party-skills.txt"
    if [[ -f "$third_party" ]]; then
        local tp_count=$(grep -cEv '^\s*(#|$)' "$third_party" 2>/dev/null || echo 0)
        echo -e "  第三方清单: ${tp_count} 个 (third-party-skills.txt)"
    fi

    $ok && echo -e "  ${GREEN}✓ Skills 正常${NC}"
}

# ========== 本机初始化代次（模板水位） ==========
# settings.json/.config.json/.claudeignore 是本机独立文件，模板更新后各机不会自动跟。
# 用 ~/.claude/.ccconfig-init 里记的 template_hash 与当前模板比，判断"这台机落后了"。
# version 字段（HEAD 短 sha）只用于把"哪次提交"打出来，不参与判定 —— 判定只看 hash。
check_init_watermark() {
    local marker="$HOME/.claude/.ccconfig-init"
    local tdir="$CCCONFIG_ROOT/templates"

    echo ""
    echo -e "${CYAN}━━━ 本机配置代次━━━${NC}"

    if [ ! -f "$marker" ]; then
        echo -e "  ${YELLOW}○${NC} 无代次标记（从未跑过 setup.sh）"
        echo -e "  ${GRAY}    修复: bash ~/git/ccprivate/setup.sh${NC}"
        return 0
    fi

    local rec_hash cur_hash rec_ver
    rec_hash=$(grep '^template_hash=' "$marker" 2>/dev/null | cut -d= -f2)
    rec_ver=$(grep '^version=' "$marker" 2>/dev/null | cut -d= -f2)
    if command -v sha256sum >/dev/null 2>&1 && [ -d "$tdir" ]; then
        cur_hash=$(cat "$tdir"/settings.json.example "$tdir"/.config.json.example 2>/dev/null | sha256sum | cut -c1-16)
    fi

    if [ -z "$rec_hash" ] || [ -z "$cur_hash" ]; then
        echo -e "  ${GRAY}○${NC} 对齐于提交 ${rec_ver:-unknown}（无法比对模板 hash）"
    elif [ "$rec_hash" = "$cur_hash" ]; then
        echo -e "  ${GREEN}✅${NC} 对齐于提交 ${rec_ver:-unknown}（模板一致）"
    else
        echo -e "  ${YELLOW}○${NC} 本机配置模板已过期（对齐于 ${rec_ver:-unknown}：本机 ${rec_hash} ≠ 当前 ${cur_hash}）"
        echo -e "  ${GRAY}    模板新键不会自动补 → 跑: bash ~/git/ccprivate/setup.sh（只补缺键，不覆盖已有）${NC}"
    fi
    return 0
}

# ========== Example 模板同步检查 ==========
check_example_sync() {
    local ccconfig_example="$CCCONFIG_ROOT/templates"
    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    echo ""
    echo -e "${CYAN}━━━ 模板同步━━━${NC}"

    # agents 检查：模板链已删（2026-10-27）。ccprivate/agents/ 现在是"直接维护"目录，
    # 不做模板 diff（无模板可比）。只报数量，避免静默空目录。
    local agents_count=0
    for f in "$ccpriv/agents/"*.md; do
        [ -f "$f" ] || continue
        agents_count=$((agents_count + 1))
    done
    if [ $agents_count -eq 0 ]; then
        echo -e "  agents: ${GRAY}空（agent 实体建议放 ~/git/skill plugin）${NC}"
    else
        echo -e "  agents: ${GRAY}${agents_count} 个（直接维护，无模板链）${NC}"
    fi

    # conf 新增模板检测
    local conf_new=0
    for example in "$CCCONFIG_ROOT"/conf/*.json.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .example)
        [ -f "$ccpriv/conf/$base" ] || conf_new=$((conf_new + 1))
    done
    [ $conf_new -gt 0 ] && echo -e "  conf: ${CYAN}${conf_new} 新模板${NC}（自 sync.sh 处理）"
    return 0
}

# ========== bridge 自愈（会话启动时自动恢复） ==========
# 有 systemd 服务时它本应已把 bridge 拉起（开机自启）；这里兜的是「服务没装/被停/起晚了」。
# 无 systemd 时退回 selfheal_bridge 直接拉起 + shell watchdog。
# 未用 bridge 的用户（settings.json 不含 127.0.0.1:8898）在 selfheal_bridge 内短路，零开销。
_bridge_cold_start() {
    local cfg
    cfg="$HOME/.cache/llm-merged.json"
    # 三层合并缓存可能未生成（冷启动），先生成再看
    [[ -f "$cfg" ]] || bash "$SCRIPT_DIR/init-llm.sh" merge >/dev/null 2>&1 || true
    [[ -f "$cfg" ]] || return 0

    # 优先交给 systemd 服务：它是唯一能跨重启存活的守护者。装/启是幂等的，
    # 服务已在跑时几乎零开销。失败（无 systemd）则往下走 shell 回退。
    if [[ -f "$SCRIPT_DIR/bridge-service.sh" ]]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/bridge-service.sh"
        if bridge_service_sync >/dev/null 2>&1; then
            # 服务接管后不必再起 shell watchdog；只在确实需要 bridge 时才提示不一致
            source "$SCRIPT_DIR/ensure-bridge.sh"
            bridge_state_check "$cfg" >/dev/null 2>&1 || \
                echo -e "  ${YELLOW}⚠${NC} bridge 运行态不一致 — 修: ${CYAN}bash maintain.sh fix${NC}"
            _tailscale_guard_report_line "$cfg"
            return 0
        fi
    fi

    source "$SCRIPT_DIR/ensure-bridge.sh"
    selfheal_bridge "$cfg" || true
    # 运行态一致性只报不修：SessionStart 该轻量，修走 `bash maintain.sh fix`
    if ! bridge_state_check "$cfg" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠${NC} bridge 运行态不一致（孤儿/未拉起/无守护）— 修: ${CYAN}bash maintain.sh fix${NC}"
    fi
    _tailscale_guard_report_line "$cfg"
}

# tailscale accept-routes 风险一行提示（只报不修：SessionStart 该轻量）。
# 仅当「tailscale 在跑 + accept-routes=true + upstream 是内网型」才提示 —— 其余静默，
# 避免每次会话启动都刷一行无关内容。
_tailscale_guard_report_line() {
    local cfg="${1:-$HOME/.cache/llm-merged.json}"
    [[ -f "$SCRIPT_DIR/tailscale-guard.sh" ]] || return 0
    source "$SCRIPT_DIR/tailscale-guard.sh"
    tailscale_available || return 0
    _tailscale_accept_routes || return 0        # 已关，无需提示
    local url="" hh=""
    if [[ -f "$HOME/.claude/llm-current" && -f "$cfg" ]]; then
        IFS=$'\t' read -r url hh < <(python3 -c "
import json
try:
    d=json.load(open('$cfg')); p=open('$HOME/.claude/llm-current').read().strip()
    l=d.get('llms',{}).get(p,{})
    print((l.get('base_url','') or '')+'\t'+(l.get('host_header','') or ''))
except Exception: print('\t')
")
    fi
    _upstream_is_private_intranet "$url" "$hh" || return 0
    echo -e "  ${YELLOW}⚠${NC} tailscale accept-routes 开启 + 内网 upstream → 黑洞风险 — 修: ${CYAN}bash lib/tailscale-guard.sh fix${NC}"
}

# ========== 执行所有检查 ==========

echo ""
if $QUICK_MODE; then
    echo -e "${GREEN}=== Claude Config 状态检查（快速模式）===${NC}"
else
    echo -e "${GREEN}=== Claude Config 状态检查 ===${NC}"
fi
echo ""

git_pull
_bridge_cold_start
check_symlinks
check_ccprivate_structure
check_deps_quick
check_autosync
check_pat_expiry
check_repos
check_feishu

if ! $QUICK_MODE; then
    check_init_watermark
    check_mcp
    check_option_components
    check_skills
    check_example_sync
fi

# 上面各 check 发现问题时报「修复: bash maintain.sh fix」。
# 问题可一键全修，但 status 本身只读不修 —— 末尾给总入口
# （--quick 也保留，SessionStart hook 跑的是 quick，用户常看的就是它）
echo ""
echo -e "  ${GRAY}发现问题? 一键全修: ${CYAN}bash maintain.sh fix${NC}${GRAY}（2E）${NC}"
echo ""
