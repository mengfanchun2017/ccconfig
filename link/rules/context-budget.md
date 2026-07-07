# Context 预算

## 硬上限
- rules 始终加载 < 15KB（当前 ~13.8KB ✓）
- rules 总计（含 path-scoped）< 20KB（当前 ~18.4KB）
- MEMORY.md < 40 条目
- 新 rule 创建前：能放 skill reference？能 path-scope？能合并到已有 rule？

## 当前分布
| 类别 | 大小 | 文件 |
|------|------|------|
| 始终加载 | 13.8 KB | code, feishu, feishu-cli-cheatsheet, search, memory, context-budget, README |
| path-scoped | 4.1 KB | python (`**/*.py`), git (`**/.git/**`), godot (`**/*.gd`) |

## 清理
- 季度 memory review：删过期记忆，mtime > 6 月的考虑归档
- `bash ccconfig/bin/memory-check.sh` 列出 stale 候选
