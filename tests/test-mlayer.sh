#!/bin/bash
# test-mlayer.sh — MLayer 回归测试
#
# 验证多模态配置链路完整性。
# 2026-11-17 起视觉为全局配置（ccprivate/conf/vision.json，7B 唯一配置点），
# 文档解析为全局注册表（ccprivate/conf/docparse.json，7C 管理），
# 两者均与 LLM 预设正交；per-preset vision_* 字段仅作 8898 openai_bridge 回落。

set -euo pipefail
cd "$(dirname "$0")/.."
export NONINTERACTIVE=true

CCCONFIG_ROOT="$PWD"
_MCFG="$HOME/.cache/llm-merged.json"
[[ -f "$_MCFG" ]] || bash lib/init-llm.sh merge >/dev/null 2>&1

ok=0 fail=0
ck() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  ✅ $label"; ok=$((ok+1)); else echo "  ❌ $label"; fail=$((fail+1)); fi }

VCONF="$HOME/git/ccprivate/conf/vision.json"

echo "== 全局视觉配置（vision.json，7B 唯一配置点）=="
ck "vision.json 存在" test -f "$VCONF"
if [[ -f "$VCONF" ]]; then
    python3 - "$VCONF" <<'PYEOF'
import json, sys
v = json.load(open(sys.argv[1]))
p = v.get('provider')
assert p in ('zhipu', 'trae'), f"provider 非法: {p}"
assert v.get('model'), "model 为空"
if p == 'zhipu':
    assert v.get('key_preset'), "zhipu 必须带 key_preset（缺了 trae_bridge 静默空 key → 401）"
    assert v.get('upstream'), "zhipu 必须带 upstream"
print("OK")
PYEOF
    ck "vision.json 结构合法" test "$?" == "0"
fi

echo ""
echo "== 7B 菜单定义（_ML_VISION_CHOICES 恰好两条）=="
python3 - maintain.sh <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'_ML_VISION_CHOICES=\(\n(.*?)\n\)', s, re.S)
assert m, "_ML_VISION_CHOICES 未定义"
entries = [l for l in m.group(1).splitlines() if l.strip().startswith('"')]
assert len(entries) == 2, f"应恰好两条选项，实有 {len(entries)}"
assert any('glm-4.6v-flash' in e and 'zhipu' in e for e in entries), "缺 zhipu/glm-4.6v-flash 选项"
assert any('deepseek-v4.1-flash' in e and 'trae' in e for e in entries), "缺 trae/deepseek-v4.1-flash 选项"
print("OK")
PYEOF
ck "7B 恰好两个视觉后端选项" test "$?" == "0"

echo ""
echo "== OCR 状态（MinerU token 存在性）=="
MU_CONF="$HOME/git/ccprivate/conf/mineru.json"
ck "MinerU 配置文件存在" test -f "$MU_CONF"
MU_TOKEN=$(python3 -c "import json; print(json.load(open('$MU_CONF')).get('token','') or '')" 2>/dev/null)
ck "MinerU token 非空" test -n "$MU_TOKEN"
ck "MinerU token 无占位符" bash -c "! (echo '$MU_TOKEN' | grep -q '请填入')"

echo ""
echo "== 文档解析注册表（docparse.json，7C 管理）=="
DOC_CONF="$HOME/git/ccprivate/conf/docparse.json"
ck "docparse.json 存在" test -f "$DOC_CONF"
if [[ -f "$DOC_CONF" ]]; then
    python3 - "$DOC_CONF" "$MU_CONF" <<'PYEOF'
import json, sys, os
d = json.load(open(sys.argv[1]))
assert d.get('active'), "active 为空"
bs = d.get('backends', [])
assert bs, "backends 为空"
names = [b.get('name') for b in bs]
assert d['active'] in names, f"active={d['active']} 不在 backends {names}"
# 每个后端的 conf 文件必须存在（凭证与 MCP/skill 共用，不能指向空）
for b in bs:
    p = os.path.join(os.path.expanduser('~/git/ccprivate/conf'), b.get('conf', ''))
    assert os.path.exists(p), f"后端 {b['name']} 的 conf 不存在: {p}"
# 生效后端的 token 字段可读（不校验非空：≤20 页免费档允许空）
print("OK")
PYEOF
    ck "docparse.json 结构合法" test "$?" == "0"
fi

echo ""
echo "== 预设完整性（glm46vflash 内置）=="
ck "glm46vflash 在合并配置中" python3 -c "
import json
d=json.load(open('$_MCFG')).get('llms',{})
assert 'glm46vflash' in d, 'glm46vflash missing'
v=d['glm46vflash']
assert v.get('vision_model') == 'glm-4.6v-flash'
assert v.get('ocr_backend') == 'mineru'
assert v.get('use_bridge') == True
"

echo ""
echo "== 视觉路由（trae 网关 8899，读全局 vision.json）=="
# trae 上游只吃文本，带图请求由网关分流。分流判定 _body_has_image（顶层 +
# tool_result 内层都算）。provider=trae 时 keep_images 直发 Trae 订阅内视觉
# 模型；provider=zhipu 时改发外部智谱。8898 无法外部套（_bridge_supported
# 拒绝 loopback）—— 路由必须在网关内部做。
python3 - <<'PY'
import ast, sys
src = open('option-trae/trae_bridge.py').read()
tree = ast.parse(src)
names = {n.name for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
assert 'messages' in names, "缺少 messages 端点"
assert '_vision_messages' in names, "缺少视觉路由函数"
assert '_load_vision' in names, "缺少视觉配置加载"
lv = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == '_load_vision')
seg = ast.get_source_segment(src, lv) or ''
assert 'vision.json' in seg, "_load_vision 未读全局 vision.json"
assert 'key_preset' in seg, "_load_vision 未解析 key_preset"
fn = next(n for n in ast.walk(tree) if isinstance(n, ast.AsyncFunctionDef) and n.name == 'messages')
seg = ast.get_source_segment(src, fn) or ''
assert '_body_has_image' in seg, "messages 未调用 _body_has_image"
assert '_vision_messages' in seg, "messages 未分流到视觉路由"
assert 'keep_images' in seg, "messages 未区分 provider（trae 直发需 keep_images）"
print("OK")
PY
ck "trae_bridge 视觉分流 + 全局配置读取" test "$?" == "0"

echo ""
echo "== 视觉路由（openai_bridge 8898，全局覆盖 + 回落）=="
# ensure_bridge 先取 per-preset vision_* 字段，再用 bridge_vision_global 叠加：
#   rc0（zhipu）→ 覆盖；rc2（trae）→ 清空（8898 无 Trae 通道，不能暗投外部）；
#   rc1（vision.json 缺失）→ 保留旧字段回落
python3 - <<'PY'
import ast, sys
src = open('lib/ensure-bridge.sh').read()
assert 'bridge_vision_global()' in src, "缺 bridge_vision_global"
assert "sys.exit(2)" in src, "provider=trae 未返回 rc2"
assert 'grc == 2' in src, "ensure_bridge 未处理 trae 清空分支"
assert 'grc == 0' in src, "ensure_bridge 未处理 zhipu 覆盖分支"
print("OK")
PY
ck "ensure_bridge 三态视觉叠加逻辑" test "$?" == "0"
source lib/ensure-bridge.sh 2>/dev/null
if [[ -f "$VCONF" ]]; then
    _gprov=$(python3 -c "import json; print(json.load(open('$VCONF')).get('provider',''))")
    if [[ "$_gprov" == "zhipu" ]]; then
        ck "bridge_vision_global 读到 model" test -n "$(bridge_vision_global model '')"
        ck "bridge_vision_global 读到 key" test -n "$(bridge_vision_global key '')"
    elif [[ "$_gprov" == "trae" ]]; then
        ck "bridge_vision_global trae 返回 rc2" bash -c "! bridge_vision_global model '' >/dev/null 2>&1"
    fi
fi

echo ""
echo "== 菜单条目注册 =="
source lib/menu-data-maintain.sh 2>/dev/null
found_7a=false; found_7b=false; found_7c=false
for e in "${MENU_ENTRIES[@]}"; do
    IFS='|' read -r cat letter title cmd action <<< "$e"
    [[ "$cat" == "7" && "$letter" == "A" ]] && found_7a=true
    [[ "$cat" == "7" && "$letter" == "B" ]] && found_7b=true
    [[ "$cat" == "7" && "$letter" == "C" ]] && found_7c=true
done
ck "7A 菜单条目" $found_7a
ck "7B 菜单条目" $found_7b
ck "7C 菜单条目" $found_7c

echo ""
echo "== 旧回落字段仍在（fresh 机器无 vision.json 时 8898 可用）=="
ck "glm46vflash 含 vision_model（回落用）" python3 -c "
import json
d=json.load(open('$_MCFG')).get('llms',{})
assert d['glm46vflash'].get('vision_model') == 'glm-4.6v-flash'
print('ok')
"

echo ""
echo "━━━ 通过 $ok 项，失败 $fail 项 ━━━"
exit $fail
