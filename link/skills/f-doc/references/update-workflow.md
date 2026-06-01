# 增量更新工作流

飞书文档的最小化编辑：读取→分析→精准修改→验证。

## Step 1: 获取文档

```bash
# 获取文档结构（非全文，减少 token）
lark-cli docs +fetch --api-version v2 --doc "{token}" --format json 2>&1 | sed '/^\[lark-cli\]/d' | \
  python3 -c "
import json,sys
d=json.load(sys.stdin)
# 提取标题层级，不展开全文
blocks=d.get('data',{}).get('document',{}).get('blocks',[])
for b in blocks:
    t=b.get('type','')
    if t.startswith('heading'):
        print(f\"{'#'*int(t[-1])} {b.get('content','')[:80]}\")
"
```

## Step 2: 展示结构

向用户展示文档的标题树，标注每个章节的行数/大小。格式：

```
# 标题 (H1) - 约200字
## 子标题 (H2) - 约150字
## 子标题 (H2) - 约300字
# 标题 (H1) - 约500字
```

## Step 3: 用户描述变更

用户自然语言描述要改什么：
- "把第三章的2026改成2027"
- "在XX章节后面增加一段关于YY的内容"
- "删除ZZ部分，替换为AA"

## Step 4: 执行编辑

优先用 `str_replace`（文本替换），匹配整个 block 时用 `block_replace`。

```bash
# 文本级别替换
lark-cli docs +update --api-version v2 --doc "{token}" \
  --command str_replace --old-str "原文" --new-str "新文"

# Block 级别替换
lark-cli docs +update --api-version v2 --doc "{token}" \
  --command block_replace --block-id "{block_id}" --content "<p>新内容</p>"

# 在某 block 后插入
lark-cli docs +update --api-version v2 --doc "{token}" \
  --command block_insert_after --block-id "{block_id}" --content "<h2>新章节</h2><p>内容</p>"
```

## Step 5: 验证

```bash
# 重新 fetch，确认变更生效
lark-cli docs +fetch --api-version v2 --doc "{token}" --format json 2>&1 | sed '/^\[lark-cli\]/d' | \
  python3 -c "..." # 检查修改的部分
```

## 批量更新

多个小改动合并为一次 `docs +update`，减少 API 调用：

```bash
lark-cli docs +update --api-version v2 --doc "{token}" \
  --command str_replace --old-str "A" --new-str "B" \
  --command str_replace --old-str "C" --new-str "D"
```

## 坑点

- str_replace 的 old_str 必须精确匹配（含空格/换行）
- block_replace 替换整个 block，标题/样式需在 content 中重新声明
- 编辑后 MUST re-fetch 验证（反馈：block_replace 返回 ok 不代表生效）
- 编辑前先 fetch，确认 block_id 未变更（飞书文档可能被他人修改）
