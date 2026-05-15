---
name: unified-research-report
user-invocable: true
description: |
  基于 unified-research 框架的报告生成。读取 results/ 中的 JSON 文件，
  生成结构化 markdown 报告。支持输出到飞书或文件。
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Unified Research Report

## 工作流程
1. 定位 outline.yaml
2. 扫描 results/*.json
3. 选择 TOC 摘要字段
4. 生成 report.md（跳过 [uncertain]）
5. 输出（RESEARCH_OUTPUT 配置）