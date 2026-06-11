# 飞书 doc 嵌入图渲染参考

> 飞书 doc 嵌入图的 4 种路径可靠性 + mermaid 飞书白板渲染能力 + 复杂图替代方案。**2026-06-10 实测**。

## 4 种嵌入路径可靠性表

| 路径 | 飞书 doc 显示 | 跨会话下载 | 备注 |
|------|---------------|-----------|------|
| `+media-insert --type image` PNG | ❌ 404 | ❌ 飞书 file URL 需登录态 | doc 内 image block 引用的 file_token 公开 URL 全部 404 |
| `+media-insert --type image` SVG | ⚠️ 100x100 缩略图 | ❌ 同上 | SVG 嵌入被强制缩放，不显示原矢量 |
| `+media-insert --type file` (任意格式) | ⚠️ file block，可下载 | ❌ | 不能直接预览 |
| `whiteboard +update --input_format mermaid` | ✅ 100% | ✅ doc 内嵌预览 | **mermaid 自动转 whiteboard，doc 内显示** |
| `whiteboard +update --input_format plantuml` | ✅ 可能支持 | ✅ | plantuml 支持更复杂（radar 等） |
| 父文档 `block_insert_after` 嵌入子文档 | ✅ | ✅ | 子文档 = 详细档案，父文档 = 摘要链接 |

**根因**：飞书 file URL（`https://<tenant>.feishu.cn/file/<token>`）所有 GET 请求返 404（需登录态）。lark-cli 上传的 file 在 doc 内 image block 引用，但 file URL 不能公开访问 → 飞书 UI 渲染 image 时显示"无法预览"。

## 飞书白板 mermaid 渲染能力

**稳定版（✅ 100% 渲染）**：

| mermaid 类型 | 飞书白板 node 数 | 用途 |
|--------------|-----------------|------|
| flowchart | ~25 | 流程/关系/架构 |
| pie | ~38 | 比例/占比 |
| gantt | ~11 | 时间/里程碑 |
| timeline | ~13 | 时间线（按年/月） |
| mindmap | ~17 | 想法结构 |

**beta 版 + quadrantChart（❌ 0 节点，飞书不支持）**：

| mermaid 类型 | 飞书白板 node 数 | 替代方案 |
|--------------|-----------------|----------|
| **radar-beta** | 0 | **2 张 pie（当前/目标并列）** |
| **quadrantChart** | 0 | **flowchart 标注区域 + 散点** |
| **sankey-beta** | 0 | **flowchart 边带数值** |
| **block-beta** | 0 | **flowchart subgraph** |
| **architecture-beta** | 0 | **flowchart + class 样式** |

**根因**：飞书白板 mermaid 渲染器**只支持稳定版语法**（v9+），**所有 `-beta` 后缀 + quadrantChart 不支持**。

**验证方法**：
```bash
lark-cli whiteboard +query --whiteboard-token <id> --output_as raw 2>&1 | python3 -c "
import json, sys
text = '\n'.join(l for l in sys.stdin.read().splitlines() if not l.startswith('Shell cwd was reset'))
d = json.loads(text)
nodes = d.get('data', {}).get('nodes', [])
print(f'nodes: {len(nodes)}', '✅ 渲染成功' if len(nodes) > 0 else '❌ 渲染失败')
"
```

## 复杂图替代方案

### 雷达图（radar）

**飞书不支持**。替代：
1. **2 张 pie 并列**（当前 6 维 / 目标 6 维）— 最简单
2. **6 张 pie 拆分**（每维 1 张）— 信息粒度更细
3. **flowchart + 数值表**（标注每维度位置）— 适合 < 4 维

### 象限图（quadrant）

**飞书不支持**。替代：
1. **flowchart + quadrant 注释**（4 个 subgraph 表示象限）
2. **gantt + axis 标注**（把 x/y 坐标转时间轴）

### 桑基图（sankey）

**飞书不支持**。替代：
1. **flowchart + 边 width + 数值标签**
2. **多张 pie**（分阶段占比）

### 块图 / 架构图（block / architecture）

**飞书不支持**。替代：
1. **flowchart subgraph**（飞书支持）— 块图大多数场景可表达
2. **本地 matplotlib + 完整代码**（架构复杂时）

## 图嵌入决策树

```
需要嵌入飞书 doc
  ├─ 简单图（占比/时间/流程/想法）→ mermaid → 自动转 whiteboard
  ├─ 复杂图（雷达/桑基/象限/块/架构）
  │    ├─ 飞书支持替代（pie/flowchart）→ 用替代
  │    └─ 无法替代 → 本地 matplotlib + 完整代码块 + 子文档
  └─ 多图集合（数据/分析图）→ 子文档约定（图+解读+代码）
```

## 操作命令速查

```bash
# mermaid 嵌入 doc（自动转 whiteboard）
cat doc.md | lark-cli docs +create --api-version v1 \
  --wiki-node <token> --as user --markdown - --title "标题"

# 验证 mermaid whiteboard 渲染（0 节点 = 失败）
lark-cli whiteboard +query --whiteboard-token <id> --output_as raw

# 删失败的 image block
lark-cli docs +update --api-version v2 --doc <id> --as user \
  --command block_delete --block-id <block_id>

# 移动 image block 到指定位置
lark-cli docs +update --api-version v2 --doc <id> --as user \
  --command block_move_after --block-id <src> --anchor-block-id <dst>
```

## 已知限制

- v2 +fetch --detail with-ids 对 v1 +create 的子文档可能返空（block 列表为空）
- v1 +fetch 不返 markdown 字段（用 `--format pretty` 看完整内容）
- 飞书 doc image block 期望 PNG/JPG/GIF/WEBP，SVG 解析为 image 但不渲染矢量
- 飞书白板 mermaid 不支持 beta 语法 + quadrantChart（2026-06-10 实测）
- 飞书 file URL 跨用户/会话访问 404（2026-06-10 实测）

## 修复历史

- **2026-06-10**：用户反馈成长曲线子文档 PNG/SVG image block 不可预览。根因 = 飞书 file URL 公开访问 404。重做子文档用 mermaid（pie × 2 + gantt × 1）+ 完整 Python 代码块。
- **2026-06-10**：建测试 doc（10 个 mermaid 类型），验证 6 渲染/4 失败。结论写入本 reference。
