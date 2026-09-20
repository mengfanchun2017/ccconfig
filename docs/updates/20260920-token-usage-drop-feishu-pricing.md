# 2026-09-20 token 用量模块去掉飞书上报与费用折算 + 菜单 3/5 类精简

> 范围：`option-usage/`（token 用量）+ `lib/init-llm-bill.sh` + maintain 菜单第 3/5 类
> 起因：用户要求「5I 5J 都删除，功能也删除 —— 后续不用飞书、不做价格设定」，并顺带问清 3D/3E/3F 的区别
> 关联：[option-usage/README.md](../../option-usage/README.md)（已同步改写）
> 同日另一篇：[20260920-maintain-flat-menu.md](20260920-maintain-flat-menu.md)（菜单扁平化 + set -e bug）

## 决定

token 用量模块的职责收窄为**只统计 token 与时间**：

- **不做价格设定、不折算钱** —— 本地按 `llm.json` 的 pricing 表自算的 `cost_cny` 既不准（价格表常年不更新）也无人消费，费用以上游账单为准
- **不外发** —— 飞书多维表格上报整条链路移除

## 摘除清单

### 飞书上报（`option-usage/token-usage.sh`）

| 摘掉的东西 | 说明 |
|---|---|
| `parse_feishu_url()` | 解析 `/base/<token>?table=<tbl>` 形式 URL |
| `push_feishu()` | 组装 `create_records` → `lark-cli base +record-batch-create` 分批推送 |
| `--feishu <url>` | CLI flag |
| `token-usage.json` 的 `feishu_url` 键 | 脚本不再读它（timer 触发飞书推送的唯一途径就是这里，删掉即彻底停） |
| 两处 `push_feishu` 调用 | by-day 归档末尾、session CSV 末尾 |
| 头部注释里的 `--feishu` 用法行 | — |

`ccconfig-token-usage.service` / `.timer` **没动** —— 它俩从未注入飞书相关环境变量，ExecStart 只跑 `--by-day`。

### 费用折算

| 摘掉的东西 | 说明 |
|---|---|
| `load_pricing()` | 从 `llm.json` 读 `pricing` map |
| `calc_cost()` | **在删之前就已经是孤儿函数**（全文件无调用点），顺手清 |
| `LLM_CONF` 变量 | 只服务 `load_pricing` |
| `cost_cny` 列 | session CSV 16→15 列；by-day CSV 17→16 列 |
| `--stats` 的三处 Cost 列 | 按模型 / 按时间段 / 按月，连同黄色 ANSI 表头 |
| 启动时「已加载 pricing 配置 / 未配置 pricing」提示 | — |
| `lib/init-llm-bill.sh` 的 cost 展示 | 数据源没了，不删的话成本恒为 0.00 |

**`lib/init-llm-bill.sh` 保留**（不是纯 pricing 工具，它按 model/day 聚合归档 CSV）。只摘掉 cost 列与其 docstring 里「成本来自上游 API」的错误描述（实际读的是本地自算列）。`lib/init-llm.sh` 的 `bill|pricing|-p` 别名收窄为 `bill`，`pricing` 输入改为明确报错并指向 `bill`。

### 配置交互

`option-usage/init.sh` 的 `config` 子命令（交互式改 `feishu_url`/`schedule`/`include_today`）**整体删除**，`set-feishu` 一并删除。保留 `set-time` / `set-today` 两个 CLI 子命令，所以改归档时间的能力没丢，只是不再有交互包装。`init.sh` 也不再 source `interact.sh`（无菜单了）。

`conf/token-usage.json.example` 与 `ccprivate/conf/token-usage.json` 都去掉了 `feishu_url` 和 `enabled`（后者从没有代码消费，只有 `status()` 打印过）。

## 菜单调整

### 第 3 类：去掉冗余入口

用户问「3D 交互多选 和 3E/3F 什么区别」。查明：3D（`update.sh menu`）与 3E（`update.sh all`）是同一件事的交互/非交互两种入口，冗余。

更重要的是**五项动的是三个不同层面**，原标签把它们混在一起了：

| 键 | 动的是什么 | 是否碰 git |
|---|---|---|
| 3A ccconfig 自更新+重建链接 | 配置仓库的代码 | 是（pull ccconfig） |
| 3B Skill 同步 | skill 软链 | 否 |
| 3C ccprivate 升级（结构） | 私有仓目录结构迁移 | 否 |
| 3D 升级工具链（全部） | **已装工具的版本**（Node/pip/npm 全局/gh/Claude/MCP 缓存/officecli/cloudflare） | 否 |
| 3E 全部仓库 git 同步 | `~/git/` 下所有仓库 | 是（拉 + 脏库提交推送） |

顺带查出一个包含关系：`sync.sh --all` 的 `list_repos()` 把 ccconfig 硬编为第一个仓库，所以 **3E 已经涵盖 3A 的「拉代码 + 重建链接」**，3A 唯一多出来的是修 memory symlink（跑 `ccprivate/setup.sh`）。原先的「3F 全量更新（自更新+拉取）」其实是 3A+3B+3E 的叠加且标签误导，已改为直接指向 `./maintain.sh sync --all`；`maintain.sh` 的 `do_full_update()` 随之删除（无引用）。

### 第 5 类：10 项 → 8 项

删 `5I 定时器配置（时间/飞书）` 与 `5J 费用 pricing 设置`，其余字母重排为 `5A–5H`。第 4 类的 `4H 用量/单价账单` 改名 `4H 归档用量（按模型+天）`（`bill` 子命令仍在，只是不再是"单价"）。

## 兼容性

**历史 CSV 不会读不了。** token-usage.sh 从不回读 CSV（只写）；`init-llm-bill.sh` 用 `csv.DictReader` 按表头取列，旧文件有 `cost_cny`、新文件没有，混在同一目录都能正常读。影响仅是旧 CSV 的 cost 列不再有人展示。

新写出的列数：session CSV 15 列、by-day CSV 16 列。

## 验证

```
bash tests/test-token-usage.sh     → PASS 14 / FAIL 0
bash tests/test-maintain.sh        → PASS 89 / FAIL 0
实测 --json / --stats / --by-day    → 三者均正常，CSV 头无 cost_cny，stats 无 Cost 列
```

`tests/test-token-usage.sh` 的 T11/T12 从「pricing 集成」「飞书 URL 解析」改写为**移除回归锁**：
断言脚本里不再出现 `push_feishu`/`parse_feishu_url`/`load_pricing`/`calc_cost`、`--feishu` 报未知参数、example 里没有 `feishu_url` —— 防止这两个功能悄悄长回来。
