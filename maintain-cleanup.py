#!/usr/bin/env python3
"""清理 maintain.sh 菜单调用：
1. menu_select items 去数字前缀（"1) xxx" → "xxx", "d) xxx" → "xxx"）
2. case 提取从 ${X:0:1} 改为 $(echo "$X" | grep -oE '^[0-9]+') 统一处理 10+ 项
3. 多行 case 用 esac 单行收尾的（已被 grep 合并）保留
"""
import re

with open('maintain.sh', 'r', encoding='utf-8') as f:
    s = f.read()

# 1. menu_select items 去前缀（多行/单行都覆盖）
# 匹配: "数字) " 或 "字母) " 前缀
def strip_prefix_in_items(items_block):
    # 匹配 "..." 字符串字面量，开头带 "<字符>) " 模式
    return re.sub(r'"([0-9a-zA-Z])\) ', r'"', items_block)

# 处理跨行 menu_select 调用：
# 找出 $(menu_select "title" \  ...  "..." "...") 整段，处理内部字符串
def fix_menu_select_calls(text):
    out = []
    i = 0
    while i < len(text):
        m = re.search(r'menu_select\s+"[^"]*"(?:\s*\\?\s*"[^"]*")+', text[i:])
        if not m:
            out.append(text[i:])
            break
        start = i + m.start()
        end = i + m.end()
        out.append(text[i:start])
        block = text[start:end]
        # 找到 title 后的所有 "..."
        # 用更稳的方法：拆分 title 和 items
        title_match = re.match(r'(menu_select\s+)"([^"]*)"', block)
        if not title_match:
            out.append(block)
            i = end
            continue
        prefix = title_match.group(1) + '"' + title_match.group(2) + '"'
        rest = block[len(prefix):]
        # rest 是 \n  + "..." "..." "..." 的形式，可能跨行
        # 提取所有 "..." 字面量
        items_raw = re.findall(r'"([^"]*)"', rest)
        # 去前缀
        items_clean = [re.sub(r'^[0-9a-zA-Z]\)\s+', '', x) for x in items_raw]
        # 重组成调用：保留缩进
        # 找到 title 后第一行的缩进
        indent_match = re.search(r'\n(\s+)"', '\n' + rest)
        indent = indent_match.group(1) if indent_match else '        '
        # 重构
        new_block = f'{prefix} \\\n'
        for j, it in enumerate(items_clean):
            sep = ' \\\n' if j < len(items_clean) - 1 else ''
            new_block += f'{indent}"{it}"{sep}'
        out.append(new_block)
        i = end
    return ''.join(out)

s = fix_menu_select_calls(s)

# 2. 把 ${VAR:0:1} / ${VAR:0:2} 提取改为 grep
# 模式: case "${c:0:1}" in → case "$(echo "$c" | grep -oE '^[0-9]+' | head -1)" in
s = re.sub(
    r'case\s+"\$\{(\w+):0:\d+\}"\s+in',
    r'case "$(echo "$\1" | grep -oE \'^[0-9]+\' | head -1)" in',
    s
)

with open('maintain.sh', 'w', encoding='utf-8') as f:
    f.write(s)

print('done')