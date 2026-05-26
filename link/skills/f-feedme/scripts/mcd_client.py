#!/usr/bin/env python3
"""McDonald's MCP HTTP client — talks directly to https://mcp.mcd.cn via JSON-RPC."""
import json, urllib.request, urllib.error, os, sys

MCP_URL = "https://mcp.mcd.cn"
CONF_FILE = os.path.expanduser("~/.claude/projects/-home-francis-git/conf/feedme/feedme.json")

class MCDClient:
    def __init__(self, token=None):
        if token is None:
            with open(CONF_FILE) as f:
                token = json.load(f)['mcd']['token']
        self.token = token
        self._sid = None

    def _headers(self):
        h = {"Content-Type": "application/json", "Authorization": f"Bearer {self.token}"}
        if self._sid:
            h["Mcp-Session-Id"] = self._sid
        return h

    def call(self, tool_name, args=None, timeout=15):
        """Call an MCP tool. Returns parsed content from response."""
        body = json.dumps({
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {"name": tool_name, "arguments": args or {}},
            "id": 1
        }).encode()

        req = urllib.request.Request(MCP_URL, data=body, headers=self._headers(), method="POST")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                # Capture session ID
                sid = resp.headers.get("Mcp-Session-Id")
                if sid:
                    self._sid = sid
                result = json.loads(resp.read())
        except urllib.error.HTTPError as e:
            return {"error": f"HTTP {e.code}: {e.reason}"}
        except Exception as e:
            return {"error": str(e)}

        if "error" in result:
            return {"error": result["error"].get("message", str(result["error"]))}

        content = result.get("result", {}).get("content", [])
        if content and "text" in content[0]:
            return {"text": content[0]["text"]}
        return {"raw": result}

    def text(self, tool_name, args=None):
        """Call tool and return just the text content."""
        r = self.call(tool_name, args)
        return r.get("text", "")

    # ── convenience methods ──────────────────────────────

    def get_addresses(self, be_type=2):
        return self.call("delivery-query-addresses", {"beType": be_type})

    def add_address(self, city, contact_name, phone, address, address_detail, be_type=2):
        return self.call("delivery-create-address", {
            "city": city, "contactName": contact_name, "phone": phone,
            "address": address, "addressDetail": address_detail, "beType": be_type
        })

    def search_stores(self, city, keyword):
        return self.call("query-nearby-stores", {"searchType": 2, "city": city, "keyword": keyword})

    def get_menu(self, store_code, be_code, order_type=2):
        return self.call("query-meals", {"storeCode": store_code, "beCode": be_code, "orderType": order_type})

    def get_meal_detail(self, code):
        return self.call("query-meal-detail", {"code": code})

    def calc_price(self, store_code, be_code, order_type, items):
        return self.call("calculate-price", {
            "storeCode": store_code, "beCode": be_code,
            "orderType": order_type, "items": items
        })

    def create_order(self, store_code, be_code, address_id, order_type, items):
        return self.call("create-order", {
            "storeCode": store_code, "beCode": be_code,
            "addressId": address_id, "orderType": order_type, "items": items
        })

    def get_order(self, order_id):
        return self.call("query-order", {"orderId": order_id})

    def get_coupons(self):
        return self.call("query-my-coupons")

    def get_available_coupons(self):
        return self.call("available-coupons")

    def bind_coupons(self):
        return self.call("auto-bind-coupons")

    def get_store_coupons(self, store_code, be_code, order_type):
        return self.call("query-store-coupons", {"storeCode": store_code, "beCode": be_code, "orderType": order_type})

    def get_account(self):
        return self.call("query-my-account")

    def get_calendar(self, date=None):
        return self.call("campaign-calendar", {"specifiedDate": date} if date else {})

    def get_nutrition(self):
        return self.call("list-nutrition-foods")

    def get_time(self):
        return self.call("now-time-info")

    def get_points_products(self):
        return self.call("mall-points-products")

    def get_points_product_detail(self, spu_id):
        return self.call("mall-product-detail", {"spuId": spu_id})

    def redeem_points(self, sku_id, count=1):
        return self.call("mall-create-order", {"skuId": sku_id, "count": count})
