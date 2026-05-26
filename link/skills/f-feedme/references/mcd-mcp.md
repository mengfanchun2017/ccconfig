# 麦当劳 MCP 工具速查

> 来源: https://github.com/M-China/mcd-mcp-server

## 点餐流程

```
query-nearby-stores → storeCode + beCode
delivery-query-addresses → addressId
query-meals → 菜单
calculate-price → 价格确认
create-order → payH5Url (支付链接)
query-order → 订单状态
```

## 工具列表

### 点餐
| 工具 | 用途 | 关键参数 |
|------|------|---------|
| `query-nearby-stores` | 搜索附近门店 | searchType(1=收藏,2=搜索), city, keyword |
| `query-meals` | 门店菜单 | storeCode, beCode, orderType(1=堂食,2=外卖) |
| `query-meal-detail` | 套餐组成 | code |
| `calculate-price` | 计算总价 | storeCode, beCode, orderType, items[] |
| `create-order` | 下单 | storeCode, beCode, addressId/takeWayCode, orderType, items[] |
| `query-order` | 订单查询 | orderId |

### 地址
| 工具 | 用途 | 关键参数 |
|------|------|---------|
| `delivery-query-addresses` | 配送地址列表 | beType(2=麦乐送,6=团餐) |
| `delivery-create-address` | 新增地址 | city, contactName, phone, address, addressDetail, beType |

### 优惠券
| 工具 | 用途 | 关键参数 |
|------|------|---------|
| `available-coupons` | 可领取券列表 | — |
| `auto-bind-coupons` | 一键领券 | — |
| `query-my-coupons` | 已持券列表 | — |
| `query-store-coupons` | 门店可用券 | storeCode, beCode, orderType |

### 积分
| 工具 | 用途 | 关键参数 |
|------|------|---------|
| `query-my-account` | 积分余额 | — |
| `mall-points-products` | 积分兑换列表 | — |
| `mall-product-detail` | 兑换品详情 | spuId |
| `mall-create-order` | 积分兑换 | skuId, count |

### 其他
| 工具 | 用途 | 关键参数 |
|------|------|---------|
| `list-nutrition-foods` | 营养信息 | — |
| `campaign-calendar` | 活动日历 | specifiedDate (可选) |
| `now-time-info` | 当前时间 | — |

## items[] 结构

```json
{
  "productCode": "M001",
  "quantity": 1,
  "couponId": "c123",
  "couponCode": "COUPON_ABC"
}
```

## orderType

| 值 | 类型 |
|----|------|
| 1 | 堂食/到店取餐 |
| 2 | 麦乐送（外卖） |

## 限速

600次/分钟/Token，超限返回 HTTP 429
