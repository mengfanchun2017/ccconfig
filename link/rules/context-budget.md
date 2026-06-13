# Context 预算

## 硬上限
- rules 总大小 < 15KB（当前 ~13KB）
- MEMORY.md < 40 条目（当前 33）
- 新 rule 创建前：能放 skill reference？能 path-scope？能合并到已有 rule？

## 清理
- 季度 memory review：删过期记忆，mtime > 6 月的考虑归档
- `bash ccconfig/bin/memory-check.sh` 列出 stale 候选
