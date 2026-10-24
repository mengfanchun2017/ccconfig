#!/bin/bash
# 回归测试：update.sh 的旧 Node 清理白名单
#
# 背景：old_node_dir=$(dirname "$(find_node_bin)")，而 find_node_bin 策略 4 会
# 回退输出 $HOME/.local/bin → dirname 得到 $HOME/.local —— 曾会用 rm -rf 抹掉
# 整个 ~/.local（claude/gh/uv/lark-cli 都在里面）。本测试锁死白名单行为。

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "=== 旧 Node 清理白名单 ==="

# 复刻 update.sh 里的 guard 逻辑（与 lib/update.sh 的 case 语句同构）
should_allow() {
    local old="$1" new="$2" HOME="$3"
    case "$old" in
        "$HOME"/.local/node-v*-linux-x64) return 0 ;;
        *) return 1 ;;
    esac
}

H="/home/u"

# 危险路径必须被拒
for bad in "$H/.local" "$H/.local/bin" "$H/.local/lib" "/tmp" "$H"; do
    if should_allow "$bad" "$H/.local/node-v22.0.0-linux-x64" "$H"; then
        fail "危险路径未被拒: $bad"
    else
        pass "拒绝危险路径: $bad"
    fi
done

# 真实 node 目录必须放行
for good in "$H/.local/node-v22.23.4-linux-x64" "$H/.local/node-v20.11.0-linux-x64"; do
    if should_allow "$good" "$H/.local/node-v22.23.4-linux-x64" "$H"; then
        pass "放行 node 目录: $(basename "$good")"
    else
        fail "node 目录被误拒: $good"
    fi
done

# find_node_bin 的兜底值确实会返回 ~/.local/bin（确认根因存在）
_v=$(bash -c 'HOME=/tmp/ghost-home; source lib/path-helper.sh 2>/dev/null; find_node_bin' 2>/dev/null)
if [ "$_v" = "/tmp/ghost-home/.local/bin" ]; then
    pass "find_node_bin 兜底 = \$HOME/.local/bin（确认危险来源，guard 已挡）"
else
    fail "find_node_bin 兜底值变了: $_v（请复查 guard）"
fi

# update.sh 源码里必须真的用 case 白名单，而不是裸 rm -rf "$old_node_dir"
if grep -qE 'case "\$old_node_dir" in' lib/update.sh && \
   grep -qE '\.local/node-v\*-linux-x64\)' lib/update.sh; then
    pass "update.sh 含白名单 case 语句"
else
    fail "update.sh 缺白名单 case（裸 rm -rf 风险回归）"
fi

echo ""
echo "────────────────────────────────────"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "────────────────────────────────────"
[ "$FAIL" -eq 0 ]