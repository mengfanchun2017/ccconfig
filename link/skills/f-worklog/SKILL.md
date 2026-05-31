---
name: f-worklog
user-invocable: false
description: [已废弃] 写入 worklog 到飞书 Base — 请使用 f-logme
allowed-tools: Bash
---

# ⛔ 已废弃 — 请使用 f-logme

f-worklog 已被 f-logme 替代。所有 worklog 操作统一走 f-logme（OKR+Worklog+Reflect+SUM 完整系统）。

新 Base：`LX5lb6VfdaJHWrsRbTgc8Y50nmj` / `tblVsC0L7QFzMeYM`（ailab 账号）

如需直接写 worklog，用以下命令：

```bash
cat > /tmp/wl.json << 'EOF'
{"fields":["标题","关联KR","成果类型","说明","日期"],
 "rows":[["claudecode xxx",[{"id":"recXXXX"}],"工具开发","说明","2026-06-01"]]}
EOF
cd /tmp && lark-cli base +record-batch-create \
  --base-token LX5lb6VfdaJHWrsRbTgc8Y50nmj \
  --table-id tblVsC0L7QFzMeYM \
  --as user \
  --json @wl.json
rm -f /tmp/wl.json
```
