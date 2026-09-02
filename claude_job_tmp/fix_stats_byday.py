#!/usr/bin/env python3
with open('option-usage/token-usage.sh') as f:
    content = f.read()

# 1. Fix model section: d['sessions'] -> len(d['unique_sessions'])
old = """print(f"{m[:24]:<24} {d['sessions']:>8} {d['in']:>12,} {d['cr']:>12,} {d['out']:>10,} {d['total']:>14,} {d['cost']:>9.2f}")
# total 汇总行
t_sessions = sum(by_model[m]["sessions"] for m in by_model)"""
new = """print(f"{m[:24]:<24} {len(d['unique_sessions']):>8} {d['in']:>12,} {d['cr']:>12,} {d['out']:>10,} {d['total']:>14,} {d['cost']:>9.2f}")
# total 汇总行
all_sids = set()
for m in by_model:
    all_sids |= by_model[m]["unique_sessions"]
t_sessions = len(all_sids)"""
assert old in content, "Model section not found"
content = content.replace(old, new, 1)

# 2. Fix 时间段 section: agg() -> agg_days()
old1 = "ns, si, so, scr, stot, cost = agg(lambda d: d == yesterday_str, yesterday_str)"
new1 = "ns, si, so, scr, stot, cost = agg_days(lambda d: d == yesterday_str)"
assert old1 in content, "agg 1 not found"
content = content.replace(old1, new1, 1)

old2 = 'ns, si, so, scr, stot, cost = agg(lambda d: d >= day7_str, "近7天")'
new2 = 'ns, si, so, scr, stot, cost = agg_days(lambda d: d >= day7_str)'
assert old2 in content, "agg 2 not found"
content = content.replace(old2, new2, 1)

old3 = 'ns, si, so, scr, stot, cost = agg(lambda d: d >= day30_str, "近30天")'
new3 = 'ns, si, so, scr, stot, cost = agg_days(lambda d: d >= day30_str)'
assert old3 in content, "agg 3 not found"
content = content.replace(old3, new3, 1)

# 3. Fix 按月 section: use by_day dict instead of rows.firstActivity
old_month = """# 按月统计（descending，首行 = 全量总计）
by_month = defaultdict(lambda: {"in":0,"cr":0,"out":0,"total":0,"sessions":0,"cost":0.0})
for r in rows:
    fa = r.get("firstActivity", "") or ""
    month = fa[:7] if len(fa) >= 7 else ""
    if not month: continue
    bm = by_month[month]
    bm["sessions"] += 1
    for mn, v in r.get("models", {}).items():
        mi = v.get("input",0); mo = v.get("output",0); mcr = v.get("cache_read",0)
        bm["in"] += mi; bm["out"] += mo; bm["cr"] += mcr
        bm["total"] += mi + mo + v.get("cache_creation",0) + mcr
        pm = p.get(mn, {})
        bm["cost"] += (mi*pm.get("input",0) + mo*pm.get("output",0) + mcr*pm.get("cache_read",0)) / 1_000_000
months = sorted(by_month.keys(), reverse=True)"""

new_month = """# 按月统计（descending，首行 = 全量总计）
by_month = defaultdict(lambda: {"in":0,"cr":0,"out":0,"total":0,"sessions":set(),"cost":0.0})
for d, bd in by_day.items():
    month = d[:7]
    bm = by_month[month]
    bm["in"] += bd["in"]; bm["cr"] += bd["cr"]; bm["out"] += bd["out"]
    bm["total"] += bd["total"]; bm["cost"] += bd["cost"]
    bm["sessions"] |= bd["unique_sessions"]
months = sorted(by_month.keys(), reverse=True)"""

assert old_month in content, "Month section not found"
content = content.replace(old_month, new_month, 1)

# 4. Fix 按月 total display: sum of sets -> union
old4 = 'all_sessions = sum(by_month[m]["sessions"] for m in months)'
new4 = 'all_sessions = len(set().union(*[by_month[m]["sessions"] for m in months]))'
assert old4 in content, "Month total not found"
content = content.replace(old4, new4, 1)

with open('option-usage/token-usage.sh', 'w') as f:
    f.write(content)
print('OK: all fixes applied')