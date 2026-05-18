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

## lark-cli 输出解析约定

**lark-cli 会在 stdout 输出日志行（非 JSON），直接 pipe 给 `python3 -c "json.load(sys.stdin)"` 会解析失败。**

### 问题特征
```
[lark-cli] [WARN] proxy detected: HTTPS_PROXY=http://127.0.0.1:7897 — ...
{
  "ok": true,
  ...
}
```

### 解决方案

```bash
# 方案1: tail 跳过第一行（最常用）
lark-cli ... 2>&1 | tail -n +2 | python3 -c "import json,sys; ..."

# 方案2: sed 删除匹配行
lark-cli ... 2>&1 | sed '/^\[lark-cli\]/d' | python3 -c "..."

# 方案3: 用 grep -v 过滤
lark-cli ... 2>&1 | grep -v '^\[lark-cli\]' | python3 -c "..."
```

### 已知的日志行前缀
- `[lark-cli] [WARN] proxy detected: ...`
- `[lark-cli] [INFO] ...`
- `[lark-cli] [ERROR] ...`

**规则：lark-cli 输出 pipe 给 JSON 解析器之前，必须先 `tail -n +2` 或 `sed '/^\[lark-cli\]/d'`。**

## 工作日志约定

- worklog 写入 Base: 自动识别 成长/工作 分类
- 字段选项速查见 worklog skill
