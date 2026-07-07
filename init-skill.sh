#!/bin/bash
# Claude Skills 管理脚本
# 功能：装 CLI 依赖 + 同步自建 skill 符号链接 + ccprivate 配置覆盖 + 装第三方 skill（npx skills 幂等）
#
# skill 来源（聚合到 ~/.claude/skills/）：
#   CLI 依赖          → 自建 skill deps.txt（per-skill 自声明），npm/go 自动安装
#   自建 f-*         → symlink 从 claude-skills/plugins/（开源仓库，单一源）
#   私有配置         → ccprivate config overlay（conf/*.yaml 覆盖 skill 内 config.yaml.example）
#   第三方 (npx)     → npx skills add 装到 ~/.agents/skills/，自动 symlink 到 ~/.claude/skills/
#
# 使用：
#   bash ccconfig/init-skill.sh sync             # 装 CLI 依赖 + 同步自建 + 装第三方
#   bash ccconfig/init-skill.sh update           # 更新所有（CLI + npx skills）
#   bash ccconfig/init-skill.sh remove <name>    # 卸载第三方 skill（从清单 + 磁盘删）
#   bash ccconfig/init-skill.sh cleanup          # 单独清 ~/.claude/skills/ 断链
#   bash ccconfig/init-skill.sh list             # 查看已安装 skills（symlink + plugin）
#   bash ccconfig/init-skill.sh status           # 状态总览
#   bash ccconfig/init-skill.sh diff             # 检测第三方 skill 清单 drift

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
SKILLS_SRC="${CLAUDE_SKILLS_SRC:-$HOME/git/claude-skills/plugins}"
CCPRIVATE_DIR="${CCPRIVATE_DIR:-$HOME/git/ccprivate}"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
THIRD_PARTY_CONF="$SCRIPT_DIR/conf/third-party-skills.txt"
GITHUB_USER="${GITHUB_USER:-$(gh api user --jq '.login' 2>/dev/null)}"
if [ -z "$GITHUB_USER" ]; then
    warn "无法检测 GitHub 用户名（gh 未登录或未安装）"
    warn "  设置环境变量: export GITHUB_USER=<your-github-username>"
fi
MARKETPLACE_REPO="$GITHUB_USER/claude-skills"
MARKETPLACE_NAME="$GITHUB_USER-skills"

# 第三方 skill 全部走 npx skills（user-managed 干净显示）
# marketplace.json 仍发布 mattpocock-skills 给其他人通过 marketplace 安装

title() { echo -e "\n========================================\n$1\n========================================\n${CYAN}"; }

# 阶段 0：装 CLI 工具依赖
# 来源：自建 skill 目录下的 deps.txt（per-skill 自声明）
# 去重：同包名只装一次，required_by 聚合多个 skill 名
do_install_cli_deps() {
    title "阶段 0/4: CLI 工具依赖（自建 skill deps.txt）"

    # 收集所有依赖条目（去重 key = pkg|mgr）
    declare -A seen_deps

    local self_deps=0
    if [[ -d "$SKILLS_SRC" ]]; then
        for skill_dir in "$SKILLS_SRC"/*/; do
            local dep_file="${skill_dir}deps.txt"
            [[ -f "$dep_file" ]] || continue
            local skill_name=$(basename "$skill_dir")
            while IFS= read -r line; do
                [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
                local pkg=$(echo "$line" | awk '{print $1}')
                local mgr=$(echo "$line" | awk '{print $2}' | cut -d: -f1)
                local key="$pkg|$mgr"
                if [[ -z "${seen_deps[$key]}" ]]; then
                    seen_deps[$key]="$skill_name"
                    self_deps=$((self_deps + 1))
                else
                    # 冲突检测：同包名被多个 skill 声明
                    local prev_skill="${seen_deps[$key]}"
                    local prev_ver=""
                    local prev_mgr=""
                    # 向前查上一个声明的版本
                    for prev_key in "${!seen_deps[@]}"; do
                        if [[ "$prev_key" == "$key" ]]; then
                            prev_ver=$(echo "$prev_key" | cut -d'|' -f1)
                            break
                        fi
                    done
                    local cur_ver="$pkg"
                    if [[ "$prev_ver" != "$cur_ver" ]]; then
                        warn "  ⚠ $pkg: 版本冲突 — $prev_skill 声明 $prev_ver, $skill_name 声明 $cur_ver（取首个）"
                    fi
                    seen_deps[$key]="${seen_deps[$key]},$skill_name"
                fi
            done < "$dep_file"
        done
    fi
    info "  扫描 $self_deps 个唯一依赖"

    [[ ${#seen_deps[@]} -eq 0 ]] && info "  无 CLI 依赖" && return 0

    echo ""

    # 安装
    local npm_global_bin
    npm_global_bin="$(npm prefix -g 2>/dev/null)/bin"

    local installed=0 skipped=0 failed=0
    for key in "${!seen_deps[@]}"; do
        local pkg="${key%%|*}"
        local mgr="${key##*|}"
        local required_by="${seen_deps[$key]}"

        case "$mgr" in
            npm)
                if npm list -g "$pkg" --depth=0 2>/dev/null | grep -q "$pkg"; then
                    info "  $pkg: 已装 — $required_by"
                    skipped=$((skipped + 1))
                else
                    info "  $pkg: 安装中..."
                    if npm install -g "$pkg" 2>&1 | tail -1; then
                        # symlink binary to ~/.local/bin
                        local bin_name="${pkg##*/}"  # strip @scope/ prefix
                        bin_name="${bin_name#@*/}"    # strip scope if still present
                        # handle npm binary name (may differ from package name)
                        if [[ -x "$npm_global_bin/$bin_name" ]]; then
                            mkdir -p "$HOME/.local/bin"
                            ln -sf "$npm_global_bin/$bin_name" "$HOME/.local/bin/$bin_name"
                        fi
                        good "  $pkg: ✓ — $required_by"
                        installed=$((installed + 1))
                    else
                        bad "  $pkg: 失败"
                        failed=$((failed + 1))
                    fi
                fi
                ;;
            go)
                local bin_name=$(basename "$pkg")
                if command -v "$bin_name" &>/dev/null; then
                    info "  $pkg (go): 已装 — $required_by"
                    skipped=$((skipped + 1))
                else
                    info "  $pkg (go): 安装中..."
                    if go install "$pkg" 2>&1; then
                        good "  $pkg (go): ✓ — $required_by"
                        installed=$((installed + 1))
                    else
                        bad "  $pkg (go): 失败"
                        failed=$((failed + 1))
                    fi
                fi
                ;;
            *)
                warn "  $pkg: 未知管理器 $mgr — 跳过"
                skipped=$((skipped + 1))
                ;;
        esac
    done

    echo ""
    good "  CLI 依赖: $installed 新装, $skipped 已装, $failed 失败"
}

# 阶段 1：symlink 自建 skill 到 ~/.claude/skills/
# 保护 npx skills 装的 symlink：目标不在 $SKILLS_SRC/ 下就跳过（user-managed）
do_link_self_built() {
    title "阶段 1/4: symlink 自建 skill → ~/.claude/skills/"

    mkdir -p "$CLAUDE_SKILLS_DIR"

    if [[ ! -d "$SKILLS_SRC" ]]; then
        bad "Skills 源目录不存在: $SKILLS_SRC"
        return 1
    fi

    local linked=0 skipped=0 cleaned=0 user_managed=0
    for skill_dir in "$SKILLS_SRC"/*; do
        [[ -d "$skill_dir" ]] || continue
        local name=$(basename "$skill_dir")
        local target="$CLAUDE_SKILLS_DIR/$name"

        if [[ -L "$target" ]] && [[ -e "$target" ]] && [[ "$(readlink -f "$target")" == "$(readlink -f "$skill_dir")" ]]; then
            info "  $name: 已链接"
            skipped=$((skipped + 1))
        elif [[ -L "$target" ]] && [[ ! -e "$target" ]]; then
            rm -f "$target"
            good "  $name: ✓ 删断链（源已移走）"
            cleaned=$((cleaned + 1))
        elif [[ -L "$target" ]]; then
            # symlink 目标存在但不在 $SKILLS_SRC/ → user-managed（npx skills 装的）
            if [[ "$(readlink -f "$target")" != "$(readlink -f "$skill_dir")" ]]; then
                info "  $name: user-managed (npx 等)，保留"
                user_managed=$((user_managed + 1))
            else
                rm -f "$target"
                ln -s "$skill_dir" "$target"
                good "  $name: ✓ (修复链接)"
                linked=$((linked + 1))
            fi
        elif [[ -d "$target" ]]; then
            info "  $name: 本地已有（非链接），跳过"
            skipped=$((skipped + 1))
        else
            ln -s "$skill_dir" "$target"
            good "  $name: ✓"
            linked=$((linked + 1))
        fi
    done
    echo ""
    good "  symlink: $linked 新建, $skipped 跳过, $cleaned 删断链, $user_managed user-managed"
}

# 阶段 2：检 marketplace（保留自建 marketplace 给 f-* 自动跟）
do_ensure_marketplace() {
    title "阶段 2/4: marketplace 检（$MARKETPLACE_NAME）"

    info "检 marketplace: $MARKETPLACE_REPO"
    if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE_NAME"; then
        good "  ✓ marketplace 已添加"
    else
        if claude plugin marketplace add "$MARKETPLACE_REPO" --scope user 2>&1 | tail -3; then
            good "  ✓ marketplace 已添加"
        else
            warn "  ! marketplace 添加失败（无网络？继续）"
        fi
    fi
    echo ""
    info "  marketplace 保留自建 skills（f-* plugin 在里面；第三方用户走 npx skills 装）"
}

# 阶段 3：npx skills 装第三方 skill（幂等，从 conf/third-party-skills.txt 读列表）
# 已装就 skip（npx skills add 本身幂等）；不重写 ~/.claude/skills/（npx 自己建 symlink）
do_install_third_party() {
    title "阶段 3/4: npx skills 装第三方 skill（conf/third-party-skills.txt）"

    if [[ ! -f "$THIRD_PARTY_CONF" ]]; then
        warn "  conf 清单不存在: $THIRD_PARTY_CONF — 跳过"
        return 0
    fi

    # 防御：github URL 走 HTTPS（init-ubuntu.sh 应已配，这里双保险）
    git config --global url."https://github.com/".insteadOf "git@github.com:" 2>/dev/null || true

    local installed=0 already=0 failed=0
    while IFS= read -r line; do
        # 跳过空行/注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # 解析 `<source>  <skill-name>`（两个空格或 tab 分隔）
        local source=$(echo "$line" | awk '{print $1}')
        local skill=$(echo "$line" | awk '{print $2}')

        # 检查 ~/.claude/skills/<skill> 是否已存在（npx 装过会有 symlink）
        if [[ -e "$CLAUDE_SKILLS_DIR/$skill" ]]; then
            info "  $skill ($source): 已装"
            already=$((already + 1))
            continue
        fi

        # 调 npx skills add
        if npx --yes skills@latest add "$source" --skill "$skill" -g -y 2>&1 | grep -qE "Installed 1 skill|✓.*$skill"; then
            good "  $skill ($source): ✓"
            installed=$((installed + 1))
        else
            warn "  $skill ($source): 失败（重试或检网络）"
            failed=$((failed + 1))
        fi
    done < "$THIRD_PARTY_CONF"

    echo ""
    good "  第三方 skill: $installed 新装, $already 已装, $failed 失败"
}

# 阶段 2.5：ccprivate 配置覆盖（委托 ccprivate/bin/apply-config.sh）
do_apply_ccprivate_config() {
    title "阶段 2.5/4: ccprivate 配置覆盖"

    local apply_script="$CCPRIVATE_DIR/bin/apply-config.sh"
    if [[ -x "$apply_script" ]]; then
        bash "$apply_script"
    else
        info "  $apply_script 不可执行，跳过（ccprivate 未初始化或未安装）"
    fi
}

do_sync() {
    do_install_cli_deps
    do_link_self_built
    do_ensure_marketplace
    do_apply_ccprivate_config
    do_install_third_party

    echo ""
    good "完成。验证: bash init-skill.sh status"
}

# 更新所有（CLI 工具 + npx skills）
# 收集自建 skill deps.txt 中的所有依赖
_collect_all_deps() {
    declare -n _deps_out=$1
    _deps_out=()

    if [[ -d "$SKILLS_SRC" ]]; then
        for skill_dir in "$SKILLS_SRC"/*/; do
            local dep_file="${skill_dir}deps.txt"
            [[ -f "$dep_file" ]] || continue
            while IFS= read -r line; do
                [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
                _deps_out+=("$line")
            done < "$dep_file"
        done
    fi
}

do_update() {
    local all_deps
    _collect_all_deps all_deps

    title "更新 CLI 工具依赖"
    declare -A updated
    for line in "${all_deps[@]}"; do
        local pkg=$(echo "$line" | awk '{print $1}')
        local mgr=$(echo "$line" | awk '{print $2}' | cut -d: -f1)
        local key="$pkg|$mgr"
        [[ -n "${updated[$key]}" ]] && continue
        updated[$key]=1

        case "$mgr" in
            npm)
                info "  npm update -g $pkg"
                npm update -g "$pkg" 2>&1 | tail -1
                ;;
            go)
                info "  go install $pkg"
                go install "$pkg" 2>&1 | tail -1
                ;;
        esac
    done

    echo ""
    title "更新 npx skills（按 upstream 拉最新）"
    git config --global url."https://github.com/".insteadOf "git@github.com:" 2>/dev/null || true
    npx --yes skills@latest update -g -y 2>&1 | tail -20

    echo ""
    good "更新完成。重启 Claude Code 加载新 skill 内容。"
}

# 清理所有 ~/.claude/skills/ 里源已不存在的断链（不删 npx-managed）
do_cleanup() {
    title "清理断链"
    local count=0
    for target in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -L "$target" ]] || continue
        if [[ ! -e "$target" ]]; then
            local name=$(basename "$target")
            rm -f "$target"
            good "  ✓ 删: $name"
            count=$((count + 1))
        fi
    done
    [[ $count -eq 0 ]] && info "  无断链"
    echo ""
    good "清理完成: $count 个"
}

do_list() {
    echo "=== 自建 skill (claude-skills/plugins/ 实体) ==="
    ls "$SKILLS_SRC" 2>/dev/null | while read n; do echo "  $n"; done
    echo ""
    echo "=== ~/.claude/skills/ (symlink + npx-installed) ==="
    for d in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -e "$d" ]] || continue
        local marker="✓"
        [[ -L "$d" ]] || marker="○"
        local src
        if [[ -L "$d" ]]; then
            src=$(readlink "$d" | sed 's|.*/\.agents/skills/|npx: |; s|.*/claude-skills/plugins/|claude-skills: |; s|.*/link/skills/|ccconfig (legacy): |')
        else
            src="(本地)"
        fi
        echo "  $marker $(basename "$d") — $src"
    done
    echo ""
    echo "=== 第三方 (npx skills 装) ==="
    if [[ -d "$HOME/.agents/skills" ]]; then
        ls "$HOME/.agents/skills" 2>/dev/null | while read n; do echo "  $n"; done
    else
        echo "  (无)"
    fi
    echo ""
    echo "=== claude plugin list (marketplace 已装) ==="
    claude plugin list 2>&1 | head -10
}

# 检测清单 vs 实际安装的 drift
# 输出：清单有但未装、已装但不在清单、自建 skill（不在清单管理的范围）
do_diff() {
    title "Skills Drift 检测（conf/third-party-skills.txt vs ~/.claude/skills/）"

    # 1. 解析清单中的第三方 skill
    declare -A MANIFEST_SKILLS  # skill_name → source
    if [[ -f "$THIRD_PARTY_CONF" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            local skill=$(echo "$line" | awk '{print $2}')
            local source=$(echo "$line" | awk '{print $1}')
            [[ -n "$skill" ]] && MANIFEST_SKILLS["$skill"]="$source"
        done < "$THIRD_PARTY_CONF"
    fi

    # 2. 扫描 ~/.claude/skills/ 实际安装
    declare -A INSTALLED
    declare -A INSTALLED_SRC  # skill_name → source_type
    for d in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -e "$d" ]] || continue
        local name=$(basename "$d")
        INSTALLED["$name"]=1
        if [[ -L "$d" ]]; then
            local target=$(readlink -f "$d")
            if [[ "$target" == *"/claude-skills/plugins"* ]] || [[ "$target" == *"$SKILLS_SRC"* ]]; then
                INSTALLED_SRC["$name"]="self-built"
            elif [[ "$target" == *".agents/skills"* ]]; then
                INSTALLED_SRC["$name"]="npx"
            else
                INSTALLED_SRC["$name"]="user-symlink"
            fi
        else
            INSTALLED_SRC["$name"]="local-dir"
        fi
    done

    # 3. 对比
    local missing=0 extra=0 ok=0

    echo ""
    echo -e "${CYAN}── 清单有但未装（需 sync）${NC}"
    for skill in "${!MANIFEST_SKILLS[@]}"; do
        if [[ -z "${INSTALLED[$skill]}" ]]; then
            echo -e "  ${RED}✗${NC} $skill — ${MANIFEST_SKILLS[$skill]}"
            missing=$((missing + 1))
        fi
    done
    [[ $missing -eq 0 ]] && echo -e "  ${GREEN}✓${NC} 无"

    echo ""
    echo -e "${CYAN}── 已装但不在清单（untracked drift）${NC}"
    for skill in "${!INSTALLED[@]}"; do
        if [[ -z "${MANIFEST_SKILLS[$skill]}" ]] && [[ "${INSTALLED_SRC[$skill]}" != "self-built" ]]; then
            local src_label="${INSTALLED_SRC[$skill]}"
            echo -e "  ${YELLOW}?${NC} $skill — $src_label（不在 third-party-skills.txt）"
            extra=$((extra + 1))
        fi
    done
    [[ $extra -eq 0 ]] && echo -e "  ${GREEN}✓${NC} 无"

    echo ""
    echo -e "${CYAN}── 自建 skill（不在清单管理范围）${NC}"
    local self_count=0
    for skill in "${!INSTALLED_SRC[@]}"; do
        if [[ "${INSTALLED_SRC[$skill]}" == "self-built" ]]; then
            info "  $skill"
            self_count=$((self_count + 1))
        fi
    done
    info "  共 $self_count 个"

    echo ""
    if [[ $missing -eq 0 ]] && [[ $extra -eq 0 ]]; then
        good "Drift 检测通过：清单与安装一致"
    else
        warn "发现 drift：$missing 缺失, $extra untracked → bash init-skill.sh sync 修复缺失"
    fi
}

do_remove() {
    local skill="$1"
    if [[ -z "$skill" ]]; then
        bad "用法: $0 remove <skill-name>"
        return 1
    fi

    title "卸载 skill: $skill"

    # 1. 检查是否为自建 skill（拒绝卸载）
    if [[ -d "$SKILLS_SRC/$skill" ]]; then
        bad "  $skill 是自建 skill，由 claude-skills 仓库管理，不能通过此脚本卸载"
        info "  如需移除自建 skill：删除 claude-skills/plugins/$skill/ 目录并提交 PR"
        return 1
    fi

    # 2. 检查是否已安装
    local target="$CLAUDE_SKILLS_DIR/$skill"
    if [[ ! -e "$target" ]]; then
        warn "  $skill 未安装（~/.claude/skills/$skill 不存在）"
    else
        rm -rf "$target"
        good "  ✓ 已从 ~/.claude/skills/ 删除"
    fi

    # 3. 从 third-party-skills.txt 中移除
    if [[ -f "$THIRD_PARTY_CONF" ]]; then
        if grep -qE "^[^#]*  $skill\$" "$THIRD_PARTY_CONF"; then
            local tmpfile=$(mktemp)
            grep -vE "^[^#]*  $skill\$" "$THIRD_PARTY_CONF" > "$tmpfile"
            mv "$tmpfile" "$THIRD_PARTY_CONF"
            good "  ✓ 已从 $THIRD_PARTY_CONF 移除"
        else
            info "  $skill 不在 third-party-skills.txt 清单中"
        fi
    fi

    # 4. 检查 npx skills 是否有对应安装
    if [[ -d "$HOME/.agents/skills/$skill" ]]; then
        warn "  $skill 在 ~/.agents/skills/ 仍有实体。手动删除："
        info "    rm -rf ~/.agents/skills/$skill"
    fi

    echo ""
    good "卸载完成：$skill"
}

do_status() {
    title "Skills 状态"
    echo -e "${CYAN}claude-skills/plugins/ (自建 $(ls "$SKILLS_SRC" 2>/dev/null | wc -l) 个)${NC}"
    for d in "$SKILLS_SRC"/*; do
        [[ -d "$d" ]] || continue
        echo -e "  ${GREEN}✓${NC} $(basename "$d")"
    done

    echo ""
    echo -e "${CYAN}~/.claude/skills/ ($(ls "$CLAUDE_SKILLS_DIR" 2>/dev/null | wc -l) 项)${NC}"
    for d in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -e "$d" ]] || continue
        local marker="✓"
        [[ -L "$d" ]] || marker="○"
        local src
        if [[ -L "$d" ]]; then
            local target=$(readlink -f "$d")
            if [[ "$target" == *"/claude-skills/plugins"* ]]; then
                src="claude-skills"
            elif [[ "$target" == *"$SKILLS_SRC"* ]]; then
                src="claude-skills"
            elif [[ "$target" == *".agents/skills"* ]]; then
                src="npx skills"
            else
                src="user"
            fi
        else
            src="(本地)"
        fi
        echo -e "  ${GREEN}$marker${NC} $(basename "$d") — $src"
    done

    echo ""
    echo -e "${CYAN}claude plugin list (marketplace 已装)${NC}"
    claude plugin list 2>&1 | head -10
    echo ""
}

action="${1:-sync}"
case "$action" in
    sync)    do_sync ;;
    update)  do_update ;;
    remove)  do_remove "$2" ;;
    cleanup) do_cleanup ;;
    list)    do_list ;;
    status)  do_status ;;
    diff)    do_diff ;;
    *)       echo "用法: $0 {sync|update|remove <name>|cleanup|list|status|diff}"; exit 1 ;;
esac

echo ""
good "提示: 新环境先跑 sync (装 CLI 依赖 + symlink 自建 + 装 npx 第三方)；更新跑 update (CLI + npx skills)；检测 drift 跑 diff"
exit 0
