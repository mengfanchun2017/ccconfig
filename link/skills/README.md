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

| Skill | 来源 | 用途 |
|-------|------|------|
| `lark-shared/` | larksuite/cli | 飞书基础：认证、多账号 |
| `lark-doc/` | larksuite/cli | 飞书云文档 CRUD |
| `lark-base/` | larksuite/cli | 飞书多维表格 |
| `lark-sheets/` | larksuite/cli | 飞书电子表格 |
| `lark-wiki/` | larksuite/cli | 飞书知识库管理 |
| `lark-whiteboard/` | larksuite/cli | 飞书画板 |
| `lark-drive/` | larksuite/cli | 飞书云空间 |
| `lark-calendar/` | larksuite/cli | 飞书日历 |
| `caveman/` | vinvcn/mattpocock-skills-zh-CN | 超压缩输出模式 |
| `diagnose/` | vinvcn/mattpocock-skills-zh-CN | 纪律化 debug 循环 |
| `grill-me/` | vinvcn/mattpocock-skills-zh-CN | 设计审查 interview |
| `improve-codebase-architecture/` | vinvcn/mattpocock-skills-zh-CN | 架构深化优化 |
| `write-a-skill/` | vinvcn/mattpocock-skills-zh-CN | 创建新 skill |
| `zoom-out/` | vinvcn/mattpocock-skills-zh-CN | 代码全景视角 |

## 同步

```bash
bash ccconfig/init-skill.sh sync          # symlink → ~/.claude/skills/
bash ccconfig/init-skill.sh marketplace   # 外部 skill 的 marketplace 安装命令
```

## Marketplace 集成（2026-06-05 新增）

ccconfig 是**工作副本**（git 同步，符号链接加载）。claude-skills 是**发布渠道**（marketplace 自动跟上游同步）。

| 类别 | 安装方式 | 更新方式 |
|------|---------|---------|
| 自建 + 公开 (f-doc/f-ppt/...) | 符号链接（ccconfig 默认） | git pull ccconfig |
| 自建 + 公开 (同上) | 也可 marketplace 装 | `claude plugin marketplace update` |
| 自建 + 私有 (f-logme) | 仅符号链接（ccconfig 私有） | git pull ccconfig |
| 外部 (lark-*/caveman/...) | 符号链接（ccconfig 兼容）| git pull ccconfig（已记录 skills-lock.json）|
| 外部 (同上) | **推荐 marketplace 装** | `claude plugin marketplace update <your-github-username>-skills` |

外部 skill 在 ccconfig 和 marketplace 装哪个都行，**不重复装**（Claude Code 会冲突）。`init-skill.sh marketplace` 列出去重后的安装命令。
