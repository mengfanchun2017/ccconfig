# option-usage — Token 用量统计组件

Claude Code 本地会话 token 用量聚合：解析 `~/.claude/projects/**/*.jsonl`，按 session/day/项目归档到 `ccprivate/usage/`。

**只统计 token 与时间**：不折算钱（费用以上游账单为准）、不外发。

## 安装

```bash
bash ccconfig/option-usage/init.sh install     # 装 systemd timer（每日 12:01 归档到昨天）
bash ccconfig/option-usage/init.sh status      # 查 timer/归档/配置状态
bash ccconfig/option-usage/init.sh uninstall   # 卸 timer
```

## 命令

通过 `bash maintain.sh token` 调用：

```bash
# 子命令
bash maintain.sh token --stats           # 跨 LLM 总量汇总（按模型/时间段/月）
bash maintain.sh token --report          # 按日聚合报告
bash maintain.sh token --by-day           # 归档到 ccprivate/usage/YYYY-MM-DD.csv（到昨天）
bash maintain.sh token --by-day --include-today   # 含今天（进行中 session 会漂移）
bash maintain.sh token --by-day --force   # 强制重算全量（改列结构后用）
bash maintain.sh token --json            # JSON 行输出
bash maintain.sh token --since 2026-07-30 --until 2026-08-01   # 日期过滤
bash maintain.sh token --project ccconfig    # 项目过滤

# 直接调用（绕过 maintain）
bash option-usage/token-usage.sh [args...]
```

## timer 配置

`ccprivate/conf/token-usage.json`：

| 键 | 说明 |
|----|------|
| `schedule` | 归档时间（systemd 格式，如 `12:01:00`）。改后需重装 timer 才生效 |
| `include_today` | 归档是否含当天（默认 false） |

```bash
bash option-usage/init.sh set-time 13:00:00   # 改时间（改完要 install 重装 timer）
bash option-usage/init.sh set-today true      # 改 include_today
```

## 数据格式

归档文件 `ccprivate/usage/YYYY-MM-DD.csv`，**写一次**策略：历史 day（< 今天）已写过即跳过（jsonl append-only，数据冻结，重算结果相同）；今天 always 覆盖（进行中 session 漂移）。`--force` 全量重算覆盖（改列结构后用）。每日 timer 只写昨天 1 个文件，不重写历史。

```csv
session_id,day,project_path,session_name,model,input_tokens,cache_read_tokens,output_tokens,total_tokens,request_count,turn_count,model_time_ms,tool_time_ms,wall_ms,first_ts,last_ts
0e00f5e3,2026-07-30,-home-user-git,<session-name>,<model-id>,130727,0,292,131019,4,1,5320,2100,137000,2026-07-30T06:48:33.606Z,2026-07-30T06:50:50.758Z
```

**字段说明**：
- `session_id`: session UUID 前 8 位
- `day`: 真实请求日期（同一 session 跨 N 天 → N 条记录，按 timestamp 自然分摊）
- `session_name`: 优先取 Claude 自动生成的 ai-title（如 "option-usage implementation"），fallback 首条 user 消息前 80 字
- `cache_read_tokens`: 缓存命中 token
- `turn_count`: 真实用户输入次数（一问一答=1，不含 tool_result）
- `model_time_ms`: LLM 推理挂钟（Σ assistant_ts − 前一条 user/tool_result 的 ts），复杂度核心指标
- `tool_time_ms`: 工具执行挂钟（Σ tool_result_ts − 前一条 assistant 的 ts，含本地 bash + MCP 远程）
- `wall_ms`: 挂钟跨度（last − first，含用户发呆；FleetView 显示的就是它）

session CSV（`sessions-<日期>.csv`，全量扫时写）比 by-day 多 `project_path`，列集合以实际表头为准。

## 历史

- 曾支持 `--feishu <url>` 推飞书多维表格 → 2026-09-20 移除（不再使用飞书上报）
- 曾按 `llm.json` 的 `pricing` 表折算 `cost_cny` 列 → 2026-09-20 移除（本地自算不准，费用以上游账单为准）
- 旧 CSV 里仍有 `cost_cny` 列，不影响读取：读取方按表头取列
