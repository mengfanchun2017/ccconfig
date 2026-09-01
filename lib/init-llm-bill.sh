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
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
pricing = d.get('pricing', {})
if not pricing:
    print("  （暂无已配价格）")
else:
    print("  当前价格：")
    for m, v in pricing.items():
        print(f"    {m}:")
        print(f"      input=¥{v.get('input',0)}/1M  output=¥{v.get('output',0)}/1M  cache_read=¥{v.get('cache_read',0)}/1M", end='')
        cc = v.get('cache_creation')
        print(f"  cache_creation=¥{cc}/1M" if cc is not None else "  cache_creation=(默认=input×1.25)")
PYEOF
}

# 输出 "model\tmark" 行（mark=✓/空），供菜单构建
list_models_marked() {
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
pricing = d.get('pricing', {})
seen = []
for k, v in d.get('llms', {}).items():
    if k == 'gateway': continue
    m = v.get('model', '')
    if m and m not in seen: seen.append(m)
for m in list(pricing.keys()):
    if m and m not in seen: seen.append(m)
for m in seen:
    print(f"{m}\t{'✓' if m in pricing else ' '}")
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

_bill_delete_menu() {
    local -a ditems=() dnames=()
    while IFS= read -r m; do
        [[ -z "$m" ]] && continue
        ditems+=("$m")
        dnames+=("$m")
    done < <(python3 -c "import json;d=json.load(open('$CONFIG_FILE'));[print(m) for m in d.get('pricing',{})]" 2>/dev/null)
    if [[ ${#dnames[@]} -eq 0 ]]; then
        warn "无已配价格"
        return
    fi
    ditems+=("返回")
    local c; c=$(menu_select "删除价格" "${ditems[@]}")
    local n=${#dnames[@]}
    [[ -z "$c" || "$c" = "0" || "$c" = "$((n+1))" ]] && return
    if [[ "$c" -ge 1 && "$c" -le "$n" ]] 2>/dev/null; then
        local m="${dnames[$((c-1))]}"
        confirm "删除 $m 的价格？" && bill_del "$m"
    fi
}

main() {
    local target="${1:-}"
    if [[ -n "$target" ]]; then
        local _mj; _mj=$(list_models)
        local _m; _m=$(resolve_model "$_mj" "$target") || { error "无效模型: $target（用序号或精确名称）"; return 1; }
        bill_set "$_m"
        return $?
    fi

    while true; do
        echo ""
        echo "═══ Bill (模型 token 单价，CNY ¥/1M) ═══"
        show_table
        echo ""
        # 菜单：模型列表（✓=已配）+ 添加自定义 + 删除 + 返回
        local -a items=() names=()
        while IFS=$'\t' read -r m mark; do
            [[ -z "$m" ]] && continue
            items+=("$m [$mark]")
            names+=("$m")
        done < <(list_models_marked)
        items+=("＋ 添加自定义模型")
        items+=("删除已配价格")
        items+=("返回")
        local n=${#names[@]}
        local c; c=$(menu_select "模型单价" "${items[@]}")
        [[ -z "$c" || "$c" = "0" ]] && return 0
        [[ "$c" = "$((n+3))" ]] && return 0
        if [[ "$c" -ge 1 && "$c" -le "$n" ]] 2>/dev/null; then
            bill_set "${names[$((c-1))]}"
        elif [[ "$c" = "$((n+1))" ]]; then
            local m; m=$(prompt "模型名称")
            [[ -z "$m" ]] && continue
            bill_set "$m"
        elif [[ "$c" = "$((n+2))" ]]; then
            _bill_delete_menu
        fi
    done
}

[[ "${TEST_MODE:-0}" == "1" ]] || main "$@"
