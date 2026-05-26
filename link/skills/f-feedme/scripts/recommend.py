#!/usr/bin/env python3
"""Rule-based food recommendation engine for feedme."""
import json, sys, os
from datetime import datetime

def time_bucket():
    """Determine current meal time bucket."""
    h = datetime.now().hour
    if 6 <= h < 10.5:
        return 'breakfast'
    elif 10.5 <= h < 14:
        return 'lunch'
    elif 14 <= h < 17:
        return 'afternoon_tea'
    elif 17 <= h < 21:
        return 'dinner'
    else:
        return 'late_night'

def score_item(item, prefs, coupons, history, bucket):
    """Score a single menu item. Returns (score, reasons)."""
    score = 0.0
    reasons = []

    name = item.get('name', '')
    code = item.get('code', '')
    price = float(item.get('price', 0))
    tags = item.get('tags', [])
    category = item.get('category', '')

    # 1. History frequency (weight: 3)
    order_count = sum(1 for h in history if any(
        i.get('code') == code or i.get('name') == name
        for i in h.get('items', [])
    ))
    if order_count > 0:
        pts = min(order_count * 3, 15)
        score += pts
        reasons.append(f"点过{order_count}次 +{pts}")

    # 2. Coupon match (weight: 2)
    for c in coupons:
        if c.get('productCode') == code or name in c.get('name', ''):
            score += 8
            reasons.append(f"有券可用 +8")
            break

    # 3. Favorite match (weight: 2.5)
    favorites = prefs.get('favorites', [])
    for fav in favorites:
        if fav in name:
            score += 6
            reasons.append(f"收藏:{fav} +6")
            break

    # 4. Taste preference (weight: 1.5)
    tastes = prefs.get('taste', [])
    tag_lower = ' '.join(tags).lower() + name.lower()
    for t in tastes:
        if t.lower() in tag_lower:
            score += 3
            reasons.append(f"口味:{t} +3")
            break

    # 5. Time relevance (weight: 1)
    time_categories = {
        'breakfast': ['早餐', 'breakfast', '咖啡', 'coffee'],
        'lunch': ['汉堡', '套餐', 'burger', 'meal', '鸡', 'chicken'],
        'afternoon_tea': ['甜品', '甜点', '冰淇淋', '饮料', 'drink', '咖啡', 'coffee', '小吃', 'snack'],
        'dinner': ['汉堡', '套餐', 'burger', 'meal', '鸡', 'chicken', '桶', 'bundle'],
        'late_night': ['小吃', 'snack', '饮料', 'drink', '甜品']
    }
    relevant = time_categories.get(bucket, [])
    for r in relevant:
        if r in name or r in category.lower():
            score += 2
            reasons.append(f"时段:{bucket} +2")
            break

    # 6. Budget fit (weight: 0.5)
    budget = prefs.get('budget', 50)
    if price <= budget * 0.5:
        score += 1
        reasons.append("预算友好 +1")
    elif price > budget:
        score -= 5
        reasons.append(f"超预算 -5")

    # 7. Dislike penalty
    dislikes = prefs.get('dislikes', [])
    for d in dislikes:
        if d in name:
            score -= 20
            reasons.append(f"忌口:{d} -20")
            break

    return round(score, 1), reasons

def recommend(menu_items, prefs, coupons, history, limit=5, bucket=None):
    """Score and rank menu items. Returns top-N with reasons."""
    if bucket is None:
        bucket = time_bucket()

    scored = []
    for item in menu_items:
        s, reasons = score_item(item, prefs, coupons, history, bucket)
        scored.append({
            'item': item,
            'score': s,
            'reasons': reasons
        })

    scored.sort(key=lambda x: x['score'], reverse=True)
    return scored[:limit]


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='feedme recommendation engine')
    parser.add_argument('--menu', required=True, help='Menu JSON from MCP query-meals')
    parser.add_argument('--coupons', default='[]', help='Coupons JSON')
    parser.add_argument('--prefs', help='Path to feedme.json (optional, auto-detects)')
    parser.add_argument('--limit', type=int, default=5, help='Max recommendations')
    parser.add_argument('--bucket', help='Meal time bucket override')
    parser.add_argument('--debug', action='store_true', help='Show scoring details')
    args = parser.parse_args()

    menu = json.loads(args.menu)
    coupons = json.loads(args.coupons)
    menu_items = menu if isinstance(menu, list) else menu.get('meals', menu.get('items', []))

    # Load prefs
    if args.prefs:
        with open(args.prefs) as f:
            data = json.load(f)
    else:
        conf_file = os.path.expanduser("~/.claude/projects/-home-francis-git/conf/feedme/feedme.json")
        if os.path.exists(conf_file):
            with open(conf_file) as f:
                data = json.load(f)
        else:
            data = {"preferences": {}, "history": []}

    prefs = data.get('preferences', {})
    history = data.get('history', [])

    results = recommend(menu_items, prefs, coupons, history, args.limit, args.bucket)

    if args.debug:
        for r in results:
            item = r['item']
            print(f"\n{'='*50}")
            print(f"⭐ {r['score']}  {item.get('name', item.get('code', '?'))}  ¥{item.get('price', '?')}")
            for reason in r['reasons']:
                print(f"   {reason}")
        print()
    else:
        # Compact output for TUI
        output = []
        for i, r in enumerate(results):
            item = r['item']
            output.append({
                'rank': i + 1,
                'score': r['score'],
                'name': item.get('name', ''),
                'code': item.get('code', ''),
                'price': item.get('price', 0),
                'category': item.get('category', ''),
                'reasons': r['reasons']
            })
        print(json.dumps(output, ensure_ascii=False))
