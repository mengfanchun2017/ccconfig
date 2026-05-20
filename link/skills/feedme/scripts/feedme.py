#!/usr/bin/env python3
"""feedme — 麦当劳智能订餐交互脚本。
直接调用 MCD MCP API，Claude 只负责启动。"""

import json, os, sys, re, textwrap
from datetime import datetime

SKILL_DIR = os.path.dirname(os.path.abspath(__file__)) + "/.."
sys.path.insert(0, os.path.join(SKILL_DIR, "scripts"))
from mcd_client import MCDClient

CONF_FILE = os.path.expanduser("~/.claude/projects/-home-francis-git/conf/feedme/feedme.json")

# ── helpers ──────────────────────────────────────────────

def load_conf():
    if os.path.exists(CONF_FILE):
        with open(CONF_FILE) as f:
            return json.load(f)
    return {"preferences": {}, "addresses": [], "history": []}

def save_conf(d):
    os.makedirs(os.path.dirname(CONF_FILE), exist_ok=True)
    with open(CONF_FILE, 'w') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)

def time_bucket():
    h = datetime.now().hour
    if 6 <= h < 10.5: return 'breakfast', '🥐'
    if 10.5 <= h < 14: return 'lunch', '🍔'
    if 14 <= h < 17: return 'afternoon_tea', '☕'
    if 17 <= h < 21: return 'dinner', '🍗'
    return 'late_night', '🌙'

def sep(title=None):
    if title:
        print(f"\n{'─'*50}\n  {title}\n{'─'*50}")
    else:
        print(f"{'─'*50}")

def parse_menu_text(text):
    """Parse MCP menu markdown response into structured items."""
    items = []
    current_cat = "其他"
    for line in text.split('\n'):
        line = line.strip()
        if line.startswith('## ') or line.startswith('### '):
            current_cat = line.lstrip('#').strip()
        elif line.startswith('- **') and '**' in line[4:]:
            m = re.match(r'-\s*\*\*(.+?)\*\*\s*[-:]?\s*(.*)', line)
            if m:
                name = m.group(1).strip()
                rest = m.group(2).strip()
                price = re.search(r'(?:¥|￥|价格[：:]\s*)([\d.]+)', rest)
                items.append({
                    'name': name, 'category': current_cat,
                    'price': float(price.group(1)) if price else 0,
                    'desc': rest
                })
    return items

def parse_coupons_text(text):
    """Parse MCP coupon response."""
    coupons = []
    current = {}
    for line in text.split('\n'):
        line = line.strip()
        if line.startswith('## ') and '元' in line:
            if current:
                coupons.append(current)
            current = {'name': line.lstrip('#').strip()}
        elif line.startswith('- **优惠**'):
            current['discount'] = line.split('**:**')[-1].strip()
        elif line.startswith('- **有效期**'):
            current['valid'] = line.split('**:**')[-1].strip()
        elif line.startswith('- **标签**'):
            current['tags'] = line.split('**:**')[-1].strip()
    if current:
        coupons.append(current)
    return coupons

# ── display helpers ──────────────────────────────────────

def show_overview(client, conf):
    bucket, emoji = time_bucket()
    print(f"\n  {emoji}  feedme · 麦当劳智能订餐 | {bucket}")
    print(f"  {'─'*40}")

    # Address
    addrs = conf.get('addresses', [])
    if addrs:
        a = addrs[0]
        print(f"  📍 {a.get('contactName','?')} {a.get('phone','?')} | {a.get('address','')}{a.get('addressDetail','')}")
    else:
        print(f"  📍 未设置地址 — 输入 `地址` 从 MCP 拉取或添加")

    # Coupons (from MCP)
    try:
        ctext = client.text("query-my-coupons")
        count = ctext.count('## ') if ctext else 0
        print(f"  🎫 {count} 张优惠券 | 输入 `券` 查看 | `领券` 一键领取")
    except:
        pass

    # Points
    try:
        ptext = client.text("query-my-account")
        p = re.search(r'(?:availablePoints|可用积分)[^\d]*(\d+)', ptext)
        if p:
            print(f"  ⭐ {p.group(1)} 积分")
    except:
        pass

    # History
    hist = [h for h in conf.get('history', []) if h.get('action') == 'order']
    if hist:
        last = hist[0]
        items = ', '.join(i.get('name','?') for i in last.get('items', []))
        print(f"  🔄 最近: {items} ¥{last.get('total','?')} | 输入 `复购` 再来一单")

    sep()
    print("  [推荐] [菜单] [券] [领券] [复购] [地址] [积分] [活动] [q退出]")
    sep()

def show_menu_text(text):
    """Display MCP menu response in readable format."""
    items = parse_menu_text(text)
    if not items:
        print(text[:500])
        return items

    cats = {}
    for m in items:
        cats.setdefault(m['category'], []).append(m)

    sep("📋 菜单")
    for cat, lst in sorted(cats.items()):
        print(f"\n  ▸ {cat}")
        for i, m in enumerate(lst):
            print(f"  {len([x for v in cats.values() for x in v if cats[list(cats.keys()).index(list(cats.keys())[list(cats.values()).index(v)])]  is lst][:i])} {i+1:>2}. {m['name']:<18s} ¥{m['price']:>5.1f}")

    print(f"\n  共 {len(items)} 种 | 输入 `选 编号` 或 `选 名称`")
    return items

def show_recommend(client, conf, menu_items=None):
    """Query menu + coupons, score, display top picks."""
    # Get store info from address
    addrs = conf.get('addresses', [])
    if not addrs:
        print("  ❌ 需要先设置地址才能推荐。输入 `地址` 拉取或添加。")
        return

    addr = addrs[0]
    store_code = addr.get('storeCode', '')
    be_code = addr.get('beCode', '')

    if not store_code:
        print("  ❌ 地址缺少门店信息。输入 `地址` 重新拉取。")
        return

    print("  ⏳ 查询菜单和优惠券...")
    try:
        menu_text = client.text("query-meals", {"storeCode": store_code, "beCode": be_code, "orderType": 2})
        menu_items = parse_menu_text(menu_text)
    except Exception as e:
        print(f"  ❌ 菜单查询失败: {e}")
        return

    try:
        coupon_text = client.text("query-my-coupons")
        coupons = parse_coupons_text(coupon_text)
    except:
        coupons = []

    prefs = conf.get('preferences', {})
    history = conf.get('history', [])

    # Call recommend engine
    sys.path.insert(0, os.path.join(SKILL_DIR, "scripts"))
    from recommend import score_item

    bucket, _ = time_bucket()
    scored = []
    for item in menu_items:
        s, reasons = score_item(item, prefs, coupons, history, bucket)
        scored.append({'item': item, 'score': s, 'reasons': reasons})
    scored.sort(key=lambda x: x['score'], reverse=True)

    sep(f"⭐ 智能推荐 ({bucket})")
    for i, r in enumerate(scored[:8]):
        item = r['item']
        stars = '⭐' * min(int(r['score']/2) + 1, 5)
        print(f"  {i+1}. {stars} {item['name']:<18s} ¥{item['price']:>5.1f}")
        if r['reasons']:
            print(f"     {', '.join(r['reasons'])}")

    sep()
    print(f"  输入 `选 编号` 加入点餐 | `详情 编号` 查看套餐组成")


def show_coupons(client):
    sep("🎫 我的优惠券")
    try:
        text = client.text("query-my-coupons")
        coupons = parse_coupons_text(text)
        if not coupons:
            # Try direct display
            print(text[:1000])
        else:
            for i, c in enumerate(coupons):
                print(f"  {i+1}. {c.get('name','?')}")
                if c.get('discount'):
                    print(f"     优惠: {c['discount']}")
                if c.get('valid'):
                    print(f"     有效期: {c['valid']}")
                print()
            print(f"  共 {len(coupons)} 张 | 输入 `领券` 一键领取")
    except Exception as e:
        print(f"  ❌ 查询失败: {e}")

def show_addresses(client, conf):
    sep("📍 配送地址")
    try:
        text = client.text("delivery-query-addresses", {"beType": 2})
        print(text[:2000])
        print("\n  输入 `加地址` 添加新地址")
    except Exception as e:
        print(f"  ❌ 查询失败: {e}")
        print("  输入 `加地址` 添加新地址")

def show_history(conf):
    sep("🔄 历史订单")
    orders = [h for h in conf.get('history', []) if h.get('action') == 'order']
    if not orders:
        print("  暂无历史订单")
        return
    for i, o in enumerate(orders[:10]):
        items = ', '.join(it.get('name','?') for it in o.get('items',[]))
        print(f"  {i+1}. {items}  ¥{o.get('total',0)}  {o.get('time','')[:16]}")
    print(f"\n  输入 `复购 N` 快速下单")

def show_activity(client):
    sep("📅 营销活动")
    try:
        text = client.text("campaign-calendar")
        print(text[:1500])
    except Exception as e:
        print(f"  ❌ 查询失败: {e}")

def show_points(client):
    sep("⭐ 我的积分")
    try:
        text = client.text("query-my-account")
        print(text[:1000])
    except Exception as e:
        print(f"  ❌ 查询失败: {e}")


# ── order flow ───────────────────────────────────────────

def start_order(client, conf):
    """Interactive order placement."""
    addrs = conf.get('addresses', [])
    if not addrs:
        print("  ❌ 请先设置地址。输入 `地址` 拉取。")
        return

    addr = addrs[0]
    store_code = addr.get('storeCode', '')
    be_code = addr.get('beCode', '')

    if not store_code:
        # Try to get store from MCP addresses
        r = client.call("delivery-query-addresses", {"beType": 2})
        text = r.get('text', '')
        # Parse addressId and storeCode from response
        print("  ⚠️ 需要先选择地址。输入 `地址` 更新。")
        return

    print("  📋 加载菜单...")
    try:
        menu_text = client.text("query-meals", {"storeCode": store_code, "beCode": be_code, "orderType": 2})
        menu_items = parse_menu_text(menu_text)
    except Exception as e:
        print(f"  ❌ {e}")
        return

    print(f"  ✅ 加载 {len(menu_items)} 种餐品。输入餐品名称或编号加入购物车，输入 `done` 结算。")

    # Quick cart
    cart = []
    while True:
        try:
            cmd = input("  选餐> ").strip()
        except (EOFError, KeyboardInterrupt):
            break

        if not cmd:
            continue
        if cmd.lower() in ('done', '下单', '结算', 'ok'):
            break
        if cmd.lower() in ('q', 'quit', '取消'):
            print("  已取消。")
            return

        # Try match by number
        matched = None
        try:
            n = int(cmd) - 1
            if 0 <= n < len(menu_items):
                matched = menu_items[n]
        except:
            # Match by name keyword
            for m in menu_items:
                if cmd in m['name']:
                    matched = m
                    break

        if matched:
            cart.append({'name': matched['name'], 'price': matched['price'], 'quantity': 1})
            total = sum(c['price'] for c in cart)
            print(f"  ✅ +{matched['name']} ¥{matched['price']} | 购物车 {len(cart)}件 ¥{total}")
        else:
            print(f"  ❓ 未找到「{cmd}」，请重试或输入 `done` 结算 `cancel` 取消")

    if not cart:
        print("  购物车为空，已取消。")
        return

    # Confirm
    total = sum(c['price'] for c in cart)
    print(f"\n  📦 订单确认:")
    for c in cart:
        print(f"     {c['name']:<20s} ¥{c['price']:.1f}")
    print(f"  {'─'*30}")
    print(f"  💰 小计: ¥{total:.1f}")
    print(f"  📍 {addr.get('contactName')} {addr.get('phone')} | {addr.get('address')}{addr.get('addressDetail')}")
    print()
    confirm = input("  确认下单? [Y/n] ").strip().lower()
    if confirm and confirm not in ('y', 'yes', '是', ''):
        print("  已取消。")
        return

    # Place order via MCP
    items = [{"productCode": c.get('code', c['name']), "quantity": c.get('quantity', 1)} for c in cart]
    print("  ⏳ 下单中...")
    try:
        r = client.create_order(store_code, be_code, addr.get('addressId', ''), 2, items)
        text = r.get('text', str(r))
        print(text[:1500])

        # Try to find pay URL
        pay_url = re.search(r'(https?://[^\s"\']+pay[^\s"\']+)', text)
        if pay_url:
            print(f"\n  🔗 支付链接: {pay_url.group(1)}")
            # Show QR
            try:
                import qrcode
                qr = qrcode.QRCode(version=2, error_correction=qrcode.constants.ERROR_CORRECT_M,
                                   box_size=1, border=2)
                qr.add_data(pay_url.group(1))
                qr.make(fit=True)
                try:
                    qr.print_ascii(tty=True)
                except OSError:
                    qr.print_ascii(tty=False)
            except:
                pass

        # Save to history
        conf.setdefault('history', []).insert(0, {
            'action': 'order', 'items': cart,
            'store': addr.get('storeName', ''), 'total': total,
            'time': datetime.now().isoformat()
        })
        save_conf(conf)
        print("\n  ✅ 订单已保存到历史。")
    except Exception as e:
        print(f"  ❌ 下单失败: {e}")


# ── main ──────────────────────────────────────────────────

def main():
    # Check MCP config
    if not os.path.exists(CONF_FILE):
        print("❌ 未配置。请先运行: bash scripts/setup.sh")
        sys.exit(1)

    conf = load_conf()
    token = conf.get('mcd', {}).get('token', '')
    if not token:
        print("❌ Token 未设置。请先运行: bash scripts/setup.sh --update")
        sys.exit(1)

    print("  ⏳ 连接麦当劳 MCP...")
    try:
        client = MCDClient(token)
        client.call("now-time-info")  # warm up
    except Exception as e:
        print(f"  ❌ 连接失败: {e}")
        print("  Token 可能已过期。运行: bash scripts/setup.sh --update")
        sys.exit(1)

    show_overview(client, conf)

    # Main loop
    while True:
        try:
            cmd = input("\nfeedme> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  👋 再见！")
            break

        if not cmd:
            continue

        cl = cmd.lower()

        # ── shortcuts ──
        if cl in ('q', 'quit', 'exit', '退出'):
            print("  👋 再见！")
            break

        elif cl in ('r', 'recommend', '推荐', '推荐一下', '有什么好吃的'):
            show_recommend(client, conf)

        elif cl in ('m', 'menu', '菜单', '看看', '有啥'):
            addrs = conf.get('addresses', [])
            if not addrs:
                print("  ❌ 需先设置地址。输入 `地址` 拉取。")
                continue
            addr = addrs[0]
            store_code = addr.get('storeCode', '')
            be_code = addr.get('beCode', '')
            if not store_code:
                print("  ❌ 地址缺少门店。输入 `地址` 重新拉取。")
                continue
            print("  ⏳ 查询菜单...")
            text = client.text("query-meals", {"storeCode": store_code, "beCode": be_code, "orderType": 2})
            show_menu_text(text)

        elif cl in ('c', 'coupon', '券', '优惠券', '我的券'):
            show_coupons(client)

        elif cl in ('领券', '领优惠券', 'bing'):
            print("  ⏳ 一键领券...")
            r = client.bind_coupons()
            print(r.get('text', r.get('error', str(r)))[:2000])

        elif cl in ('re', 'reorder', '复购', '历史', '再来一单'):
            show_history(conf)

        elif cl.startswith('复购 ') or cl.startswith('re '):
            n = int(cl.split()[-1]) - 1
            orders = [h for h in conf.get('history', []) if h.get('action') == 'order']
            if 0 <= n < len(orders):
                o = orders[n]
                print(f"  复购: {', '.join(i.get('name','?') for i in o['items'])}")
                print(f"  ⚠️ 下单功能: 输入 `下单` 进入交互点餐流程")
            else:
                print(f"  ❌ 无效编号")

        elif cl in ('a', 'addr', '地址', '地址管理'):
            show_addresses(client, conf)

        elif cl.startswith('加地址') or cl in ('+addr',):
            print("  添加新地址:")
            city = input("  城市 (如 北京): ").strip()
            name = input("  联系人: ").strip()
            phone = input("  电话: ").strip()
            addr = input("  地址 (如 朝阳区): ").strip()
            detail = input("  门牌号 (如 望京SOHO T1 1501): ").strip()
            if all([city, name, phone, addr, detail]):
                r = client.add_address(city, name, phone, addr, detail)
                print(r.get('text', str(r))[:2000])
                # Refresh addresses
                r2 = client.call("delivery-query-addresses", {"beType": 2})
                text = r2.get('text', '')
                # Update conf with basic info
                conf.setdefault('addresses', []).insert(0, {
                    'contactName': name, 'phone': phone,
                    'address': addr, 'addressDetail': detail,
                })
                save_conf(conf)
                print("  ✅ 地址已添加")
            else:
                print("  ❌ 所有字段必填")

        elif cl in ('活动', '活动日历', 'calendar', 'cal'):
            show_activity(client)

        elif cl in ('积分', 'points', '我的积分', 'pt'):
            show_points(client)

        elif cl in ('下单', 'order', '点餐'):
            start_order(client, conf)

        elif cl in ('help', '?', '帮助', 'h'):
            print("""
  快捷指令:
    r/推荐     — 智能推荐           券/优惠券   — 查看优惠券
    m/菜单     — 浏览菜单           领券        — 一键领取所有券
    复购/历史   — 历史订单           地址        — 查看/添加地址
    下单       — 交互点餐           积分        — 积分查询
    活动       — 活动日历           q/退出      — 退出
""")

        else:
            print(f"  ❓ 未知指令「{cmd}」。输入 `help` 查看帮助。")


if __name__ == '__main__':
    main()
