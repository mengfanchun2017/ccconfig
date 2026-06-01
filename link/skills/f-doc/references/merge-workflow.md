# 多文档整合（Merge）

将散落在多个飞书文档中的同主题内容合并为一份。

## Step 1: 发现候选文档

```bash
# 多关键词搜索，覆盖不同角度
lark-cli drive +search --query "核心词1" --doc-types "wiki,doc,docx" --page-size 20
lark-cli drive +search --query "核心词2" --doc-types "wiki,doc,docx" --page-size 20
```

去重（按 token），合并候选列表。

## Step 2: 批量获取结构

逐个 fetch 候选文档的标题层级（非全文），评估内容范围：

```bash
for token in token1 token2 token3; do
  lark-cli docs +fetch --api-version v2 --doc "$token" --format json 2>&1 | sed '/^\[lark-cli\]/d' | \
    python3 -c "import json,sys;d=json.load(sys.stdin);..." > /tmp/doc_${token}.json
done
```

## Step 3: 分析 & 去重

### 相似度判断
- 标题完全一致 → 可能重复，对比内容
- 标题相似（编辑距离小）→ 可能为版本迭代，用最新
- 摘要/关键词重叠 >50% → 标记为重叠，需合并章节

### 去重决策矩阵

| 情况 | 处理 |
|------|------|
| 两个文档内容重复 >80% | 保留最新编辑的，丢弃旧的 |
| 部分章节重叠 | 保留信息更完整的版本，标注来源 |
| 内容互补（同主题不同角度）| 合并为一份，按逻辑重排章节 |
| 存在矛盾/冲突 | 标记出来，让用户决策 |

## Step 4: 输出合并方案

向用户展示：

```
=== 合并方案 ===

源文档:
  [A] AI算力租用与采购5年成本研究 (2026-04-22, VtdB...)
  [B] 算力MaaS与自建成本分析 (2026-04-20, Dpxm...)
  [C] 算力产能需求评估 (2025-11-26, EDhw...)

建议结构:
  # 算力采购综合报告
    ## 1. 市场概况 (← [A]第一章 + [B]第一章)
    ## 2. 成本对比分析 (← [A]核心章节, 信息更完整)
    ## 3. MaaS vs 自建 (← [B]主体)
    ## 4. 产能需求评估 (← [C]全文)
    ## 5. 2027-2028 规划建议 (← 新撰写)

去重:
  - [A]第二章与[B]第三章重叠80% → 保留[A]版本
  - [B]第一章信息量不足 → 用[A]第一章替代

冲突:
  - [A]预估2027年成本100万 vs [B]预估120万 → 需确认
```

## Step 5: 用户审批 & 创建

用户确认方案后：
1. 按方案提取各部分内容
2. 组装为完整 DocxXML
3. `lark-cli docs +create --api-version v2 --content "{xml}"`

或覆写到已有文档：
```bash
lark-cli docs +update --api-version v2 --doc "{target_token}" \
  --command overwrite --content "{全文XML}"
```

## 坑点

- 不要假设文档顺序有意义，按语义重排
- 合并后标题层级需统一调整
- 保留原始文档的引用链接（不要断链）
- 合并结果应标注各章节来源（`> 引用自 [文档标题](URL)`）
