#!/usr/bin/env python3
"""feedme CLI — one-shot commands for Claude-driven McDonald's ordering.
Usage: python3 feedme.py <command> [args...]"""

import json, os, sys, re
from datetime import datetime

SKILL_DIR = os.path.dirname(os.path.abspath(__file__)) + "/.."
sys.path.insert(0, os.path.join(SKILL_DIR, "scripts"))
from mcd_client import MCDClient

CONF_FILE = os.path.expanduser("~/.claude/projects/-home-francis-git/conf/feedme/feedme.json")
CART_FILE = "/tmp/feedme_cart.json"
MENU_CACHE = "/tmp/feedme_menu_cache.json"

# ═══════════════════════════════════════════════════════════
# JSON extraction
# ═══════════════════════════════════════════════════════════

def _extract_json(text):
    m = re.search(r'##\s*Original\s*Response\s*(\{.+?\})\s*$', text, flags=re.DOTALL)
    if not m:
        # retry with greedy match (prefer outermost JSON object)
        m = re.search(r'##\s*Original\s*Response\s*(\{.+\})\s*$', text, flags=re.DOTALL)
    if m:
        try: return json.loads(m.group(1))
        except: pass
    idx = text.find('{"success"')
    if idx >= 0:
        depth = 0; end = idx; in_str = False; esc = False
        for i in range(idx, len(text)):
            c = text[i]
            if esc: esc = False; continue
            if c == '\\': esc = True; continue
            if c == '"': in_str = not in_str; continue
            if in_str: continue
            if c == '{': depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0: end = i + 1; break
        if end > idx:
            try: return json.loads(text[idx:end])
            except: pass
    return None

# ═══════════════════════════════════════════════════════════
# Parsers (reused from MCP responses)
# ═══════════════════════════════════════════════════════════

def parse_store_coupons(text):
    """Parse query-store-coupons JSON response into structured list."""
    data = _extract_json(text)
    if not data:
        return []
    items = data.get('data', [])
    if isinstance(items, dict):
        items = items.get('list', items.get('coupons', []))
    if not isinstance(items, list):
        return []
    result = []
    for c in items:
        products = c.get('products', [])
        for p in products:
            result.append({
                'title': c.get('title', ''),
                'couponId': c.get('couponId', ''),
                'couponCode': c.get('couponCode', ''),
                'productCode': p.get('productCode', ''),
                'productName': p.get('productName', ''),
                'tradeDateTime': c.get('tradeDateTime', ''),
            })
    return result

def parse_addresses(text, conf):
    data = _extract_json(text)
    if data and data.get('data', {}).get('addresses'):
        addrs = data['data']['addresses']
        conf['addresses'] = [{
            'addressId': a.get('addressId', ''),
            'contactName': a.get('contactName', ''),
            'phone': a.get('phone', ''),
            'fullAddress': a.get('fullAddress', ''),
            'storeCode': a.get('storeCode', ''),
            'storeName': a.get('storeName', ''),
            'beCode': a.get('beCode', ''),
        } for a in addrs]
        save_conf(conf)
        return conf['addresses']
    return conf.get('addresses', [])

def parse_menu(text):
    data = _extract_json(text)
    if data:
        d = data.get('data', {})
        meals_lookup = d.get('meals', {})
        categories = d.get('categories', [])
        seen = set()
        result = []
        for cat in categories:
            cat_name = cat.get('name', '其他')
            for m in cat.get('meals', []):
                code = m.get('code', '')
                if code in seen: continue
                seen.add(code)
                detail = meals_lookup.get(code, {})
                name = detail.get('name', m.get('name', code))
                price = float(detail.get('currentPrice', detail.get('price', 0)))
                result.append({
                    'name': name, 'code': code,
                    'price': price, 'category': cat_name,
                    'tags': m.get('tags', []),
                })
        return result
    return []

def parse_coupons(text):
    coupons = []
    current = {}
    for line in text.split('\n'):
        line = line.strip()
        if re.match(r'^##\s+', line) and not 'Response' in line and not '字段' in line and not '输出' in line and not '您的' in line and not '共' in line and not '|' in line and not '<img' in line:
            if current: coupons.append(current)
            current = {'name': line.lstrip('#').strip()}
        elif line.startswith('- **优惠**'):
            v = line.split('**:', 1)[-1].strip() if '**:' in line else line.split(':', 1)[-1].strip()
            current['discount'] = v
        elif line.startswith('- **有效期**'):
            v = line.split('**:', 1)[-1].strip() if '**:' in line else line.split(':', 1)[-1].strip()
            current['valid'] = v
        elif line.startswith('- **标签**'):
            v = line.split('**:', 1)[-1].strip() if '**:' in line else line.split(':', 1)[-1].strip()
            current['tags'] = v
    if current: coupons.append(current)
    return coupons

def parse_account(text):
    data = _extract_json(text)
    if data and data.get('data'):
        d = data['data']
        return {'available': d.get('availablePoint', '?'),
                'accumulated': d.get('accumulativePoint', '?'),
                'used': d.get('usedPoint', '?')}
    pts = {}
    for k in ('availablePoint', 'accumulativePoint', 'usedPoint'):
        m = re.search(rf'{k}[^\d]*(\d+\.?\d*)', text)
        if m: pts[k] = m.group(1)
    return pts

# ═══════════════════════════════════════════════════════════
# Conf / cart helpers
# ═══════════════════════════════════════════════════════════

def load_conf():
    if os.path.exists(CONF_FILE):
        with open(CONF_FILE) as f: return json.load(f)
    return {"preferences": {}, "addresses": [], "history": []}

def save_conf(d):
    os.makedirs(os.path.dirname(CONF_FILE), exist_ok=True)
    with open(CONF_FILE, 'w') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)

def load_cart():
    if os.path.exists(CART_FILE):
        with open(CART_FILE) as f: return json.load(f)
    return []

def save_cart(items):
    with open(CART_FILE, 'w') as f:
        json.dump(items, f, ensure_ascii=False)

def load_menu_cache():
    if os.path.exists(MENU_CACHE):
        with open(MENU_CACHE) as f: return json.load(f)
    return []

def save_menu_cache(items):
    with open(MENU_CACHE, 'w') as f:
        json.dump(items, f, ensure_ascii=False)

def time_bucket():
    h = datetime.now().hour
    if 6 <= h < 10.5: return 'breakfast', '🥐'
    if 10.5 <= h < 14: return 'lunch', '🍔'
    if 14 <= h < 17: return 'afternoon_tea', '☕'
    if 17 <= h < 21: return 'dinner', '🍗'
    return 'late_night', '🌙'

def get_default_addr(conf):
    addrs = conf.get('addresses', [])
    return addrs[0] if addrs else None

def init_client():
    conf = load_conf()
    token = conf.get('mcd', {}).get('token', '')
    if not token:
        print("❌ Token 未配置。运行: bash ~/.claude/skills/feedme/scripts/setup.sh")
        sys.exit(1)
    return MCDClient(token), conf

# ═══════════════════════════════════════════════════════════
# Command handlers
# ═══════════════════════════════════════════════════════════

def cmd_overview(client, conf):
    bucket, emoji = time_bucket()

    # Build compact status line
    parts = [f"{emoji} feedme · {bucket}"]

    addrs = conf.get('addresses', [])
    if not addrs:
        try:
            text = client.text("delivery-query-addresses", {"beType": 2})
            addrs = parse_addresses(text, conf)
        except: pass
    if addrs:
        a = addrs[0]
        addr_short = a.get('fullAddress','')[:30]
        parts.append(f"📍{a.get('contactName','?')} {addr_short}")
    else:
        parts.append(f"📍未设置")

    # Coupons, points, history in one line
    stats = []
    try:
        text = client.text("query-my-coupons")
        coupons = parse_coupons(text)
        stats.append(f"🎫{len(coupons)}券")
    except: pass
    try:
        text = client.text("query-my-account")
        pts = parse_account(text)
        stats.append(f"⭐{pts.get('available','?')}分")
    except: pass
    orders = [h for h in conf.get('history', []) if h.get('action') == 'order']
    if orders:
        items = ','.join(i.get('name','')[:6] for i in orders[0].get('items', [])[:2])
        stats.append(f"🔄{items} ¥{orders[0].get('total','?')}")

    cart = load_cart()
    if cart:
        ctotal = sum(c['price'] * c['quantity'] for c in cart)
        stats.append(f"🛒{len(cart)}件¥{ctotal:.0f}")

    parts.append(' | '.join(stats))

    print()
    print('  ' + ' | '.join(parts))
    print(f"  {'─'*50}")
    print("  [推荐] [菜单] [券] [领券] [下单] [复购] [地址] [积分] [活动]")
    print()

def cmd_menu(client, conf):
    a = get_default_addr(conf)
    if not a:
        print("❌ 需先设置地址。说「地址」拉取。")
        return
    sc = a.get('storeCode', ''); bc = a.get('beCode', '')
    if not sc:
        print("❌ 地址缺少门店。说「地址」重新拉取。")
        return
    print("⏳ 查询菜单...")
    text = client.text("query-meals", {"storeCode": sc, "beCode": bc, "orderType": 2})
    items = parse_menu(text)
    if not items:
        print(text[:5000])
        return
    save_menu_cache(items)

    cats = {}
    for m in items:
        cats.setdefault(m.get('category', '其他'), []).append(m)

    print(f"\n📋 麦当劳菜单（{len(items)} 种）")
    print("─" * 60)
    idx = 0
    for cat, lst in sorted(cats.items()):
        print(f"\n  ▸ {cat}")
        for m in lst:
            idx += 1
            print(f"  {idx:>3}. {m['name']:<24s} ¥{m['price']:>7.1f}")
    print(f"\n─" * 60)
    print(f"共 {idx} 种 | 说「选 N」或「要 名称」加购物车 | 「推荐」智能推荐")
    print()

def cmd_recommend(client, conf):
    a = get_default_addr(conf)
    if not a:
        print("❌ 需先设置地址。说「地址」拉取。")
        return
    sc = a.get('storeCode', ''); bc = a.get('beCode', '')
    if not sc:
        print("❌ 地址缺少门店。说「地址」重新拉取。")
        return

    print("⏳ 分析中...")
    menu_text = client.text("query-meals", {"storeCode": sc, "beCode": bc, "orderType": 2})
    menu_items = parse_menu(menu_text)
    if not menu_items:
        print("❌ 菜单解析失败。")
        return
    save_menu_cache(menu_items)

    try:
        coupon_text = client.text("query-store-coupons", {"storeCode": sc, "beCode": bc, "orderType": 2})
        store_coupons = parse_store_coupons(coupon_text)
    except:
        store_coupons = []

    from recommend import score_item
    prefs = conf.get('preferences', {})
    history = conf.get('history', [])
    bucket, _ = time_bucket()

    # Build coupon lookup: item code → coupon info (hybrid: code + name match)
    coupon_by_item = {}
    for scp in store_coupons:
        pc = scp.get('productCode', '')
        pn = scp.get('productName', '')
        for m in menu_items:
            mc = m.get('code', '')
            mn = m.get('name', '')
            if mc in coupon_by_item:
                continue
            if pc and mc and pc == mc:
                coupon_by_item[mc] = scp
            elif pn and mn and (pn in mn or mn in pn):
                coupon_by_item[mc] = scp

    # Convert to old-style coupon dicts for score_item
    coupons_for_scoring = [{'name': c['title'], 'productCode': c['productCode']} for c in store_coupons]

    scored = [(m, *score_item(m, prefs, coupons_for_scoring, history, bucket)) for m in menu_items]
    scored.sort(key=lambda x: x[1], reverse=True)

    # Save scored items as menu cache so "选 N" maps correctly
    save_menu_cache([s[0] for s in scored])

    # Save coupon map for cart-add to use (keyed by item code)
    import json, os
    os.makedirs('/tmp', exist_ok=True)
    with open('/tmp/feedme_coupon_map.json', 'w') as f:
        json.dump(coupon_by_item, f, ensure_ascii=False)

    print(f"\n⭐ 智能推荐 ({bucket})")
    print("─" * 50)
    for i, (item, score, reasons) in enumerate(scored[:8]):
        stars = '⭐' * min(int(score/2) + 1, 5)
        info = coupon_by_item.get(item.get('code', ''))
        if info:
            price_str = f"¥{item['price']:.1f} 🎫{info['title']}"
        else:
            price_str = f"¥{item['price']:.1f}"
        print(f"  {i+1}. {item['name']}  {price_str}")
        other = [r for r in reasons if '有券可用' not in r]
        if other:
            print(f"      {', '.join(other)}")
    print("─" * 50)
    print("说「选 N」加购物车 | 「下单」进入点餐")

def cmd_coupons(client, conf):
    print("⏳ 查询优惠券...")
    text = client.text("query-my-coupons")
    coupons = parse_coupons(text)
    if not coupons:
        print(text[:5000])
        return
    print(f"\n🎫 我的优惠券（{len(coupons)} 张）")
    print("─" * 60)
    for i, c in enumerate(coupons):
        print(f"  {i+1}. {c.get('name','?')}")
        if c.get('discount'): print(f"     优惠: {c['discount']}")
        if c.get('valid'):   print(f"     有效期: {c['valid']}")
        if c.get('tags'):    print(f"     标签: {c['tags']}")
        print()
    print("─" * 60)
    print("说「领券」一键领取")
    print()

def cmd_bind_coupons(client, conf):
    print("⏳ 一键领券...")
    r = client.bind_coupons()
    print(r.get('text', str(r))[:5000])

def cmd_addresses(client, conf):
    print("⏳ 查询地址...")
    text = client.text("delivery-query-addresses", {"beType": 2})
    addrs = parse_addresses(text, conf)
    if not addrs:
        print(text[:5000])
        return
    print(f"\n📍 配送地址（{len(addrs)} 个）")
    print("─" * 60)
    for i, a in enumerate(addrs):
        mark = '👉' if i == 0 else '  '
        print(f"  {mark} {a['contactName']} | {a['phone']}")
        print(f"     {a['fullAddress']}")
        print(f"     门店: {a.get('storeName','?')} ({a.get('storeCode','?')})")
        print()
    print("─" * 60)

def cmd_add_address(client, conf, args):
    if len(args) < 5:
        print("❌ 用法: 加地址 城市 姓名 电话 地址 门牌号")
        print("   示例: 加地址 北京 张三 13800138000 朝阳区 望京SOHO T1")
        return
    city, name, phone, addr, detail = args[0], args[1], args[2], args[3], ' '.join(args[4:])
    print(f"⏳ 添加地址: {name} {phone} {city}{addr}{detail}...")
    r = client.add_address(city, name, phone, addr, detail)
    print(r.get('text', str(r))[:5000])
    print("⏳ 刷新地址列表...")
    text = client.text("delivery-query-addresses", {"beType": 2})
    parse_addresses(text, conf)
    print("✅ 地址已添加。")

def cmd_history(client, conf):
    orders = [h for h in conf.get('history', []) if h.get('action') == 'order']
    if not orders:
        print("暂无历史订单。")
        return
    print(f"\n🔄 历史订单（最近 {min(10, len(orders))} 单）")
    print("─" * 60)
    for i, o in enumerate(orders[:10]):
        items = ', '.join(it.get('name','?') for it in o.get('items', []))
        print(f"  {i+1}. {items}")
        print(f"     ¥{o.get('total',0)}  {o.get('time','')[:16]}  {o.get('store','')}")
        print()
    print("─" * 60)
    print("说「复购 N」快速下单")

def cmd_points(client, conf):
    print("⏳ 查询积分...")
    text = client.text("query-my-account")
    pts = parse_account(text)
    if pts:
        print(f"\n⭐ 我的积分")
        print("─" * 40)
        for k, v in pts.items():
            print(f"  {k}: {v}")
        print()
    else:
        print(text[:5000])

def cmd_activity(client, conf):
    print("⏳ 查询活动...")
    text = client.text("campaign-calendar")
    print(text[:5000])

# ═══════════════════════════════════════════════════════════
# Cart commands
# ═══════════════════════════════════════════════════════════

def _find_items(indices_or_names):
    """Find items from menu cache by index (1-based) or name substring."""
    menu = load_menu_cache()
    if not menu:
        print("⚠️ 请先查看菜单或推荐。说「菜单」或「推荐」。")
        return []
    found = []
    for sel in indices_or_names:
        sel = sel.strip()
        # Try index
        try:
            n = int(sel) - 1
            if 0 <= n < len(menu):
                found.append(menu[n])
                continue
        except ValueError:
            pass
        # Try name match (case-insensitive substring)
        matches = [m for m in menu if sel.lower() in m.get('name', '').lower()]
        if len(matches) == 1:
            found.append(matches[0])
        elif len(matches) > 1:
            print(f"  多个匹配「{sel}」: {', '.join(m['name'] for m in matches[:5])}")
            print(f"  请用编号或更精确的名称。")
            return []
        else:
            print(f"  ❓ 未找到「{sel}」。用「菜单」查看。")
            return []
    return found

def cmd_cart_add(client, conf, args):
    if not args:
        print("❌ 用法: 选 1,3,5 或 选 巨无霸")
        return
    # Support both comma-separated and space-separated
    parts = []
    for a in args:
        parts.extend([p.strip() for p in a.split(',') if p.strip()])
    items = _find_items(parts)
    if not items:
        return
    # Load coupon map (written by recommend)
    coupon_map = {}
    try:
        with open('/tmp/feedme_coupon_map.json') as f:
            coupon_map = json.load(f)
    except: pass

    cart = load_cart()
    for item in items:
        existing = next((c for c in cart if c['code'] == item['code']), None)
        if existing:
            existing['quantity'] += 1
            entry = existing
        else:
            entry = {'name': item['name'], 'code': item['code'],
                     'price': item['price'], 'quantity': 1}
            cinfo = coupon_map.get(item.get('code', ''))
            if cinfo:
                entry['couponId'] = cinfo.get('couponId', '')
                entry['couponCode'] = cinfo.get('couponCode', '')
                entry['couponTitle'] = cinfo.get('title', '')
            cart.append(entry)
        ctag = f"  🎫{entry.get('couponTitle','')}" if entry.get('couponTitle') else ''
        print(f"  ✅ {item['name']} x{entry['quantity']}  ¥{item['price']:.1f}{ctag}")
    save_cart(cart)
    total_qty = sum(c['quantity'] for c in cart)
    total = sum(c['price'] * c['quantity'] for c in cart)
    coupon_count = sum(1 for c in cart if c.get('couponCode'))
    cextra = f'  🎫{coupon_count}张券' if coupon_count else ''
    print(f"  🛒 {total_qty}件 ¥{total:.1f}{cextra}")
    print(f"  购物车 | 结算 | 清空")

def cmd_cart_show(client, conf):
    cart = load_cart()
    if not cart:
        print("🛒 购物车为空。说「菜单」或「推荐」开始选餐。")
        return
    total = sum(c['price'] * c['quantity'] for c in cart)
    print(f"\n🛒 购物车（{len(cart)} 种）")
    print("─" * 44)
    for i, c in enumerate(cart):
        qty = f"x{c['quantity']}" if c['quantity'] > 1 else ""
        ctag = f"  🎫{c['couponTitle']}" if c.get('couponTitle') else ""
        print(f"  {i+1}. {c['name']} {qty}  ¥{c['price'] * c['quantity']:.1f}{ctag}")
    print("─" * 44)
    print(f"  💰 ¥{total:.1f}")
    print()
    print("选 N 加餐 | 删 N | 清空 | 结算")
    print()

def cmd_cart_remove(client, conf, args):
    if not args:
        print("❌ 用法: 删 1 或 删 巨无霸")
        return
    cart = load_cart()
    if not cart:
        print("🛒 购物车为空。")
        return
    try:
        n = int(args[0]) - 1
        if 0 <= n < len(cart):
            removed = cart.pop(n)
            save_cart(cart)
            print(f"  ✅ 已移除: {removed['name']}")
            return
    except ValueError:
        pass
    # Match by name
    matches = [c for c in cart if args[0].lower() in c['name'].lower()]
    if len(matches) == 1:
        cart.remove(matches[0])
        save_cart(cart)
        print(f"  ✅ 已移除: {matches[0]['name']}")
    elif len(matches) > 1:
        print(f"  多个匹配: {', '.join(c['name'] for c in matches)}")
    else:
        print(f"  ❓ 购物车中未找到「{args[0]}」。")

def cmd_cart_clear(client, conf):
    if os.path.exists(CART_FILE):
        os.remove(CART_FILE)
    print("🛒 购物车已清空。")

# ═══════════════════════════════════════════════════════════
# Order flow
# ═══════════════════════════════════════════════════════════

def cmd_checkout(client, conf):
    """Calculate price and show order summary."""
    cart = load_cart()
    if not cart:
        print("🛒 购物车为空。说「菜单」或「推荐」选餐。")
        return

    a = get_default_addr(conf)
    if not a:
        print("❌ 缺少地址。说「地址」拉取。")
        return

    cart_total = sum(c['price'] * c['quantity'] for c in cart)
    coupon_tags = []
    for c in cart:
        if c.get('couponTitle'):
            coupon_tags.append(c['couponTitle'])

    print(f"\n📦 订单确认")
    print("═" * 44)
    for c in cart:
        qty = f"x{c['quantity']}" if c['quantity'] > 1 else ""
        tag = f"  🎫{c['couponTitle']}" if c.get('couponTitle') else ""
        print(f"  {c['name']} {qty}  ¥{c['price'] * c['quantity']:.1f}{tag}")
    print("─" * 44)

    # Calculate actual price via MCP
    print("  ⏳ 询价...")
    order_items = []
    for c in cart:
        oi = {"productCode": c['code'], "quantity": c['quantity']}
        if c.get('couponCode'):
            oi['couponCode'] = c['couponCode']
        if c.get('couponId'):
            oi['couponId'] = c['couponId']
        order_items.append(oi)
    try:
        r = client.calc_price(a['storeCode'], a['beCode'], 2, order_items)
        text = r.get('text', '')
        data = _extract_json(text)

        if data and data.get('data'):
            d = data['data']
            def _y(v): return int(v) / 100 if v else 0

            p_actual = _y(d.get('productPrice', 0))
            d_actual = _y(d.get('deliveryPrice', 0))
            pk_actual = _y(d.get('packingPrice', 0))
            discount = _y(d.get('discount', 0))
            final_total = _y(d.get('price', 0))

            print(f"  商品 ¥{p_actual:.2f}  |  配送 ¥{d_actual:.2f}  |  优惠 ¥{discount:.2f}  |  实付 ¥{final_total:.2f}")
        else:
            print(text[:2000])
    except Exception as e:
        print(f"  ⚠️ 价格计算异常: {e}")

    print("─" * 44)
    print(f"  📍 {a.get('contactName','?')} {a.get('phone','?')}")
    print(f"     {a.get('fullAddress','')[:60]}")
    print("═" * 44)
    print()
    print("说「确认」完成下单 | 「取消」放弃 | 「选 N」继续加餐")

def cmd_confirm(client, conf):
    """Place order."""
    cart = load_cart()
    if not cart:
        print("🛒 购物车为空。")
        return

    a = get_default_addr(conf)
    if not a:
        print("❌ 缺少地址。")
        return

    total = sum(c['price'] * c['quantity'] for c in cart)
    order_items = []
    for c in cart:
        oi = {"productCode": c['code'], "quantity": c['quantity']}
        if c.get('couponCode'):
            oi['couponCode'] = c['couponCode']
        if c.get('couponId'):
            oi['couponId'] = c['couponId']
        order_items.append(oi)

    print("⏳ 下单中...")
    try:
        r = client.create_order(a['storeCode'], a['beCode'], a.get('addressId', ''), 2, order_items)
        text = r.get('text', '')

        # Parse JSON from response
        data = _extract_json(text)
        if data and data.get('success') == False:
            err_code = data.get('code', '?')
            err_msg = data.get('message', data.get('msg', '未知错误'))
            print(f"❌ 下单失败 [{err_code}]: {err_msg}")
            return

        if not data or not data.get('data'):
            print("❌ 下单响应解析失败，请检查订单状态")
            print(text[:5000])
            return

        d = data['data']
        detail = d.get('orderDetail', d)
        delivery = d.get('deliveryInfo', detail.get('deliveryInfo', {}))

        print(f"\n📋 下单成功")
        print("═" * 50)
        print(f"  订单号: {d.get('orderId','?')}")
        print(f"  门店:   {detail.get('storeName', a.get('storeName','?'))}")
        print(f"  状态:   {detail.get('orderStatus','?')}")
        print(f"  商品:   {detail.get('orderProductList', d.get('productList', [{}]))[0].get('productName','?')} x{detail.get('orderProductList', d.get('productList', [{}]))[0].get('quantity','?')}")
        print(f"  实付:   ¥{float(detail.get('realTotalAmount', detail.get('totalAmount', 0))):.2f}")
        print(f"  地址:   {delivery.get('customerNickname', a.get('contactName','?'))} {delivery.get('mobilePhone', a.get('phone','?'))}")
        addr_line = delivery.get('deliveryAddress', a.get('fullAddress',''))
        addr_detail = delivery.get('addressDetail', '')
        print(f"          {addr_line} {addr_detail}")
        print("═" * 50)
        print(f"\n📱 请打开麦当劳 App → 我的 → 待支付订单 → 完成支付")

        # Save to history, clear cart
        conf.setdefault('history', []).insert(0, {
            'action': 'order', 'items': cart,
            'orderId': d.get('orderId', ''),
            'store': detail.get('storeName', a.get('storeName', '')),
            'total': float(detail.get('realTotalAmount', total)),
            'time': datetime.now().isoformat()
        })
        save_conf(conf)
        if os.path.exists(CART_FILE):
            os.remove(CART_FILE)
        print("✅ 订单已保存。")
    except Exception as e:
        print(f"❌ 下单失败: {e}")

def cmd_reorder(client, conf, args):
    orders = [h for h in conf.get('history', []) if h.get('action') == 'order']
    if not orders:
        print("暂无历史订单。")
        return
    n = 1
    if args:
        try: n = int(args[0])
        except ValueError: n = 1
    idx = n - 1
    if not (0 <= idx < len(orders)):
        print(f"❌ 无效编号。共 {len(orders)} 单。")
        return
    o = orders[idx]
    print(f"🔄 复购: {', '.join(i.get('name','?') for i in o['items'])}")
    # Fill cart with this order's items
    cart = [{'name': i['name'], 'code': i.get('code', i['name']),
             'price': i.get('price', 0), 'quantity': i.get('quantity', 1)}
            for i in o['items']]
    save_cart(cart)
    print(f"🛒 已装车。说「结算」确认下单。")

def cmd_cancel(client, conf):
    if os.path.exists(CART_FILE):
        os.remove(CART_FILE)
    print("已取消。购物车清空。")

# ═══════════════════════════════════════════════════════════
# Dispatch
# ═══════════════════════════════════════════════════════════

def main():
    if len(sys.argv) < 2:
        print("usage: feedme.py <command> [args...]", file=sys.stderr)
        print("commands: overview menu recommend coupons bind-coupons addresses", file=sys.stderr)
        print("          add-address history points activity cart-add cart-show", file=sys.stderr)
        print("          cart-remove cart-clear checkout confirm reorder cancel", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]
    args = sys.argv[2:]

    # Commands that don't need MCP
    if cmd in ('cart-show',):
        cmd_cart_show(None, load_conf())
        return
    if cmd in ('cart-clear', 'cancel'):
        cmd_cart_clear(None, None)
        return

    client, conf = init_client()

    handlers = {
        'overview':      lambda: cmd_overview(client, conf),
        'menu':          lambda: cmd_menu(client, conf),
        'recommend':     lambda: cmd_recommend(client, conf),
        'coupons':       lambda: cmd_coupons(client, conf),
        'bind-coupons':  lambda: cmd_bind_coupons(client, conf),
        'addresses':     lambda: cmd_addresses(client, conf),
        'add-address':   lambda: cmd_add_address(client, conf, args),
        'history':       lambda: cmd_history(client, conf),
        'points':        lambda: cmd_points(client, conf),
        'activity':      lambda: cmd_activity(client, conf),
        'cart-add':      lambda: cmd_cart_add(client, conf, args),
        'cart-show':     lambda: cmd_cart_show(client, conf),
        'cart-remove':   lambda: cmd_cart_remove(client, conf, args),
        'cart-clear':    lambda: cmd_cart_clear(client, conf),
        'checkout':      lambda: cmd_checkout(client, conf),
        'confirm':       lambda: cmd_confirm(client, conf),
        'reorder':       lambda: cmd_reorder(client, conf, args),
        'cancel':        lambda: cmd_cancel(client, conf),
    }

    h = handlers.get(cmd)
    if h:
        h()
    else:
        print(f"❓ 未知命令「{cmd}」。可用: {', '.join(sorted(handlers.keys()))}")
        sys.exit(1)

if __name__ == '__main__':
    main()
