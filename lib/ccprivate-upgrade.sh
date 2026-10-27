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
    # skill-local 已删（2026-10-27）：私有 skill 机制从未被使用（目录长期只有 .gitkeep），
    # 实体统一放公开的 ~/git/skill/plugins。此处再要求它会每次 status 报缺目录。
    local expected=("skill" "rules" "agents" "commands" "bin" "link/memory")
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

    # 与模板逐字节比对才是"最新"的唯一判据。
    # 旧逻辑用 grep 'resolve_conf'/'link/memory' 判 v3 —— 这两个串在注释里就命中，
    # 于是任何被本机改过的 setup.sh 都被误判"已是最新"，自定义改动静默留在原地，
    # 直到上游改注释才突然被判 fix → 无条件 cp 覆盖，自定义消失。
    if diff -q "$CCCONFIG_DIR/templates/ccprivate-setup.sh" "$CCPRIVATE/setup.sh" &>/dev/null; then
        return 0
    fi

    echo -e "  ${YELLOW}⚠${NC}  setup.sh 与模板不同（本机有修改，或模板已更新）"
    return 1
}

check_link_content() {
    # link/ 只放共享文件；settings.json/.config.json/.claudeignore 是本机文件，从
    # ccconfig/templates/*.example 一次性 cp，不在本仓（要求它们在这会误报）。
    # 2026-10-27 起 link/*.example 副本已删 —— 模板唯一真相源 = ccconfig/templates/。
    local required=("CLAUDE.md")
    local missing=() stale=()
    for f in "${required[@]}"; do
        [ -f "$CCPRIVATE/link/$f" ] || missing+=("$f")
    done
    # 已废弃模板副本也算"需修"——否则老机器上的残留永远不会被清（见下方 fix）。
    for f in settings.json .config.json .claudeignore; do
        [ -f "$CCPRIVATE/link/$f.example" ] && stale+=("$f.example")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC}  link/ 缺少: ${missing[*]}"
        return 1
    fi
    if [ ${#stale[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC}  link/ 有已废弃模板副本: ${stale[*]}"
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
    local dirs=("skill" "rules" "agents" "commands" "bin" "link/memory")
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
        # 备份带时分秒：旧写法只到日，同一天第二次升级会覆盖当天备份，
        # 恰好把"升级前那一版"弄丢。后缀同时被 ccprivate/.gitignore 的 setup.sh.bak.* 挡住。
        local _bak="$CCPRIVATE/setup.sh.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$CCPRIVATE/setup.sh" "$_bak"
        info "已备份: $(basename "$_bak")"
    fi
    mark_init_version 2>/dev/null || true

    # 本机改过的 setup.sh（与模板不同且非已知旧版）不直接覆盖 —— 静默丢弃用户的
    # 自定义会连带丢功能（如项目级记忆 symlink）。改为另存 .new 让人工合并，或确认后覆盖。
    if [ -f "$CCPRIVATE/setup.sh" ] && ! diff -q "$tpl" "$CCPRIVATE/setup.sh" &>/dev/null; then
        if [ "${CCPRIVATE_SETUP_FORCE:-0}" = "1" ]; then
            cp "$tpl" "$CCPRIVATE/setup.sh"
            chmod +x "$CCPRIVATE/setup.sh"
            ok "setup.sh 已强制覆盖（CCPRIVATE_SETUP_FORCE=1）"
        else
            cp "$tpl" "$CCPRIVATE/setup.sh.new"
            warn "setup.sh 本机有修改，未覆盖 —— 新版已存为 setup.sh.new"
            info "  合并: diff $CCPRIVATE/setup.sh $CCPRIVATE/setup.sh.new"
            info "  放弃本机改动: CCPRIVATE_SETUP_FORCE=1 bash maintain.sh fix"
        fi
        return 0
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
    # 本机文件（LLM 选择/会话配置/context 策略）的模板唯一真相源是
    # ccconfig/templates/*.example，setup.sh 直接从那里 cp。此前这里往
    # ccprivate/link/ 复制一份副本 → 两处模板必然漂移，2026-10-27 已删副本。
    # 残留清理：老机器升级时把历史副本移除（setup.sh 已不读它们）。
    local f
    for f in settings.json .config.json .claudeignore; do
        [ -f "$CCPRIVATE/link/$f.example" ] && rm -f "$CCPRIVATE/link/$f.example"
    done
    ok "link/ 就绪（模板统一走 ccconfig/templates/）"
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
    [ "${check_results[link]}" = "fix" ] && echo "  • 补齐 link/ 文件 + 清理已废弃模板副本"
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
