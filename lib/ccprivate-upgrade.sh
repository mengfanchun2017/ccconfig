#!/bin/bash
# ccprivate-upgrade.sh — ccprivate 结构检测与升级
#
# 检测旧版 ccprivate 结构问题，一键修复到当前 ccconfig 期望的 v3 格式。
#
# 用法:
#   bash ccconfig/lib/ccprivate-upgrade.sh              # 检测 + 交互修复
#   bash ccconfig/lib/ccprivate-upgrade.sh --check-only  # 仅检测，不改动
#   bash ccconfig/lib/ccprivate-upgrade.sh --yes         # 检测 + 自动修复（跳过确认）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
CCCONFIG_DIR="$CCCONFIG_ROOT"
source "$SCRIPT_DIR/dry-run.sh"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/interact.sh"
source "$SCRIPT_DIR/path-helper.sh" 2>/dev/null || true

CCPRIVATE="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
CHECK_ONLY=false
AUTO_YES=false

for arg in "${@}"; do
    case "$arg" in
        --check-only) CHECK_ONLY=true ;;
        --yes|-y) AUTO_YES=true ;;
    esac
done

# ═══════════════════════════════════════════════════════════════
# 检测函数
# ═══════════════════════════════════════════════════════════════

check_generated_dir() {
    local gendir="$CCPRIVATE/conf/.generated"
    if [ ! -d "$gendir" ]; then
        return 0
    fi
    local files=()
    for f in "$gendir"/*.json; do
        [ -f "$f" ] || continue
        files+=("$(basename "$f")")
    done
    if [ ${#files[@]} -eq 0 ]; then
        return 0
    fi

    # 检查哪些已迁移、哪些未迁移
    local pending=() already=()
    for f in "${files[@]}"; do
        if [ -f "$CCPRIVATE/conf/$f" ]; then
            already+=("$f")
        else
            pending+=("$f")
        fi
    done

    echo -e "  ${YELLOW}⚠${NC}  conf/.generated/ 残留"
    [ ${#pending[@]} -gt 0 ] && echo -e "    待迁移: ${pending[*]}"
    [ ${#already[@]} -gt 0 ] && echo -e "    已存在 conf/ 中 (可安全删除 .generated/): ${already[*]}"
    return 1
}

check_directories() {
    local expected=("skill" "skill-local" "rules" "agents" "commands" "bin" "usage" "link/memory")
    local missing=()
    for d in "${expected[@]}"; do
        [ -d "$CCPRIVATE/$d" ] || missing+=("$d")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC}  缺少目录: ${missing[*]}"
        return 1
    fi
    return 0
}

check_setup_sh_version() {
    if [ ! -f "$CCPRIVATE/setup.sh" ]; then
        echo -e "  ${RED}❌${NC} setup.sh 缺失"
        return 1
    fi

    # v2 签名检测
    if grep -q 'shell_aliases' "$CCPRIVATE/setup.sh" 2>/dev/null; then
        echo -e "  ${RED}❌${NC} setup.sh 为旧版 (v2) — 含 shell_aliases 引用"
        return 1
    fi

    if grep -q 'link/projects' "$CCPRIVATE/setup.sh" 2>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC}  setup.sh 使用 link/projects/ 循环模式 (v2，与当前 v3 模板不同)"
        return 1
    fi

    # 检查是否含 v3 关键特征
    if grep -q 'resolve_conf' "$CCPRIVATE/setup.sh" 2>/dev/null && \
       grep -q 'link/memory' "$CCPRIVATE/setup.sh" 2>/dev/null; then
        return 0
    fi

    # 结构不同但无明确 v2 特征 → 可能是用户修改版
    if ! diff -q "$CCCONFIG_DIR/templates/ccprivate-setup.sh" "$CCPRIVATE/setup.sh" &>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC}  setup.sh 与当前模板不同（可能已自定义）"
        return 1
    fi
    return 0
}

check_link_content() {
    # link/ 只放共享文件 + .example 模板；settings.json/.config.json 是本机文件，
    # 存在但不跨机同步（gitignore），要求它们在 link/ 下会误报。查 .example 模板即可。
    local required=("CLAUDE.md" "settings.json.example" ".config.json.example" ".claudeignore.example")
    local missing=()
    for f in "${required[@]}"; do
        [ -f "$CCPRIVATE/link/$f" ] || missing+=("$f")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC}  link/ 缺少: ${missing[*]}"
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════
# 修复函数
# ═══════════════════════════════════════════════════════════════

fix_generated_dir() {
    local gendir="$CCPRIVATE/conf/.generated"
    [ -d "$gendir" ] || return 0

    local migrated=0 skipped=0
    for f in "$gendir"/*.json; do
        [ -f "$f" ] || continue
        local name=$(basename "$f")
        if [ -f "$CCPRIVATE/conf/$name" ]; then
            info "跳过 (已存在): $name"
            skipped=$((skipped + 1))
        else
            cp -n "$f" "$CCPRIVATE/conf/$name" 2>/dev/null || true
            ok "迁移: conf/.generated/$name → conf/$name"
            migrated=$((migrated + 1))
        fi
    done

    if [ $skipped -gt 0 ] || [ $migrated -gt 0 ]; then
        rm -rf "$gendir"
        ok "已删除 conf/.generated/"
    fi
}

fix_directories() {
    local dirs=("skill" "skill-local" "rules" "agents" "commands" "bin" "usage" "link/memory")
    for d in "${dirs[@]}"; do
        if [ ! -d "$CCPRIVATE/$d" ]; then
            mkdir -p "$CCPRIVATE/$d"
            ok "创建目录: $d/"
        fi
    done
}

fix_setup_sh() {
    local tpl="$CCCONFIG_DIR/templates/ccprivate-setup.sh"
    if [ ! -f "$tpl" ]; then
        err "模板缺失 $tpl，无法更新 setup.sh"
        return 1
    fi
    if [ -f "$CCPRIVATE/setup.sh" ]; then
        cp "$CCPRIVATE/setup.sh" "$CCPRIVATE/setup.sh.bak.$(date +%Y%m%d)"
        info "已备份: setup.sh.bak.$(date +%Y%m%d)"
    fi
    cp "$tpl" "$CCPRIVATE/setup.sh"
    chmod +x "$CCPRIVATE/setup.sh"
    ok "setup.sh 已更新（来自 templates/ccprivate-setup.sh）"
}

fix_link_content() {
    if [ ! -f "$CCPRIVATE/link/CLAUDE.md" ]; then
        local claude_tpl="$CCCONFIG_DIR/templates/CLAUDE.md.example"
        if [ -f "$claude_tpl" ]; then
            cp "$claude_tpl" "$CCPRIVATE/link/CLAUDE.md"
            ok "创建: link/CLAUDE.md（来自 templates/CLAUDE.md.example）"
        else
            err "模板缺失 $claude_tpl，无法创建 link/CLAUDE.md"
            return 1
        fi
    fi
    # 本机文件（LLM 选择/会话配置/context 策略）不跨机同步，只放 .example 模板
    local f
    for f in settings.json .config.json .claudeignore; do
        if [ -f "$CCCONFIG_DIR/templates/$f.example" ]; then
            cp "$CCCONFIG_DIR/templates/$f.example" "$CCPRIVATE/link/$f.example"
        else
            warn "模板缺失: $CCCONFIG_DIR/templates/$f.example"
        fi
    done
    ok "link/*.example 模板就绪"
}

fix_symlinks() {
    if [ -x "$CCPRIVATE/setup.sh" ]; then
        bash "$CCPRIVATE/setup.sh"
    else
        err "ccprivate/setup.sh 不可执行，无法重建 symlink"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  ccprivate 结构检测${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Guard: ccprivate 不存在
if [ ! -d "$CCPRIVATE" ]; then
    echo -e "  ${RED}❌${NC} ccprivate 目录不存在: $CCPRIVATE"
    echo -e "  ${GRAY}创建: bash ccconfig/init-bootstrap.sh${NC}"
    exit 1
fi

echo -e "  ccprivate: ${GREEN}$CCPRIVATE${NC}"
echo ""

# ── 执行所有检测 ──
declare -A check_results
total_issues=0

echo -e "${BOLD}1. .generated/ 迁移${NC}"
if check_generated_dir; then
    echo -e "  ${GREEN}✅${NC} 无需迁移"
    check_results[generated]="ok"
else
    check_results[generated]="fix"
    total_issues=$((total_issues + 1))
fi

echo ""
echo -e "${BOLD}2. 目录结构${NC}"
if check_directories; then
    echo -e "  ${GREEN}✅${NC} 目录完整"
    check_results[dirs]="ok"
else
    check_results[dirs]="fix"
    total_issues=$((total_issues + 1))
fi

echo ""
echo -e "${BOLD}3. setup.sh 版本${NC}"
if check_setup_sh_version; then
    echo -e "  ${GREEN}✅${NC} setup.sh 为当前版本"
    check_results[setup]="ok"
else
    check_results[setup]="fix"
    total_issues=$((total_issues + 1))
fi

echo ""
echo -e "${BOLD}4. link/ 内容${NC}"
if check_link_content; then
    echo -e "  ${GREEN}✅${NC} link/ 文件完整"
    check_results[link]="ok"
else
    check_results[link]="fix"
    total_issues=$((total_issues + 1))
fi

echo ""
echo -e "${BOLD}5. 符号链接${NC}"
echo -e "  ${GRAY}(修复阶段自动重建)${NC}"

echo ""

if [ $total_issues -eq 0 ]; then
    ok "ccprivate 结构已是最新"
    exit 0
fi

if $CHECK_ONLY; then
    echo -e "  ${YELLOW}发现 ${total_issues} 个问题${NC}"
    echo -e "  ${GRAY}修复: bash maintain.sh upgrade-ccprivate${NC}"
    exit 1
fi

# ── 确认 ──
if ! $AUTO_YES; then
    echo -e "${YELLOW}发现 ${total_issues} 个问题，将进行以下修复:${NC}"
    echo ""
    [ "${check_results[generated]}" = "fix" ] && echo "  • 迁移 conf/.generated/ → conf/"
    [ "${check_results[dirs]}" = "fix" ] && echo "  • 创建缺失目录"
    [ "${check_results[setup]}" = "fix" ] && echo "  • 更新 setup.sh (备份为 .bak)"
    [ "${check_results[link]}" = "fix" ] && echo "  • 创建缺失的 link/ 文件"
    echo "  • 重建所有符号链接"
    echo ""
    confirm "是否修复？" y || { info "已取消"; exit 0; }
fi

echo ""
echo -e "${CYAN}── 开始修复 ──${NC}"
echo ""

# 按顺序执行修复
[ "${check_results[generated]}" = "fix" ] && fix_generated_dir
[ "${check_results[dirs]}" = "fix" ] && fix_directories
[ "${check_results[link]}" = "fix" ] && fix_link_content
[ "${check_results[setup]}" = "fix" ] && fix_setup_sh

# 始终重建 symlink（确保链路正确）
echo ""
fix_symlinks

# 同步模板
if [ -x "$SCRIPT_DIR/example-sync.sh" ]; then
    echo ""
    bash "$SCRIPT_DIR/example-sync.sh" sync 2>/dev/null || true
fi

echo ""
ok "ccprivate 升级完成"
echo -e "  ${GRAY}验证: bash maintain.sh status${NC}"
