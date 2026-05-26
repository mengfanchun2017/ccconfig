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
| `f-feedme/` | 智能订餐助手 |
| `f-vessel/` | AI 浏览器操控 |

## 二级：第三方 skill

| Skill | 来源 | 用途 |
|-------|------|------|
| `lark-shared/` | larksuite/cli | 飞书基础：认证、多账号 |
| `lark-doc/` | larksuite/cli | 飞书云文档 CRUD |
| `lark-base/` | larksuite/cli | 飞书多维表格 |
| `lark-sheets/` | larksuite/cli | 飞书电子表格 |
| `lark-wiki/` | larksuite/cli | 飞书知识库管理 |
| `lark-whiteboard/` | larksuite/cli | 飞书画板 |
| `lark-drive/` | larksuite/cli | 飞书云空间 |
| `lark-extend/` | larksuite/cli | 飞书本地覆盖约定 |
| `lark-calendar/` | larksuite/cli | 飞书日历 |
| `caveman/` | vinvcn/mattpocock-skills-zh-CN | 超压缩输出模式 |
| `diagnose/` | vinvcn/mattpocock-skills-zh-CN | 纪律化 debug 循环 |
| `grill-me/` | vinvcn/mattpocock-skills-zh-CN | 设计审查 interview |
| `improve-codebase-architecture/` | vinvcn/mattpocock-skills-zh-CN | 架构深化优化 |
| `write-a-skill/` | vinvcn/mattpocock-skills-zh-CN | 创建新 skill |
| `zoom-out/` | vinvcn/mattpocock-skills-zh-CN | 代码全景视角 |

## 同步

```bash
bash ccconfig/init-skill.sh sync
```
