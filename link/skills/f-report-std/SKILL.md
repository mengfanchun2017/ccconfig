---
name: f-report-std
description: |
  报告写作横向规范 — 内容结构、数据呈现、论证逻辑、图表约定。
  4 套模板（研究/分析/对比/方案）+ 通用规则。
  Use when 用户说"写报告"/"出报告"/"分析报告"/"对比报告"/"方案报告"，
  或任何需要产出"长篇正式文档"的场景。
allowed-tools: Read, Write, Glob, Grep, Bash
---

# f-report-std — 报告写作规范

横向能力，定义"什么是好的报告"。**不绑定任何输出平台**（飞书/Word/Notion 都适用），具体飞书格式委派 `f-doc`。

## 职责边界

| 本 skill 负责 | 不负责（委派其他 skill） |
|--------------|---------------------|
| 内容结构（H1/章节顺序/概括） | 飞书格式（lark-table 822 等）→ f-doc |
| 论证规范（数据+因果+不确定） | 搜索/数据收集 → f-research |
| 数据呈现原则（对比用表/数值量级） | 图表生成（python/mermaid）→ f-doc 工作流 G |
| 模板（4 套） | 报告工作流执行 → f-research-report |
| 引用规范（国标/通用性） | 文档索引维护 → f-doc |

## 4 套模板

| 模板 | 用途 | 章节骨架 |
|------|------|----------|
| `templates/research.md` | 调研/研究报告 | 摘要 → 背景 → 现状分析 → 调研发现 → 关键洞察 → 建议 |
| `templates/analysis.md` | 分析/复盘报告 | 摘要 → 起因 → 过程 → 根因 → 影响 → 改进 |
| `templates/comparison.md` | 对比/选型报告 | 摘要 → 目标 → 候选方案 → 多维对比 → 推荐 |
| `templates/proposal.md` | 方案/规划报告 | 摘要 → 背景 → 目标 → 方案 → 实施路径 → 风险 |

> 调用方式：用户说"写 X 报告"→ 复制对应模板 → 按用户大纲填充

## 报告规范（核心）

### 结构

- **H1 顶级**：每个 H1 是一级章节
- **每章 2-3 句概括**：H1 后第一段简短说明本章解决什么问题
- **不加手动编号**：飞书自动生成目录
- **章节顺序遵循模板**：执行摘要 → 分析框架 → 逐章展开 → 对比/矩阵 → 关键结论

### 数据呈现

- **对比场景（X vs Y）**：表格/矩阵呈现，禁纯列表罗列
- **多层级架构图**：每层横向并列，避免全纵向过长
- **数值量级**：与真实用量匹配（万元级非千元级）

### 论证

- **每章 3 要素**：数据支撑 + 因果链条 + 不确定项标注
- **通用性**：使用"该企业""目标场景"等泛指，不写具体企业名
- **不确定项**：明确标 [待确认] [数据有限] [需补充]

### 引用

- **国标/标准引用完整**：三级体系只用到两级也要说全三级
- **行业报告**：注明来源 + 时间 + 数据范围

## 图子文档约定（与 f-doc 协作）

| 步骤 | 责任方 | 工具 |
|------|--------|------|
| 1. 写 python 脚本（图） | f-research-report | matplotlib/seaborn/plotly |
| 2. 跑脚本 → /tmp/figs/*.png | f-research-report | python3 |
| 3. 建子文档（图 + 解读 + 代码 3 段） | f-doc | lark-cli docs +create |
| 4. 父文档 block_insert_after 嵌入 | f-doc | lark-cli docs +update |
| 5. 父文档加"详见《<子文档名>》" | f-doc | lark-cli |

**关键原则**：
- 子文档 = 详细档案（唯一源，可被多父文档嵌入）
- 父文档 = 摘要嵌入（绝不复制图，飞书是引用）
- 脚本存 `/tmp/figs/<图名>.py`（可重跑、可追溯）

## 与其他 skill 的协作

```
用户："写一份 X 报告"
  └─→ f-report-std（选模板 + 规范）
       ├─→ f-research（搜索调研）         [可选]
       ├─→ f-research-report（出报告）     [执行]
       │     └─→ f-doc（飞书格式 + 图子文档）
       └─→ 完成
```

## 用户配置

`config.yaml` 可配置项：
- `default_template`: 默认模板（research/analysis/comparison/proposal）
- `strict_mode`: 严格模式（强制所有章节必有 2-3 句概括）

```bash
cat "$SKILL_DIR/config.yaml"
```

## 关联 Skills
- `f-doc` — 飞书格式 + 图子文档工作流 G
- `f-research` — 搜索调研
- `f-research-report` — 报告生成执行
- `f-logme` — OKR/SUM 总结可参考本框架

## 线上文档索引

> f-report-std 直接创建的文档。通常通过 f-research-report/f-logme 创建，不直接索引。
