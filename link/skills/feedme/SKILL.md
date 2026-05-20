---
name: feedme
user-invocable: true
description: 智能订餐助手 — 麦当劳订餐、优惠券管理、偏好推荐、地址管理
allowed-tools: Bash
---

# feedme — 智能订餐助手

当用户说 "feedme" / "订餐" / "叫外卖" / "点麦当劳" / "吃麦当劳" 时触发。

## 核心规则

**Claude 只做路由，不做加工。** 每次用户输入对应一个 bash 命令，把输出原样展示给用户（代码块即可），不画表格、不加评论、不总结。脚本已处理所有格式化和引导语。

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
