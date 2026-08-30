#!/bin/bash
# ==============================================
# 模型单价配置（init-llm.sh bill 子命令独立版本）
#
# 4 字段: input / output / cache_read / cache_creation
# cache_creation 缺省 = input × 1.25（Anthropic 标准）
# OpenAI 兼容端点无 cache_creation，留空或 0
#
# 用法: bash init-llm-bill.sh              # 交互菜单
#       bash init-llm-bill.sh <model>      # 直接配
# ==============================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/path-helper.sh"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/interact.sh"

CONFIG_FILE="$(resolve_conf llm.json)" || exit 1

list_models() {
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except: sys.exit(0)
seen = []
for k, v in d.get('llms', {}).items():
    if k == 'gateway': continue
    m = v.get('model', '')
    if m and m not in seen: seen.append(m)
for m in d.get('pricing', {}).keys():
    if m and m not in seen: seen.append(m)
print(json.dumps(seen, ensure_ascii=False))
PYEOF
}

show_table() {
    local models_json="$1"
    python3 - "$CONFIG_FILE" "$models_json" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
models = json.loads(sys.argv[2])
pricing = d.get('pricing', {})
print("  模型列表（✓=已配）：")
for i, m in enumerate(models, 1):
    mark = "✓" if m in pricing else " "
    print(f"    {i:>2}) [{mark}] {m}")
if pricing:
    print("\n  当前价格：")
    for m, v in pricing.items():
        print(f"    {m}:")
        print(f"      input=¥{v.get('input',0)}/1M  output=¥{v.get('output',0)}/1M  cache_read=¥{v.get('cache_read',0)}/1M", end='')
        cc = v.get('cache_creation')
        print(f"  cache_creation=¥{cc}/1M" if cc is not None else "  cache_creation=(默认=input×1.25)")
PYEOF
}

resolve_model() {
    local models_json="$1" sel="$2"
    python3 - "$models_json" "$sel" << 'PYEOF'
import json, sys
models = json.loads(sys.argv[1])
sel = sys.argv[2].strip()
if sel.isdigit() and 1 <= int(sel) <= len(models):
    print(models[int(sel) - 1])
elif sel in models:
    print(sel)
else:
    sys.exit(1)
PYEOF
}

bill_set() {
    local model="$1"
    [[ -z "$model" ]] && { warn "模型名不能为空"; return 1; }
    echo ""
    echo "  '$model' 价格（CNY ¥/1M tokens，留空=0）："
    local in_v; in_v=$(prompt "  input         "); in_v="${in_v:-0}"
    local out_v; out_v=$(prompt "  output        "); out_v="${out_v:-0}"
    local cr_v; cr_v=$(prompt "  cache_read    "); cr_v="${cr_v:-0}"
    local cc_v; cc_v=$(prompt "  cache_creation（默认 input×1.25，留空）")
    python3 - "$CONFIG_FILE" "$model" "$in_v" "$out_v" "$cr_v" "$cc_v" << 'PYEOF'
import json, sys
path, model, in_v, out_v, cr_v, cc_v = sys.argv[1:7]
with open(path) as f: d = json.load(f)
d.setdefault('pricing', {})[model] = {
    'input': float(in_v),
    'output': float(out_v),
    'cache_read': float(cr_v),
}
if cc_v.strip():
    d['pricing'][model]['cache_creation'] = float(cc_v)
with open(path, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
print(f"OK: {model}")
PYEOF
}

bill_del() {
    local model="$1"
    python3 - "$CONFIG_FILE" "$model" << 'PYEOF'
import json, sys
path, model = sys.argv[1:3]
with open(path) as f: d = json.load(f)
if d.get('pricing', {}).pop(model, None) is not None:
    with open(path, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
    print(f"OK: {model}")
else:
    print("NOT_FOUND")
PYEOF
}

main() {
    local target="${1:-}"
    if [[ -n "$target" ]]; then
        local _mj; _mj=$(list_models)
        local _m; _m=$(resolve_model "$_mj" "$target") || { error "无效模型: $target（用序号或精确名称）"; return 1; }
        bill_set "$_m"
        return $?
    fi

    local models_json; models_json=$(list_models)

    while true; do
        echo ""
        echo "═══ Bill (模型 token 单价，CNY ¥/1M) ═══"
        show_table "$models_json"
        echo ""
        local op; op=$(prompt "操作 (a=添加/修改  d=删除  0=返回)")
        case "$op" in
            a|A)
                local sel model
                sel=$(prompt "模型序号或名称")
                model=$(resolve_model "$models_json" "$sel") || { error "无效: $sel"; continue; }
                bill_set "$model"
                ;;
            d|D)
                local sel model
                sel=$(prompt "模型序号或名称")
                model=$(resolve_model "$models_json" "$sel") || { error "无效: $sel"; continue; }
                bill_del "$model"
                ;;
            0|q|return|back) return 0 ;;
            *) warn "无效: $op" ;;
        esac
    done
}

[[ "${TEST_MODE:-0}" == "1" ]] || main "$@"
