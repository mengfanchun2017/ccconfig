---
name: f-logme
user-invocable: true
description: 个人管理系统 — OKR 目标管理、Worklog 工作日志、Reflect 反思、SUM 周期/领域总结生成。数据存飞书 Base，输出到飞书文档。
allowed-tools: Bash, Read, Write, Edit, Agent, WebSearch, mcp__tavily__*, mcp__minimax__*
---

# f-logme — 个人管理系统

OKR → KR → Worklog → Reflect → SUM 五层架构，全部数据存飞书 Base。

## 架构

```
🎯 OKR（最高级）
   ├─ O: 方向性目标，季度/年度级别，变化慢
   └─ KR: 可量化关键结果，变化快，关联一个 O
        │
        ▼
📝 Worklog（日常记录）
   └─ 每条必须关联一个 KR，自动继承分类
        │
        ▼
🪞 Reflect（定期反思）
   └─ 周/月/季度，可选关联 O
        │
        ▼
📊 SUM（总结生成）双通道
   ├─ 个人总结: 读取以上三层 → 内置模板 → 飞书文档
   └─ 汇报输出: 学习外置模板 → Worklog+KR数据+用户输入 → 飞书文档
```

**核心原则**：
- O 回答 "why" — 为什么要做这些事
- KR 回答 "what success looks like" — 做成什么样算成功
- Worklog 回答 "what I did" — 具体做了什么
- Reflect 回答 "what I learned" — 学到了什么、哪里要改进
- SUM 回答 "what it means" — 把以上串成一个完整叙事

**分类体系**：所有层级共用 `work / learn / project` 三类。
- work: 公司工作、团队协作、业务交付
- learn: 学习、课程、论文、考试备考
- project: 个人秘密项目、side project

---

## 飞书资源

**Space ID**: `7626581506382728129`
**SUM 文档父目录**: `VPsDw42KsixH77kugfcc8FyInCh`（OKR Base v2 wiki 节点，所有 OKR/SUM 文档统一放此节点下）

### OKR Base v2（主：目标管理 + 反思 + SUM）🆕 2026-05-30

**Base token**: `LX5lb6VfdaJHWrsRbTgc8Y50nmj`
**URL**: https://<your-tenant>.feishu.cn/wiki/VPsDw42KsixH77kugfcc8FyInCh

| 表 | Table ID | 用途 |
|----|----------|------|
| OKR_O | `tbli0erWbDwrfiEj` | 长期目标（15个O：work×4, learn×6, project×5） |
| OKR_KR | `tblZhpELO31mAkg6` | 关键结果（23个KR，关联 O） |
| Worklog | `tblVsC0L7QFzMeYM` | 日常记录（关联 KR） |
| Reflect | `tblNLcyrOHD3OU87` | 定期反思（可选关联 O） |

**分类体系**：`work`（公司汇报）/ `learn`（个人学习）/ `project`（个人项目）
**变更追踪**：O 和 KR 表含 `创建日期` + `更新日期`，状态含 `Abandoned`（不删除，只废弃）
**视图**：OKR_O 含 4 个视图 — 表格（全部）/ 进行中（状态=Active）/ 公司汇报(work)（分类=work）/ 个人(private)（分类=learn+project）
**编号字段**：OKR_O 已删除；OKR_KR/Worklog/Reflect 因飞书 API 不支持修改主字段，已从所有视图隐藏

### AI 技能画像 Base（技能+职责匹配）🆕 2026-05-31

**Base token**: `QN7Ab0l68a0AqesmSAMcUgbynEh`
**URL**: https://<your-tenant>.feishu.cn/base/QN7Ab0l68a0AqesmSAMcUgbynEh
**用途**: AI 简历数据基础 — 记录工作内容与技能实践的匹配，可与 OKR Base v2 Worklog/Reflect 联动

| 表 | Table ID | 用途 |
|----|----------|------|
| SFIA技能库 | `tblVyKe0AvTMXZUQ` | SFIA 9 技能定义+当前/目标等级（22条） |
| 岗位职责 | `tblS49hdjYlAB2Gz` | 2024-2026 工作职责时间线（12条） |
| 技能匹配 | `tblN5Gv98uuC7Ui5` | 技能←→职责映射+熟练程度 |
| 技能证据 | `tbl5Jtdzrtwj8lXr` | 具体证据关联 OKR Base Worklog |

**四层架构**: SFIA技能库 → 技能匹配 ← 岗位职责 → 技能证据 ← OKR Base Worklog

### OKR Base v1（旧版，保留参考）

**Base token**: `L8wjb4CYRa1HeOsGx4BcIOFknyg`
**URL**: https://<your-tenant>.feishu.cn/base/L8wjb4CYRa1HeOsGx4BcIOFknyg

| 表 | Table ID | 用途 |
|----|----------|------|
| OKR_O | `tblC4ykRAWqBFGjt` | （旧）长期目标 |
| OKR_KR | `tblGODTVWxc3fwcI` | （旧）关键结果 |
| Worklog | `tblwuptJB1ZUNZOY` | （旧）日常记录 |
| Reflect | `tblFaF3kT7PgGCty` | （旧）定期反思 |

### Worklog Base（历史数据 + 简易记录）

**Base token**: `DLk8bb838ahfr3sF1UnchSHlnTf`
**Wiki URL**: https://<your-tenant>.feishu.cn/wiki/UQeFwqU5CibOCtkam4UceLgBn8g
**数据范围**: 2024-12 ~ 2026-01

| 表 | Table ID | 用途 |
|----|----------|------|
| 任务表 | `tblWNiZP1xWj1hdd` | 历史 worklog 记录 |
| 周报生成表 | `tbloq6yxz0cNI06p` | AI 辅助周报生成 |

**标题格式**（用于 ai分类 字段自动区分）：
- 成长类：`英文标识 中文描述`（如 `claudecode 模型分流配置和逻辑`），英文前缀触发飞书自动分类
- 工作类：纯中文描述（如 `云资源接入成本评估与方案对比`）
- ❌ 禁止 `【】` 括号前缀

**字段映射（任务表 → f-logme Worklog）**：

| 任务表字段 | → | f-logme 字段 | 说明 |
|-----------|----|-------------|------|
| 标题 | → | 标题 | 直接映射 |
| ai分类 | → | 分类 | 工作→work, 成长→learn |
| ai板块 | → | 领域标签 | agent/aiagent/workflow/architecture/... |
| 说明 | → | 说明 | 直接映射 |
| 完成日期 | → | 完成日期 | 直接映射 |
| ai链接 | → | — | 额外字段，f-logme 无对应 |
| 父记录 | → | — | 自关联，f-logme 无对应 |

## 数据模型

### OKR_O 表字段

| 字段 | 类型 | 说明 |
|------|------|------|
| 标题 | 文本 | Objective，方向性描述 |
| 分类 | 单选 | work / learn / project |
| 周期 | 单选 | 2026Q1, 2026Q2, 2026Q3, 2026Q4, 2026 Full Year |
| 状态 | 单选 | Active / Completed / Abandoned |
| 优先级 | 数字 | 1-5，1 最高 |
| 说明 | 多行文本 | 为什么这个 O 重要 |

### OKR_KR 表字段

| 字段 | 类型 | 说明 |
|------|------|------|
| 标题 | 文本 | KR，可量化结果 |
| 关联O | 关联列 → OKR_O | 必须关联一个 O |
| 周期 | 单选 | 与关联 O 对齐 |
| 类型 | 单选 | Committed (100% 必达) / Aspirational (70% 即成功) / Learning (探索性) |
| KR.PARA | 单选 | projects（交付）/ areas（持续）/ research（探索）/ archive（归档） |
| KR.状态 | 单选 | Active（进行中）/ Done（已完成）/ Cancelled（取消） |
| 关联ADR | 文本 | 引用 ADR 文档 token（多 ADR 用空格分隔） |
| 最终评分 | 数字 | 0.0-1.0，周期结束时填入 |
| 说明 | 多行文本 | KR 的上下文 |

**状态语义**：KR.状态是 KR 进展的唯一状态字段。完成 KR 时主动跑 `log_write.py kr-status --kr recXXX --status Done`，不靠 worklog/reflect 自动触发。

### Worklog 表字段

| 字段 | 类型 | 说明 |
|------|------|------|
| 标题 | 文本 | `claudecode 完成sum skill框架搭建` |
| 关联KR | 关联列 → OKR_KR | 必须关联一个 KR |
| 成果类型 | 单选 | 项目交付 / 技术方案 / 学习笔记 / 问题排查 / 会议沟通 / 文档输出 / 工具开发 |
| 量化结果 | 文本 | 可选。数字、百分比、前后对比 |
| 说明 | 多行文本 | 一句话说明做了什么 |
| 日期 | 日期 | 完成日期，唯一日期字段（无单独创建日期） |

> 分类（work/learn/project）和领域标签通过关联 KR→O 自动继承，不需要在 Worklog 里重复维护。

### Reflect 表字段

| 字段 | 类型 | 说明 |
|------|------|------|
| 标题 | 文本 | `2026Q2 Week 3 Reflect` |
| 周期类型 | 单选 | 周 / 月 / 季度 / 年 |
| 关联O | 关联列 → OKR_O | 可选 |
| 做得好 | 文本 | 这周/月/季度做得好的 |
| 待改进 | 文本 | 需要改进的地方 |
| 学到 | 文本 | 学到了什么 |
| 下阶段 | 文本 | 下阶段聚焦什么 |
| 日期 | 日期 | |

### KR_Progress 表字段 🆕 2026-06-04 → 已废弃 2026-06-09

KR 进度历史快照表已于 2026-06-09 废弃（[ADR-0003](file:///home/francis/git/ccconfig/docs/adr/0003-deprecate-tasks-and-kr-progress.md)）。设计反思：每 worklog +5% 的伪指标无法反映 KR 真实进展，与"3 状态"语义冲突。OKR_KR.进度 / 信心 字段同步删除。状态推进改为手动管理，详见 `log_write.py kr-status` 命令。

---

## 工作流

### 1. OKR 创建

```
用户: "新设一个 work 的 O：XXX，季度目标"
  → 在 OKR_O 表创建 Objective
  → 引导用户拆解 2-5 个 KR
  → 在 OKR_KR 表创建 KR，关联 O
  → 确认分类、周期、类型
```

**KR 写法检查**：
- ✅ "模型分流系统上线，P99 延迟降低 50%"
- ❌ "完成模型分流开发"（这是任务，不是结果）
- ✅ "CC小能手能自动生成季度工作总结"
- ❌ "写 sum skill"（这是活动，不是结果）

### 2. Worklog 写入

```
用户: "今天做了 X"
  → 判断分类（work/learn/project）
  → 列出活跃 KR 让用户选择关联
  → 调 log_write.py worklog 写入 Worklog 表
  → 可选填写量化结果
```

**与 f-worklog 的关系**：f-logme 是 f-worklog 的升级版。f-worklog 已废弃，所有 worklog 操作统一用 f-logme。

### 3. Reflect 写入

```
用户: "做周反思" / "weekly reflect"
  → 拉取本周 Worklog 记录
  → 拉取关联 KR（用于 Reflect 关联 KR 字段，非自动改 KR 状态）
  → 引导填写四个象限：做得好 / 待改进 / 学到 / 下阶段
  → 可选关联 O
  → 调 log_write.py reflect 写入 Reflect 表
  → 注: 不自动改 KR 状态，KR 完成时主动跑 kr-status
```

### 4. SUM 总结生成

SUM 分两条通道：

```
用户说"生成X总结"
  ├─ 个人总结（模板内置）→ 工作流 4a
  └─ 汇报输出（模板外置）→ 工作流 4b
```

#### 4a. 个人总结（模板内置）

周期/领域/OKR复盘/年报，模板写在本 skill 中。

```
用户: "生成本季度工作总结"
  → 确定周期和分类
  → 拉取 OKR_O → OKR_KR → Worklog → Reflect
  → 按内置模板填充
  → 委托 f-doc 创建飞书文档
```

| 类型 | 触发示例 | 模板侧重 |
|------|---------|---------|
| 周期总结 | "生成本季度工作总结" | 时间维度：做了什么、成果、不足、下阶段 |
| 领域总结 | "生成 AI 领域年度总结" | 领域维度：该领域所有 worklog 聚合 |
| OKR 复盘 | "复盘 Q2 OKR" | O 达成度、KR 评分、经验教训 |
| 综合年报 | "生成年度个人报告" | 三分类汇总 + 成长轨迹 + 新年 OKR |

#### 4b. 汇报输出（模板外置，飞书文档模板）

**模板即飞书文档**。用户创建模板文档 → 我 fetch 学习其结构/格式/风格 → 生成时照模板结构填入数据。

**模板位置**：OKR wiki 节点 `VPsDw42KsixH77kugfcc8FyInCh` 下的「模板」文件夹。

**工作流**：

```
用户: "生成周报" / "写月报" / "做季度汇报"
  → Step 1: 定位模板
      → 搜索 OKR wiki 节点下「模板」文件夹
      → 匹配模板名（周报/月报/季度/年度/专项）
  → Step 2: 学习模板
      → fetch 模板文档，提取结构（H1/H2 层级、表格、固定文案）
      → 理解每个 section 的数据需求
  → Step 3: 拉取数据
      → 确定时间范围（本周/本月/本季度）
      → 从 OKR Base 拉取 work 分类 Worklog
      → 拉取关联 KR 信息（标题/状态/最终评分）
      → 用户补充上下文（对话中提供）
  → Step 4: 生成
      → 按模板结构写 Markdown，数据替换、固定文案保留
      → 委托 f-doc 创建飞书文档（父目录 = OKR wiki 节点）
```

**模板学习要点**：
- 层级结构（几级标题、什么顺序）
- 表格格式（几列、列标题、数据粒度）
- 固定文案（部门名称、栏目名、说明文字）→ 原样保留
- 数据区域（哪里填 worklog 内容、哪里填 KR 状态、哪里留给用户补充）
- 风格（PPT 风格【】标题、量化指标偏好、叙述详略）

**数据填充优先级**：
1. 模板结构（骨架，不动）
2. Worklog 数据（主体内容，从 Base 拉）
3. KR 状态 / 最终评分（量化结果，从 Base 拉）
4. 用户输入（补充背景/重点，对话中获取）

**模板索引**（创建后追加）：

| 模板名 | 文档链接 | 用途 |
|--------|---------|------|
| — | — | — |

---

## 内置模板（个人总结用）

### 周期总结模板

```markdown
## {周期} {分类}总结（{时间范围}）

### OKR 达成
| O | KR | 状态 | 评分 |
|----|-----|------|------|
{从 OKR 表拉取}

### 核心成果
{从 Worklog 按成果类型分组，STAR 格式重写 top 5}
- 成果类型分布：项目交付 X 项 / 技术调研 Y 项 / 学习输入 Z 项

### 量化总览
- 总记录数：X
- 涉及 KR：Y 个
- 完成率：Z%

### 反思
{从 Reflect 提取关键洞察}

### 下阶段计划
{从 Reflect 的下阶段聚焦 + OKR 的下一周期目标}
```

### 领域总结模板

```markdown
## {年度} {领域} 专项总结

### 概述
{领域标签下的 worklog 总量、时间分布、KR 覆盖}

### 关键里程碑
{按时间线列出该领域最重要的 3-5 个成果}

### 能力积累
{从 Reflect 和 Worklog 的成果类型提取}

### 明年规划
{关联到该领域的下一年 OKR}
```

### OKR 复盘模板

```markdown
## {周期} OKR 复盘

### O1: {标题}
| KR | 类型 | 评分 | 备注 |
|----|------|------|------|
| KR1: xxx | Aspirational | 0.7 | |
| KR2: xxx | Committed | 1.0 | |

### 总体评估
- 平均评分：X
- Committed 达成率：Y%
- Aspirational 达成率：Z%

### 做得好的

### 待改进的

### 下周期调整
```

---

## Base 初始化

新建 Bitable 后有一张默认空表 "数据表"。**推荐直接复用默认表**，不要创建新表再删默认表。

### 推荐方案：Rename + 加字段

```bash
# 1. 重命名默认表
lark-cli base +table-update --base-token $T --table-id "数据表" --name "OKR_O" --as user

# 2. 给第一张表加字段
lark-cli base +field-create --base-token $T --table-id tblXXX \
  --json '{"field_name":"分类","type":"select","options":[{"name":"work","color":0},{"name":"learn","color":1}]}'

# 3. 创建其余表（第2张起）
lark-cli base +table-create --base-token $T --as user --name "OKR_KR" --fields '[...]'
```

**为什么不用 "新建+删默认" 方案**：
- 默认表 "数据表" 是最后一张表时无法删除（"A base must keep at least one table"）
- 新建→删默认需要 2 步 2 次 API；rename 只需 1 步，字段直接加到重命名后的表上
- 新 Base 默认没有 workflow / dashboard，无需处理

### 踩坑记录

| 默认项 | 是否存在 | 能否删除 |
|--------|---------|---------|
| 默认空表 "数据表" | ✅ 有 | ✅ 可删（但至少保留1张表） |
| 默认 workflow | ❌ 无 | ❌ lark-cli 无 `+workflow-delete`，API 无 DELETE endpoint |
| 默认 dashboard | ❌ 无 | ✅ `+dashboard-delete --yes` |

---

## 数据写入脚本

`log_write.py` — 统一封装 worklog / reflect / kr-status 三个写入动作。**不自动改 KR 字段**（KR 状态手动管理）。

```bash
SCRIPT="python3 $HOME/git/ccconfig/link/skills/f-logme/log_write.py"

# 写 worklog
$SCRIPT worklog --title "完成 X" --kr recXXXX --type "项目交付" --note "..." --date 2026-06-12

# 写 reflect（含批量关联 KR，仅写入关联字段，不改 KR.状态）
$SCRIPT reflect --title "Q2 W3" --period "周" \
  --good "..." --improve "..." --learned "..." --next "..." \
  --batch-kr recXXX recYYY --date 2026-06-12

# 改 KR.状态（Active → Done / Cancelled 时手动跑）
$SCRIPT kr-status --kr recXXXX --status Done
```

**设计原则**：
- worklog/reflect 只写入对应表，不联动其他表 / 字段
- KR 状态推进靠用户主动判断，不靠累积量自动涨
- 量化指标（最终评分）改在季度末手填 KR.最终评分 字段

## 命令速查

### Base 操作（lark-cli）

```bash
export LARKSUITE_CLI_CONFIG_DIR="$HOME/.lark-cli-<account>"
export PATH="$HOME/.local/bin:$PATH"
```

#### OKR Base（目标管理 + 反思 + 状态管理）

```bash
T="LX5lb6VfdaJHWrsRbTgc8Y50nmj"

# 拉取 OKR_O
lark-cli base +record-list --base-token $T --table-id tbli0erWbDwrfiEj --as user

# 拉取 OKR_KR（含关联 O）
lark-cli base +record-list --base-token $T --table-id tblZhpELO31mAkg6 --as user

# 拉取 Worklog
lark-cli base +record-list --base-token $T --table-id tblVsC0L7QFzMeYM --as user --limit 200

# 拉取 Reflect
lark-cli base +record-list --base-token $T --table-id tblNLcyrOHD3OU87 --as user

# 写数据：统一用 log_write.py（见上面「数据写入脚本」）
```

#### Worklog Base（历史数据）

```bash
W="DLk8bb838ahfr3sF1UnchSHlnTf"

# 拉取全部历史 worklog
lark-cli base +record-list --base-token $W --table-id tblWNiZP1xWj1hdd --as user --format json --limit 200 2>&1 | sed '/^\[lark-cli\]/d' > /tmp/worklog_history.json

# 写入新记录（字段: 标题, ai分类, ai板块, 说明, 完成日期）
cat > /tmp/wl2.json << 'EOF'
{"fields":["标题","ai分类","ai板块","说明","完成日期"],
 "rows":[["claudecode xxx",["成长"],["agent"],"说明","2026-05-29"]]}
EOF
cd /tmp && lark-cli base +record-batch-create --base-token $W --table-id tblWNiZP1xWj1hdd --as user --json @wl2.json
```

### SUM 生成流程

**Step 1: 拉取 Base 数据**

```bash
export LARKSUITE_CLI_CONFIG_DIR="$HOME/.lark-cli-<account>"
export PATH="$HOME/.local/bin:$PATH"
T="L8wjb4CYRa1HeOsGx4BcIOFknyg"
D=/tmp/sum_$(date +%s) && mkdir -p $D

lark-cli base +record-list --base-token $T --table-id tbli0erWbDwrfiEj --as user --format json --limit 200 2>&1 | sed '/^\[lark-cli\]/d' > $D/okr_o.json
lark-cli base +record-list --base-token $T --table-id tblZhpELO31mAkg6 --as user --format json --limit 200 2>&1 | sed '/^\[lark-cli\]/d' > $D/okr_kr.json
lark-cli base +record-list --base-token $T --table-id tblVsC0L7QFzMeYM --as user --format json --limit 200 2>&1 | sed '/^\[lark-cli\]/d' > $D/worklog.json
lark-cli base +record-list --base-token $T --table-id tblNLcyrOHD3OU87 --as user --format json --limit 200 2>&1 | sed '/^\[lark-cli\]/d' > $D/reflect.json
```

**Step 2: 生成 Markdown**

```bash
# 周期总结（Q2 工作）
python3 ccconfig/link/skills/f-logme/sum_generate.py \
  --okr-o $D/okr_o.json --okr-kr $D/okr_kr.json \
  --worklog $D/worklog.json --reflect $D/reflect.json \
  --period 2026Q2 --category work --type period \
  --output $D/summary.md

# 领域总结（AI 领域）
python3 ccconfig/link/skills/f-logme/sum_generate.py \
  --okr-o $D/okr_o.json --okr-kr $D/okr_kr.json \
  --worklog $D/worklog.json --reflect $D/reflect.json \
  --type domain --domain learn --year 2026 \
  --output $D/summary.md

# OKR 复盘
python3 ccconfig/link/skills/f-logme/sum_generate.py \
  --okr-o $D/okr_o.json --okr-kr $D/okr_kr.json \
  --worklog $D/worklog.json --reflect $D/reflect.json \
  --period 2026Q2 --type okr-review \
  --output $D/summary.md

# 年度综合报告
python3 ccconfig/link/skills/f-logme/sum_generate.py \
  --okr-o $D/okr_o.json --okr-kr $D/okr_kr.json \
  --worklog $D/worklog.json --reflect $D/reflect.json \
  --type annual --year 2026 \
  --output $D/summary.md
```

**Step 3: 委托 f-doc 创建飞书文档**

f-logme 不自己调 `lark-cli docs +create`。将生成的 Markdown 交给 f-doc skill，由 f-doc 统一编排 lark-cli 创建飞书文档。f-doc 自动处理表格宽度（822px）、标题层级（≤H3）、文档父目录等格式化规则（详见 f-doc skill 格式约束）。

## 集成点

| 系统 | 关系 |
|------|------|
| f-worklog | 简化版，f-logme 是其升级替代 |
| f-doc | SUM 输出目标：飞书文档，统一编排 lark-cli（不直接依赖 lark-* skill） |
| f-ppt | 年度总结可选输出 PPT |
| f-research-domain | 领域总结前可联动做行业调研 |
| lark-cli | 所有飞书操作（文档/Base/表格/日历）通过 lark-cli（npm 全局） |

## 文档创建规则

SUM 生成飞书文档时，**必须通过 f-doc skill 创建**（不裸调 lark-cli），原因：
- f-doc → lark-doc → lark-doc-style.md 加载链保证格式化规则完整进 context
- f-doc skill 被调用时加载，提供父目录/标题/表格等基础规则
- 直接裸调会丢失格式化约束，导致编号标题、分割线、窄表格等问题

f-logme 职责：从 Base 聚合数据 → 按模板填 Markdown → 交给 f-doc 创建文档。

---

## 线上文档索引

> 每生成一份 SUM 文档，追加到下表。格式：`[标题](url) | 日期`

| 标题 | 链接 | 日期 |
|------|------|------|
| 2026Q2 项目总结（SUM 测试） | https://<your-tenant>.feishu.cn/docx/XFvtd6UzToMNHexryw5cOuolnsk | 2026-05-29 |
| OKR+Worklog 管理系统说明（原迁移计划） | https://<your-tenant>.feishu.cn/docx/JFBedI4aCoIbKgxYzzbc9P2Fn3q | 2026-05-30 → 05-31 更新 |

> 数据源：OKR Base / Worklog Base 见「飞书资源」章节。

---

## 历史数据迁移（2026-05-30 v2 重建）

旧 Worklog Base（`DLk8bb838ahfr3sF1UnchSHlnTf`）的 200 条记录（2024-12 ~ 2026-01）已分析并反推为 14 个 O + 21 个 KR，写入新 Base v2。

O/KR 结构覆盖了旧 worklog 的所有主题聚类：
- 工作 → O1 AI平台建设, O2 日常需求交付
- 成长 → O5 AI工具链, O6 Coze深潜, O7 系统分析师
- 其余 learn/project O 从当前工作延伸

**迁移完成**（2026-05-31）：200 条旧记录按 KR+标题相似度聚类合并为 74 条，覆盖 16 个 KR。合并策略：同 KR 内相似主题归并，说明含日期标记 `【YYYY-MM-DD】`，不丢信息。

### 变更追踪机制

- O 和 KR 表含 `创建日期` + `更新日期` 字段
- 状态含 `Abandoned` 选项：**不删除，只废弃**，保留完整历史轨迹
- `周期` 字段按时间分组（2025H1/H2, 2026Q1-4, 2026 Full Year, 2027）
- 按周期筛选可纵向对比各阶段的目标演进

---

## 当前状态

> 每次操作后更新此节。

| 指标 | 值 | 最后更新 |
|------|-----|---------|
| Base | OKR Base v2 `LX5lb6VfdaJHWrsRbTgc8Y50nmj` | 2026-06-12 |
| OKR_O 记录 | 15（work×4, learn×6, project×5） | 2026-05-31 |
| OKR_KR 记录 | 23 | 2026-05-31 |
| Worklog 记录 | 74（200条旧记录合并迁移，关联16个KR） | 2026-05-31 |
| Reflect 记录 | 0 | 2026-05-31 |
| 写入脚本 | `log_write.py`（worklog/reflect/kr-status 三命令，2026-06-12 去伪指标改造） | 2026-06-12 |
| 活跃周期 | 2026Q2 | — |
| 旧 Worklog Base | `DLk8bb838ahfr3sF1UnchSHlnTf`（200条, 2024-12 ~ 2026-01） | 保留参考 |
| 旧 OKR Base v1 | `L8wjb4CYRa1HeOsGx4BcIOFknyg` | 保留参考 |

## 参考

- John Doerr, *Measure What Matters* (2018)
- Google re:Work OKR Guide
- Perdoo OKR Guide (2026)
- Julia Evans, Brag Documents
- Tiago Forte, PARA Method
