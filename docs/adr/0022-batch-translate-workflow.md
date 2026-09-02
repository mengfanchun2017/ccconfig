# 0022. 批量文档翻译工作流架构

> **Status**: ✅ Accepted
> **日期**: 2026-09-01
> **关联**: python-docx → init-option 安装
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

每周需翻译 100+ 篇文档（PDF / DOCX / HTML），翻译为中文后归档，要求：

1. 输出 DOCX 的中文版本，**样式与原文档一致**（字体/字号/颜色/表格/缩进/页眉页脚等）
2. 归档为目录结构：每个文档独立目录，含原文 + 中文版
3. 最终打包为 zip 交付
4. 后续计划通过 cc-connect 接入微信/飞书，IM 收发 zip

初期考虑过 MD 中间格式方案（原文→MD→翻译 MD→DOCX），但 Markdown 会丢失大量格式信息（表格合并单元格、字体样式、分段缩进等），**MD→DOCX 再转回时样式不可逆丢失**。

## Decision Drivers

- **D1 格式保真度**：输出 DOCX 与输入样式一致，是最高优先级
- **D2 并行效率**：100 篇文档需并发处理
- **D3 工具链简洁**：最少依赖，最少中间格式转换
- **D4 可配置**：输入输出路径、命名规则、归档结构可灵活调整

## Decision

### 核心架构：DOCX 作为统一中间格式 + python-docx 原地替换文本

```
输入 → 统一转为 DOCX → python-docx 遍历 runs 替换文本 → 输出中文 DOCX
```

### 具体流程

```
                ┌───────────┐
PDF ──→ officecli ──→ DOCX  │
DOCX ─────────────────→ DOCX │──→ python-docx 遍历 ──→ 每个 run.text ──→ LLM 翻译
HTML ─→ officecli ──→ DOCX  │       paragraph/runs         ↓
                └───────────┘                          run.text = 中文
                                                             ↓
                                                     保存为 xxx-cn.docx
                                                     样式与原文档完全一致

归档: xxx-xxx/
  ├── xxx-xxx.原始格式 (原文)
  └── xxx-xxx-cn.docx (中文，样式一致)
```

### 工具选型

| 环节 | 工具 | 理由 |
|------|------|------|
| 任意格式→DOCX | **officecli** | 现有已验证工具，PDF/HTML→DOCX 保真度高，保留 Office 引擎排版 |
| DOCX 文本替换 | **python-docx** | 直接操作 XML run，只替换文字内容，格式属性完全不动 |
| 翻译 | **Workflow subagent + 当前 LLM** | 并发处理，subagent 独立调用模型，互不干扰 |
| 编排 | **Workflow parallel()** | 100 个文档并行调度，每批 ~10 并发 |

### 为什么不做 MD 中间格式

MD 作为中间格式引入两级不可逆损失：

1. DOCX→MD：格式信息丢弃（字体/色号/缩进/表格合并单元格/页眉页脚等）
2. MD→DOCX：Markdown 中不存在的信息需要猜测（行距/分页/编号样式等）

叠加后输出 DOCX 与原文差异明显。**只在 DOCX 层做文本替换，格式零损失。**

### 配置结构

独立 YAML 配置文件，工作流脚本读取：

```yaml
input:
  zip_path: "/path/to/weekly.zip"
  extract_dir: "/path/to/workdir"

output:
  base_dir: "/path/to/output"
  naming: "{stem}-cn.docx"
  structure: dir_per_doc   # dir_per_doc | flat

model: "current"           # 翻译用模型名

options:
  keep_original: true
  repack: true
  zip_output: "/path/to/translated-weekly.zip"
```

### IM 集成路线

后续通过 cc-connect 桥接：

```
用户 微信/飞书
  → 发 zip 文件
    → cc-connect 转发到 Claude Code
      → Workflow 执行翻译
        → 生成 zip
          → cc-connect 发送回聊天
```

## Consequences

### 正面

- **格式零损失**：输出 DOCX 样式与输入完全一致——只是文字翻译了
- **处理链短**：原文→DOCX→翻译→输出，中间格式损失降到最低
- **并发高效**：Workflow parallel() 自动调度 100 个文档
- **officecli 保留**：不废弃已有工具，发挥其 PDF/HTML→DOCX 的独特优势
- **可扩展**：后续加新输入格式（PPT/XLS）只需加 officecli 转换步骤

### 负面

- officecli 依赖 .NET runtime（已安装，无新增依赖）
- PDF→DOCX 依赖 officecli/Word 引擎效果（实测已确认好）
- 翻译不能预览——直接改原文文件，无法撤销

### 风险与缓解

- **officecli 长期维护**：如果 officecli 停止维护，PDF→DOCX 可回退至 Docling CPU + pandoc
- **大文件运行时**：100 页+ DOCX 在 Subagent 中翻译可能较慢，可设 token 预算限制

## Related Decisions

- [ADR-0004](0004-officecli-skill-architecture.md) — OfficeCLI skill 架构
- [ADR-0018](0018-permission-mode-strategy.md) — 权限模式策略

## Implementation

- python-docx → init-option 作为 Python 依赖安装
- translate-weekly.js → 工作流脚本（后续实现）
- translate-config.yaml → 配置文件模板