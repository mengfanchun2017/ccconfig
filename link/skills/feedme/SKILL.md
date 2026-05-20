---
name: feedme
user-invocable: true
description: 智能订餐助手 — 麦当劳订餐、优惠券管理、偏好推荐、地址管理
allowed-tools: Bash
---

# feedme — 智能订餐助手

当用户说 "feedme" / "订餐" / "叫外卖" / "点麦当劳" / "吃麦当劳" 时触发。

## 核心规则

**Claude 只做路由。** 每次执行一个命令，命令输出就是给用户的全部内容——把 stdout 完整贴出来（代码块），不加任何额外文字。不画表格、不总结、不分析、不评论。脚本输出的最后一行就是引导语。用户看到输出后自己决定下一步说什么。

## 启动

```
bash ~/.claude/skills/feedme/scripts/feedme.sh
```

## 命令路由

用户说 → 执行命令（在 skill 目录）：

| 用户说 | 命令 |
|--------|------|
| `feedme` | `bash scripts/feedme.sh` |
| `推荐` | `python3 scripts/feedme.py recommend` |
| `菜单` | `python3 scripts/feedme.py menu` |
| `券` / `优惠券` | `python3 scripts/feedme.py coupons` |
| `领券` | `python3 scripts/feedme.py bind-coupons` |
| `地址` | `python3 scripts/feedme.py addresses` |
| `加地址 A B C D E` | `python3 scripts/feedme.py add-address A B C D E` |
| `积分` | `python3 scripts/feedme.py points` |
| `活动` / `日历` | `python3 scripts/feedme.py activity` |
| `历史` / `复购` | `python3 scripts/feedme.py history` |
| `复购 N` | `python3 scripts/feedme.py reorder N` |
| `选 N` / `加 N` | `python3 scripts/feedme.py cart-add N` |
| `选 A B C` | `python3 scripts/feedme.py cart-add A B C` |
| `购物车` | `python3 scripts/feedme.py cart-show` |
| `删 N` / `移除 N` | `python3 scripts/feedme.py cart-remove N` |
| `清空` | `python3 scripts/feedme.py cart-clear` |
| `结算` / `下单` | `python3 scripts/feedme.py checkout` |
| `确认` / `确认下单` | `python3 scripts/feedme.py confirm` |
| `取消` | `python3 scripts/feedme.py cancel` |

执行目录设为 skill 根目录（`cd ~/.claude/skills/feedme &&` 或使用绝对路径）。

## 用户输入模糊时

如果用户说「要巨无霸」「来个大薯条」等，映射到 `cart-add 巨无霸` / `cart-add 大薯条`（按商品名搜索）。

## 首次使用

如果脚本输出 "Token 未配置"：

```
bash ~/.claude/skills/feedme/scripts/setup.sh
```

获取 Token: https://open.mcd.cn/mcp

## API 限制

MCP API 与麦当劳 App 功能不完全对等，以下功能 **不可用**：

| 限制 | 详情 |
|------|------|
| 备注 | `create-order` items 只有 productCode/quantity/couponCode/couponId，无 remark 字段 |
| 特制/定制 | 手机 App 的「特制」(去酱、加菜、换配料) MCP 未暴露。`query-meal-detail` 对独立汉堡返回 `rounds: []` |
| 套餐选配 | 套餐有 rounds (选小食/饮料)，但 `create-order` 不接受 rounds 参数，选配结果无法传递 |
| 在线支付 | `payH5Url` 扫码后 App 报「获取信息失败」，MCP 创建的订单无法通过扫码支付 |

如果用户要求定制（备注/去酱/加菜），告知需在麦当劳 App 手动操作，不要试图在 feedme 中实现。
下单成功后提醒用户去麦当劳 App 完成支付，不展示 QR 码或支付链接。
