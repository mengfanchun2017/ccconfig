#!/usr/bin/env python3
# Fix token-usage.sh: replace print_period() calls in 按时间段 section with inline table format

with open('option-usage/token-usage.sh') as f:
    content = f.read()

old = '# 单日 = 昨天（latest full day）\nns, si, so, scr, stot, cost = agg(lambda d: d == yesterday_str, yesterday_str)\nprint_period(yesterday_str, ns, si, so, scr, stot, cost)\nns, si, so, scr, stot, cost = agg(lambda d: d >= day7_str, "近7天")\nprint_period("近7天", ns, si, so, scr, stot, cost)\nns, si, so, scr, stot, cost = agg(lambda d: d >= day30_str, "近30天")\nprint_period("近30天", ns, si, so, scr, stot, cost)'

new_lines = [
    '# 单日 = 昨天（latest full day）',
    'ns, si, so, scr, stot, cost = agg(lambda d: d == yesterday_str, yesterday_str)',
    'if ns > 0:',
    '    print(f"{yesterday_str:<16} {ns:>9} {si:>12,} {so:>10,} {scr:>12,} {stot:>14,} {cost:>10.2f}")',
    'else:',
    '    print(f"{yesterday_str:<16} 无数据")',
    'ns, si, so, scr, stot, cost = agg(lambda d: d >= day7_str, "近7天")',
    'if ns > 0:',
    r"    print(f"{'近7天':<16} {ns:>9} {si:>12,} {so:>10,} {scr:>12,} {stot:>14,} {cost:>10.2f}")",
    'else:',
    r"    print(f"{'近7天':<16} 无数据")",
    'ns, si, so, scr, stot, cost = agg(lambda d: d >= day30_str, "近30天")',
    'if ns > 0:',
    r"    print(f"{'近30天':<16} {ns:>9} {si:>12,} {so:>10,} {scr:>12,} {stot:>14,} {cost:>10.2f}")",
    'else:',
    r"    print(f"{'近30天':<16} 无数据")",
]
new = '\n'.join(new_lines)

if old in content:
    content = content.replace(old, new, 1)
    with open('option-usage/token-usage.sh', 'w') as f:
        f.write(content)
    print('OK: replaced')
else:
    print('ERROR: old string not found')
    # Debug: show surrounding context
    idx = content.find('单日 = 昨天')
    if idx >= 0:
        print('Context:', repr(content[idx:idx+400]))
