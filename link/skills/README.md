# skills/ — Skills

> Claude Code 技能定义，通过符号链接到 `~/.claude/skills/`。
> 自建 skill 多数同时发布到 [<your-github-username>/claude-skills](https://github.com/<your-github-username>/claude-skills) marketplace（公私双轨，ccconfig 是工作副本，marketplace 是发布渠道）。

## 一级：f-* 编排层（自建）

| Skill | 用途 | 发布 |
|-------|------|------|
| `f-doc/` | 统一文档入口 — 创建/更新/合并/拆分/转换/对比 | ✅ marketplace |
| `f-ppt/` | PPT 生成 — 双引擎（ppt-master + OfficeCLI）| ✅ marketplace |
| `f-research/` | 统一研究框架 — 三源搜索、自动领域判断 | ✅ marketplace |
| `f-research-deep/` | 深度研究 — 批量 JSON 输出 | ✅ marketplace |
| `f-research-report/` | 报告生成 — JSON → Markdown | ✅ marketplace |
| `f-pdf/` | PDF 内容提取原语 — 文字/图片/元数据 | ✅ marketplace |
| `f-vessel/` | AI 浏览器操控 | ✅ marketplace |
| `f-logme/` | 个人管理系统 — OKR/Worklog/Reflect/SUM | 🔒 **私有**（含飞书 tenant + Base ID）|
| `f-worklog/` | [已废弃] 工作日志 — 请用 f-logme | — |
| ~~`f-feedme/`~~ | ~~智能订餐助手（麦当劳）~~ | [2026-06-05 已删，niche 价值低] |
| ~~`f-feedmeng/`~~ | ~~二次元虚拟点餐~~ | [2026-06-05 已删，未实现] |

## 二级：第三方 skill

**已从本目录移走，2026-06-05 改 marketplace 装**（避免 symlink + marketplace 冲突）。详见下方"Marketplace 集成"。

| Skill | 官方源 | 装法 |
|-------|-------|------|
| `lark-shared` / `lark-doc` / `lark-base` / `lark-sheets` / `lark-wiki` / `lark-whiteboard` / `lark-drive` / `lark-calendar` | [larksuite/cli](https://github.com/larksuite/cli) | `npm install -g @larksuite/cli`（拿完整 CLI + skill）|
| `caveman` / `diagnose` / `grill-me` / `improve-codebase-architecture` / `write-a-skill` / `zoom-out` | [vinvcn/mattpocock-skills-zh-CN](https://github.com/vinvcn/mattpocock-skills-zh-CN) | 走 [<your-github-username>/claude-skills](https://github.com/<your-github-username>/claude-skills) marketplace |

## 同步

```bash
bash ccconfig/init-skill.sh sync            # symlink 自建 skill → ~/.claude/skills/
bash ccconfig/init-skill.sh install         # 一键装 marketplace 外部 skill（执行 claude plugin install）
```

## Marketplace 集成（2026-06-05 新增）

ccconfig/link/skills/ **只保留自建 skill**（7 个 f-* + f-logme 私有）。外部 skill（lark-*/vinvcn 6 个）**已从本目录移除**，统一从 marketplace 装，避免 symlink 重复。

| 类别 | 位置 | 装法 |
|------|------|------|
| 自建 + 公开 (f-doc/f-ppt/...) | ccconfig/link/skills/ | `init-skill.sh sync`（默认 symlink）|
| 自建 + 私有 (f-logme) | ccconfig/link/skills/ | `init-skill.sh sync`（只在本机）|
| 外部 (lark-*) | [larksuite/cli](https://github.com/larksuite/cli) | `npm install -g @larksuite/cli` |
| 外部 (vinvcn 6 个) | [claude-skills marketplace](https://github.com/<your-github-username>/claude-skills) | `init-skill.sh install`（一键装）|
