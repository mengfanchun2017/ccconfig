#!/bin/bash
# Claude Config - 状态检查
#
# 检查项：
# 1. 配置文件符号链接 + ccprivate 结构
# 2. 核心依赖
# 3. auto-sync 状态
# 4. GitHub 最后推送
# 5. MEMORY（~/.claude/projects/ 直查）
# 6. Git 项目状态
# 7. 飞书 lark-cli 状态
# 8. Playwright 浏览器测试
# 9. MCP 服务器状态
# 10. option-* 可选组件（含远程连接 SSH/Tailscale）
# 11. Skills 安装状态
# 12. Example 模板同步
#
# 用途：通过 SessionStart hook 在 Claude 启动时运行

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/path-helper.sh"
REPO_DIR="$CCCONFIG_ROOT"

# --quick: 跳过慢检查（MCP、option 组件、模板对比）
QUICK_MODE=false
[[ "${1:-}" == "--quick" ]] && QUICK_MODE=true

# ========== Git 拉取 ==========
git_pull() {
    if [ ! -d "$REPO_DIR/.git" ]; then
        return 0
    fi
    if timeout 30 git -C "$REPO_DIR" fetch origin main 2>/dev/null; then
        local updates=$(git -C "$REPO_DIR" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
        if [ "$updates" -gt 0 ]; then
            echo -e "${CYAN}[Git]${NC} 发现 $updates 个更新，正在拉取..."
            timeout 30 git -C "$REPO_DIR" pull --rebase origin main 2>/dev/null
        fi
    fi
}

# ========== 1. 检查符号链接 ==========
check_symlinks() {
    echo -e "${CYAN}━━━ 配置文件链接━━━${NC}"

    local issues=0

    # settings.json
    if [ -L "$HOME/.claude/settings.json" ] && [ -e "$HOME/.claude/settings.json" ]; then
        echo -e "  ${GREEN}✅${NC} settings.json"
    else
        echo -e "  ${RED}❌${NC} settings.json"
        issues=$((issues + 1))
    fi

    # .config.json
    if [ -L "$HOME/.claude/.config.json" ] && [ -e "$HOME/.claude/.config.json" ]; then
        echo -e "  ${GREEN}✅${NC} .config.json"
    else
        echo -e "  ${RED}❌${NC} .config.json"
        issues=$((issues + 1))
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
    local mem_ok=false
    if [ -L "$HOME/.claude/projects" ]; then
        # ccprivate 创建的 symlink：~/.claude/projects → ccprivate/link/projects
        local mem_target=$(readlink "$HOME/.claude/projects" 2>/dev/null)
        if [ -d "$HOME/.claude/projects" ]; then
            mem_ok=true
        fi
    elif [ -d "$HOME/.claude/projects" ]; then
        # Claude Code 自动创建了 projects 目录
        mem_ok=true
    elif [ -d "$CCPRIVATE_HOME/link/projects" ]; then
        # ccprivate/link/projects 链路存在
        # ~/.claude/projects 尚未创建（新装，Claude Code 未运行过）
        mem_ok=true
    fi
    if $mem_ok; then
        echo -e "  ${GREEN}✅${NC} MEMORY.md"
    else
        echo -e "  ${YELLOW}○${NC} MEMORY.md (ccprivate 未链接，run setup.sh)"
    fi

    # rules (条件规则)
    if [ -L "$HOME/.claude/rules" ] && [ -d "$HOME/.claude/rules" ]; then
        local rule_count=$(ls "$HOME/.claude/rules/"*.md 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✅${NC} rules ($rule_count 个)"
    else
        echo -e "  ${YELLOW}○${NC} rules (未链接)"
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        echo -e "  ${GREEN}配置链接就绪${NC}"
    else
        echo -e "  ${GRAY}自动修复中...${NC}"
        local fixed=false
        if [ -x "$CCPRIVATE_HOME/setup.sh" ]; then
            if bash "$CCPRIVATE_HOME/setup.sh" 2>/dev/null; then
                echo -e "  ${GREEN}✅ 配置链接已自动修复 (ccprivate/setup.sh)${NC}"
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
        echo -e "  ${GRAY}创建: bash ccconfig/init-ccprivate-repo.sh${NC}"
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
    local expected_dirs=("skill-config" "rules" "agents" "commands" "bin")
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
    local missing_links=()
    for f in "CLAUDE.md" "settings.json" ".config.json"; do
        [ -f "$ccpriv/link/$f" ] || missing_links+=("$f")
    done
    if [ ${#missing_links[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC}  link/ 缺少: ${missing_links[*]}"
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        echo -e "  ${GREEN}✅ ccprivate 结构正常${NC}"
    else
        echo -e "  ${GRAY}修复: bash maintain.sh upgrade-ccprivate${NC}"
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

# ========== 4. GitHub 最后推送 ==========
check_last_push() {
    echo -e "${CYAN}━━━ 最后推送━━━${NC}"

    if [ ! -d "$REPO_DIR/.git" ]; then
        echo -e "  ${YELLOW}⚠️${NC} 非 Git 仓库"
        return
    fi

    # 获取最后一次提交的日期和消息
    local log=$(git -C "$REPO_DIR" log -1 --format="%ci|%s" 2>/dev/null)
    if [ -n "$log" ]; then
        local date=$(echo "$log" | cut -d'|' -f1 | cut -d' ' -f1)
        local msg=$(echo "$log" | cut -d'|' -f2-)
        echo -e "  📅 $date"
        echo -e "  📝 $msg"
    else
        echo -e "  ${YELLOW}⚠️${NC} 无提交记录"
    fi
}

# ========== 5. MEMORY 最后更新 ==========
check_memory() {
    echo -e "${CYAN}━━━ MEMORY━━━${NC}"

    local projects_dir="$HOME/.claude/projects"
    local found=0

    if [[ ! -d "$projects_dir" ]]; then
        echo -e "  ${YELLOW}⚠️${NC} ~/.claude/projects/ 不存在（Claude Code 首次运行后自动创建）"
        return
    fi

    for proj_dir in "$projects_dir"/*/; do
        [[ -d "$proj_dir" ]] || continue
        local proj_name=$(basename "$proj_dir")
        [[ "$proj_name" == *"--claude-worktrees-"* ]] && continue

        local mem_dir="${proj_dir}memory"
        local display_name=$(echo "$proj_name" | sed 's/^-home-[^-]*-//' | tr '-' '/')

        # symlink 检查
        local link_info=""
        if [[ -L "$mem_dir" ]]; then
            local target=$(readlink "$mem_dir" 2>/dev/null)
            if [[ -d "$mem_dir" ]]; then
                link_info=" → $target"
            else
                echo -e "  ${RED}❌${NC} $display_name — symlink 断链: $target"
                found=$((found + 1))
                continue
            fi
        fi

        if [[ -f "$mem_dir/MEMORY.md" ]]; then
            local mtime=$(stat -L -c %y "$mem_dir/MEMORY.md" 2>/dev/null | cut -d'.' -f1)
            local count=$(ls -1 "$mem_dir"/*.md 2>/dev/null | grep -v MEMORY | wc -l)
            echo -e "  ${GREEN}✅${NC} $display_name — $mtime — ${count} 条记忆${link_info}"
            found=$((found + 1))
        elif [[ -d "$mem_dir" ]]; then
            echo -e "  ${GRAY}○${NC} $display_name — 无 MEMORY.md${link_info}"
            found=$((found + 1))
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo -e "  ${GRAY}(尚无项目 memory，Claude Code 运行后自动创建)${NC}"
    fi
}

# ========== 6. Git 项目状态 ==========
check_git_projects() {
    echo -e "${CYAN}━━━ Git 项目━━━${NC}"

    local found=0
    for git_dir in "$HOME/git"/*/; do
        [ -d "${git_dir}.git" ] || continue
        local name=$(basename "$git_dir")
        # ccprivate 是私有数据层，不作为开发项目展示
        if [ "$name" = "ccprivate" ]; then
            continue
        fi
        found=$((found + 1))

        # CLAUDE.md 状态
        local claude_status=""
        if [ -L "${git_dir}CLAUDE.md" ]; then
            local target=$(readlink "${git_dir}CLAUDE.md" 2>/dev/null)
            if [ -e "${git_dir}CLAUDE.md" ]; then
                if echo "$target" | grep -q "ccprivate"; then
                    claude_status="${GREEN}✅ ccprivate${NC}"
                else
                    claude_status="${YELLOW}⚠️  ${target}${NC}"
                fi
            else
                claude_status="${RED}❌ 断链${NC}"
            fi
        elif [ -f "${git_dir}CLAUDE.md" ]; then
            claude_status="${YELLOW}📄 项目文件${NC}"
        else
            claude_status="${GRAY}－${NC}"
        fi

        # Memory 状态
        # /home/user/git/<project-name> → -home-user-git-<project-name>
        local rel_path="${git_dir#/}"
        rel_path="${rel_path%/}"
        local proj_id="-${rel_path//\//-}"
        local mem_status=""
        local mem_path="$HOME/.claude/projects/$proj_id/memory"
        if [ -L "$mem_path" ] && [ -d "$mem_path" ]; then
            local mem_target=$(readlink "$mem_path" 2>/dev/null)
            if [ -d "$mem_target" ]; then
                mem_status="${GREEN}✅${NC}"
            else
                mem_status="${RED}❌ 断链${NC}"
            fi
        elif [ -d "$mem_path" ] && [ -f "$mem_path/MEMORY.md" ]; then
            mem_status="${GREEN}✅ 本地${NC}"
        else
            mem_status="${GRAY}－${NC}"
        fi

        # Git 状态
        local git_status=""
        local dirty=$(git -C "$git_dir" status --porcelain 2>/dev/null | wc -l)
        local branch=$(git -C "$git_dir" branch --show-current 2>/dev/null)
        local remote=$(git -C "$git_dir" remote get-url origin 2>/dev/null || echo "")
        if [ -z "$remote" ]; then
            git_status="${YELLOW}无 remote${NC}"
        elif [ "$dirty" -gt 0 ]; then
            git_status="${YELLOW}${branch} (${dirty} 改动)${NC}"
        else
            git_status="${GREEN}${branch} 干净${NC}"
        fi

        printf "  %-20s CLAUDE: %b  Mem: %b  Git: %b\n" "$name" "$claude_status" "$mem_status" "$git_status"
    done

    if [ $found -eq 0 ]; then
        echo -e "  ${GRAY}(~/git/ 下无项目)${NC}"
    fi
}


# ========== MCP 服务器状态 ==========
check_mcp() {
    echo ""
    echo -e "${CYAN}━━━ MCP 服务器━━━${NC}"

    local list
    list=$(claude mcp list 2>&1) || true
    if [ -z "$list" ]; then
        echo -e "  ${GRAY}claude mcp list 无返回${NC}"
        return
    fi
    echo "$list" | while IFS= read -r line; do
        echo "  $line"
    done
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

    # 检查配置
    if command -v lark-cli &> /dev/null; then
        echo -n "  配置 ... "
        if lark-cli config show 2>/dev/null | grep -q "appId"; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${YELLOW}○${NC} 未配置"
        fi

        # 检查授权
        echo -n "  授权 ... "
        if lark-cli config show 2>/dev/null | grep -q "users"; then
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

    # lark-channel-bridge 状态
    echo -n "  lark-bridge ... "
    if command -v lark-channel-bridge &> /dev/null; then
        if systemctl --user is-active lark-channel-bridge.service &>/dev/null 2>&1; then
            echo -e "${GREEN}✅${NC} (systemd 运行中)"
        elif pgrep -f "lark-channel-bridge" > /dev/null 2>&1; then
            echo -e "${GREEN}✅${NC} (进程运行中)"
        else
            echo -e "${YELLOW}○${NC} (已装未运行)"
        fi
    else
        echo -e "${GRAY}－${NC} (未安装)"
    fi
    echo -e "  ${GRAY}安装/启动: bash ccconfig/option-larkbridge/init.sh --run${NC}"
    echo -e "  ${GRAY}后台服务: bash ccconfig/option-larkbridge/init.sh --start${NC}"
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

    # 分组：与 init-option.sh 保持一致
    local groups=(
        "--os--|bat glow nano"
        "--claude--|mcp skill"
        "--lark--|larkcli larkbridge"
        "--other--|officecli remote cloudflare"
        "--key--|feishu_key"
    )

    for group_entry in "${groups[@]}"; do
        local group_title="${group_entry%%|*}"
        local group_items="${group_entry#*|}"

        echo -e "  ${BOLD}${group_title}${NC}"

        for name in $group_items; do
            # 检测是否存在
            case "$name" in
                mcp|feishu_key) ;;
                bat|glow|nano) ;;
                *) [ -d "$REPO_DIR/option-$name" ] || continue ;;
            esac
            found=$((found + 1))

            icon="" detail=""
            if [ "$name" = "mcp" ]; then
                local claude_json="$HOME/.claude/.config.json"
                if [ -f "$claude_json" ]; then
                    local count=$(python3 -c "import json; d=json.load(open('$claude_json')); print(len(d.get('mcp_servers',[])))" 2>/dev/null || echo "0")
                    [ "$count" -gt 0 ] && { icon="ok"; detail="$count 个 MCP 服务器"; } || { icon="miss"; detail="MCP 未配置（bash lib/init-mcp.sh sync）"; }
                else
                    icon="miss"; detail="claude.json 未找到"
                fi
            elif [ "$name" = "feishu_key" ]; then
                local feishu_conf
                feishu_conf=$(resolve_conf feishu.json 2>/dev/null) || { icon="miss"; detail="ccprivate/conf/feishu.json 不存在"; }
                if [ -z "$icon" ]; then
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
                    icon="${fk_out%%|*}"; detail="${fk_out#*|}"
                fi
            elif [ "$name" = "bat" ]; then
                local ver=$(bat --version 2>/dev/null | head -1 || batcat --version 2>/dev/null | head -1 || echo "")
                [ -n "$ver" ] && { icon="ok"; detail="bat 已安装 ($ver)"; } || { icon="miss"; detail="bat 未安装"; }
            elif [ "$name" = "glow" ]; then
                local ver=$(glow --version 2>/dev/null | head -1)
                [ -n "$ver" ] && { icon="ok"; detail="glow 已安装 ($ver)"; } || { icon="miss"; detail="glow 未安装"; }
            elif [ "$name" = "nano" ]; then
                local ver=$(nano --version 2>/dev/null | head -1)
                [ -n "$ver" ] && { icon="ok"; detail="nano 已安装 ($ver)"; } || { icon="miss"; detail="nano 未安装"; }
            else
                # 从 option-* init.sh --status 取首行解析
                local init_script="$REPO_DIR/option-$name/init.sh"
                local out
                out=$(bash "$init_script" --status 2>&1) || true
                local line
                line=$(echo "$out" | sed 's/\x1b\[[0-9;]*[mK]//g' | grep -vE '^[[:space:]]*$' | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                if echo "$line" | grep -qi "^OK"; then icon="ok"; detail="${line#OK }"
                elif echo "$line" | grep -qi "^WARN"; then icon="warn"; detail="${line#WARN }"
                elif echo "$line" | grep -qiE "^(MISSING|FAIL)"; then icon="miss"; detail="${line#MISSING }"; detail="${detail#FAIL }"
                else icon="?"; detail="$line"; fi
            fi

            _print_option "$name" "$icon" "$detail"

            # option-remote: 额外展开子行
            if [ "$name" = "remote" ]; then
                local init_script="$REPO_DIR/option-remote/init.sh"
                local out
                out=$(bash "$init_script" --status 2>&1) || true
                echo "$out" | sed 's/\x1b\[[0-9;]*[mK]//g' | grep -vE '^[[:space:]]*$' | tail -n +2 | while IFS= read -r sub; do
                    echo "      $sub"
                done
            fi
        done
    done

    if [ $found -eq 0 ]; then
        echo -e "  ${GRAY}(无可选组件)${NC}"
    fi
    echo ""
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
        local broken=0 linked=0
        for d in "$skills_dir"/*; do
            if [[ -L "$d" ]] && [[ ! -e "$d" ]]; then
                broken=$((broken + 1))
            elif [[ -L "$d" ]]; then
                linked=$((linked + 1))
            fi
        done
        echo -e "  已链接: ${GREEN}${linked}${NC} 个"
        if [[ $broken -gt 0 ]]; then
            echo -e "  ${RED}断链: ${broken}${NC} 个 → bash init-skill.sh cleanup"
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

# ========== Example 模板同步检查 ==========
check_example_sync() {
    local ccconfig_example="$CCCONFIG_ROOT/templates"
    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    echo ""
    echo -e "${CYAN}━━━ 模板同步━━━${NC}"

    # rules 检查
    local rules_outdated=0 rules_new=0 rules_added=0
    for example in "$ccconfig_example/rules/"*.md.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .md.example)
        local target="$ccpriv/rules/${base}.md"
        if [ ! -f "$target" ]; then
            rules_new=$((rules_new + 1))
        elif ! diff -q "$example" "$target" &>/dev/null; then
            rules_outdated=$((rules_outdated + 1))
        fi
    done
    rules_added=0
    for f in "$ccpriv/rules/"*.md; do
        [ -f "$f" ] || continue
        base=$(basename "$f" .md)
        [ -f "$ccconfig_example/rules/${base}.md.example" ] || rules_added=$((rules_added + 1))
    done

    local out=""
    [ $rules_outdated -gt 0 ] && out="${out}${YELLOW}${rules_outdated} 过期${NC} "
    [ $rules_new -gt 0 ] && out="${out}${CYAN}${rules_new} 新增${NC} "
    [ $rules_added -gt 0 ] && out="${out}${GRAY}${rules_added} 独有${NC} "
    [ -z "$out" ] && out="${GREEN}✅ 同步${NC}"
    echo -e "  rules: $out"

    # agents 检查
    local agents_outdated=0 agents_new=0 agents_added=0
    for example in "$ccconfig_example/agents/"*.md.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .md.example)
        local target="$ccpriv/agents/${base}.md"
        if [ ! -f "$target" ]; then
            agents_new=$((agents_new + 1))
        elif ! diff -q "$example" "$target" &>/dev/null; then
            agents_outdated=$((agents_outdated + 1))
        fi
    done
    agents_added=0
    for f in "$ccpriv/agents/"*.md; do
        [ -f "$f" ] || continue
        base=$(basename "$f" .md)
        [ -f "$ccconfig_example/agents/${base}.md.example" ] || agents_added=$((agents_added + 1))
    done

    local out=""
    [ $agents_outdated -gt 0 ] && out="${out}${YELLOW}${agents_outdated} 过期${NC} "
    [ $agents_new -gt 0 ] && out="${out}${CYAN}${agents_new} 新增${NC} "
    [ $agents_added -gt 0 ] && out="${out}${GRAY}${agents_added} 独有${NC} "
    [ -z "$out" ] && out="${GREEN}✅ 同步${NC}"
    echo -e "  agents: $out"

    local needs_action=$((rules_outdated + rules_new + agents_outdated + agents_new))
    if [ $needs_action -gt 0 ]; then
        echo ""
        echo -e "  ${GRAY}运行: bash maintain.sh example promote${NC}"
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

# ========== 执行所有检查 ==========

echo ""
if $QUICK_MODE; then
    echo -e "${GREEN}=== Claude Config 状态检查（快速模式）===${NC}"
else
    echo -e "${GREEN}=== Claude Config 状态检查 ===${NC}"
fi
echo ""

git_pull
check_symlinks
check_ccprivate_structure
check_deps_quick
check_autosync
check_last_push
check_memory
check_git_projects
check_feishu

if ! $QUICK_MODE; then
    check_mcp
    check_option_components
    check_example_sync
fi

echo ""
