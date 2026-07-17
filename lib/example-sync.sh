#!/bin/bash
# example-sync.sh — 模板同步管理
#
# 管理 ccconfig .example 与 ccprivate 运行时文件的同步。
# .example 是上游模板，ccprivate 是用户实际加载的文件。
#
# 用法：
#   bash ccconfig/lib/example-sync.sh status          # 差异检测
#   bash ccconfig/lib/example-sync.sh promote          # 交互式推动
#   bash ccconfig/lib/example-sync.sh promote <file>   # 单文件推动
#
# 文件匹配规则：
#   ccconfig/link/rules/<name>.md.example  →  ccprivate/rules/<name>.md
#   ccconfig/link/agents/<name>.md.example →  ccprivate/agents/<name>.md
#   ccconfig/conf/<name>.json.example       →  ccprivate/conf/<name> (不含 .example)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
CCPRIVATE="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

source "$SCRIPT_DIR/colors.sh" 2>/dev/null || {
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
    RED='\033[0;31m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'
}

info() { echo -e "  ${GRAY}$1${NC}"; }
ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
err()  { echo -e "  ${RED}❌ $1${NC}"; }

# ── 收集差异 ──
# 返回数组: outdated=("path1" "path2")  new_files=("path3")
collect_diffs() {
    local -n _outdated="$1" _new="$2"
    local mapping=(
        "link/rules:rules:.md.example:.md"
        "link/agents:agents:.md.example:.md"
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
            local base
            base=$(basename "$example" "$src_suffix")
            local target="$CCPRIVATE/$dst_dir/${base}${dst_suffix}"
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
    echo -e "${CYAN}━━━ Example 模板同步状态 ─━━${NC}"
    echo ""

    local -a outdated=() new_files=()
    collect_diffs outdated new_files

    if [ ${#outdated[@]} -eq 0 ] && [ ${#new_files[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✅ 全部同步${NC}"
        return 0
    fi

    [ ${#outdated[@]} -gt 0 ] && echo -e "  ${YELLOW}${#outdated[@]} 个过期文件${NC}:"
    for f in "${outdated[@]}"; do
        local rel="${f#$CCCONFIG_ROOT/}"
        echo -e "    ${GRAY}→${NC} $rel"
    done

    [ ${#new_files[@]} -gt 0 ] && echo -e "  ${CYAN}${#new_files[@]} 个新增模板${NC}:"
    for f in "${new_files[@]}"; do
        local rel="${f#$CCCONFIG_ROOT/}"
        echo -e "    ${GRAY}→${NC} $rel"
    done

    echo ""
    echo -e "  ${GRAY}运行 promote 推送: bash ccconfig/lib/example-sync.sh promote${NC}"
}

# ── 单文件 promote ──
# 参数: 源文件路径（ccconfig 中的 .example 路径）
promote_one() {
    local example="$1"
    [ -f "$example" ] || { err "文件不存在: $example"; return 1; }

    # 判断源路径类别
    local rel="${example#$CCCONFIG_ROOT/}"
    local base dst

    if [[ "$rel" == link/rules/*.md.example ]]; then
        base=$(basename "$example" .md.example)
        dst="$CCPRIVATE/rules/${base}.md"
    elif [[ "$rel" == link/agents/*.md.example ]]; then
        base=$(basename "$example" .md.example)
        dst="$CCPRIVATE/agents/${base}.md"
    elif [[ "$rel" == conf/*.json.example ]]; then
        base=$(basename "$example" .example)
        dst="$CCPRIVATE/conf/$base"
    else
        err "未知类别: $rel"
        return 1
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$example" "$dst"
    ok "$rel → ${dst#$CCPRIVATE/}"
}

# ── 交互式 promote ──
do_promote_interactive() {
    local -a outdated=() new_files=()
    collect_diffs outdated new_files
    local all=("${outdated[@]}" "${new_files[@]}")
    [ ${#all[@]} -eq 0 ] && { echo -e "${GREEN}✅ 无待同步文件${NC}"; return 0; }

    echo ""
    echo -e "${CYAN}━━━ 选择要 promote 的文件 ─━━${NC}"
    echo ""

    # 分组显示
    local idx=1
    local -A choices=()
    for f in "${outdated[@]}"; do
        local rel="${f#$CCCONFIG_ROOT/}"
        echo -e "  ${BOLD}${idx})${NC} $rel  ${YELLOW}(过期)${NC}"
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
        ok "所有文件已同步"
        return 0
    fi

    # 单文件或区间
    for n in $sel; do
        if [ -n "${choices[$n]:-}" ]; then
            echo ""
            promote_one "${choices[$n]}"
        fi
    done
    echo ""
    ok "操作完成"
}

# ── 入口 ──
case "${1:-status}" in
    status)
        do_status
        ;;
    promote)
        if [ -n "${2:-}" ]; then
            # 接收相对路径或绝对路径
            file="$2"
            [[ "$file" != /* ]] && file="$CCCONFIG_ROOT/$file"
            promote_one "$file"
        else
            do_promote_interactive
        fi
        ;;
    *)
        echo "用法: bash ccconfig/lib/example-sync.sh [status|promote [file]]"
        exit 1
        ;;
esac
