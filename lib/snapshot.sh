#!/bin/bash
# snapshot.sh — 关键配置快照 + 回滚
#
# 升级链此前无回滚：update.sh 只往 .snapshots/ 存版本号（不存文件），
# ccprivate-upgrade 只备份 setup.sh 一份 → 改坏了没法退。
# 本脚本在升级/初始化前把「本机独立 + 共享」的关键文件打包，支持一键恢复。
#
# 用法:
#   bash lib/snapshot.sh take [label]      # 打快照（默认 label=manual）
#   bash lib/snapshot.sh list              # 列出快照
#   bash lib/snapshot.sh restore <name>    # 恢复指定快照
#   bash lib/snapshot.sh prune [keep]      # 只保留最近 N 个（默认 10）
#
# 快照落点：~/.claude/ccconfig-snapshots/<时间戳>-<label>/
# 归档内容（存在才收）：
#   .claude/settings.json  .claude/.config.json  .claude/.claudeignore
#   .claude/.ccconfig-init  .claude/llm-current
#   ccprivate/setup.sh  ccprivate/conf/*.json  ccprivate/link/CLAUDE.md
# 不含：密钥类运行时文件之外的任何大目录（memory/skills/plugins 不入快照）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/colors.sh" 2>/dev/null || {
    ok() { echo "✅ $1"; }; warn() { echo "⚠️  $1"; }
    err() { echo "❌ $1"; }; info() { echo "ℹ️  $1"; }
}

CLAUDE_DIR="$HOME/.claude"
CCPRIVATE="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
SNAP_ROOT="$CLAUDE_DIR/ccconfig-snapshots"

take_snapshot() {
    local label="${1:-manual}"
    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local dir="$SNAP_ROOT/${ts}-${label}"

    mkdir -p "$dir/files/.claude" "$dir/files/ccprivate/conf"
    # 快照含真实密钥（settings.json 的 ANTHROPIC_AUTH_TOKEN / .config.json 的 MCP key）
    chmod 700 "$SNAP_ROOT" "$dir" "$dir/files" "$dir/files/.claude" "$dir/files/ccprivate" "$dir/files/ccprivate/conf" 2>/dev/null || true

    local n=0
    for f in settings.json .config.json .claudeignore .ccconfig-init llm-current; do
        if [ -f "$CLAUDE_DIR/$f" ]; then
            cp "$CLAUDE_DIR/$f" "$dir/files/.claude/$f" 2>/dev/null && n=$((n + 1))
        fi
    done
    if [ -f "$CCPRIVATE/setup.sh" ]; then
        cp "$CCPRIVATE/setup.sh" "$dir/files/ccprivate/setup.sh" && n=$((n + 1))
    fi
    if [ -d "$CCPRIVATE/conf" ]; then
        for f in "$CCPRIVATE/conf"/*.json; do
            [ -f "$f" ] || continue
            cp "$f" "$dir/files/ccprivate/conf/" 2>/dev/null && n=$((n + 1))
        done
    fi

    # 记录 ccconfig 自身 commit，便于归因
    {
        echo "snapshot_time=$(date --iso-8601=seconds 2>/dev/null || date)"
        echo "label=$label"
        echo "ccconfig_commit=$(git -C "$CCCONFIG_ROOT" rev-parse --short HEAD 2>/dev/null)"
        echo "ccconfig_branch=$(git -C "$CCCONFIG_ROOT" branch --show-current 2>/dev/null)"
        echo "files=$n"
    } > "$dir/meta.txt"

    ok "快照已建: $dir（$n 个文件）"
    prune_snapshots 10
}

list_snapshots() {
    [ -d "$SNAP_ROOT" ] || { info "无快照目录 ($SNAP_ROOT)"; return 0; }
    echo "快照目录: $SNAP_ROOT"
    local d
    for d in "$SNAP_ROOT"/*/; do
        [ -d "$d" ] || continue
        local meta="$d/meta.txt"
        if [ -f "$meta" ]; then
            printf '  %-32s %s\n' "$(basename "$d")" "$(grep '^files=' "$meta" | cut -d= -f2) 文件"
        else
            printf '  %s\n' "$(basename "$d")"
        fi
    done
}

restore_snapshot() {
    local name="$1"
    [ -n "$name" ] || { err "用法: snapshot.sh restore <name>"; return 1; }
    local dir="$SNAP_ROOT/$name"
    [ -d "$dir" ] || dir=$(ls -d "$SNAP_ROOT"/*"$name"*/ 2>/dev/null | head -1)
    [ -d "$dir" ] || { err "快照不存在: $name"; return 1; }

    info "从快照恢复: $(basename "$dir")"
    local restored=0
    for f in settings.json .config.json .claudeignore .ccconfig-init llm-current; do
        if [ -f "$dir/files/.claude/$f" ]; then
            # 先备份当前值，避免"恢复"本身造成不可逆
            [ -f "$CLAUDE_DIR/$f" ] && cp "$CLAUDE_DIR/$f" "$CLAUDE_DIR/$f.pre-restore.$(date +%s)" 2>/dev/null || true
            cp "$dir/files/.claude/$f" "$CLAUDE_DIR/$f" && { ok "  恢复 $f"; restored=$((restored + 1)); }
        fi
    done
    if [ -f "$dir/files/ccprivate/setup.sh" ]; then
        cp "$dir/files/ccprivate/setup.sh" "$CCPRIVATE/setup.sh" && chmod +x "$CCPRIVATE/setup.sh" && { ok "  恢复 ccprivate/setup.sh"; restored=$((restored + 1)); }
    fi
    for f in "$dir/files/ccprivate/conf"/*.json; do
        [ -f "$f" ] || continue
        cp "$f" "$CCPRIVATE/conf/" && { ok "  恢复 conf/$(basename "$f")"; restored=$((restored + 1)); }
    done
    ok "恢复完成（$restored 个文件）。当前值已另存 .pre-restore.<时间戳>"
}

prune_snapshots() {
    local keep="${1:-10}"
    [ -d "$SNAP_ROOT" ] || return 0
    local all; all=$(ls -1d "$SNAP_ROOT"/*/ 2>/dev/null | sort)
    local total; total=$(printf '%s\n' "$all" | grep -c . || echo 0)
    [ "$total" -le "$keep" ] && return 0
    local drop=$((total - keep))
    printf '%s\n' "$all" | head -n "$drop" | while IFS= read -r d; do
        [ -d "$d" ] && rm -rf "$d" && info "  清理旧快照: $(basename "$d")"
    done
}

case "${1:-}" in
    take|"")  take_snapshot "${2:-manual}" ;;
    list)     list_snapshots ;;
    restore)  restore_snapshot "${2:-}" ;;
    prune)    prune_snapshots "${2:-10}" ;;
    *)
        echo "用法: bash lib/snapshot.sh {take [label]|list|restore <name>|prune [keep]}"
        exit 1 ;;
esac