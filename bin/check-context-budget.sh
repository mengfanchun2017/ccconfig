#!/bin/bash
# check-context-budget.sh — 检查 rules context 预算，超限非零退出
# 用法: bash ccconfig/bin/check-context-budget.sh [--quiet]
#
# 硬上限（见 rules/context-budget.md）：
#   always-loaded < 15KB  |  总计（含 path-scoped）< 20KB

set -euo pipefail

RULES_DIR="${RULES_DIR:-$HOME/.claude/rules}"
[ -d "$RULES_DIR" ] || RULES_DIR="$HOME/git/ccprivate/rules"

ALWAYS_LIMIT=15360   # 15 KB
TOTAL_LIMIT=20480    # 20 KB
QUIET=false
JSON=false
for _a in "$@"; do
    [[ "$_a" == "--quiet" ]] && QUIET=true
    [[ "$_a" == "--json" ]] && JSON=true
done

[ -d "$RULES_DIR" ] || { echo "rules 目录不存在: $RULES_DIR"; exit 2; }

always=0; scoped=0
always_files=(); scoped_files=()

for f in "$RULES_DIR"/*.md; do
    [ -f "$f" ] || continue
    sz=$(stat -c %s "$f")
    base=$(basename "$f")
    # path-scoped = frontmatter 含 paths: 行
    if head -20 "$f" | grep -q '^paths:'; then
        scoped=$((scoped + sz))
        scoped_files+=("$base")
    else
        always=$((always + sz))
        always_files+=("$base")
    fi
done

total=$((always + scoped))
rc=0

if $JSON; then
    :  # 延后到 limit 检查之后统一输出（要带 ok 字段）
fi

if ! $QUIET && ! $JSON; then
    echo "# Rules Context 预算 ($(date +%Y-%m-%d))"
    echo ""
    echo "  always-loaded: $always bytes ($(awk "BEGIN{printf \"%.1f\", $always/1024}") KB)  上限 $((ALWAYS_LIMIT/1024)) KB  [${#always_files[@]} 文件]"
    echo "  path-scoped:   $scoped bytes ($(awk "BEGIN{printf \"%.1f\", $scoped/1024}") KB)  [${#scoped_files[@]} 文件]"
    echo "  总计:          $total bytes ($(awk "BEGIN{printf \"%.1f\", $total/1024}") KB)  上限 $((TOTAL_LIMIT/1024)) KB"
    echo ""
fi

if [ "$always" -gt "$ALWAYS_LIMIT" ]; then
    echo "  ❌ always-loaded 超限 $((always - ALWAYS_LIMIT)) bytes" >&2
    echo "     超限文件: $(for x in "${always_files[@]}"; do printf '%s(%d) ' "$x" "$(stat -c %s "$RULES_DIR/$x")"; done)" >&2
    rc=1
fi
if [ "$total" -gt "$TOTAL_LIMIT" ]; then
    echo "  ❌ 总计超限 $((total - TOTAL_LIMIT)) bytes" >&2
    rc=1
fi

if $JSON; then
    python3 -c "import json; print(json.dumps({'always_bytes':$always,'scoped_bytes':$scoped,'total_bytes':$total,'always_kb':round($always/1024,1),'total_kb':round($total/1024,1),'always_files':${#always_files[@]},'scoped_files':${#scoped_files[@]},'ok':$( [ "$rc" -eq 0 ] && echo True || echo False )}))"
else
    if [ "$rc" -eq 0 ]; then
        ! $QUIET && echo "  ✅ 预算内"
    else
        echo "  瘦身方向: 长 rule 拆到 skill reference / 加 paths frontmatter 收窄为 path-scoped / 合并重复节" >&2
    fi
fi

exit $rc