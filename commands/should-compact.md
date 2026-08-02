---
description: 查看当前 session token 用量，决定要不要 /compact
---

读取最近一个 Claude Code session transcript（路径模式：`~/.claude/projects/*/<SESSION_ID>.jsonl`，SESSION_ID 在当前环境变量 `CLAUDE_CODE_SESSION_ID`）末尾 30-50 条，统计：

- 总 input tokens
- 总 output tokens
- cache_creation tokens（写）
- cache_read tokens（命中）
- 估算当前 context window 占用（input+output+cache, 100k 为窗口）
- 最近 10 轮的 avg input / turn

然后按以下阈值给建议：

| context 占用 | 建议 |
|--------------|------|
| > 70k（窗口 70%） | 强烈建议立即 `/compact` |
| 50k – 70k | 中度建议，长任务前主动 compact |
| 25k – 50k | 健康，可继续 |
| < 25k | 早，不必 compact |

输出格式（caveman 极简）：

```
ctx ~<N>k / 100k — <建议>
in/turn ~<N> | cache hit <N>% | session $CLAUDE_CODE_SESSION_ID 短 8=<前8字符>
如要 compact：`/compact`（标准）或告诉 agent "先 /compact 再继续"
```

不要修改文件，不要跑重型命令 — 只读 + 数值汇总。
