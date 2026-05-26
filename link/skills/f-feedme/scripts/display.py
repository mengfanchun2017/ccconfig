#!/usr/bin/env python3
"""feedme display engine — formats data for terminal output.
Claude handles conversation + MCP calls; this script handles display only.
Usage: display.py <command> [json_data_or_file]"""

import json, sys, os
from datetime import datetime

CONF_FILE = os.path.expanduser("~/.claude/projects/-home-francis-git/conf/feedme/feedme.json")

# ── helpers ──────────────────────────────────────────────

def _load_conf():
    if os.path.exists(CONF_FILE):
        with open(CONF_FILE) as f:
            return json.load(f)
    return {}

def _input_data():
    """Read JSON from stdin or argv[2] file."""
    if len(sys.argv) > 2:
        arg = sys.argv[2]
        if arg == '-':
            return json.load(sys.stdin)
        if os.path.isfile(arg):
            with open(arg) as f:
                return json.load(f)
        return json.loads(arg)
    return json.load(sys.stdin)

def _time_bucket():
    h = datetime.now().hour
    if 6 <= h < 10.5: return 'breakfast'
    elif 10.5 <= h < 14: return 'lunch'
    elif 14 <= h < 17: return 'afternoon_tea'
    elif 17 <= h < 21: return 'dinner'
    else: return 'late_night'

def _bucket_emoji(b):
    return {'breakfast':'🥐','lunch':'🍔','afternoon_tea':'☕','dinner':'🍗','late_night':'🌙'}.get(b,'🍽️')

# ── display commands ──────────────────────────────────────

def overview():
    """Show quick context: addresses, recent orders, coupons, time."""
    conf = _load_conf()
    prefs = conf.get('preferences', {})
    addrs = conf.get('addresses', [])
    history = conf.get('history', [])
    bucket = _time_bucket()
    budget = prefs.get('budget', 50)
    tastes = prefs.get('taste', [])
    favs = prefs.get('favorites', [])

    print()
    print("╔══════════════════════════════════════════╗")
    print(f"║  🍔  feedme · 麦当劳智能订餐              ║")
    print(f"║  {_bucket_emoji(bucket)}  时段: {bucket}                              ║")
    print("╚══════════════════════════════════════════╝")
    print()

    if addrs:
        a = addrs[0]
        print(f"📍 默认地址: {a['contactName']} {a['phone']}")
        print(f"   {a['address']}{a['addressDetail']}")
    else:
        print("📍 未设置地址 — 说「加地址」添加配送地址")

    print()

    if favs:
        print(f"⭐ 偏好: {', '.join(favs[:4])} | 口味: {', '.join(tastes) if tastes else '未设置'} | 预算: ¥{budget}")
    else:
        print(f"⭐ 偏好未设置 | 预算: ¥{budget}")

    print()

    orders = [h for h in history if h.get('action') == 'order']
    if orders:
        last = orders[0]
        items = ', '.join(i.get('name','?') for i in last.get('items', []))
        print(f"🔄 最近一单: {items}  ¥{last.get('total','?')}  {last.get('time','')[:16]}")
        print(f"   说「复购」快速再来一单")
    print()

    print("─" * 44)
    print("快捷指令: 推荐 | 菜单 | 优惠券 | 复购 | 加地址 | 设置")
    print("─" * 44)
    print()

def menu(data):
    """Display formatted menu from MCP query-meals output."""
    items = data if isinstance(data, list) else data.get('meals', data.get('items', []))
    meals = data if isinstance(data, list) else data.get('meals', data.get('items', []))

    bucket = _time_bucket()
    print()
    print(f"📋 麦当劳菜单 ({_bucket_emoji(bucket)} {bucket})")
    print("─" * 56)

    # Group by category
    cats = {}
    for m in meals:
        cat = m.get('category', '其他')
        cats.setdefault(cat, []).append(m)

    for cat, items in sorted(cats.items()):
        print(f"\n  ▸ {cat}")
        for m in items:
            name = m.get('name', m.get('code', '?'))
            price = m.get('price', '?')
            price_str = str(price) if not isinstance(price, str) else price
            tags = ' '.join(m.get('tags', [])[:3])
            tag_str = f"  [{tags}]" if tags else ""
            print(f"    {name:<20s} ¥{price_str:>6s}{tag_str}")

    print()
    print("─" * 56)
    print(f"共 {len(meals)} 种 | 说「选 编号/名称」加入点餐")
    print()

def recommend(data):
    """Display recommendation results from recommend.py."""
    if isinstance(data, str):
        data = json.loads(data)

    print()
    print("⭐ 智能推荐")
    print("─" * 56)
    print()

    for r in data:
        rank = r.get('rank', '?')
        score = r.get('score', 0)
        name = r.get('name', '?')
        price = r.get('price', '?')
        reasons = r.get('reasons', [])
        stars = '⭐' * min(int(score/2) + 1, 5)

        print(f"  {rank}. {stars} {name}  ¥{price}")
        if reasons:
            print(f"     {', '.join(reasons)}")
        print()

    print("─" * 56)
    print("说「选 N」或「要 名称」加入点餐")

def coupons(data):
    """Display coupon list from MCP query-my-coupons / available-coupons."""
    if isinstance(data, str):
        data = json.loads(data)

    print()
    print("🎫 可用优惠券")
    print("─" * 56)
    print()

    if not data:
        print("  暂无可用优惠券")
        print("  说「领券」一键领取")
        return

    for i, c in enumerate(data):
        name = c.get('name', c.get('title', '优惠券'))
        discount = c.get('discount', c.get('desc', ''))
        valid = c.get('validDate', c.get('expire', ''))
        status = c.get('status', '')

        icon = '🟢' if status in ('available', '可使用') else '🔴'
        print(f"  {i+1}. {icon} {name}")
        if discount:
            print(f"     优惠: {discount}")
        if valid:
            print(f"     有效期: {valid}")
        print()

    print("─" * 56)
    print(f"共 {len(data)} 张 | 说「领券」一键领取全部")

def order_summary(items, total, address, delivery_fee=None, discount=None):
    """Display order confirmation before placing."""
    print()
    print("╔══════════════════════════════════════════╗")
    print("║  ✅ 订单确认                              ║")
    print("╚══════════════════════════════════════════╝")
    print()

    print("  📦 餐品:")
    for item in items:
        qty = item.get('quantity', 1)
        name = item.get('name', item.get('productCode', '?'))
        price = item.get('price', 0)
        if qty > 1:
            print(f"     {qty}x {name}  ¥{price * qty}")
        else:
            print(f"     {name}  ¥{price}")
    print()

    print(f"  💰 小计: ¥{total}")
    if delivery_fee:
        print(f"  🚚 配送费: ¥{delivery_fee}")
    if discount:
        print(f"  🎫 优惠: -¥{discount}")
    print(f"  ──────────────")
    print(f"  💰 合计: ¥{total + (delivery_fee or 0) - (discount or 0)}")
    print()

    addr = address if isinstance(address, dict) else {}
    print(f"  📍 {addr.get('contactName','?')} {addr.get('phone','?')}")
    print(f"     {addr.get('address','')}{addr.get('addressDetail','')}")
    print()

    print("─" * 44)
    print("说「确认下单」完成订单 | 「取消」放弃")
    print()

def addresses(data):
    """Display saved addresses."""
    if isinstance(data, str):
        data = json.loads(data)

    print()
    print("📍 配送地址")
    print("─" * 44)
    print()

    if not data:
        print("  未设置地址")
        print("  说「加地址」添加: 城市 姓名 电话 地址 门牌号")
        return

    for i, a in enumerate(data):
        mark = '👉' if i == 0 else '  '
        print(f"  {mark} {a.get('contactName','?')}  {a.get('phone','?')}")
        print(f"     {a.get('address','')}{a.get('addressDetail','')}")
        print()

    print("─" * 44)
    print("说「用地址 N」选择配送地址")

def history_list(data):
    """Display recent order history."""
    if isinstance(data, str):
        data = json.loads(data)
    orders = [h for h in data if h.get('action') == 'order']

    print()
    print("🔄 历史订单")
    print("─" * 56)
    print()

    if not orders:
        print("  暂无历史订单")
        return

    for i, o in enumerate(orders[:10]):
        items = ', '.join(it.get('name','?') for it in o.get('items',[]))
        total = o.get('total', 0)
        t = o.get('time','')[:16]
        store = o.get('store', '')

        print(f"  {i+1}. {items}")
        print(f"     ¥{total}  {t}  {store}")
        print()

    print("─" * 56)
    print("说「复购 N」快速再来一单")

def qr_pay(url):
    """Display payment QR code."""
    print()
    print("=" * 52)
    print("  📱 扫描二维码支付")
    print("=" * 52)
    print()

    try:
        import qrcode
        qr = qrcode.QRCode(version=2, error_correction=qrcode.constants.ERROR_CORRECT_M,
                           box_size=1, border=2)
        qr.add_data(url)
        qr.make(fit=True)
        try:
            qr.print_ascii(tty=True)
        except OSError:
            qr.print_ascii(tty=False)
    except ImportError:
        print("  [qrcode 未安装]")

    print()
    print(f"  🔗 {url}")
    print()
    print("=" * 52)

def points(data):
    """Display points balance."""
    if isinstance(data, str):
        data = json.loads(data)
    print()
    print("⭐ 我的积分")
    print("─" * 44)
    for k, v in data.items():
        print(f"  {k}: {v}")
    print()

# ── main ──────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("usage: display.py <overview|menu|recommend|coupons|order|addresses|history|qr|points> [json]", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]
    commands = {
        'overview': lambda: overview(),
        'menu': lambda: menu(_input_data()),
        'recommend': lambda: recommend(_input_data()),
        'coupons': lambda: coupons(_input_data()),
        'addresses': lambda: addresses(_input_data()),
        'history': lambda: history_list(_input_data()),
        'qr': lambda: qr_pay(sys.argv[2] if len(sys.argv) > 2 else ''),
        'points': lambda: points(_input_data()),
    }

    if cmd in commands:
        commands[cmd]()
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        print(f"Available: {', '.join(commands.keys())}", file=sys.stderr)
        sys.exit(1)
