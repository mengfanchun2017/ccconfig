---
name: feedme
user-invocable: true
description: 智能订餐助手 — 麦当劳MCP订餐、优惠券管理、偏好推荐、地址管理
allowed-tools: Bash
---

# feedme — 智能订餐助手

当用户说 "feedme" / "订餐" / "叫外卖" / "点麦当劳" / "吃麦当劳" 时触发。

## 启动

```
bash scripts/feedme.sh
```

Claude 只负责运行这个命令。之后所有交互在 Python 脚本内完成（直连 MCD MCP API），不经过 LLM。

## 交互模式

脚本启动后进入命令循环，显示实时 MCP 数据：

```
🍔  feedme · 麦当劳智能订餐 | lunch

📍 张三 13800138000 | 朝阳区望京SOHO
🎫 6 张优惠券 | ⭐ 1,234 积分
🔄 最近: 巨无霸套餐 ¥32

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [推荐] [菜单] [券] [领券] [复购] [地址] [积分] [活动] [q退出]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

feedme>
```

## 快捷指令

| 指令 | 功能 |
|------|------|
| `r` / `推荐` | 基于偏好+优惠券+时段智能推荐 |
| `m` / `菜单` | 浏览当前门店菜单 |
| `券` / `优惠券` | 查看已持优惠券 |
| `领券` | 一键领取所有可用券 |
| `复购` / `历史` | 查看历史订单 |
| `下单` | 交互式选餐→确认→下单→显示支付二维码 |
| `地址` | 从 MCP 拉取配送地址 |
| `加地址` | 交互式添加新地址 |
| `积分` | 查询积分余额 |
| `活动` | 查询当月营销活动 |
| `q` / `退出` | 退出 |

## 首次使用

如果没有配置 MCP Token，脚本会提示运行：

```bash
bash ~/.claude/skills/feedme/scripts/setup.sh
```

## 脚本组件

| 文件 | 职责 |
|------|------|
| `scripts/feedme.py` | 主交互脚本，命令循环 |
| `scripts/mcd_client.py` | MCD MCP HTTP 客户端 |
| `scripts/recommend.py` | 推荐引擎（规则打分） |
| `scripts/prefs.py` | 偏好/历史 本地存储 |
| `scripts/qrpay.py` | 支付二维码显示 |
| `scripts/display.py` | 独立格式化工具 |
| `scripts/setup.sh` | MCP 安装向导 |
| `references/mcd-mcp.md` | MCP 工具速查 |
