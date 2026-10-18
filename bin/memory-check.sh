#!/bin/bash
# memory-check.sh — 检查 memory 文件新鲜度，标记 stale 候选
# 用法: bash ccconfig/bin/memory-check.sh [--stale-only]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_DIR="$HOME/.claude/projects/-$(echo "$HOME/git/ccconfig" | sed 's|^/||; s|/|-|g')/memory"
INDEX="$MEMORY_DIR/MEMORY.md"
NOW=$(date +%s)

if [[ ! -d "$MEMORY_DIR" ]]; then
  echo "memory dir not found: $MEMORY_DIR"
  exit 1
fi

echo "# Memory 新鲜度报告 ($(date +%Y-%m-%d))"
echo ""

stale=0; fresh=0; orphan=0

for md in "$MEMORY_DIR"/*.md; do
  fname=$(basename "$md")
  [[ "$fname" == "MEMORY.md" ]] && continue

  mtime=$(stat -c %Y "$md")
  age_days=$(( (NOW - mtime) / 86400 ))

  # Determine staleness
  if [[ $age_days -gt 180 ]]; then
    status="⚠️  STALE"
    stale=$((stale + 1))
  else
    [[ "${1:-}" == "--stale-only" ]] && continue
    status="✅"
    fresh=$((fresh + 1))
  fi

  # Orphan check
  orphan_mark=""
  if ! grep -qF "($fname)" "$INDEX" 2>/dev/null; then
    orphan_mark=" [ORPHAN]"
    orphan=$((orphan + 1))
  fi

  printf "  %s  %4dd  %s%s\n" "$status" "$age_days" "$fname" "$orphan_mark"
done

echo ""
echo "---"
echo "stale (>180d): $stale | fresh: $fresh | orphan: $orphan"

# MEMORY.md 条目数上限（rules/context-budget.md 定 <40）。
# 此前无人检查：条目堆到 84 条、索引重复也无人报警，规则形同虚设。
# 这里只报数不自动删 —— 删哪些是用户判断。
entries=$(grep -cE '^- \[' "$INDEX" 2>/dev/null || echo 0)
echo "MEMORY.md 条目: $entries（上限 40）"
if [[ $entries -gt 40 ]]; then
  echo "⚠️  超上限 $((entries - 40)) 条 — 按 rules/context-budget.md 做季度 review 合并/归档"
fi
echo ""

if [[ $stale -gt 0 ]]; then
  echo "清理: 编辑 $INDEX 移除 stale 条目，文件保留在磁盘可恢复"
fi
if [[ $orphan -gt 0 ]]; then
  echo "清理: 删孤儿文件或加回 MEMORY.md 索引"
fi
