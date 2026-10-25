#!/bin/bash
# 回归测试：update.sh 的 claude 更新路径
#
# 背景（2026-10-25 实测）：
#  1. `claude install --force` 没有"只检查"模式，每次无条件重下 278MB。
#     downloads.claude.ai 直连不通 → 3 次重试 ~95s 后失败 → 再回退 npm。
#     交互 shell 无 proxy env（只有 systemd 单元有），2B 就是在这条路上白等。
#  2. `claude install` 不带 target 装的是 **stable**，而 latest 可能更新
#     （实测 stable 2.1.308 / latest 2.1.310）。拿 latest 比会永远追不平。
#  3. 本机领先 stable 时不能被 --force 拉回去（等于替用户降级）。
#  4. 每个旧二进制 240-280MB，攒三代 = 797MB，必须清。

set -u
CCCONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CCCONFIG_DIR"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "=== update_claude 快路径 / 不降级 / 清理 ==="

SRC="$(sed -n '/^update_claude()/,/^}$/p' lib/update.sh)"
CLN="$(sed -n '/^cleanup_old_claude_versions()/,/^}$/p' lib/update.sh)"

# 1. 用 stable 清单而不是 latest 比对（两者会不一致）
grep -q 'claude-code-releases/stable"' lib/update.sh && pass "以 stable 清单为比对目标" \
    || fail "未使用 stable 清单（会与 claude install 的实际安装目标不一致）"
grep -q 'claude-code-releases/latest"' lib/update.sh && fail "仍在用 latest 清单比对" \
    || pass "未误用 latest 清单"

# 2. 已最新时不得调用 claude install
echo "$SRC" | grep -q '跳过下载' && pass "已最新时走跳过分支" || fail "无跳过分支"

# 3. 不降级保护存在
echo "$SRC" | grep -q '领先于 stable' && pass "有领先 stable 的不降级保护" || fail "无不降级保护"
echo "$SRC" | grep -q 'sort -V' && pass "版本比较用 sort -V（非字符串比较）" || fail "版本比较不安全"

# 4. 代理显式传给子进程
echo "$SRC" | grep -q 'env \${proxy:+HTTPS_PROXY' && pass "代理显式传递给 claude install" || fail "未传代理"

# 5. cleanup 函数存在且带白名单（只删 x.y.z 形式）
[ -n "$CLN" ] && pass "cleanup_old_claude_versions 存在" || fail "缺 cleanup 函数"
echo "$CLN" | grep -q 'regex' && pass "清理有版本号正则白名单" || fail "清理无白名单（可能误删）"
echo "$CLN" | grep -q 'keep' && pass "清理保留当前版本" || fail "清理不保留当前版本"

# 6. 功能实测：cleanup 在假 versions 目录下只留 2 个（隔离 HOME）
T="$CLAUDE_JOB_DIR/tmp/claude-vers-test.$$"
mkdir -p "$T/.local/share/claude/versions"
for v in 1.0.0 1.0.1 1.0.2 1.0.3; do echo x > "$T/.local/share/claude/versions/$v"; done
echo junk > "$T/.local/share/claude/versions/notaversion"
HOME="$T" bash -c "source '$CCCONFIG_DIR/lib/colors.sh' 2>/dev/null; $CLN; cleanup_old_claude_versions 1.0.3" >/dev/null 2>&1
left=$(ls "$T/.local/share/claude/versions" | sort | tr '\n' ' ')
keep_cur=$([ -f "$T/.local/share/claude/versions/1.0.3" ] && echo yes || echo no)
keep_prev=$([ -f "$T/.local/share/claude/versions/1.0.2" ] && echo yes || echo no)
kept_junk=$([ -f "$T/.local/share/claude/versions/notaversion" ] && echo yes || echo no)
old_gone=$([ -f "$T/.local/share/claude/versions/1.0.0" ] && echo no || echo yes)

[ "$keep_cur" = yes ] && pass "清理保留当前版本 1.0.3" || fail "当前版本被删"
[ "$keep_prev" = yes ] && pass "清理保留上一版本 1.0.2（可回退）" || fail "上一版本被删"
[ "$old_gone" = yes ] && pass "清理删除更旧版本 1.0.0" || fail "旧版本未删"
[ "$kept_junk" = yes ] && pass "白名单保护非版本文件" || fail "误删非版本文件"
echo "  （剩余: $left）"

echo ""
echo "────────────────────────────────────"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "────────────────────────────────────"
[ "$FAIL" -eq 0 ] || exit 1