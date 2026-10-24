#!/bin/bash
# 回归测试：dry_run_parse_argv 让 `bash lib/x.sh --dry-run` 真正生效
#
# 背景：run() 曾在被包装命令自己的参数里找 --dry-run，永远找不到 →
# 「--dry-run」名义支持、实际真跑（init-skill 的 sudo apt-get / npm -g 会真装）。

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "=== dry-run argv 接线 ==="

# 写一个只 source 后打印状态的探针
probe() {
    local tmp; tmp=$(mktemp)
    cat > "$tmp" <<EOF
#!/bin/bash
source "$PWD/lib/dry-run.sh"
echo "\${CCC_DRY_RUN:-unset}"
EOF
    bash "$tmp" "$@"
    rm -f "$tmp"
}

r=$(probe --dry-run status)
[ "$r" = "1" ] && pass "带 --dry-run → CCC_DRY_RUN=1" || fail "带 --dry-run 未生效（得到 $r）"

r=$(probe status)
[ "$r" = "unset" ] && pass "不带参数 → 不启用 dry-run" || fail "误启用（得到 $r）"

r=$(probe sync --dry-run)
[ "$r" = "1" ] && pass "子命令后的 --dry-run 也识别" || fail "位置参数形式未生效（得到 $r）"

# run() 在 dry-run 下不得真执行命令
tmp=$(mktemp)
cat > "$tmp" <<EOF
#!/bin/bash
source "$PWD/lib/dry-run.sh"
run touch /tmp/ccc-dryrun-should-not-exist-$$
EOF
rm -f /tmp/ccc-dryrun-should-not-exist-*
bash "$tmp" --dry-run >/dev/null 2>&1
if ls /tmp/ccc-dryrun-should-not-exist-* 2>/dev/null | grep -q .; then
    fail "run() 在 dry-run 下仍真执行了（文件被创建）"
else
    pass "run() 在 dry-run 下不执行真命令"
fi
rm -f "$tmp" /tmp/ccc-dryrun-should-not-exist-*

echo ""
echo "────────────────────────────────────"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "────────────────────────────────────"
[ "$FAIL" -eq 0 ]