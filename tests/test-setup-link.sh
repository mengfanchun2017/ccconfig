#!/bin/bash
# test-setup-link.sh — setup_link 死链处理回归测试
#
# 背景：readlink -f 对死链返回的是【规范路径字符串】（非空，退出码 0），
# 所以旧实现 `[ "$existing" = "$expected" ]` 会把死链判成"已链接" → 永远不修。
# 症状：另一台机器初始化后 maintain 反复报 memory 断链，跑 self cc 也修不好
# （因为 setup_link 认为它已经链好了）。
#
# 测试直接 eval 模板里的真实函数体，不复制粘贴，避免与实现漂移。

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$REPO/templates/ccprivate-setup.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
_pass() { echo -e "  \033[0;32m✅\033[0m $1"; PASS=$((PASS+1)); }
_fail() { echo -e "  \033[0;31m❌\033[0m $1"; FAIL=$((FAIL+1)); }
# 桩：setup.sh 依赖 colors.sh 的输出函数
info() { :; }; ok() { :; }; warn() { :; }

echo ""
echo "═══ setup_link 死链处理回归测试 ═══"
echo "  模板: $TPL"
echo ""

if [ ! -f "$TPL" ]; then
    _fail "模板不存在: $TPL"
    exit 1
fi
eval "$(sed -n '/^setup_link() {/,/^}/p' "$TPL")"
if ! declare -F setup_link &>/dev/null; then
    _fail "无法从模板提取 setup_link"
    exit 1
fi
_pass "已从模板提取 setup_link"

# ── T1: 目标存在 → 建立健康链接 ──
echo "T1 目标存在时应建立链接"
mkdir -p "$WORK/t1/target"
setup_link "$WORK/t1/link" "$WORK/t1/target" "T1" >/dev/null 2>&1
if [ -L "$WORK/t1/link" ] && [ -e "$WORK/t1/link" ]; then
    _pass "链接已建立且可解析"
else
    _fail "链接未建立或不可解析"
fi

# ── T2: 目标是死链（已存在但指向不存在）→ 必须识别，不得判"已链接" ──
# 这是核心回归点：旧实现会走 "if [ -L "$link" ]" 分支，
# readlink -f 两边都返回同一路径字符串 → 判"已链接" → 直接 return 0
echo "T2 死链必须被识别为异常（不得判成已链接）"
mkdir -p "$WORK/t2"
ln -s "$WORK/t2/gone-forever" "$WORK/t2/link"
[ -e "$WORK/t2/link" ] && _fail "前置构造失败：引用竟可解析"
before_inode=$(stat -c %i "$WORK/t2/link" 2>/dev/null || echo none)
setup_link "$WORK/t2/link" "$WORK/t2/gone-forever" "T2" >/dev/null 2>&1
after_inode=$(stat -c %i "$WORK/t2/link" 2>/dev/null || echo removed)
if [ "$after_inode" = "removed" ]; then
    _pass "死链已被清理（旧实现会原样保留）"
elif [ "$before_inode" = "$after_inode" ]; then
    _fail "死链被当成'已链接'保留 —— 这正是老 bug（永远修不好）"
else
    _fail "行为异常：链接被换成其它 inode 但仍不可解析"
fi

# ── T3: 目标不存在 → 不得建出死链 ──
echo "T3 目标不存在时不应建立死链"
setup_link "$WORK/t3/link" "$WORK/t3/nonexistent-target" "T3" >/dev/null 2>&1
if [ -e "$WORK/t3/link" ] || [ -L "$WORK/t3/link" ]; then
    _fail "建出了指向不存在目标的链接（下次运行还会被判'已链接'）"
else
    _pass "未建链接（问题暴露而非隐藏）"
fi

# ── T4: 死链 + 目标恢复 → 自动修复为健康链接 ──
echo "T4 目标恢复后应自动修复"
mkdir -p "$WORK/t4"
ln -s "$WORK/t4/target" "$WORK/t4/link"      # 目标尚未创建 → 死链
mkdir -p "$WORK/t4/target"                    # 目标回来了
setup_link "$WORK/t4/link" "$WORK/t4/target" "T4" >/dev/null 2>&1
if [ -e "$WORK/t4/link" ]; then
    _pass "链接已可解析"
else
    _fail "目标恢复后链接仍不可解析"
fi

# ── T5: 健康链接重复调用 → 幂等（不得反复重建）──
echo "T5 健康链接应幂等（不重建）"
mkdir -p "$WORK/t5/target"
setup_link "$WORK/t5/link" "$WORK/t5/target" "T5" >/dev/null 2>&1
inode_a=$(stat -c %i "$WORK/t5/link")
setup_link "$WORK/t5/link" "$WORK/t5/target" "T5" >/dev/null 2>&1
inode_b=$(stat -c %i "$WORK/t5/link")
if [ "$inode_a" = "$inode_b" ]; then
    _pass "未重建（inode 不变）"
else
    _fail "重复调用重建了链接（每次 setup 都产生噪声）"
fi

# ── T6: 指向别处的健康链接 → 应改指向 ──
echo "T6 链接指向错误目标时应纠正"
mkdir -p "$WORK/t6/old" "$WORK/t6/new"
setup_link "$WORK/t6/link" "$WORK/t6/old" "T6" >/dev/null 2>&1
setup_link "$WORK/t6/link" "$WORK/t6/new" "T6" >/dev/null 2>&1
if [ "$(readlink -f "$WORK/t6/link")" = "$(readlink -f "$WORK/t6/new")" ]; then
    _pass "已改指到新目标"
else
    _fail "未纠正（仍指向旧目标）"
fi

echo ""
echo "─── lib/setup-links.sh 的同名函数（同一 bug 的第二处）───"
SL="$REPO/lib/setup-links.sh"
run() { "$@"; }          # dry-run 包装的桩
eval "$(sed -n '/^setup_link() {/,/^}/p' "$SL")"

# ── T7: 死链不得判"已链接，跳过" ──
echo "T7 [setup-links] 死链必须被识别"
mkdir -p "$WORK/t7"
ln -s "$WORK/t7/gone" "$WORK/t7/link"
before_inode=$(stat -c %i "$WORK/t7/link")
setup_link "$WORK/t7/link" "$WORK/t7/gone" "T7" >/dev/null 2>&1
after_inode=$(stat -c %i "$WORK/t7/link" 2>/dev/null || echo removed)
if [ "$after_inode" = "removed" ]; then
    _pass "死链已被清理"
elif [ "$before_inode" = "$after_inode" ]; then
    _fail "死链被判'已链接，跳过'（与 ccprivate/setup.sh 同源缺陷）"
else
    _fail "行为异常"
fi

# ── T8: 健康链接幂等 ──
echo "T8 [setup-links] 健康链接幂等"
mkdir -p "$WORK/t8/target"
setup_link "$WORK/t8/link" "$WORK/t8/target" "T8" >/dev/null 2>&1
inode_a=$(stat -c %i "$WORK/t8/link")
setup_link "$WORK/t8/link" "$WORK/t8/target" "T8" >/dev/null 2>&1
inode_b=$(stat -c %i "$WORK/t8/link")
[ "$inode_a" = "$inode_b" ] && _pass "未重建" || _fail "重复调用重建了链接"

echo ""
echo "───────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
    echo -e "\033[0;32m全部通过\033[0m ($PASS)"
else
    echo -e "\033[0;31m$FAIL 项失败\033[0m / $PASS 项通过"
fi
echo ""
exit $(( FAIL > 0 ? 1 : 0 ))
