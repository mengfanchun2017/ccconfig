#!/bin/bash
# 回归测试：密钥正则单一真相源 + 消费方接线
#
# 背景：pre-commit 与 example-sync.sh 各自写过一份 KEY_RE，漂移过（漏 tavily/
# cloudflare/supabase/Exa 四类）。现在统一在 lib/secret-patterns.sh。
#
# 2026-10-25 又漏过第 5 类：lark-cli 飞书 Base 导出的 *.manifest.json（真 base_token/
# table_id/record_id/file_token 被 auto-sync 直接推上公开库）。以下为防回归样本。
#
# 注意：本文件不能出现字面量的密钥样本 —— pre-commit hook 会命中并阻断提交。
# 样本一律运行时拼装（A 段 + 重复字符），文件内容对正则是干净的。

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "=== 密钥正则 ==="

source lib/secret-patterns.sh
[ -n "${SECRET_RE:-}" ] && pass "SECRET_RE 已定义" || fail "SECRET_RE 未定义"

# 运行时拼装样本：前缀 + 足量重复字符，避免字面量落盘
rep() { local n="$1" c="$2"; printf "%0.s$c" $(seq 1 "$n"); }

# 飞书 Base 导出类按 JSON 字段名匹配，样本也要拼成字段名+值的形式
jf() { printf '"%s": "%s"' "$1" "$2"; }

declare -a samples=(
    "sk-$(rep 24 a)"
    "sk-ant-$(rep 24 a)"
    "github_pat_$(rep 24 a)"
    "ghp_$(rep 36 a)"
    "tvly-$(rep 16 a)"
    "cfut_$(rep 16 a)"
    "sbp_$(rep 32 a)"
    "sb_secret_$(rep 24 a)"
    "sb_publishable_$(rep 24 a)"
    "$(jf base_token "$(rep 20 a)")"
    "$(jf table_id "tbl$(rep 12 b)")"
    "$(jf file_token "$(rep 24 c)")"
    "$(jf record_id "rec$(rep 12 d)")"
)
for k in "${samples[@]}"; do
    if printf '%s' "$k" | grep -qE "$SECRET_RE"; then
        pass "命中: ${k:0:12}…"
    else
        fail "漏检前缀: ${k:0:12}…"
    fi
done

# 占位符/普通文本不得命中（防误报阻断正常提交）
for clean in '请填入你的 Tavily Key' 'your-api-key-here' '正常的中文说明文本' 'model: claude-sonnet-5-5' \
             '"base_token": "<base_token>"' '"table_id": "tbl"' '--base-token <base_token>' \
             '"record_id": "rec-占位"' '"file_token": "FILE_TOKEN"'; do
    if printf '%s' "$clean" | grep -qE "$SECRET_RE"; then
        fail "误报: $clean"
    else
        pass "不误报: $clean"
    fi
done

echo ""
echo "=== 消费方接线 ==="
grep -q 'secret-patterns.sh' lib/example-sync.sh && \
    pass "example-sync.sh source 了 secret-patterns.sh" || \
    fail "example-sync.sh 未接线"
grep -q 'FORCE_REVERSE' lib/example-sync.sh && \
    pass "reverse 有密钥闸（含 FORCE_REVERSE 越权口）" || \
    fail "reverse 缺密钥闸"
grep -q '写入后复检' lib/example-sync.sh && \
    pass "reverse 有写后复检" || fail "reverse 缺写后复检"

echo ""
echo "=== 本文件自查：不得含字面量密钥样本 ==="
if grep -qE "$SECRET_RE" "$0" 2>/dev/null; then
    fail "本文件含字面量密钥样本（会被 pre-commit 拦）"
else
    pass "本文件对正则是干净的"
fi

echo ""
echo "────────────────────────────────────"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "────────────────────────────────────"
[ "$FAIL" -eq 0 ]