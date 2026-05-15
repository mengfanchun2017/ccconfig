---
name: unified-research-report
user-invocable: true
description: |
  基于 unified-research 框架的报告生成。读取 results/ 目录中的 JSON 文件，
  生成结构化 markdown 报告。支持输出到飞书或文件。
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Unified Research Report

报告生成模块，将 JSON 研究结果转换为可读报告。

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

## 关联 Skills
- `/unified-research` - 初步研究
- `/unified-research-deep` - 深度研究