---
name: feedme
user-invocable: true
description: 智能订餐助手 — 麦当劳MCP订餐、优惠券管理、偏好推荐、地址管理
allowed-tools: Bash, Read, Write, Edit, mcp__mcd_mcp__list-nutrition-foods, mcp__mcd_mcp__delivery-query-addresses, mcp__mcd_mcp__delivery-create-address, mcp__mcd_mcp__query-nearby-stores, mcp__mcd_mcp__query-store-coupons, mcp__mcd_mcp__query-meals, mcp__mcd_mcp__query-meal-detail, mcp__mcd_mcp__calculate-price, mcp__mcd_mcp__create-order, mcp__mcd_mcp__query-order, mcp__mcd_mcp__available-coupons, mcp__mcd_mcp__auto-bind-coupons, mcp__mcd_mcp__query-my-coupons, mcp__mcd_mcp__query-my-account, mcp__mcd_mcp__mall-points-products, mcp__mcd_mcp__mall-product-detail, mcp__mcd_mcp__mall-create-order, mcp__mcd_mcp__campaign-calendar, mcp__mcd_mcp__now-time-info
---

# feedme — 智能订餐助手

当用户说 "feedme" / "订餐" / "叫外卖" / "点麦当劳" / "吃麦当劳" / "饿了"（搭配订餐语境）时触发。

## 交互模式

**Claude 对话驱动**（不用 whiptail TUI）。Claude 负责：
- 理解用户意图和自然语言
- 调用 MCP 工具获取数据
- 调用 `display.py` 格式化输出
- 维持多轮对话状态直到下单完成

## ⚡ 启动入口

用户说 "feedme" 后，立即执行两步：

```
1. bash scripts/setup.sh --check  → 确认MCP已配置
2. python3 scripts/display.py overview → 显示上下文概览
```

overview 输出示例含：时段/默认地址/偏好/最近订单/快捷指令提示。Claude 基于此引导用户选择下一步。

## 📋 对话交互流程

### 节奏规则
- **每次只显示当前需要的信息**，不要堆所有数据
- **给用户简洁的选项提示**（2-5个），包含默认快捷选择
- **记住上下文**（已选餐品、地址、门店），跨轮传递

### 快捷指令映射

| 用户说 | Claude 做什么 |
|--------|--------------|
| `推荐` / `有什么好吃的` | 调 MCP query-meals + query-my-coupons → 数据传 recommend.py → display.py recommend |
| `菜单` / `看看` / `汉堡` | 调 MCP query-meals → display.py menu |
| `优惠券` / `我的券` / `领券` | 调 MCP query-my-coupons → display.py coupons。说「领券」→ auto-bind-coupons |
| `复购` / `再来一单` / `复购 1` | 读 prefs.py get history → display.py history → 用户选编号 |
| `加地址` / `添加地址` | 交互式收集：城市/姓名/电话/地址/门牌号 → MCP delivery-create-address |
| `地址` / `改地址` | 调 MCP delivery-query-addresses → display.py addresses |
| `积分` / `我的积分` | 调 MCP query-my-account → display.py points |
| `设置` / `偏好` | 读 prefs.py → 列出当前设置 → 引导修改 |
| `选 1` / `要 巨无霸` | 根据当前上下文识别餐品 → 加入点餐列表 |
| `确认` / `下单` / `确认下单` | 调 MCP calculate-price → display order → 最终确认 → create-order → qrpay.py |
| `取消` / `不要了` | 清空当前选餐 |
| `活动` / `有什么活动` | 调 MCP campaign-calendar |

### 点餐状态追踪

Claude 在对话中跟踪：
- `selected_items` — 当前已选餐品列表
- `current_store` — 当前门店
- `current_address` — 配送地址
- `bucket` — 用餐时段

选择餐品时，每选一个立即显示「已添加 X，共 N 件，小计 ¥Y」，而非等全部选完再算。

### 推荐展示

```
python3 scripts/recommend.py --menu '<menu_json>' --coupons '<coupons_json>' --limit 5
python3 scripts/display.py recommend '<recommend_json>'
```

推荐含打分理由（券匹配/历史/口味/时段/预算），用户一眼知道为什么推荐。

### 下单确认

下单前必须展示（用 `display.py` order 格式的逻辑，由 Claude 组装信息展示）：
- 餐品列表 + 小计
- 配送费 + 优惠
- 合计金额
- 配送地址 + 联系人
- 预计送达时间

确认后调用 MCP create-order → 拿到 payH5Url → `python3 scripts/qrpay.py "<url>"`

## 📁 配置管理

单文件 `~/.claude/projects/-home-francis-git/conf/feedme/feedme.json`

```bash
python3 scripts/prefs.py get <path>       # 读取
python3 scripts/prefs.py set <path> '<v>' # 写入
python3 scripts/prefs.py add-history '<entry>'  # 追加历史
python3 scripts/prefs.py show             # 全量查看
```

## 🔧 MCP 安装

```bash
bash scripts/setup.sh          # 交互式安装
bash scripts/setup.sh --check  # 检查（退出码0=已配置）
bash scripts/setup.sh --update # 更新Token
```

## 📖 MCP 工具清单（共14个）

完整参数 → `references/mcd-mcp.md`
