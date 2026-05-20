#!/usr/bin/env python3
"""feedme — 麦当劳智能订餐交互脚本。
直连 MCD MCP API，Claude 只负责启动。"""

import json, os, sys, re
from datetime import datetime

SKILL_DIR = os.path.dirname(os.path.abspath(__file__)) + "/.."
sys.path.insert(0, os.path.join(SKILL_DIR, "scripts"))
from mcd_client import MCDClient

CONF_FILE = os.path.expanduser("~/.claude/projects/-home-francis-git/conf/feedme/feedme.json")

# ── MCP response parsers ──────────────────────────────────

def _extract_json(text):
    """Extract embedded JSON from MCP markdown response. Tries multiple patterns."""
    # Try the "Original Response" marker first
    m = re.search(r'##\s*Original\s*Response\s*(\{.+?\})\s*$', text, flags=re.DOTALL)
    if m:
        try: return json.loads(m.group(1))
        except: pass
    # Fallback: find {"success" and use brace counter to extract complete JSON
    idx = text.find('{"success"')
    if idx >= 0:
        depth = 0; end = idx
        in_str = False; esc = False
        for i in range(idx, len(text)):
            c = text[i]
            if esc: esc = False; continue
            if c == '\\': esc = True; continue
            if c == '"': in_str = not in_str; continue
            if in_str: continue
            if c == '{': depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
        if end > idx:
            try: return json.loads(text[idx:end])
            except: pass
    return None

def parse_addresses(text, conf):
    """Parse MCP address response. Update conf with real address data. Returns list."""
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

def parse_account(text):
    """Extract points values from MCP account response."""
    data = _extract_json(text)
    if data and data.get('data'):
        d = data['data']
        return {
            'available': d.get('availablePoint', '?'),
            'accumulated': d.get('accumulativePoint', '?'),
            'used': d.get('usedPoint', '?'),
        }
    # Fallback: regex from markdown
    pts = {}
    for k in ('availablePoint', 'accumulativePoint', 'usedPoint'):
        m = re.search(rf'{k}[^\d]*(\d+)', text)
        if m:
            pts[k] = m.group(1)
    return pts

def parse_menu(text):
    """Parse MCP menu response. Returns list of {name, code, price, category, desc}.
    MCP response structure: data.categories[].meals[].code + data.meals[code].{name,currentPrice}"""
    data = _extract_json(text)
    if data:
        d = data.get('data', {})
        meals_lookup = d.get('meals', d.get('products', {}))
        categories = d.get('categories', [])
        seen = set()
        result = []
        for cat in categories:
            cat_name = cat.get('name', '其他')
            for m in cat.get('meals', []):
                code = m.get('code', '')
                if code in seen:
                    continue
                seen.add(code)
                detail = meals_lookup.get(code, {})
                name = detail.get('name', m.get('name', code))
                price = float(detail.get('currentPrice', detail.get('price', 0)))
                tags = m.get('tags', [])
                result.append({
                    'name': name, 'code': code,
                    'price': price, 'category': cat_name,
                    'tags': tags,
                    'desc': detail.get('description', ''),
                })
        return result

    # Fallback: parse markdown
    items = []
    current_cat = '其他'
    for line in text.split('\n'):
        line = line.strip()
        if re.match(r'^#{2,3}\s', line):
            current_cat = line.lstrip('#').strip()
            if '结构' in current_cat or 'Response' in current_cat or '输出' in current_cat:
                current_cat = '其他'
        elif line.startswith('- **') and '**' in line[4:]:
            m = re.match(r'-\s*\*\*(.+?)\*\*\s*[-:]?\s*(.*)', line)
            if m:
                name = m.group(1).strip()
                rest = m.group(2).strip()
                price = re.search(r'(?:¥|￥|价格[：:]\s*)([\d.]+)', rest)
                items.append({
                    'name': name, 'category': current_cat,
                    'price': float(price.group(1)) if price else 0,
                    'code': name, 'desc': rest
                })
    return items

def parse_coupons(text):
    """Parse MCP coupon response. Returns list of {name, discount, valid, tags}."""
    coupons = []
    current = {}
    for line in text.split('\n'):
        line = line.strip()
        if re.match(r'^##\s+', line) and not 'Response' in line and not '字段' in line and not '输出' in line and not '您的' in line and not '共' in line and not '|' in line and not '<img' in line:
            if current:
                coupons.append(current)
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
    if current:
        coupons.append(current)
    return coupons

# ── conf helpers ──────────────────────────────────────────

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

def bar():
    print(f"  {'─'*46}")

# ── display functions ─────────────────────────────────────

def show_overview(client, conf):
    bucket, emoji = time_bucket()
    print(f"\n  {emoji}  feedme · 麦当劳智能订餐 | {bucket}")
    bar()

    # Address — auto-fetch from MCP if not in conf
    addrs = conf.get('addresses', [])
    if not addrs:
        try:
            text = client.text("delivery-query-addresses", {"beType": 2})
            addrs = parse_addresses(text, conf)
        except:
            pass

    if addrs:
        a = addrs[0]
        phone = a.get('phone', '')
        print(f"  📍 {a.get('contactName','?')} {phone} | {a.get('fullAddress', a.get('address','?')+'')[:40]}")
    else:
        print(f"  📍 未设置地址 | 输入 `地址` 从 MCP 拉取 | `加地址` 添加")

    # Coupons
    try:
        text = client.text("query-my-coupons")
        coupons = parse_coupons(text)
        print(f"  🎫 {len(coupons)} 张优惠券 | `券` 查看 | `领券` 一键领取")
    except:
        pass

    # Points
    try:
        text = client.text("query-my-account")
        pts = parse_account(text)
        av = pts.get('availablePoint', pts.get('available', '?'))
        print(f"  ⭐ {av} 可用积分")
    except:
        pass

    # Recent order
    orders = [h for h in conf.get('history', []) if h.get('action') == 'order']
    if orders:
        last = orders[0]
        items = ', '.join(i.get('name','?') for i in last.get('items',[]))
        print(f"  🔄 最近: {items} ¥{last.get('total','?')} | `复购` 再来一单")

    bar()
    print("  [r推荐] [m菜单] [c券] [领券] [复购] [地址] [积分] [活动] [下单] [q退出]")
    bar()

def show_menu(client, conf):
    addrs = conf.get('addresses', [])
    if not addrs:
        print("  ❌ 需先设置地址。输入 `地址` 拉取。")
        return []
    a = addrs[0]
    sc = a.get('storeCode', '')
    bc = a.get('beCode', '')
    if not sc:
        print("  ❌ 地址缺少门店信息。输入 `地址` 重新拉取。")
        return []

    print("  ⏳ 查询菜单...")
    try:
        text = client.text("query-meals", {"storeCode": sc, "beCode": bc, "orderType": 2})
    except Exception as e:
        print(f"  ❌ {e}")
        return []

    items = parse_menu(text)
    if not items:
        # Raw display as fallback
        print(text[:2000])
        return []

    # Group by category
    cats = {}
    for m in items:
        c = m.get('category', '其他')
        cats.setdefault(c, []).append(m)

    sep("📋 菜单")
    idx = 0
    for cat, lst in sorted(cats.items()):
        print(f"\n  ▸ {cat}")
        for m in lst:
            idx += 1
            price_str = str(m['price']) if m['price'] else '?'
            print(f"  {idx:>3}. {m['name']:<20s} ¥{price_str:>6s}")
    print(f"\n  共 {idx} 种 | `选 编号` 加购物车 | `推荐` 智能推荐")
    return items

def show_recommend(client, conf):
    addrs = conf.get('addresses', [])
    if not addrs:
        print("  ❌ 需先设置地址。输入 `地址` 拉取。")
        return
    a = addrs[0]
    sc = a.get('storeCode', '')
    bc = a.get('beCode', '')
    if not sc:
        print("  ❌ 地址缺少门店。输入 `地址` 重新拉取。")
        return

    print("  ⏳ 查询菜单和优惠券...")
    try:
        menu_text = client.text("query-meals", {"storeCode": sc, "beCode": bc, "orderType": 2})
        menu_items = parse_menu(menu_text)
    except Exception as e:
        print(f"  ❌ 菜单查询失败: {e}")
        return
    if not menu_items:
        print("  ❌ 未能解析菜单。输入 `m` 查看原始数据。")
        return

    try:
        coupon_text = client.text("query-my-coupons")
        coupons = parse_coupons(coupon_text)
    except:
        coupons = []

    prefs = conf.get('preferences', {})
    history = conf.get('history', [])

    from recommend import score_item
    bucket, _ = time_bucket()
    scored = [(m, *score_item(m, prefs, coupons, history, bucket)) for m in menu_items]
    scored.sort(key=lambda x: x[1], reverse=True)

    sep(f"⭐ 智能推荐 ({bucket})")
    for i, (item, score, reasons) in enumerate(scored[:8]):
        stars = '⭐' * min(int(score/2) + 1, 5)
        price_str = str(item['price']) if item['price'] else '?'
        print(f"  {i+1}. {stars} {item['name']:<20s} ¥{price_str:>6s}")
        if reasons:
            print(f"     {', '.join(reasons)}")
    bar()
    print(f"  `选 编号` 加购物车 | `下单` 结算")
    return [s[0] for s in scored]  # Return scored items for selection

def show_coupons(client):
    sep("🎫 我的优惠券")
    try:
        text = client.text("query-my-coupons")
        coupons = parse_coupons(text)
        if not coupons:
            print(text[:1500])
        else:
            for i, c in enumerate(coupons):
                print(f"  {i+1}. {c.get('name','?')}")
                if c.get('discount'): print(f"     优惠: {c['discount']}")
                if c.get('valid'):   print(f"     有效期: {c['valid']}")
                if c.get('tags'):    print(f"     标签: {c['tags']}")
                print()
            print(f"  共 {len(coupons)} 张 | `领券` 一键领取")
    except Exception as e:
        print(f"  ❌ 查询失败: {e}")

def show_addresses(client, conf):
    sep("📍 配送地址")
    try:
        text = client.text("delivery-query-addresses", {"beType": 2})
        addrs = parse_addresses(text, conf)
        if not addrs:
            # Try raw display
            print(text[:2000])
            return
        for i, a in enumerate(addrs):
            mark = '👉' if i == 0 else '  '
            print(f"  {mark} {a['contactName']} | {a['phone']}")
            print(f"     {a['fullAddress']}")
            print(f"     门店: {a['storeName']} ({a['storeCode']})")
            print()
        print(f"  共 {len(addrs)} 个地址 | `加地址` 添加 | 第一个为默认地址")
    except Exception as e:
        print(f"  ❌ 查询失败: {e}")

def show_activity(client):
    sep("📅 营销活动")
    try:
        text = client.text("campaign-calendar")
        print(text[:2000])
    except Exception as e:
        print(f"  ❌ 查询失败: {e}")

def show_points(client):
    sep("⭐ 我的积分")
    try:
        text = client.text("query-my-account")
        pts = parse_account(text)
        if pts:
            for k, v in pts.items():
                print(f"  {k}: {v}")
        else:
            print(text[:1000])
    except Exception as e:
        print(f"  ❌ 查询失败: {e}")

# ── order flow ───────────────────────────────────────────

def start_order(client, conf, pre_selected=None):
    """Interactive order placement."""
    addrs = conf.get('addresses', [])
    if not addrs:
        print("  ❌ 请先设置地址。输入 `地址` 拉取。")
        return

    a = addrs[0]
    sc = a.get('storeCode', '')
    bc = a.get('beCode', '')
    if not sc:
        print("  ❌ 地址缺少门店。输入 `地址` 重新拉取。")
        return

    print("  ⏳ 加载菜单...")
    try:
        text = client.text("query-meals", {"storeCode": sc, "beCode": bc, "orderType": 2})
        menu_items = parse_menu(text)
    except Exception as e:
        print(f"  ❌ {e}")
        return

    if not menu_items:
        print("  ❌ 菜单为空")
        return

    print(f"  ✅ {len(menu_items)} 种餐品已加载。")
    print(f"  输入餐品编号或名称添加 | `done` 结算 | `cancel` 取消")

    cart = []
    if pre_selected:
        for item in pre_selected:
            if isinstance(item, dict) and 'name' in item:
                cart.append({'name': item['name'], 'code': item.get('code', ''), 'price': item.get('price', 0), 'quantity': 1})
                total = sum(c['price'] * c['quantity'] for c in cart)
                print(f"  ✅ {item['name']} ¥{item.get('price',0)} | {len(cart)}件 ¥{total}")

    while True:
        try:
            cmd = input("  选餐> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not cmd:
            continue
        if cmd.lower() in ('done', '下单', '结算', 'ok', ''):
            break
        if cmd.lower() in ('cancel', 'q', '取消'):
            print("  已取消。")
            return

        # Match by number
        matched = None
        try:
            n = int(cmd) - 1
            if 0 <= n < len(menu_items):
                matched = menu_items[n]
        except ValueError:
            # Match by name keyword
            for m in menu_items:
                if cmd in m.get('name', ''):
                    matched = m
                    break

        if matched:
            # Check if already in cart
            existing = next((c for c in cart if c['name'] == matched['name']), None)
            if existing:
                existing['quantity'] += 1
            else:
                cart.append({'name': matched['name'], 'code': matched.get('code', matched['name']),
                             'price': matched.get('price', 0), 'quantity': 1})
            total = sum(c['price'] * c['quantity'] for c in cart)
            print(f"  ✅ {'+' if not existing else '🔁'} {matched['name']} ¥{matched.get('price',0):.1f} | 购物车 {len(cart)}件 ¥{total:.1f}")
        else:
            print(f"  ❓ 未找到「{cmd}」。重试或 `done` 结算 `cancel` 取消")

    if not cart:
        print("  购物车为空。")
        return

    # Show order summary
    total = sum(c['price'] * c['quantity'] for c in cart)
    print()
    sep("📦 订单确认")
    for c in cart:
        qty = f"x{c['quantity']}" if c['quantity'] > 1 else ""
        print(f"  {qty:>3s} {c['name']:<20s} ¥{c['price']:.1f}")
    bar()
    print(f"  💰 合计: ¥{total:.1f}")
    print(f"  📍 {a['contactName']} {a['phone']} | {a.get('fullAddress', a.get('address',''))[:50]}")
    bar()

    confirm = input("  确认下单? [Y/n] ").strip().lower()
    if confirm and confirm not in ('y', 'yes', '是', '', 'ok'):
        print("  已取消。")
        return

    # Calculate price first
    print("  ⏳ 计算价格...")
    order_items = [{"productCode": c['code'], "quantity": c['quantity']} for c in cart]
    try:
        price_r = client.calc_price(sc, bc, 2, order_items)
        price_text = price_r.get('text', '')
        print(price_text[:500])
    except Exception as e:
        print(f"  ⚠️ 价格计算异常: {e}")

    # Place order
    print("  ⏳ 下单中...")
    try:
        r = client.create_order(sc, bc, a.get('addressId', ''), 2, order_items)
        text = r.get('text', '')
        print(text[:1500])

        # Extract payment URL
        pay_url = re.search(r'(https?://[^\s"\'>]+(?:pay|order|payment)[^\s"\'>]*)', text)
        if not pay_url:
            pay_url = re.search(r'payH5Url[：:]\s*(https?://[^\s"\'>]+)', text)
        if not pay_url:
            pay_url = re.search(r'(https?://[^\s"\']+)', text)

        if pay_url:
            url = pay_url.group(1) if pay_url.lastindex else pay_url.group(0) if hasattr(pay_url, 'group') else pay_url
            print(f"\n  🔗 支付链接: {url}")
            try:
                import qrcode
                qr = qrcode.QRCode(version=2, error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=1, border=2)
                qr.add_data(url)
                qr.make(fit=True)
                try:
                    qr.print_ascii(tty=True)
                except OSError:
                    qr.print_ascii(tty=False)
            except:
                pass

        # Save history
        conf.setdefault('history', []).insert(0, {
            'action': 'order', 'items': cart,
            'store': a.get('storeName', ''), 'total': total,
            'time': datetime.now().isoformat()
        })
        save_conf(conf)
        print("  ✅ 订单已保存。")
    except Exception as e:
        print(f"  ❌ 下单失败: {e}")

# ── main loop ─────────────────────────────────────────────

def main():
    if not os.path.exists(CONF_FILE):
        print("❌ 未配置。运行: bash ~/.claude/skills/feedme/scripts/setup.sh")
        print("   获取 Token: https://open.mcd.cn/mcp")
        sys.exit(1)

    conf = load_conf()
    token = conf.get('mcd', {}).get('token', '')
    if not token:
        print("❌ Token 未设置。运行: bash ~/.claude/skills/feedme/scripts/setup.sh --update")
        sys.exit(1)

    print("  ⏳ 连接麦当劳 MCP...")
    try:
        client = MCDClient(token)
        client.call("now-time-info")
    except Exception as e:
        print(f"  ❌ 连接失败: {e}")
        print("  运行: bash ~/.claude/skills/feedme/scripts/setup.sh --update")
        sys.exit(1)

    show_overview(client, conf)

    last_menu = []
    last_recommend = []

    while True:
        try:
            cmd = input("\nfeedme> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  👋 再见！")
            break

        if not cmd:
            continue

        cl = cmd.lower()

        if cl in ('q', 'quit', 'exit', '退出'):
            print("  👋 再见！")
            break

        elif cl in ('r', 'recommend', '推荐', '推荐一下'):
            last_recommend = show_recommend(client, conf) or []

        elif cl in ('m', 'menu', '菜单'):
            last_menu = show_menu(client, conf)

        elif cl in ('c', 'coupon', '券', '优惠券'):
            show_coupons(client)

        elif cl in ('领券', 'bind'):
            print("  ⏳ 一键领券...")
            try:
                r = client.bind_coupons()
                print(r.get('text', str(r))[:2000])
            except Exception as e:
                print(f"  ❌ {e}")

        elif cl in ('re', 'reorder', '复购', '历史'):
            orders = [h for h in conf.get('history', []) if h.get('action') == 'order']
            if not orders:
                print("  暂无历史订单。")
                continue
            sep("🔄 历史订单")
            for i, o in enumerate(orders[:10]):
                items = ', '.join(it.get('name','?') for it in o.get('items',[]))
                print(f"  {i+1}. {items}  ¥{o.get('total',0)}  {o.get('time','')[:16]}")
            bar()
            print("  `复购 N` 快速下单")

        elif cl.startswith('复购 ') or cl.startswith('re '):
            try:
                n = int(cl.split()[-1]) - 1
                orders = [h for h in conf.get('history', []) if h.get('action') == 'order']
                if 0 <= n < len(orders):
                    o = orders[n]
                    print(f"  🔄 复购: {', '.join(i.get('name','?') for i in o['items'])}")
                    start_order(client, conf, pre_selected=o['items'])
                else:
                    print(f"  ❌ 无效编号")
            except ValueError:
                print("  ❌ 用法: `复购 1`")

        elif cl in ('a', 'addr', '地址'):
            show_addresses(client, conf)

        elif cl.startswith('加地址') or cl in ('+addr',):
            print("  添加新地址:")
            city = input("  城市 (如 北京): ").strip()
            name = input("  联系人: ").strip()
            phone = input("  电话: ").strip()
            addr = input("  地址 (如 朝阳区): ").strip()
            detail = input("  门牌号 (如 望京SOHO T1): ").strip()
            if all([city, name, phone, addr, detail]):
                try:
                    r = client.add_address(city, name, phone, addr, detail)
                    print(r.get('text', str(r))[:2000])
                    # Re-fetch addresses to get the new one with store info
                    print("  ⏳ 刷新地址列表...")
                    text = client.text("delivery-query-addresses", {"beType": 2})
                    parse_addresses(text, conf)
                    print("  ✅ 地址已添加。")
                except Exception as e:
                    print(f"  ❌ {e}")
            else:
                print("  ❌ 所有字段必填")

        elif cl in ('活动', '日历', 'cal'):
            show_activity(client)

        elif cl in ('积分', '点', 'points', 'pt'):
            show_points(client)

        elif cl in ('下单', 'order', 'buy'):
            start_order(client, conf)

        elif cl.startswith('选 ') or cl.startswith('s '):
            # Quick add from last menu/recommend
            sel = cl.split(' ', 1)[1]
            all_items = last_recommend or last_menu
            if all_items:
                matched = None
                try:
                    n = int(sel) - 1
                    if 0 <= n < len(all_items):
                        matched = all_items[n]
                except ValueError:
                    for m in all_items:
                        if sel in m.get('name', ''):
                            matched = m
                            break
                if matched:
                    print(f"  ⚠️ 请使用 `下单` 进入点餐流程，目前不支持快捷加购。")
                    print(f"  💡 已记录: {matched['name']}")
                else:
                    print(f"  ❓ 未找到「{sel}」。先 `推荐` 或 `菜单` 查看。")
            else:
                print("  ⚠️ 先运行 `推荐` 或 `菜单`。")

        elif cl in ('help', '?', '帮助', 'h'):
            print("""
  快捷指令:
    r 推荐    智能推荐          券    查看优惠券
    m 菜单    浏览菜单          领券  一键领取
    复购      历史订单          地址  查看/添加
    下单      交互点餐          积分  积分查询
    活动      活动日历          q    退出

  交互中: 输入编号或名称选择 | done 结算 | cancel 取消
""")

        else:
            print(f"  ❓ 未知「{cmd}」。`help` 查看帮助。")


if __name__ == '__main__':
    main()
