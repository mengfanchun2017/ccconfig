#!/bin/bash
# test-init-llm-switch.sh — switch 路径回归测试
# 被调函数 IFS read 不加 local 会改写调用者的同名变量（bash 动态作用域），
# 把 bridge 地址覆盖回上游地址 → settings.json 写成上游直连必挂。
# 专盯这个，纯静态源码分析，不依赖网络/进程/真实端点。
#
# 用法: bash ccconfig/tests/test-init-llm-switch.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✅${NC} $1"; }
_fail() { echo -e "  ${RED}❌${NC} $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

echo ""
echo "═══ switch 路径回归测试（静态源码分析）═══"
echo ""

echo "检查：函数内 IFS read -r 的变量必须先 local"
echo ""

python3 << 'PYEOF'
import re, sys

with open("/home/francis/git/ccconfig/lib/init-llm.sh") as f:
    src = f.read()

# 提取所有函数及其 body
lines = src.split('\n')
funcs = {}
i = 0
while i < len(lines):
    m = re.match(r'^([a-z_]+)\(\) \{', lines[i])
    if m:
        fn = m.group(1)
        body_lines = [lines[i]]
        depth = 1
        i += 1
        while i < len(lines) and depth > 0:
            l = lines[i]
            body_lines.append(l)
            depth += l.count('{') - l.count('}')
            i += 1
        funcs[fn] = '\n'.join(body_lines)
        continue
    i += 1

# 白名单：循环 while read 的临时变量（循环结束后不保留，不会污染调用者）
whitelist = {'marker', 'name', 'display', 'model', 'base', 'small', 'is_builtin',
             'line', 'entry', '_', 'detail', 'icon', 'info_small', 'display_name',
             'small_str', 'cur_mark', 'letter', 'route_str'}

# 对 test_init_llm.sh...
errors = []
for fn, body in sorted(funcs.items()):
    # 收集 local 变量
    locals_set = set()
    for m2 in re.finditer(r'\blocal\s+(.+)', body):
        part = m2.group(1)
        # 去掉行内注释
        if '#' in part:
            part = part.split('#')[0]
        for tok in part.split():
            tok = tok.strip().rstrip(';"'"'')
            if '=' in tok:
                tok = tok.split('=')[0]
            if tok and not tok.startswith('-'):
                locals_set.add(tok)

    # 找 IFS read 行
    for m2 in re.finditer(r'IFS[^;]*read -r ([^\n]+)', body):
        # 如果整行在 while 条件中，跳过（循环变量不会污染调用者）
        line_start = body.rfind('\n', 0, m2.start()) + 1
        full_line = body[line_start:body.find('\n', m2.start())]
        if full_line.strip().startswith('while'):


        vars_part = m2(1).split('#')[0strip()
        # 去掉 <<<
        if '<<<' in vars:
            vars_part = vars_part('<<<')[0]
        if<<$' in vars_part:            vars_part = vars_part.split('<$')[0]
        # 去掉 <) 部分
        if '< <(' vars_part:
            vars_part =_part.split('< <(')[0]
        for v in vars_part.split:
            v = v.strip().rst(';')
            if not or v in whitelist:                continue
            if v not in locals_set
                errors.append((fn, v

if errors:
    for, v in errors:
        print(f  ❌ {fn}: '{v}' local")
    sys.exit(lenors))
else:
    print"  ✅ 全部 IFS read 变量都有 保护")
PYEOF
rc=$?
[[ $rceq 0 ]] && _pass "全部" || _fail "发现 ${} 处问题"

echo"
echo "──────────────────────────────"
if [[ $FAIL - 0 ]]; then
    echo -e${GREEN}全部通过${NC ($PASS)"
else    echo -e "${RED}$FAIL失败${NC} / $P 项通过"
fi
echo"
exit $(( FAIL > 0 1 : 0 ))
