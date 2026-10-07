#!/bin/bash
# test-init-llm-merge.sh — 三层 LLM 配置合并读取的单元测试
#
# 覆盖 _llms_merged_py 的核心行为（ADR-LLM3L：定义与 key 分离）：
#   1. normal + private + keys 三层合并，key 正确取到
#   2. _src 来源判定（normal=内置 / private=自定义）
#   3. 同名覆盖：private 覆盖 normal（用户想改默认上游）
#   4. llm.json 缺 key 文件时兜底（key 为空，不崩）
#   5. 缓存文件格式：llms 含 _src + current 从 llm-current 读
#
# 用法: bash ccconfig/tests/test-init-llm-merge.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✅${NC} $1"; }
_fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}❌${NC} $1${2:+ — $2}"; }

# 读 _llms_merged_py 在给定三层文件下的输出（复用环境变量覆盖机制）
# 第 5 参可选：隔离 HOME（读 llm-current 用），不传则默认隔离到 WORKDIR
run_merge() {
    local normal="$1" priv="$2" keys="$3" cache="$4" test_home="${5:-$WORKDIR/home}"
    mkdir -p "$test_home/.claude" "$WORKDIR/home"
    LLM_NORMAL_FILE="$normal" LLM_PRIVATE_FILE="$priv" \
    LLM_KEYS_FILE="$keys" LLM_MERGED_CACHE="$cache" HOME="$test_home" \
    TEST_MODE=1 bash -c 'source "$1/lib/init-llm.sh"; _llms_merged_py' _ "$CCCONFIG_DIR" \
        2>/dev/null
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR"

cat > "$WORKDIR/normal.json" <<'JSON'
{
  "llms": {
    "builtin-a": { "name": "BuiltinA", "base_url": "https://a.example", "model": "m-a" },
    "shared": { "name": "SharedNormal", "base_url": "https://n.example", "model": "m-n", "small_model": "m-n" }
  }
}
JSON

cat > "$WORKDIR/private.json" <<'JSON'
{
  "llms": {
    "custom-x": { "name": "CustomX", "base_url": "https://x.example", "model": "m-x" },
    "shared": { "name": "SharedCustom", "base_url": "https://c.example", "model": "m-c" }
  }
}
JSON

cat > "$WORKDIR/keys.json" <<'JSON'
{
  "llms": {
    "builtin-a": { "key": "sk-builtin" },
    "shared": { "key": "sk-shared" },
    "custom-x": { "key": "sk-custom" }
  }
}
JSON

echo ""
echo "═══ 三层 LLM 合并读取单元测试 ═══"
echo ""

# ── T1: 三层合并 — 4 个 llms 全出，key 全取到 ──
echo "T1 三层合并：normal+private+keys → 全部 preset 且有 key"
out=$(run_merge "$WORKDIR/normal.json" "$WORKDIR/private.json" "$WORKDIR/keys.json" "$WORKDIR/cache.json")
rc=$?
n_keys=$(printf '%s' "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(len(d))
need = {'builtin-a':'sk-builtin', 'shared':'sk-shared', 'custom-x':'sk-custom'}
ok = all(d[n].get('key')==k for n,k in need.items())
print('KEYOK' if ok else 'KEYBAD')")
n_count=$(printf '%s' "$n_keys" | sed -n 1p)
key_ok=$(printf '%s' "$n_keys" | sed -n 2p)
if [[ $rc -eq 0 && "$n_count" == "3" && "$key_ok" == "KEYOK" ]]; then
    _pass "合并出 3 个 preset（2+2 同名去重），key 合并正确"
else
    _fail "三层合并失败" "rc=$rc out_prefix=$(printf '%s' "$out" | head -c 120)"
fi

# ── T2: _src 来源判定 ──
echo "T2 _src 判定：内置=normal / 自定义=private"
src=$?; src=$(printf '%s' "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d['builtin-a'].get('_src','MISS'))
print(d['custom-x'].get('_src','MISS'))
print(d['builtin-a'].get('key',''), d['builtin-a'].get('base_url',''))")
if [[ $(echo "$src" | sed -n 1p) == "normal" && $(echo "$src" | sed -n 2p) == "private" ]]; then
    _pass "_src 正确（builtin-a=normal, custom-x=private）"
else
    _fail "_src 判定错误" "got: $src"
fi

# ── T3: 同名覆盖 — private 的 shared 覆盖 normal ──
echo "T3 同名覆盖：shared 在 private 定义 → name/base_url 用 private 的，key 保留"
shared=$(printf '%s' "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
s = d['shared']
print(s.get('name',''), s.get('base_url',''), s.get('key',''), s.get('_src',''))")
if [[ "$shared" == "SharedCustom https://c.example sk-shared private" ]]; then
    _pass "shared 被 private 覆盖（name/base_url 用 custom，key 未丢，_src=private）"
else
    _fail "同名覆盖行为错" "got: [$shared]"
fi

# ── T4: keys 缺失兜底 — key 为空但不崩 ──
echo "T4 llm.json 缺失兜底：key 字段空，merge 不崩"
out_no=$(run_merge "$WORKDIR/normal.json" "$WORKDIR/private.json" "/nonexistent/keys.json" "$WORKDIR/cache2.json")
keys_str=$(printf '%s' "$out_no" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('KEYOK' if d['builtin-a'].get('key','') == '' else 'KEYBAD')
print(len(d))")
key_ok=$(printf '%s' "$keys_str" | sed -n 1p)
n_count=$(printf '%s' "$keys_str" | sed -n 2p)
if [[ "$key_ok" == "KEYOK" && "$n_count" == "3" ]]; then
    _pass "keys 文件缺失时 key 为空、其余字段完整、merge 不崩"
else
    _fail "keys 缺失兜底失败" "got: $keys_str"
fi

# ── T5: 缓存文件格式 — llms 含 _src（bridge 组件读）+ current 字段 ──
echo "T5 缓存文件：含 llms(with _src) + current（从隔离 HOME 的 llm-current 读）"
mkdir -p "$WORKDIR/home/.claude"
printf 'shared' > "$WORKDIR/home/.claude/llm-current"
run_merge "$WORKDIR/normal.json" "$WORKDIR/private.json" "$WORKDIR/keys.json" "$WORKDIR/cache3.json" "$WORKDIR/home" > /dev/null
cache_ok=$(python3 -c "
import json
d = json.load(open('$WORKDIR/cache3.json'))
llms = d.get('llms', {})
assert 'builtin-a' in llms and 'shared' in llms, 'llms 不全'
assert llms['custom-x'].get('_src') == 'private', '缺 _src'
assert llms['custom-x'].get('key') == 'sk-custom', '缓存缺 key'
print('CACHEOK current=' + repr(d.get('current','')))
" 2>&1)
if [[ "$cache_ok" == *"CACHEOK"* && "$cache_ok" == *"current='shared'"* ]]; then
    _pass "缓存文件正确（llms 含 _src/key，current='shared'）"
else
    _fail "缓存文件格式错" "got: $cache_ok"
fi

# ── T6: 旧格式 llm.json 升级兼容 — 带 base_url 的完整条目收编为自定义预设 ──
echo "T6 旧格式 llm.json（三层前的完整配置）：收编 + key 保留 + current 继承"
cat > "$WORKDIR/legacy-keys.json" << 'EOF'
{
    "llms": {
        "builtin-a": { "key": "sk-new-format" },
        "legacy-full": {
            "name": "LegacyFull",
            "base_url": "https://api.legacy.example/anthropic",
            "model": "legacy-model",
            "small_model": "legacy-small",
            "key": "sk-legacy-full"
        }
    },
    "current": "legacy-full"
}
EOF
legacy_out=$(run_merge "$WORKDIR/normal.json" "$WORKDIR/private.json" "$WORKDIR/legacy-keys.json" "$WORKDIR/cache4.json" "$WORKDIR/legacy-home")
legacy_ok=$(printf '%s' "$legacy_out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ok = True
lg = d.get('legacy-full', {})
if lg.get('_src') != 'private': ok = False
if lg.get('key') != 'sk-legacy-full': ok = False
if lg.get('model') != 'legacy-model': ok = False
if d['builtin-a'].get('key') != 'sk-new-format': ok = False
print('LEGACYOK' if ok else 'LEGACYBAD')
")
cache_cur=$(python3 -c "
import json
d = json.load(open('$WORKDIR/cache4.json'))
print('CUR=' + repr(d.get('current','')))
")
if [[ "$legacy_ok" == "LEGACYOK" && "$cache_cur" == "CUR='legacy-full'" ]]; then
    _pass "旧格式收编：legacy-full 成自定义预设（key/model 保留），current 继承"
else
    _fail "旧格式兼容失败" "got: $legacy_ok $cache_cur"
fi

echo ""
echo "───────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}全部通过${NC} ($PASS)"
else
    echo -e "${RED}$FAIL 项失败${NC} / $PASS 项通过"
fi
echo ""
exit $(( FAIL > 0 ? 1 : 0 ))