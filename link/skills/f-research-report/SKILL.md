---
name: f-research-report
user-invocable: true
description: |
  报告生成 — 读 JSON / 大纲 / 自由素材 → 结构化 markdown 报告。
  3 种输入模式，按用户场景自动选择。内容规范委派 f-report-std。
  飞书输出委派 f-doc（图子文档工作流 G）。
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Unified Research Report

报告生成模块，将研究结果/大纲/自由素材转换为可读报告。

> **格式硬约束** → `../f-report-std/rules.d/f-report-std.md`（全局加载）
> **飞书格式** → `../f-doc/SKILL.md`（工作流 G 处理图子文档）

## 3 种输入模式

| 模式 | 触发条件 | 数据来源 | 工作流 |
|------|----------|----------|--------|
| **JSON 模式** | 有 `outline.yaml` + `results/*.json` | 已有调研结果 | Step 1-5 原有流程 |
| **大纲模式** | 用户给章节大纲/题目 | 无 JSON | 大纲模式（见下） |
| **自由模式** | 用户说"写 X 报告"无素材 | 无 | 委托 f-research 搜索 + 调模板 |

### 模式选择

```
用户："写一份 X 报告"
  ├─ 检查当前目录：有 outline.yaml + results/*.json → JSON 模式
  ├─ 检查用户输入：含章节大纲（如"分析现状/根因/建议"） → 大纲模式
  └─ 其他 → 自由模式（调 f-report-std 选模板 + f-research 搜索）
```

## 模板委派

任何模式都委派 `f-report-std` 选模板：
- `research` — 调研/研究
- `analysis` — 分析/复盘
- `comparison` — 对比/选型
- `proposal` — 方案/规划

模板在 `../f-report-std/templates/`。

## 工作流（按模式）

### 模式 1: JSON 模式（原 5 步流程）

#### Step 1: 定位研究目录
查找当前工作目录中的 `*/outline.yaml`

#### Step 2: 扫描 JSON 文件
读取 `output_dir` 中所有 `.json` 文件（排除 `_summary.json`）。

提取字段用于目录显示：name / release_date / github_stars / market_share / key metrics

#### Step 3: 询问用户 TOC 选项
展示可用的摘要字段，让用户选择显示在目录中的字段。

#### Step 4: 生成报告
生成 `report.md`，跳过 `[uncertain]` 值。

报告结构（按模板）：
- Table of Contents（anchor links + 摘要字段）
- Executive Summary
- Item Details（按 field category 组织）
- Comparative Analysis（跨 items 对比）
- Sources
- Uncertainty Register

#### Step 5: 输出
根据 `RESEARCH_OUTPUT` 配置：feishu（默认）/ file / both
输出到飞书时，委派 f-doc skill（工作流 0 创建新文档）。

### 模式 2: 大纲模式

适用：用户给章节大纲但无调研数据。

#### Step 大纲.1: 解析大纲
用户输入示例：
- "分析现状/根因/建议，三段"
- "对比 A/B/C 方案"
- "技术调研：背景/现状/趋势/建议"

#### Step 大纲.2: 选模板
按大纲结构匹配 `f-report-std/templates/`：
- 现状+原因+建议 → `analysis.md`
- 候选对比 → `comparison.md`
- 背景+现状+趋势 → `research.md`

#### Step 大纲.3: 调 f-research 补素材
对每个章节调 f-research 做轻量搜索（2-3 源），产出每章 200-500 字。

#### Step 大纲.4: 填充模板
按模板骨架 + f-research 素材生成报告。

#### Step 大纲.5: 输出
委派 f-doc 创建飞书文档。

### 模式 3: 自由模式

适用：用户只说"写 X 报告"无任何素材。

#### Step 自由.1: 选模板
按 X 的性质匹配：
- 行业/技术/市场 → `research.md`
- 复盘/问题/根因 → `analysis.md`
- 选型/对比 → `comparison.md`
- 方案/规划 → `proposal.md`

不确定时用 AskUserQuestion 让用户选。

#### Step 自由.2: 调 f-research 深度搜索
全流程走 f-research 框架：
- 领域判断
- 三源并行搜索
- 聚合去重
- 输出到 results/

#### Step 自由.3: 转 JSON 模式
搜索结果存为 `results/*.json` → 自动进入 JSON 模式 Step 1-5。

## 工作流 G: 图子文档生成（数据/分析图）

> 架构/流程图走 Mermaid 白板（f-doc 默认）。**数据/分析图走本工作流**——每个图建独立子文档。

### 何时用

| 图类型 | 走法 |
|--------|------|
| 架构图 / 流程图 / 时序图 | Mermaid 白板嵌入（f-doc） |
| 数据图（折线/柱状/散点/热力图） | **本工作流** → python 脚本 → 子文档 |
| 对比图 / 占比图 | **本工作流** 或 plotly 交互图 |
| 示意图（无数据） | Mermaid 白板 |

### Step G.1: 写 python 脚本
- 选型：常规图 matplotlib + seaborn；交互图 plotly
- 存到 `/tmp/figs/<图名>.py`（脚本可追溯、可重跑）
- 中文字体显式设置：`plt.rcParams['font.sans-serif']=['Noto Sans CJK SC']`
- 默认 `figsize=(10, 6)`, `dpi=150`
- 图存到 `/tmp/figs/<图名>.png`（PNG 飞书兼容）

### Step G.2: 创建子文档
- 父文档已存在 → 用父文档 token 作为 `--parent-token`
- 子文档名 = 图名（简洁中文）
- 子文档结构（3 段）：
  1. **图**：嵌入 PNG
  2. **解读**：分析、对比、洞察、注意点
  3. **代码**：完整 python 脚本（可重跑）

### Step G.3: 父文档嵌入
- 父文档用 `block_insert_after` 把子文档的图块嵌入到指定位置
- **绝不复制图到父文档**（飞书是引用，子文档 = 唯一源）
- 父文档插入位置写一句"详见《<子文档名>》"，引导跳转

### 详细命令
见 `../f-doc/SKILL.md` 工作流 G（含 lark-cli 完整命令）。

## 关联 Skills
- `f-report-std` — 内容规范、模板（必读）
- `f-research` — 搜索调研
- `f-research-deep` — 批量研究
- `f-doc` — 飞书格式 + 图子文档 lark-cli 命令
