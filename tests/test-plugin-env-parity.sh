#!/bin/bash
# test-plugin-env-parity.sh — 配置解析唯一实现的双语一致性回归
#
# 背景：skill 配置解析原来有 15 处各写一份的实现（3 种变量名并存）。
# 2026-10-27 收敛为 ffeishu/references/plugin_env.sh（bash）+ config_env.py（python），
# 两者必须给出**完全相同**的结果 —— 两份实现最大的风险就是漂移，故用同一组
# 输入同时喂给两者并逐条比对。
#
# 覆盖：8 级优先级的每一级单独命中 + 全量填充时取最高级 + 缺失时两者都报缺失。

set -uo pipefail

SKILL_REPO="${SKILL_SRC:-$HOME/git/skill}"
REF="$SKILL_REPO/plugins/ffeishu/references"
SH="$REF/plugin_env.sh"
PY="$REF/config_env.py"

PASS=0; FAIL=0
_pass() { echo -e "  \033[0;32m✅\033[0m $1"; PASS=$((PASS+1)); }
_fail() { echo -e "  \033[0;31m❌\033[0m $1"; FAIL=$((FAIL+1)); }

echo ""
echo "═══ 配置解析双语一致性（plugin_env.sh vs config_env.py）═══"
echo "  $REF"
echo ""

for f in "$SH" "$PY"; do
    [ -f "$f" ] || { _fail "实现缺失: $f"; echo; exit 1; }
done
_pass "两个实现都存在"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_HOME="$WORK/home"
PLUGIN="$WORK/pdir/probe"
mkdir -p "$FAKE_HOME/.claude" "$PLUGIN/references"
cp "$SH" "$PLUGIN/references/"
cp "$PY" "$PLUGIN/references/"

# ── 各源的可区分值 ──
mk_all_sources() {
    rm -rf "$FAKE_HOME/.claude/plugins" "$FAKE_HOME/.claude/skill-config"
    rm -f "$FAKE_HOME/.claude/settings.json" "$FAKE_HOME/.claude/.credentials.json"
    mkdir -p "$FAKE_HOME/.claude/plugins/data/probe" "$FAKE_HOME/.claude/skill-config"

    # 2 plugin-data
    echo '{"k":"L2-plugin-data"}' > "$FAKE_HOME/.claude/plugins/data/probe/config.json"
    # 3 settings.pluginConfigs
    echo '{"pluginConfigs":{"probe@mkt":{"options":{"k":"L3-settings"}}}}' \
        > "$FAKE_HOME/.claude/settings.json"
    # 4 credentials.pluginSecrets
    echo '{"pluginSecrets":{"probe@mkt":{"k":"L4-creds"}}}' \
        > "$FAKE_HOME/.claude/.credentials.json"
    # 5/6 私有仓（用显式 CCPRIVATE_HOME 指向沙箱，避免碰到真实仓）
    mkdir -p "$WORK/priv/conf" "$WORK/priv/skill"
    echo 'k: L5-ccprivate-conf'  > "$WORK/priv/conf/probe.yaml"
    printf 'wiki_nodes:\n  default: NODE-OK\n' >> "$WORK/priv/conf/probe.yaml"
    echo 'k: L6-ccprivate-skill' > "$WORK/priv/skill/probe.yaml"
    # 7 skill-config
    echo 'k: L7-skill-config' > "$FAKE_HOME/.claude/skill-config/probe.yaml"
    # 8 plugin/config.yaml
    echo 'k: L8-plugin-config' > "$PLUGIN/config.yaml"
}

# 两者取值（都返回 stdout 单行）
run_sh() { HOME="$FAKE_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN" CCPRIVATE_HOME="$WORK/priv" \
           bash -c "source '$PLUGIN/references/plugin_env.sh'; skillconf_get k" 2>/dev/null; }
run_sh_dotted() { HOME="$FAKE_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN" CCPRIVATE_HOME="$WORK/priv" \
           bash -c "source '$PLUGIN/references/plugin_env.sh'; skillconf_get wiki_nodes.default" 2>/dev/null; }
run_py_dotted() { HOME="$FAKE_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN" CCPRIVATE_HOME="$WORK/priv" \
           python3 -c "
import sys; sys.path.insert(0, '$PLUGIN/references')
from config_env import get; print(get('wiki_nodes.default') or '')
" 2>/dev/null; }
run_py() { HOME="$FAKE_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN" CCPRIVATE_HOME="$WORK/priv" \
           python3 -c "
import sys; sys.path.insert(0, '$PLUGIN/references')
from config_env import get
v = get('k'); print(v if v is not None else '')
" 2>/dev/null; }

# ── 逐级断言 ──
assert_level() {
    local desc="$1" expect="$2"
    local a b
    a="$(run_sh)"; b="$(run_py)"
    if [ "$a" = "$expect" ] && [ "$b" = "$expect" ]; then
        _pass "$desc → 两者都取到 $expect"
    else
        _fail "$desc → 期望 $expect / bash='$a' python='$b'"
    fi
}

echo "── 全量填充：两者必须都取最高级 L2 ──"
mk_all_sources
assert_level "8 源齐备取 plugin-data" "L2-plugin-data"

echo ""
echo "── 逐级降级：删高优先级源，两者同步降级 ──"
rm -f "$FAKE_HOME/.claude/plugins/data/probe/config.json"
assert_level "删 L2 → settings" "L3-settings"

echo '{}' > "$FAKE_HOME/.claude/settings.json"
assert_level "删 L3 → credentials" "L4-creds"

echo '{}' > "$FAKE_HOME/.claude/.credentials.json"
assert_level "删 L4 → ccprivate/conf" "L5-ccprivate-conf"

rm -f "$WORK/priv/conf/probe.yaml"
assert_level "删 L5 → ccprivate/skill（旧位置）" "L6-ccprivate-skill"

rm -f "$WORK/priv/skill/probe.yaml"
assert_level "删 L6 → skill-config（旧）" "L7-skill-config"

rm -f "$FAKE_HOME/.claude/skill-config/probe.yaml"
assert_level "删 L7 → plugin/config.yaml（旧 symlink）" "L8-plugin-config"

rm -f "$PLUGIN/config.yaml"
echo ""
echo "── 全部清空：两者都必须报缺失 ──"
a="$(run_sh)"; b="$(run_py)"
if [ -z "$a" ] && [ -z "$b" ]; then
    _pass "无任何源 → 两者都返回空"
else
    _fail "无源时期望都空 / bash='$a' python='$b'"
fi

# ── 环境变量覆盖（优先级最高）──
echo ""
echo "── L1 环境变量覆盖 ──"
mk_all_sources
a="$(HOME="$FAKE_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN" CCPRIVATE_HOME="$WORK/priv" SKILLCONF_K=L1-env \
     bash -c "source '$PLUGIN/references/plugin_env.sh'; skillconf_get k" 2>/dev/null)"
b="$(HOME="$FAKE_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN" CCPRIVATE_HOME="$WORK/priv" SKILLCONF_K=L1-env \
     python3 -c "
import sys; sys.path.insert(0, '$PLUGIN/references')
from config_env import get; print(get('k') or '')
" 2>/dev/null)"
if [ "$a" = "L1-env" ] && [ "$b" = "L1-env" ]; then
    _pass "env 覆盖 8 源 → 两者都取 L1-env"
else
    _fail "env 覆盖失败 / bash='$a' python='$b'"
fi

echo ""
echo "── 点号键（wiki_nodes.default）──"
# 点号键曾构造出 SKILLCONF_WIKI_NODES.DEFAULT → Bash "invalid variable name" 直接中止。
# 这是常用形态（wiki_nodes.default 几乎每个 skill 都用），必须两实现都能取到。
mk_all_sources
a="$(run_sh_dotted)"; b="$(run_py_dotted)"
if [ "$a" = "NODE-OK" ] && [ "$b" = "NODE-OK" ]; then
    _pass "点号键两实现都能取到"
else
    _fail "点号键失败 / bash='$a' python='$b'"
fi
# env 覆盖点号键也必须两实现一致
a="$(HOME="$FAKE_HOME" CCPRIVATE_HOME="$WORK/priv" SKILLCONF_WIKI_NODES_DEFAULT=ENV-DOT \
     bash -c "source '$PLUGIN/references/plugin_env.sh'; skillconf_get wiki_nodes.default" 2>/dev/null)"
b="$(HOME="$FAKE_HOME" CCPRIVATE_HOME="$WORK/priv" SKILLCONF_WIKI_NODES_DEFAULT=ENV-DOT \
     python3 -c "
import sys; sys.path.insert(0, '$PLUGIN/references')
from config_env import get; print(get('wiki_nodes.default') or '')
" 2>/dev/null)"
if [ "$a" = "ENV-DOT" ] && [ "$b" = "ENV-DOT" ]; then
    _pass "点号键的 env 覆盖两实现一致"
else
    _fail "点号键 env 覆盖 / bash='$a' python='$b'"
fi

echo ""
echo "──────────────────────────────"
[ "$FAIL" -eq 0 ] && echo -e "\033[0;32mPASS: $PASS  FAIL: 0\033[0m" \
                  || echo -e "\033[0;31mPASS: $PASS  FAIL: $FAIL\033[0m"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)