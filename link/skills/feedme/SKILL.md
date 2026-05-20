---
name: feedme
user-invocable: true
description: 智能订餐助手 — 麦当劳MCP订餐、优惠券管理、偏好推荐、地址管理
allowed-tools: Bash, Read, Write, Edit, mcp__mcd_mcp__list-nutrition-foods, mcp__mcd_mcp__delivery-query-addresses, mcp__mcd_mcp__delivery-create-address, mcp__mcd_mcp__query-nearby-stores, mcp__mcd_mcp__query-store-coupons, mcp__mcd_mcp__query-meals, mcp__mcd_mcp__query-meal-detail, mcp__mcd_mcp__calculate-price, mcp__mcd_mcp__create-order, mcp__mcd_mcp__query-order, mcp__mcd_mcp__available-coupons, mcp__mcd_mcp__auto-bind-coupons, mcp__mcd_mcp__query-my-coupons, mcp__mcd_mcp__query-my-account, mcp__mcd_mcp__mall-points-products, mcp__mcd_mcp__mall-product-detail, mcp__mcd_mcp__mall-create-order, mcp__mcd_mcp__campaign-calendar, mcp__mcd_mcp__now-time-info
---

# feedme — 智能订餐助手

当用户说 "feedme" / "订餐" / "叫外卖" / "点麦当劳" / "吃麦当劳" / "饿了"（在订餐语境）时触发。

## 核心流程

```
feedme 触发
  └─ ① 检查 MCP 是否配置（scripts/setup.sh --check）
       └─ 未配置 → 引导安装
  └─ ② 启动交互 TUI（scripts/feedme.sh）
       └─ 展示主菜单 → 选餐 → 确认 → 下单 → 显示支付二维码
```

## 交互方式

CLI 对话 + TUI 弹窗混合：

**CLI 对话层（Claude 负责）**：
- 理解用户意图（"想吃辣的" → 辣味餐品筛选）
- 调用 MCP 工具查菜单/优惠券/价格
- 将数据传给 Python 推荐引擎

**TUI 弹窗层（whiptail 负责）**：
- 主菜单选择（快速复购 / 浏览菜单 / 推荐 / 优惠券 / 设置）
- 确认对话框（地址、价格、下单确认）
- 设置表单（地址、偏好）

## 配置

所有数据存在单个文件 `conf/feedme/feedme.json`，通过 `scripts/prefs.py` 读写。

## 命令

```bash
# 主入口（在 skill 目录下运行）
bash scripts/feedme.sh [mcd]

# 安装/检查 MCP 配置
bash scripts/setup.sh              # 交互式安装
bash scripts/setup.sh --check      # 仅检查，返回状态码
bash scripts/setup.sh --update     # 更新 MCP 配置

# 偏好管理
python3 scripts/prefs.py get preferences.taste        # 读取偏好
python3 scripts/prefs.py set preferences.taste spicy  # 写入偏好
python3 scripts/prefs.py get addresses                # 查看地址列表
python3 scripts/prefs.py add-history '{"action":"order","items":["巨无霸"],"time":"2026-05-20T12:00"}'

# 推荐引擎
python3 scripts/recommend.py --menu <menu_json> --coupons <coupons_json> --limit 5

# 生成支付二维码
python3 scripts/qrpay.py "<payH5Url>"
```

## MCP 工具速查（麦当劳）

| 工具 | 用途 | 关键参数 |
|------|------|---------|
| `query-meals` | 查门店菜单 | storeCode, beCode, orderType |
| `query-meal-detail` | 套餐详情 | code |
| `calculate-price` | 算总价 | storeCode, beCode, orderType, items[] |
| `create-order` | 下单 | storeCode, beCode, addressId, orderType, items[] |
| `query-order` | 查订单 | orderId |
| `delivery-query-addresses` | 查地址 | beType (2=麦乐送) |
| `delivery-create-address` | 加地址 | city, contactName, phone, address, addressDetail, beType |
| `query-nearby-stores` | 找门店 | searchType, city, keyword |
| `available-coupons` | 可领券 | — |
| `auto-bind-coupons` | 一键领券 | — |
| `query-my-coupons` | 已持券 | — |
| `query-store-coupons` | 门店券 | storeCode, beCode, orderType |
| `query-my-account` | 积分查询 | — |
| `campaign-calendar` | 活动日历 | specifiedDate (可选) |
| `now-time-info` | 当前时间 | — |
