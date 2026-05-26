---
name: f-research-deep
user-invocable: true
description: |
  基于 unified-research 框架的深度研究。使用 outline.yaml 中的 items 列表，
  三源并行搜索，输出结构化 JSON 到 results/ 目录。
allowed-tools: Read, Write, Glob, Bash, WebSearch, Task,
  mcp__tavily__tavily_search, mcp__tavily__tavily_research,
  mcp__tavily__tavily_extract, mcp__minimax__web_search
---

# Unified Research Deep

深度研究模块，执行批量 item 研究。

## 搜索策略

方向遵循 `rules/search.md`，详细方法（Tavily 参数、Python 过滤、去重代码）→ `skills/f-research/SKILL.md`。

## 工作流程

### Step 1: 定位 outline.yaml
在当前工作目录查找 `*/outline.yaml` 文件。

### Step 2: 恢复检查
检查 `output_dir` 中已完成的 JSON 文件，跳过已完成 items。

### Step 3: 批量执行
每批 `batch_size` 个 items，并行启动 research-agent。
默认 batch_size=3。

### Step 4: 三源覆盖（强制并行）
每个 item 同时执行 WebSearch + Tavily + Minimax（遵循 `rules/search.md`）。

### Step 5: 输出 JSON
输出到 `{output_dir}/{item_name_slug}.json`

JSON 结构包含：
- name, domain, _sources, _confidence
- 领域字段（来自 unified-research）
- uncertain 数组

### Step 6: 验证
执行 validate_json.py 验证字段覆盖。

## 关联 Skills
- `f-research` - 初步研究
- `f-research-report` - 报告生成