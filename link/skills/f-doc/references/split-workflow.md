# 大文档拆分（Split）

将单个大文档按逻辑边界拆分为多个独立文档。

## 适用场景

- 单文档超长（>5000字或>10个H2），不便维护
- 内容涉及多个独立主题，各自可单独引用
- 需要分发给不同受众（仅需部分内容）

## Step 1: 获取文档结构

```bash
lark-cli docs +fetch --api-version v2 --doc "{token}" --format json 2>&1 | sed '/^\[lark-cli\]/d' | \
  python3 -c "
import json,sys
d=json.load(sys.stdin)
blocks=d.get('data',{}).get('document',{}).get('blocks',[])
for b in blocks:
    t=b.get('type','')
    bid=b.get('block_id','')[:8]
    if t.startswith('heading'):
        lvl=int(t[-1])
        content=b.get('content','')[:100]
        print(f\"{'  '*(lvl-1)}[{bid}] {'#'*lvl} {content}\")
    elif t=='paragraph':
        print(f\"    [{bid}] P: {b.get('content','')[:60]}...\")
"
```

## Step 2: 识别拆分边界

### 拆分策略

| 策略 | 适用场景 | 边界识别 |
|------|---------|---------|
| **H1 拆分** | 文档有多章独立主题 | 每个 H1 为一个子文档 |
| **H2 拆分** | 单章内容过长 | H2 为候选边界 |
| **字数拆分** | 无明显标题层级 | 按 ~2000字/文档 |
| **受众拆分** | 不同读者需要不同部分 | 用户指定归属 |

### 拆分规则
- H1 章节 <500字且主题相关 → 合并到相邻章节
- 前言/引言 → 独立或附在第一部分
- 附录/参考 → 独立为"参考资料"文档

## Step 3: 输出拆分方案

```
=== 拆分方案 ===

源文档: 算力采购综合报告 (共8500字, 5个H1, 12个H2)

[子文档1] 算力市场概况与趋势 (约2000字)
  包含: H1"市场概况" + H2"2026-2028趋势"

[子文档2] 算力成本对比：MaaS vs 自建 (约3000字)
  包含: H1"成本分析"完整章节

[子文档3] 算力产能需求评估方法 (约1500字)
  包含: H1"产能评估"完整章节

[子文档4] 附录：供应商对比表 (约800字)
  包含: H1"附录"
```

## Step 4: 用户审批 & 创建

用户确认后：
1. 按 split points 切分 blocks
2. 每个子文档独立组装 XML
3. 逐个创建

```bash
# 逐个创建子文档
lark-cli docs +create --api-version v2 --content "{part1_xml}"
lark-cli docs +create --api-version v2 --content "{part2_xml}"
```

创建后更新拆分方案文档，添加子文档链接。

## Step 5: 更新源文档

在源文档开头添加导航块，链接到各子文档：

```xml
<callout type="info">
  <p>本文档已拆分为以下子文档：</p>
  <ul>
    <li><a href="子文档1URL">算力市场概况与趋势</a></li>
    <li><a href="子文档2URL">算力成本对比</a></li>
  </ul>
</callout>
```

## 坑点

- 拆分后交叉引用链接会断裂，需检查 `<a href="...">` 内部锚点
- 图片/附件需要判断归属，可能需要复制到新文档
- 拆分后原文档不应删除（保留作为索引/参考）
- 子文档应保持原文档的标题层级（H1→H1, H2→H2），不用重新编号
