---
name: lark-extend
description: lark-cli 定制扩展 — 覆盖/补充官方 lark-base/lark-doc/lark-shared 的约定和规则。包含文档创建规范、Base 操作约定、飞书特有规则。
---

# Lark 扩展规则

本 skill 不重复官方 lark-* skill 的内容，只覆盖和补充。

## 前置依赖

- [../lark-shared/SKILL.md](../lark-shared/SKILL.md) — 认证、多账号、工具选型
- [../lark-doc/SKILL.md](../lark-doc/SKILL.md) — 文档 CRUD
- [../lark-base/SKILL.md](../lark-base/SKILL.md) — 多维表格 CRUD

## 文档约定

- **默认父目录**: 创建文档时默认 `--wiki-node CyZ6wmItQiso3AkbjZBcP3vtnAb`
- **标题层级**: ≤ H3，禁止 H1/H2 编号（如 "1."、"一、"）
- **缩写定义**: 首次出现用 DFN 格式（`定义`）
- **表格宽度**: 飞书文档表格 820px 全宽
- **链接格式**: 使用 `www.feishu.cn` 域名，非 `open.feishu.cn`
- **禁止表格裸 URL**: 表格内链接必须用 Markdown 链接格式
- **画板插入**: 需要图表时优先插入画板而非图片
- **输出优先飞书文档**: 学习研究总结默认生成飞书文档而非终端文本

## Base 约定

- 字段设计优先考虑公式字段、查找引用
- 涉及跨表计算时优先用关联字段而非硬编码 ID

## 工作日志约定

- worklog 写入 Base: 自动识别 成长/工作 分类
- 字段选项速查见 worklog skill
