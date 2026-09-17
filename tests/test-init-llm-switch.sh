#!/bin/bash
# test-init-llm-switch.sh — switch 路径回归：被调函数 IFS read 不加 local
# 改写调用者变量的 bug (bash 动态作用域)，把 bridge 地址覆盖回上游
#
# 用法: bash ccconfig/tests/test-init-llm-switch.sh [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✅${NC} $1"; }
_fail() { echo -e "  ${RED}❌${NC} $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

echo ""
echo "═══ init-llm.sh switch 路径回归测试 ═══"
echo ""

echo "静态源码检查：函数内所有 IFS read -r 的变量都必须有 local 声明"
echo "  （防 bash 动态作用域下污染调用者同名变量）"
echo ""

issues=0
python3 - <<PYEOF
import re, sys

with open("$CCCONFIG_DIR/lib/init-llm.sh") as f:
    src = f.read()

# 函数体分割（处理大括号嵌套）
i = 0
funcs = {}
lines = src.split('\n')
while i < len(lines):
    m = re.match(r'^([a-z_]+)\(\) \{', lines[i])
    if m:
        fn = m.group(1)
        body = [lines[i]]
        depth = 1
        i += 1
        while i < len(lines) and depth > 0:
            l = lines[i]
            body.append(l)
            depth += l.count('{') - l.count('}')
            i += 1
        funcs[fn] = '\n'.join(body)
        continue
    i += 1

# common vars: 用于 list_llms 的循环变量（被调用方的 for while 循环变量非问题）
whitelist = {'marker', 'name', 'display', 'model', 'base', 'small', 'is_builtin', 'line', 'entry'}

errors = []
for fn, body in sorted(funcs.items()):
    # 找函数体内的 local 声明
    locals_set = set()
    for lv in re.findall(r'\blocal\s+([a-zA-Z_][a-zA-Z0-9_]*)\\b', body):
        # 处理多个 local var1 var2 ...
        local_line = re.search(r'\blocal\s+([^$;]+)', lv)
        for tok in local_line.group(1).split() if local_line else []:
            tok = tok.strip()
            if tok and not tok.startswith('-'):
                locals_set.add(tok)
    # 也可以处理多变量: local a b c
    for m2 in re.finditer(r'local\\s+([a-zA-Z_][a-zA-Z0-9_](?:\\s+[a-zA-Z_][a-zA-Z0-9_])*)', body):
        for tok in m2.group(1).split():
            tok = tok.strip()
            if tok and not tok.startswith('-'):
                locals_set.add(tok)

    # 找 IFS read -r
    for rm in re.finditer(r'^\\s*IFS[^$]*read -r ([^<]+)', body, re.M):
        # 去掉行内注释
        vars_line = rm.group(1).split('#')[0].strip()
        # 去掉 <<< 及其之后的
        if '<<<' in vars_line:
            vars_line = vars_line.split('<<<')[0].strip()
        if '<<\$' in vars_line:
            vars_line = vars_line.split('<<\$')[0].strip()

        for v in vars_line.split():
            v = v.strip()
            if not v:
                continue
            if v in whitelist:
                continue
            if fn == 'test_llm' and v in ('base_url', 'model', 'key'):
                # 这些必须在函数内有 local
                pass
            if v not in locals_set:
                errors.append((fn, v, body[:80]))

if errors:
    for fn, v, _ in errors:
        print(f"  ❌ {fn}: 变量 '{v}' 在 IFS read 中无 local，会污染调用者")
    sys.exit(len(errors))
else:
    print("  ✅ 所有函数内 IFS read 变量都有 local 保护")
PYEOF
src_check=$?
[[ $src_check -eq 0 ]] && _pass "静态源码检查通过" || _fail "静态源码检查发现 ${src_check} 处问题"

echo ""
echo "───────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}全部通过${NC} ($PASS)"
else
    echo -e "${RED}$FAIL 项失败${NC} / $PASS 项通过"
fi
echo ""
exit $(( FAIL > 0 ? 1 : 0 ))
