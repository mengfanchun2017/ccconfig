---
name: f-launch
user-invocable: true
description: |
  项目启动 skill — 从意图到可运行项目的全流程(类型判断 → 脚手架 → OKR → 风险)。
  覆盖 8 类项目模板:static-web-personal / web-api-backend / cli-tool /
  ai-agent-tool / data-pipeline / mobile-app / desktop-app / game。
  Use when 用户说"新项目" / "建项目" / "scaffold" / "项目启动" /
  "项目立项" / "我想做一个 X" / "init project"。
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# f-launch — 项目启动 skill

将"想做一个 X"转成"~/git/<name>/ + CLAUDE.md + OKR + 风险清单"的标准产物。

## 项目约束

命名、脚手架、文档规范见本 SKILL.md 工作流步骤。

## 快速决策

```
用户意图
  ├─ "新项目" / "建项目" / "scaffold"      → 工作流 A: 全流程启动
  ├─ "添加类型模板"                        → 工作流 B: 扩展 references/
  └─ "查看已有项目" / "列出我的项目"        → 工作流 C: 扫描 ~/git/
```

## 工作流 A:全流程启动(主流程)

### Step 1:类型判断

读 `references/types.md` 获取 8 类项目特征。向用户问 1-2 题确认类型。

### Step 2:加载类型模板

读 `references/<type>.md` 拿到:
- 场景描述
- 默认技术栈
- 脚手架目录结构
- OKR 模板
- 风险点清单
- 真实案例参考

### Step 3:询问项目元数据

| 字段 | 说明 |
|------|------|
| 项目代号 | `~/git/<代号>/`,kebab-case |
| 一句话目标 | 写进 CLAUDE.md + OKR.O |
| 合规层级 | 个人/学习 / 商业 / 金融医疗政企 |
| 是否需要飞书输出 | 是 → 调 f-doc 生成 wiki 报告 |

### Step 4:脚手架生成

调用 `bash init.sh scaffold <代号> <类型>` 生成:
```
~/git/<代号>/
├── CLAUDE.md          # AI 行为指南(必填)
├── README.md          # 项目说明
├── ROADMAP.md         # 开发路线图(Now/Next/Phase 2/3/Later)
├── LICENSE            # MIT/Apache
├── .gitignore         # 按类型定制
├── .editorconfig      # 统一编辑器风格
├── docs/
│   ├── plan.md        # 8 周计划(适用大项目)
│   └── adr/           # 架构决策记录(按需)
└── <类型专属目录>     # src/ / app/ / data/ 等
```

### Step 5:OKR 关联(可选)

调 f-logme skill,在 OKR Base 写 1 个 O + 2-3 个 KR。Worklog 关联 KR。

### Step 6:风险点输出

按类型模板的"风险点"段输出 5 项 + 缓解。

### Step 7:memory 记录

写到 `~/.claude/projects/-home-francis-git/memory/project_<代号>.md`,更新 MEMORY.md 索引。

---

## 8 类项目模板

| 代号 | 场景 | 默认栈 | 真实案例 |
|------|------|--------|----------|
| `static-web-personal` | 个人静态 web(礼物/纪念/展示) | HTML+CSS+JS ESM + Leaflet + Supabase(可选) + R2(可选) | [[project-name]] |
| `web-api-backend` | Web 后端 API(CRUD/REST) | Node 22 + Hono + Drizzle + Zod + Vitest | [[project-name]] |
| `cli-tool` | CLI 工具 | Node (TypeScript) / Go / Rust | (待补) |
| `ai-agent-tool` | AI Agent / 工具调用 | Python + Claude API / LangChain | (待补) |
| `data-pipeline` | 数据 / ML Pipeline | Python + Airflow / Dagster | (待补) |
| `mobile-app` | 移动 App | React Native / Flutter | (待补) |
| `desktop-app` | 桌面 App | Electron / Tauri | (待补) |
| `game` | 游戏 | Godot / Unity | (待补) |

类型详情 → `references/<type>.md`

---

## 工作流 B:添加类型模板

1. 在 `references/<new-type>.md` 写新模板(场景/默认栈/脚手架/OKR/风险/案例)
2. 在 SKILL.md"8 类项目模板"表加一行
3. 在 `references/types.md` 加类型描述
4. 提交 PR 到 ccconfig 仓

## 工作流 C:扫描已有项目

```bash
for dir in ~/git/*/; do
  if [[ -d "$dir/.git" ]]; then
    name=$(basename "$dir")
    type=$(grep -l "类型:" "$dir/CLAUDE.md" 2>/dev/null && head -1 "$dir/CLAUDE.md" | grep "类型:" || echo "未分类")
    echo "$name — $type"
  fi
done
```

---

## 关联 Skills

- `f-logme` — OKR 关联
- `f-doc` — 飞书 wiki 报告输出
- `f-research-domain` — 技术选型(中大型项目)
- `f-report-gen` — 立项报告生成

## 用户配置

编辑 `config.yaml` 可配置:
- `default_license`: 默认 LICENSE(MIT/Apache/None)
- `git_init`: 是否自动 git init
- `wiki_report`: 是否默认生成飞书 wiki
- `okr_association`: 是否默认关联 f-logme OKR

---

## 线上文档索引(占位)

> f-launch 生成的飞书文档每次追加

| 标题 | 链接 | 日期 | 说明 |
|------|------|------|------|
| Web 后端 CRUD/REST API 技术栈选型报告 | <飞书文档 URL> | 2026-06-11 | web-api-backend 类型的技术选型示例 |
