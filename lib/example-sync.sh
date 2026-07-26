#!/bin/bash
# example-sync.sh — 模板同步管理
#
# 管理 ccconfig .example 与 ccprivate 运行时文件的同步。
# .example 是上游模板，ccprivate 是用户实际加载的文件。
#
# 用法：
#   bash ccconfig/lib/example-sync.sh status           # 差异检测
#   bash ccconfig/lib/example-sync.sh diff [file]       # 查看差异内容
#   bash ccconfig/lib/example-sync.sh promote [file]    # 正向: ccconfig → ccprivate
#   bash ccconfig/lib/example-sync.sh reverse [file]    # 反向: ccprivate → ccconfig（需写权限）
#   bash ccconfig/lib/example-sync.sh sync              # 非交互自动同步（仅新增）
#
# 文件匹配规则：
#   ccconfig/templates/rules/<name>.md.example  →  ccprivate/rules/<name>.md
#   ccconfig/templates/agents/<name>.md.example →  ccprivate/agents/<name>.md
#   ccconfig/conf/<name>.json.example       →  ccprivate/conf/<name>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
CCPRIVATE="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

source "$SCRIPT_DIR/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; DIM='\033[2m'; NC='\033[0m'
    ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
    err()   { echo -e "  ${RED}❌ $1${NC}"; }
    warn()  { echo -e "  ${YELLOW}⚠  $1${NC}"; }
    info()  { echo -e "  ${GRAY}$1${NC}"; }
    section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
}

# ── 路径映射 ──

# .example 路径 → ccprivate 路径
derive_ccprivate() {
    local example="$1"
    local rel="${example#$CCCONFIG_ROOT/}"
    if [[ "$rel" == templates/rules/*.md.example ]]; then
        local base; base=$(basename "$example" .md.example)
        echo "$CCPRIVATE/rules/${base}.md"
    elif [[ "$rel" == templates/agents/*.md.example ]]; then
        local base; base=$(basename "$example" .md.example)
        echo "$CCPRIVATE/agents/${base}.md"
    elif [[ "$rel" == conf/*.example ]]; then
        local base; base=$(basename "$example" .example)
        echo "$CCPRIVATE/conf/$base"
    fi
}

# ccprivate 路径 → .example 路径
derive_example() {
    local ccprivate_file="$1"
    local rel="${ccprivate_file#$CCPRIVATE/}"
    if [[ "$rel" == rules/*.md ]]; then
        local base; base=$(basename "$ccprivate_file" .md)
        echo "$CCCONFIG_ROOT/templates/rules/${base}.md.example"
    elif [[ "$rel" == agents/*.md ]]; then
        local base; base=$(basename "$ccprivate_file" .md)
        echo "$CCCONFIG_ROOT/templates/agents/${base}.md.example"
    elif [[ "$rel" == conf/* ]]; then
        local base; base=$(basename "$ccprivate_file")
        echo "$CCCONFIG_ROOT/conf/${base}.example"
    fi
}

# ── 写权限检查 ──
check_write_permission() {
    if git -C "$CCCONFIG_ROOT" push --dry-run origin HEAD &>/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# ── 收集差异 ──
collect_diffs() {
    local -n _outdated="$1" _new="$2"
    local mapping=(
        "templates/rules:rules:.md.example:.md"
        "templates/agents:agents:.md.example:.md"
        "conf:conf:.json.example:.json"
    )

    for entry in "${mapping[@]}"; do
        local src_dir="${entry%%:*}"
        local rest="${entry#*:}"
        local dst_dir="${rest%%:*}"
        rest="${rest#*:}"
        local src_suffix="${rest%%:*}"
        local dst_suffix="${rest#*:}"

        for example in "$CCCONFIG_ROOT/$src_dir/"*"$src_suffix"; do
            [ -f "$example" ] || continue
            local target; target=$(derive_ccprivate "$example")
            [ -z "$target" ] && continue
            if [ ! -f "$target" ]; then
                _new+=("$example")
            elif ! diff -q "$example" "$target" &>/dev/null; then
                _outdated+=("$example")
            fi
        done
    done
}

# ── 状态显示 ──
do_status() {
    section "Example 模板同步状态"
    echo ""

    local -a outdated=() new_files=()
    collect_diffs outdated new_files

    if [ ${#outdated[@]} -eq 0 ] && [ ${#new_files[@]} -eq 0 ]; then
        ok "全部同步"
        return 0
    fi

    [ ${#outdated[@]} -gt 0 ] && echo -e "  ${YELLOW}${#outdated[@]} 个差异文件${NC}:"
    for f in "${outdated[@]}"; do
        local rel="${f#$CCCONFIG_ROOT/}"
        if [[ "$rel" == conf/* ]]; then
            echo -e "    ${GRAY}→${NC} $rel  ${DIM}(conf，可能含密钥)${NC}"
        else
            echo -e "    ${GRAY}→${NC} $rel"
        fi
    done

    [ ${#new_files[@]} -gt 0 ] && echo -e "  ${CYAN}${#new_files[@]} 个新增模板${NC}:"
    for f in "${new_files[@]}"; do
        local rel="${f#$CCCONFIG_ROOT/}"
        echo -e "    ${GRAY}→${NC} $rel"
    done

    echo ""
    echo -e "  ${GRAY}操作: diff 查看 | promote 正向 | reverse 反向${NC}"
}

# ── 单文件 diff ──
_diff_one() {
    local example="$1"
    local rel="${example#$CCCONFIG_ROOT/}"
    local target; target=$(derive_ccprivate "$example")

    echo -e "${CYAN}── ${rel} ──${NC}"
    if [ -n "$target" ] && [ -f "$target" ]; then
        diff -u "$example" "$target" || true
    else
        echo -e "  ${YELLOW}ccprivate 中尚不存在${NC}"
        echo -e "  ${GRAY}模板内容（前 30 行）:${NC}"
        head -30 "$example"
    fi
    echo ""
}

do_diff() {
    local target="${1:-}"

    if [ -n "$target" ]; then
        local example
        # 接受 .example 路径或 ccprivate 路径
        if [[ "$target" == *.example ]] || [[ "$target" == templates/* ]] || [[ "$target" == conf/*.example ]]; then
            [[ "$target" != /* ]] && target="$CCCONFIG_ROOT/$target"
            example="$target"
        else
            # 尝试作为 ccprivate 路径处理
            [[ "$target" != /* ]] && target="$CCPRIVATE/$target"
            example=$(derive_example "$target")
        fi
        [ -n "${example:-}" ] && [ -f "${example:-}" ] || { err "找不到: $target"; return 1; }
        _diff_one "$example"
        return
    fi

    local -a outdated=() new_files=()
    collect_diffs outdated new_files
    local all=("${outdated[@]}" "${new_files[@]}")
    [ ${#all[@]} -eq 0 ] && { ok "无差异"; return 0; }

    for f in "${all[@]}"; do
        _diff_one "$f"
    done
}

# ── 正向 promote: ccconfig → ccprivate ──
promote_one() {
    local example="$1"
    [ -f "$example" ] || { err "文件不存在: $example"; return 1; }

    local rel="${example#$CCCONFIG_ROOT/}"
    local dst; dst=$(derive_ccprivate "$example")
    [ -z "$dst" ] && { err "未知类别: $rel"; return 1; }

    mkdir -p "$(dirname "$dst")"
    cp "$example" "$dst"
    ok "$rel → ${dst#$CCPRIVATE/}"
}

do_promote_interactive() {
    local -a outdated=() new_files=()
    collect_diffs outdated new_files
    local all=("${outdated[@]}" "${new_files[@]}")
    [ ${#all[@]} -eq 0 ] && { ok "无待同步文件"; return 0; }

    echo ""
    section "选择要 promote 的文件（ccconfig → ccprivate）"
    echo ""

    local idx=1
    local -A choices=()
    for f in "${outdated[@]}"; do
        local rel="${f#$CCCONFIG_ROOT/}"
        local tag=""; [[ "$rel" == conf/* ]] && tag=" ${DIM}(conf)${NC}"
        echo -e "  ${BOLD}${idx})${NC} $rel  ${YELLOW}(差异)${NC}$tag"
        choices[$idx]="$f"
        idx=$((idx + 1))
    done
    for f in "${new_files[@]}"; do
        local rel="${f#$CCCONFIG_ROOT/}"
        echo -e "  ${BOLD}${idx})${NC} $rel  ${CYAN}(新增)${NC}"
        choices[$idx]="$f"
        idx=$((idx + 1))
    done
    echo "  a) 全部"
    echo "  0) 取消"
    echo ""

    read -p "选择: " sel
    [ "$sel" = "0" ] && { echo ""; info "已取消"; return 0; }

    if [ "$sel" = "a" ]; then
        echo ""
        for f in "${all[@]}"; do
            promote_one "$f"
        done
        echo ""
        ok "所有文件已正向同步"
        return 0
    fi

    for n in $sel; do
        if [ -n "${choices[$n]:-}" ]; then
            echo ""
            promote_one "${choices[$n]}"
        fi
    done
    echo ""
    ok "操作完成"
}

# ── 反向 promote: ccprivate → ccconfig ──
reverse_one() {
    local ccprivate_file="$1"
    [ -f "$ccprivate_file" ] || { err "文件不存在: $ccprivate_file"; return 1; }

    local rel="${ccprivate_file#$CCPRIVATE/}"
    local example; example=$(derive_example "$ccprivate_file")
    [ -z "$example" ] && { err "无法识别文件类别: $rel"; return 1; }
    [ ! -f "$example" ] && { err ".example 模板不存在: ${example#$CCCONFIG_ROOT/}（反向同步仅支持已有模板的更新，新建模板请手动创建 .example）"; return 1; }

    # 权限检查
    if ! check_write_permission; then
        err "没有 ccconfig 仓库写权限，无法反向同步"
        info "→ 如已 fork，请提 PR 贡献改动"
        return 1
    fi

    # conf 文件特殊处理：必须展示 diff + 人工确认
    if [[ "$rel" == conf/* ]]; then
        warn "conf 文件可能含密钥/token，请确认不会泄露敏感值"
        echo ""
        diff -u "$example" "$ccprivate_file" || true
        echo ""
        read -p "确认反向同步此 conf 文件？[y/N]: " confirm
        [[ "$confirm" =~ ^[Yy] ]] || { info "已取消"; return 0; }
    fi

    cp "$ccprivate_file" "$example"
    ok "反向同步: ${rel} → ${example#$CCCONFIG_ROOT/}"
    info "记得 git add + commit + push"
}

do_reverse() {
    if ! check_write_permission; then
        err "没有 ccconfig 仓库写权限"
        info "→ 反向同步需要 push 权限。如已 fork，请提 PR"
        return 1
    fi

    local -a _out_arr=()
    local -a _new_arr=()
    collect_diffs _out_arr _new_arr
    [ ${#_out_arr[@]} -eq 0 ] && { ok "无差异文件，不需要反向同步"; return 0; }

    echo ""
    section "反向同步（ccprivate → ccconfig .example）"
    echo ""

    local idx=1
    local -A choices=()
    for f in "${_out_arr[@]}"; do
        local rel="${f#$CCCONFIG_ROOT/}"
        local tag=""; [[ "$rel" == conf/* ]] && tag=" ${RED}(敏感⚠)${NC}"
        echo -e "  ${BOLD}${idx})${NC} $rel$tag"
        choices[$idx]="$f"
        idx=$((idx + 1))
    done
    echo "  a) 全部"
    echo "  0) 取消"
    echo ""

    read -p "选择: " sel
    [ "$sel" = "0" ] && { echo ""; info "已取消"; return 0; }

    if [ "$sel" = "a" ]; then
        echo ""
        for f in "${_out_arr[@]}"; do
            local ccprivate_file; ccprivate_file=$(derive_ccprivate "$f")
            [ -n "$ccprivate_file" ] && [ -f "$ccprivate_file" ] && reverse_one "$ccprivate_file"
        done
        echo ""
        ok "全部反向同步完成"
        return 0
    fi

    for n in $sel; do
        if [ -n "${choices[$n]:-}" ]; then
            echo ""
            local ccprivate_file; ccprivate_file=$(derive_ccprivate "${choices[$n]}")
            [ -n "$ccprivate_file" ] && [ -f "$ccprivate_file" ] && reverse_one "$ccprivate_file"
        fi
    done
    echo ""
    ok "操作完成"
}

# ── 非交互自动同步 ──
do_sync() {
    local -a _out_arr=() _new_arr=()
    collect_diffs _out_arr _new_arr
    if [ ${#_new_arr[@]} -eq 0 ] && [ ${#_out_arr[@]} -eq 0 ]; then
        ok "模板已是最新"
        return 0
    fi
    for f in "${_new_arr[@]}"; do
        local rel="${f#$CCCONFIG_ROOT/}"
        promote_one "$f" > /dev/null 2>&1
        info "新增: $rel"
    done
    [ ${#_out_arr[@]} -gt 0 ] && warn "${#_out_arr[@]} 个差异文件未覆盖（可能含用户编辑，手动 diff + promote 或 reverse）"
    ok "模板同步完成"
}

# ── 入口 ──
case "${1:-status}" in
    status)
        do_status
        ;;
    diff)
        do_diff "${2:-}"
        ;;
    sync)
        do_sync
        ;;
    promote)
        if [ -n "${2:-}" ]; then
            file="$2"
            [[ "$file" != /* ]] && file="$CCCONFIG_ROOT/$file"
            promote_one "$file"
        else
            do_promote_interactive
        fi
        ;;
    reverse)
        if [ -n "${2:-}" ]; then
            file="$2"
            [[ "$file" != /* ]] && file="$CCPRIVATE/$file"
            reverse_one "$file"
        else
            do_reverse
        fi
        ;;
    *)
        echo "用法: bash ccconfig/lib/example-sync.sh [status|diff|promote|reverse|sync] [file]"
        exit 1
        ;;
esac
