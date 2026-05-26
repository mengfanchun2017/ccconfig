# skills/ — Skills

> Claude Code 技能定义，通过符号链接到 `~/.claude/skills/`。

## 一级：f-* 编排层（自建）

| Skill | 用途 |
|-------|------|
| `f-doc/` | 统一文档入口 — 创建/更新/合并/拆分/转换/对比 |
| `f-ppt/` | PPT 生成 — 双引擎（ppt-master + OfficeCLI）|
| `f-research/` | 统一研究框架 — 三源搜索、自动领域判断 |
| `f-research-deep/` | 深度研究 — 批量 JSON 输出 |
| `f-research-report/` | 报告生成 — JSON → Markdown |
| `f-worklog/` | 工作日志写入飞书 Base |
| `f-skill/` | 创建新 skill |
| `f-caveman/` | 超压缩输出模式 |
| `f-diagnose/` | 纪律化 debug 循环 |
| `f-feedme/` | 智能订餐助手 |
| `f-grill/` | 设计审查 interview |
| `f-arch/` | 架构深化优化 |
| `f-vessel/` | AI 浏览器操控 |
| `f-zoom/` | 代码全景视角 |

## 二级：lark-* 原语层（第三方）

| Skill | 用途 |
|-------|------|
| `lark-shared/` | 飞书基础：认证、多账号 |
| `lark-doc/` | 飞书云文档 CRUD |
| `lark-base/` | 飞书多维表格 |
| `lark-sheets/` | 飞书电子表格 |
| `lark-wiki/` | 飞书知识库管理 |
| `lark-whiteboard/` | 飞书画板 |
| `lark-drive/` | 飞书云空间 |
| `lark-extend/` | 飞书本地覆盖约定 |
| `lark-calendar/` | 飞书日历 |

## 同步

```bash
bash ccconfig/init-skill.sh sync
```
