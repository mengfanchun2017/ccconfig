# skills/ — Skills 双源聚合

> Claude Code skill 通过 **symlink（自建）+ claude plugin install（外部）** 两条路，聚合到 `~/.claude/skills/` 和 `claude plugin list`。
> `bash init-skill.sh sync` 一条命令搞定两路（幂等）。

## 来源 1：ccconfig 私有（symlink 装到 `~/.claude/skills/`）

**在 `link/skills/` 仓内实体**，symlink 装。**新增/修改**直接 git 提交即可生效。

| Skill | 用途 | 发布 |
|-------|------|------|
| `f-doc/` | 统一文档入口 — 创建/更新/合并/拆分/转换/对比 | ✅ marketplace 公开 |
| `f-ppt/` | PPT 生成 — 双引擎（ppt-master + OfficeCLI）| ✅ marketplace 公开 |
| `f-pdf/` | PDF 内容提取原语 — 文字/图片/元数据 | ✅ marketplace 公开 |
| `f-research/` | 统一研究框架 — 三源搜索、自动领域判断 | ✅ marketplace 公开 |
| `f-research-deep/` | 深度研究 — 批量 JSON 输出 | ✅ marketplace 公开 |
| `f-research-report/` | 报告生成 — JSON → Markdown | ✅ marketplace 公开 |
| `f-report-std/` | 报告写作横向规范（4 套模板）| ✅ marketplace 公开 |
| `f-vessel/` | AI 浏览器操控 | ✅ marketplace 公开 |
| `f-logme/` | 个人管理系统 — OKR/Worklog/Reflect/SUM | 🔒 **私有**（含飞书 tenant + Base ID）|
| `skill-template/` | 脚手架（开发用）| — 不发布 |

**8 个公开自建**会同步到 [<your-github-username>/claude-skills](https://github.com/<your-github-username>/claude-skills) marketplace。

## 来源 2：claude-skills marketplace 聚合（auto install via `sync`）

**不在本仓**，装时从 marketplace 拉。`init-skill.sh sync` 阶段 2/3 装好。

| 类别 | Skill | 来源仓 | 装法 |
|------|-------|--------|------|
| vinvcn 6 | `caveman` / `diagnose` / `grill-me` / `improve-codebase-architecture` / `write-a-skill` / `zoom-out` | [vinvcn/mattpocock-skills-zh-CN](https://github.com/vinvcn/mattpocock-skills-zh-CN) | marketplace（auto）|
| lark-* 8 | `lark-shared` / `lark-doc` / `lark-base` / `lark-sheets` / `lark-wiki` / `lark-whiteboard` / `lark-drive` / `lark-calendar` | [larksuite/cli](https://github.com/larksuite/cli) | marketplace（auto）+ 配 [lark-cli](https://www.npmjs.com/package/@larksuite/cli) CLI（`update.sh` 月度更新）|

> **lark-* 与 lark-cli 关系**：lark-* 是 Claude Code 编排层（`metadata.requires.bins: ["lark-cli"]`），lark-cli 是系统层 CLI 工具。**两者独立，都必须装**。lark-cli 缺失会让 lark-* skill 触发时报 "command not found"。

## 同步

```bash
bash ccconfig/init-skill.sh sync      # 一次性：symlink 8 自建 + 装 14 external（幂等 ~2s）
bash ccconfig/init-skill.sh cleanup   # 单独清 ~/.claude/skills/ 断链
bash ccconfig/init-skill.sh status    # 状态总览
```

**首次跑 sync**（新机器）：
1. 阶段 1：symlink 8 自建到 `~/.claude/skills/`
2. 阶段 2：`claude plugin marketplace add <your-github-username>/claude-skills`
3. 阶段 3：装 14 个 external plugin（`claude plugin install <plugin>@<your-github-username>-skills`）
4. 耗时 ~30s

**之后跑 sync**：~2s（全部幂等 skip）

## 架构

```
~/.claude/skills/                       ← symlink (来源 1)
   f-doc → ../../git/ccconfig/link/skills/f-doc
   f-logme → ...
   ...
   
claude plugin list                      ← marketplace install (来源 2)
   f-pdf@<your-github-username>-skills
   f-vessel@<your-github-username>-skills
   caveman@<your-github-username>-skills
   ...
   lark-doc@<your-github-username>-skills      (lark-* skill)
   ...

+ lark-cli (system)                     ← npm 全局 (独立, update.sh 管)
```

**设计意图**：
- **symlink 装自建**：本地工作副本直接生效，git 改 = ~/.claude/skills/ 改
- **marketplace 装外部**：避免重复维护（lark-* 跟 larksuite/cli 仓自动同步，vinvcn 跟 mattpocock-skills-zh-CN 自动同步）
- **claude plugin list 看到全部**：跟拆分前 UX 一致
