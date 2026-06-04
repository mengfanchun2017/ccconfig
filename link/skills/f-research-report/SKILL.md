---
name: f-research-report
user-invocable: true
description: |
  基于 unified-research 框架的报告生成。读取 results/ 目录中的 JSON 文件，
  生成结构化 markdown 报告。支持输出到飞书或文件。
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Unified Research Report

报告生成模块，将 JSON 研究结果转换为可读报告。

> **格式硬约束** → `rules.d/f-research-report.md`（全局加载，研究报告格式/结构/内容规范）

## 工作流程

### Step 1: 定位研究目录
查找当前工作目录中的 `*/outline.yaml`

### Step 2: 扫描 JSON 文件
读取 `output_dir` 中所有 `.json` 文件（排除 `_summary.json`）。

提取字段用于目录显示：
- name
- release_date / date
- github_stars / stars
- market_share
- key metrics

### Step 3: 询问用户 TOC 选项
展示可用的摘要字段，让用户选择显示在目录中的字段。

### Step 4: 生成报告
生成 `report.md`，跳过 `[uncertain]` 值。

报告结构：
- Table of Contents（anchor links + 摘要字段）
- Executive Summary
- Item Details（按 field category 组织）
- Comparative Analysis（跨 items 对比）
- Sources
- Uncertainty Register

### Step 5: 输出
根据 `RESEARCH_OUTPUT` 配置：feishu（默认）/ file / both

**输出到飞书时**，委托 f-doc skill（工作流 0 创建新文档）。格式约束参考 `../f-doc/references/write-checklist.md`。

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
  1. **图**：嵌入 PNG（`<img src="/tmp/figs/xxx.png">` 或上传飞书 media）
  2. **解读**：分析、对比、洞察、注意点
  3. **代码**：完整 python 脚本（可重跑）

### Step G.3: 父文档嵌入
- 父文档用 `block_insert_after` 把子文档的图块嵌入到指定位置
- **绝不复制图到父文档**（飞书是引用，子文档 = 唯一源）
- 父文档插入位置写一句"详见《<子文档名>》"，引导跳转

### 详细格式
见 `../f-doc/references/write-checklist.md` 图子文档段。

## 关联 Skills
- `f-research` - 初步研究
- `f-research-deep` - 深度研究
- `f-doc` - 图嵌入 + 飞书格式（工作流 G 委派）