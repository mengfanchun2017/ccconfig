# option-usage — Token 用量统计组件

Claude Code 本地会话 token 用量聚合：解析 `~/.claude/projects/**/*.jsonl`，按 session/day/项目归档到 `ccprivate/usage/`，可推飞书多维表格。

## 安装

```bash
bash ccconfig/option-usage/init.sh             # 创建归档目录
bash ccconfig/option-usage/init.sh --timer     # 启用每日 systemd timer（可选）
```

## 命令

通过 `bash maintain.sh token` 调用：

```bash
# 子命令
bash maintain.sh token --stats           # 总会话统计
bash maintain.sh token --report          # 按日聚合报告
bash maintain.sh token --by-day          # 归档到 ccprivate/usage/YYYY-MM-DD.csv（增量）
bash maintain.sh token --json            # JSON 行输出
bash maintain.sh token --feishu <url>    # 推送到飞书多维表格
bash maintain.sh token --since 2026-07-30 --until 2026-08-01   # 日期过滤
bash maintain.sh token --project ccconfig    # 项目过滤

# 直接调用（绕过 maintain）
bash option-usage/token-usage.sh [args...]
```

## 数据格式

归档文件 `ccprivate/usage/2026-08-02.csv`：

```csv
session_id,day,project_path,route,session_name,model,input_tokens,output_tokens,cache_create_tokens,cache_read_tokens,total_tokens,request_count,first_ts,last_ts,cost_cny
0e00f5e3,2026-07-30,-home-francis-git,deepseek-direct,<session_name>,deepseek-v4-flash,130727,292,0,0,131019,4,...
```

**字段说明**：
- `session_id`: session UUID 前 8 位
- `day`: 真实请求日期（同一 session 跨 N 天 → N 条记录）
- `route`: `deepseek-direct` / `minimax-direct` / `anthropic-direct` / `bridge-openaialt` / `synthetic`
- `session_name`: session 首条 user 消息前 80 字
- `cache_create_tokens`: 你的 deepseek/MiniMax 环境恒为 0（上游 API 不返回）
- `cache_read_tokens`: 缓存命中 token（计费按 0.1× input）
- `cost_cny`: 按 `pricing` 表估算的成本（CNY ¥）

## 价格配置

价格表在 `ccprivate/conf/llm.json` 的 `pricing` 字段，由 `bash init-llm.sh` 配置。

字段（USD / 1M tokens）：
- `input`: 普通输入
- `output`: 输出
- `cache_read`: 缓存命中
- `cache_creation`: 缓存创建（1.25× input 价；deepseek/MiniMax 不适用）

价格按**模型名**配置，与渠道（gateway/bridge/直连）无关。