#!/bin/bash
# test-ccprivate-sandbox-e2e.sh — 沙箱端到端：新机安装 + 老机升级
#
# 目的：本次改动（本机文件模板改为从 ccconfig/templates 取、skill-local 删除、
# agents 模板链删除）最容易在**安装/升级链路**上炸，而单元测试覆盖不到整链。
# 本测试用假 HOME + 假 ccprivate 跑真实 setup.sh，断言最终磁盘状态。
#
# 关键设计：不碰真实 ~/.claude。全部在 mktemp 沙箱内，HOME 被重指，
# CCPRIVATE_HOME / CCCONFIG_DIR 显式传入，退出即清理。

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
_pass() { echo -e "  \033[0;32m✅\033[0m $1"; PASS=$((PASS+1)); }
_fail() { echo -e "  \033[0;31m❌\033[0m $1"; FAIL=$((FAIL+1)); }

echo ""
echo "═══ ccprivate 沙箱端到端（新装 / 升级）═══"
echo "  沙箱: $WORK"
echo ""

# ── 沙箱骨架 ──
FAKE_HOME="$WORK/home"
FAKE_PRIV="$WORK/ccprivate"
mkdir -p "$FAKE_HOME/git" "$FAKE_PRIV"
# 造出 setup.sh 需要的私有仓最小结构（真实 ccprivate 是 git 仓，这里不需要 git）
for d in conf rules agents commands bin link/memory; do mkdir -p "$FAKE_PRIV/$d"; done
printf '# 用户级约定\n' > "$FAKE_PRIV/link/CLAUDE.md"
printf 'ailab\n'        > "$FAKE_PRIV/link/.lark-default-account"
printf '{}\n'            > "$FAKE_PRIV/conf/llm.json"

# 新机：setup.sh 由 upgrade/bootstrap 从模板 cp 过来（此处模拟同样动作）
cp "$REPO/templates/ccprivate-setup.sh" "$FAKE_PRIV/setup.sh"
chmod +x "$FAKE_PRIV/setup.sh"

# ── T1: 新机 setup.sh 能跑通且本机三件套落盘 ──
echo "── T1: 新机安装 ──"
if HOME="$FAKE_HOME" CCPRIVATE_HOME="$FAKE_PRIV" CCCONFIG_DIR="$REPO" \
   bash "$FAKE_PRIV/setup.sh" > "$WORK/t1.log" 2>&1; then
    _pass "setup.sh 退出码 0"
else
    _fail "setup.sh 非零退出（日志尾部）"
    tail -15 "$WORK/t1.log" | sed 's/^/     /'
fi

for f in settings.json .config.json .claudeignore; do
    if [ -f "$FAKE_HOME/.claude/$f" ]; then
        _pass "$f 已创建"
    else
        _fail "$f 未创建（模板链断了）"
    fi
done

# settings.json 必须含权限基线（不是空壳）—— 这正是"只补缺键"逻辑的考点
if [ -f "$FAKE_HOME/.claude/settings.json" ] && \
   python3 -c "
import json,sys
d=json.load(open('$FAKE_HOME/.claude/settings.json'))
sys.exit(0 if d.get('permissions',{}).get('allow') else 1)
" 2>/dev/null; then
    _pass "settings.json 含 permissions.allow 基线（非空壳）"
else
    _fail "settings.json 缺 permissions.allow（新机白名单静默失效）"
fi

# ── T2: 不得创建已删的 skill-local / agents 模板 ──
echo ""
echo "── T2: 已删项未被重建 ──"
[ ! -e "$FAKE_PRIV/skill-local" ] && _pass "skill-local 未重建" \
                                  || _fail "skill-local 被 setup.sh 重建了"
[ ! -e "$FAKE_PRIV/openclaw" ] && _pass "无多余目录" || true

# ── T3: 幂等 —— 第二次跑不报错、不丢已有值 ──
echo ""
echo "── T3: 幂等（二次运行）──"
# 先写一个用户自定义值，二次运行必须保留
python3 - <<PY 2>/dev/null
import json
p = "$FAKE_HOME/.claude/settings.json"
d = json.load(open(p))
d["_user_marker"] = "keep-me"
json.dump(d, open(p, "w"), indent=4)
PY
if HOME="$FAKE_HOME" CCPRIVATE_HOME="$FAKE_PRIV" CCCONFIG_DIR="$REPO" \
   bash "$FAKE_PRIV/setup.sh" > "$WORK/t3.log" 2>&1; then
    _pass "二次运行退出码 0"
else
    _fail "二次运行非零退出"
    tail -10 "$WORK/t3.log" | sed 's/^/     /'
fi
if python3 -c "
import json,sys
d=json.load(open('$FAKE_HOME/.claude/settings.json'))
sys.exit(0 if d.get('_user_marker')=='keep-me' else 1)
" 2>/dev/null; then
    _pass "用户自定义键未被覆盖"
else
    _fail "二次运行覆盖了用户自定义键"
fi

# ── T4: 老机升级 —— 残留 link/*.example 应被清理 ──
echo ""
echo "── T4: 老机升级清理残留 ──"
printf '{}\n' > "$FAKE_PRIV/link/settings.json.example"
printf '{}\n' > "$FAKE_PRIV/link/.config.json.example"
printf '#\n'  > "$FAKE_PRIV/link/.claudeignore.example"
mkdir -p "$FAKE_PRIV/skill-local" && touch "$FAKE_PRIV/skill-local/.gitkeep"

if CCPRIVATE_HOME="$FAKE_PRIV" CCCONFIG_DIR="$REPO" \
   bash "$REPO/lib/ccprivate-upgrade.sh" --yes > "$WORK/t4.log" 2>&1; then
    _pass "ccprivate-upgrade 退出码 0"
else
    # 升级脚本对缺 git 的沙箱仓可能报错，但功能断言仍要查
    echo -e "  \033[0;33m⚠\033[0m  upgrade 非零退出（沙箱无 git，继续查副作用）"
fi

for f in settings.json .config.json .claudeignore; do
    [ ! -e "$FAKE_PRIV/link/$f.example" ] && _pass "残留 link/$f.example 已清" \
                                          || _fail "残留 link/$f.example 未清"
done

# setup.sh 应被模板刷新（这是 upgrade 的核心职责）
if diff -q "$REPO/templates/ccprivate-setup.sh" "$FAKE_PRIV/setup.sh" &>/dev/null; then
    _pass "setup.sh 与模板一致（升级刷新生效）"
else
    _fail "setup.sh 与模板不一致"
fi

echo ""
echo "──────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
    echo -e "\033[0;32mPASS: $PASS  FAIL: 0\033[0m"
else
    echo -e "\033[0;31mPASS: $PASS  FAIL: $FAIL\033[0m"
fi
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)