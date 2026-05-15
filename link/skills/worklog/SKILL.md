---
name: worklog
user-invocable: true
description: 写入 worklog 到飞书 Base（表格），自动识别成长/工作分类，字段选项速查
allowed-tools: Bash
---

# worklog 写入

自动将任务写入飞书 Base：`Tq1ebqPA7aT0cSsSA8GcADZQnqd` / `tblpkMMzVHTTomp1`

## 字段格式

| 字段 | 说明 | 示例 |
|------|------|------|
| 标题 | 成长: `英文标识 中文描述` \| 工作: `纯中文` | `claudecode 模型分流配置` |
| ai分类 | 默认成长 | 成长 / 工作 |
| ai板块 | 单选，用选项值 | architecture |
| 说明 | 一句话总结 | 完成模型分流配置和逻辑 |
| 完成日期 | 今天 | 2026-05-15 |

## ai板块 选项值

| 选项值 | 说明 |
|--------|------|
| agent | Agent 相关 |
| aiagent | AI Agent |
| workflow | 工作流 |
| architecture | 架构（常用）|
| requirement | 需求 |
| solution | 方案 |
| rag | RAG |
| platform | 平台 |
| application | 应用 |
| 资源环境 | 资源环境 |
| 应用开发 | 应用开发 |
| 技术趋势 | 技术趋势 |
| 模型研究 | 模型研究 |
| 数据准备 | 数据准备 |

## 命令

```bash
cat > tmp_worklog.json << 'EOF'
{
  "fields": ["标题", "ai分类", "ai板块", "说明", "完成日期"],
  "rows": [["claudecode xxx", "成长", "architecture", "说明", "2026-05-15"]]
}
EOF
lark-cli base +record-batch-create \
  --base-token Tq1ebqPA7aT0cSsSA8GcADZQnqd \
  --table-id tblpkMMzVHTTomp1 \
  --as user \
  --json @tmp_worklog.json
rm -f tmp_worklog.json
```

## 自动分类

- 标题含英文前缀（claudecode/coze/rag/feishu/metaso 等）→ ai分类=成长
- 纯中文标题 → ai分类=工作
- 用户明确说"工作"/"work" → ai分类=工作

## 标题规则

- ✅ `claudecode 模型分流配置`
- ✅ `rag 多路召回测试`
- ✅ `云资源评估`
- ❌ 不使用【】括号
- ❌ 不使用【LLM架构】前缀