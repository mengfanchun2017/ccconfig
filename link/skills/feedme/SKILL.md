---
name: feedme
user-invocable: true
description: 智能订餐助手 — 麦当劳订餐、优惠券管理、偏好推荐、地址管理
allowed-tools: Bash
---

# feedme — 智能订餐助手

当用户说 "feedme" / "订餐" / "叫外卖" / "点麦当劳" / "吃麦当劳" 时触发。

## 启动

用户首次说 feedme 时，运行：

```bash
bash ~/.claude/skills/feedme/scripts/feedme.sh
```

这会显示 overview（地址、优惠券、积分、历史订单、购物车）。

之后所有交互由 Claude 根据用户输入路由到对应命令。

## 命令路由表

每次用户输入一个指令后，执行对应命令即可。脚本每次只做一个操作，立即返回。

| 用户说 | 执行 |
|--------|------|
| `feedme` | `python3 scripts/feedme.py overview` |
| `推荐` / `推荐一下` | `python3 scripts/feedme.py recommend` |
| `菜单` | `python3 scripts/feedme.py menu` |
| `券` / `优惠券` | `python3 scripts/feedme.py coupons` |
| `领券` | `python3 scripts/feedme.py bind-coupons` |
| `地址` | `python3 scripts/feedme.py addresses` |
| `加地址 <城市> <姓名> <电话> <地址> <门牌>` | `python3 scripts/feedme.py add-address <...>` |
| `积分` | `python3 scripts/feedme.py points` |
| `活动` / `日历` | `python3 scripts/feedme.py activity` |
| `历史` / `复购` | `python3 scripts/feedme.py history` |
| `复购 N` / `再来第N单` | `python3 scripts/feedme.py reorder N` |
| `选 N` / `要 N` / `加 N` | `python3 scripts/feedme.py cart-add N` |
| `选 1,3,5` 多个 | `python3 scripts/feedme.py cart-add 1 3 5` |
| `选 巨无霸` 按名称 | `python3 scripts/feedme.py cart-add 巨无霸` |
| `购物车` | `python3 scripts/feedme.py cart-show` |
| `删 N` / `移除 N` | `python3 scripts/feedme.py cart-remove N` |
| `清空` | `python3 scripts/feedme.py cart-clear` |
| `结算` / `下单` | `python3 scripts/feedme.py checkout` |
| `确认` / `确认下单` | `python3 scripts/feedme.py confirm` |
| `取消` | `python3 scripts/feedme.py cancel` |
| `q` / `退出` / `不吃了` | 结束，不需执行命令 |

## 执行路径

所有命令在 skill 目录执行：

```bash
cd ~/.claude/skills/feedme && python3 scripts/feedme.py <command> [args...]
```

## 首次使用

如果脚本输出 "Token 未配置"，告诉用户：

```
bash ~/.claude/skills/feedme/scripts/setup.sh
```

获取 Token: https://open.mcd.cn/mcp

## 脚本组件

| 文件 | 职责 |
|------|------|
| `scripts/feedme.py` | CLI 调度器，每个命令一次调用 |
| `scripts/feedme.sh` | 入口，MCP 检查 + overview |
| `scripts/mcd_client.py` | MCD MCP HTTP 客户端 |
| `scripts/recommend.py` | 推荐引擎（规则打分） |
| `scripts/display.py` | 独立格式化工具（可选） |
| `scripts/qrpay.py` | 支付二维码显示 |
| `scripts/setup.sh` | MCP Token 安装向导 |
| `references/mcd-mcp.md` | MCP 工具速查 |
