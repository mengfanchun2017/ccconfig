#!/bin/bash
# test-plugin-install-e2e.sh — 真实 /plugin install 端到端（沙箱 config dir）
#
# 目的：这是唯一能证伪"装机即断"的办法。此前 27 个 plugin 从没跑过一次真实安装，
# 靠 ccprivate symlink 活着 → 陌生用户装完拿不到任何配置。
#
# 本测试：CLAUDE_CONFIG_DIR 指向沙箱 → 真跑 marketplace add + 逐个 install，
# 然后断言每个装好的 cache 副本能 ① 认出自己 ② 读到 userConfig 的值，
# 全程**不接触 ccprivate**（env -u CCPRIVATE_HOME/-u CCPRIVATE_DIR）。
#
# 需要 claude CLI 与网络（marketplace 是本地 directory，无网络）。

set -uo pipefail

SKILL_REPO="${SKILL_SRC:-$HOME/git/skill}"
PASS=0; FAIL=0
_pass() { echo -e "  \033[0;32m✅\033[0m $1"; PASS=$((PASS+1)); }
_fail() { echo -e "  \033[0;31m❌\033[0m $1"; FAIL=$((FAIL+1)); }

echo ""
echo "═══ /plugin install 端到端（沙箱）═══"
echo ""

if ! command -v claude >/dev/null 2>&1; then
    echo "  ⚠️  claude CLI 不在 PATH，跳过（CI 里应已装）"; exit 0
fi
if [[ ! -d "$SKILL_REPO/.claude-plugin" ]]; then
    echo "  ⚠️  skill 仓不在 $SKILL_REPO，跳过"; exit 0
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
CFG="$WORK/cfg"; HOME_FAKE="$WORK/home"
mkdir -p "$CFG" "$HOME_FAKE/.claude/plugins"

MKT="$(python3 -c "import json;print(json.load(open('$SKILL_REPO/.claude-plugin/marketplace.json'))['name'])")"

# ── 1. 加 marketplace ──
CLAUDE_CONFIG_DIR="$CFG" claude plugin marketplace add "$SKILL_REPO" >/dev/null 2>&1
if [[ -f "$CFG/plugins/known_marketplaces.json" ]] || \
   CLAUDE_CONFIG_DIR="$CFG" claude plugin marketplace list 2>/dev/null | grep -q "$MKT"; then
    _pass "marketplace 注册成功（$MKT）"
else
    _fail "marketplace 注册失败"; echo; exit 1
fi

# ── 2. 逐个安装 ──
plugins=$(cd "$SKILL_REPO/plugins" && ls -d */ 2>/dev/null | sed 's|/||')
total=0; inst_ok=0
for p in $plugins; do
    total=$((total + 1))
    CLAUDE_CONFIG_DIR="$CFG" claude plugin install "$p@$MKT" >/dev/null 2>&1 \
        && inst_ok=$((inst_ok + 1)) || echo "     装失败: $p"
done
if [[ $inst_ok -eq $total ]]; then
    _pass "全部 $total 个 plugin 安装成功"
else
    _fail "安装 $inst_ok/$total"
fi

# 装机用户的 HOME 布局（installed_plugins.json 是反查 plugin 名的权威表）
cp "$CFG/plugins/installed_plugins.json" "$HOME_FAKE/.claude/plugins/" 2>/dev/null || true

# ── 3. 每个副本必须能认出自己（且不碰 ccprivate）──
echo ""
echo "── 身份识别（无 ccprivate）──"
bad=0; checked=0
for d in "$CFG/plugins/cache/$MKT"/*/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$(dirname "$d")")"
    boot="$d/references/_skillconf_boot.sh"
    [[ -f "$boot" ]] || { _fail "$name: 缺 boot stub"; bad=$((bad+1)); continue; }
    got=$(env -u CCPRIVATE_HOME -u CCPRIVATE_DIR HOME="$HOME_FAKE" CLAUDE_PLUGIN_ROOT="${d%/}" \
          bash -c "source '$boot' 2>/dev/null; skillconf_plugin_name" 2>/dev/null)
    checked=$((checked + 1))
    [[ "$got" == "$name" ]] || { _fail "$name 认成 '$got'"; bad=$((bad+1)); }
done
[[ $bad -eq 0 && $checked -gt 0 ]] && _pass "$checked 个 plugin 全部正确认出自己"

# ── 4. userConfig 值必须能被读到（核心：这是装机用户唯一的配置通道）──
echo ""
echo "── userConfig 通道 ──"
python3 - "$CFG/settings.json" "$MKT" <<'PY' 2>/dev/null
import json, sys
p, mkt = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d.setdefault("pluginConfigs", {})
d["pluginConfigs"][f"ffeishu@{mkt}"] = {"options": {
    "tenant_domain": "E2E-TENANT.feishu.cn", "wiki_node_default": "E2E-NODE"}}
json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
PY
cp "$CFG/settings.json" "$HOME_FAKE/.claude/" 2>/dev/null || true

fd=$(ls -d "$CFG/plugins/cache/$MKT/ffeishu"/*/ 2>/dev/null | head -1)
if [[ -n "$fd" ]]; then
    got=$(env -u CCPRIVATE_HOME -u CCPRIVATE_DIR HOME="$HOME_FAKE" CLAUDE_PLUGIN_ROOT="${fd%/}" \
          bash -c "source '${fd%/}/references/_skillconf_boot.sh' 2>/dev/null; skillconf_get tenant_domain" 2>/dev/null)
    if [[ "$got" == "E2E-TENANT.feishu.cn" ]]; then
        _pass "ffeishu 从 pluginConfigs 读到 tenant_domain"
    else
        _fail "ffeishu 读 pluginConfigs 失败（得到 '$got'）"
    fi
    # python 孪生也要一致
    gotpy=$(env -u CCPRIVATE_HOME -u CCPRIVATE_DIR HOME="$HOME_FAKE" CLAUDE_PLUGIN_ROOT="${fd%/}" \
            python3 -c "
import sys; sys.path.insert(0,'${fd%/}/references')
from _skillconf_boot import config_env
print(config_env.get('tenant_domain') if config_env else '')" 2>/dev/null)
    [[ "$gotpy" == "E2E-TENANT.feishu.cn" ]] && _pass "config_env.py 孪生读到同值" \
        || _fail "config_env.py 读到 '$gotpy'"
else
    _fail "ffeishu 未装成功，无法测 userConfig"
fi

# ── 5. 反向断言：缓存副本里不得有 config.yaml（symlink 通道已废弃）──
echo ""
echo "── 旧通道已清除 ──"
leftover=$(find "$CFG/plugins/cache" -name "config.yaml" 2>/dev/null | head -3)
[[ -z "$leftover" ]] && _pass "cache 副本内无 config.yaml" \
                     || _fail "cache 内仍有 config.yaml: $leftover"

echo ""
echo "──────────────────────────────"
[[ "$FAIL" -eq 0 ]] && echo -e "\033[0;32mPASS: $PASS  FAIL: 0\033[0m" \
                    || echo -e "\033[0;31mPASS: $PASS  FAIL: $FAIL\033[0m"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)