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
📊 SUM（总结生成）
   └─ 读取以上三层 → 按模板生成周期/领域总结 → 飞书文档
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

**Base token**: `L8wjb4CYRa1HeOsGx4BcIOFknyg`
**Base URL**: https://<your-tenant>.feishu.cn/base/L8wjb4CYRa1HeOsGx4BcIOFknyg
**SUM 文档父目录**: `<your-feishu-wiki-token>`（Claude 工作 wiki）
**Space ID**: `7626581506382728129`

| 表 | Table ID | 用途 |
|----|----------|------|
| OKR_O | `tblC4ykRAWqBFGjt` | 长期目标（季度/年度） |
| OKR_KR | `tblGODTVWxc3fwcI` | 关键结果（关联 O） |
| Worklog | `tblwuptJB1ZUNZOY` | 日常记录（关联 KR） |
| Reflect | `tblFaF3kT7PgGCty` | 定期反思（可选关联 O） |

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
| 进度 | 进度条 | 0-100%，手动或公式 |
| 信心 | 单选 | On Track / At Risk / Blocked / Done |
| 最终评分 | 数字 | 0.0-1.0，周期结束时填入 |
| 说明 | 多行文本 | KR 的上下文 |

### Worklog 表字段

| 字段 | 类型 | 说明 |
|------|------|------|
| 标题 | 文本 | `claudecode 完成sum skill框架搭建` |
| 关联KR | 关联列 → OKR_KR | 必须关联一个 KR |
| 成果类型 | 单选 | 项目交付 / 技术调研 / 学习输入 / 故障应急 / 团队建设 / 其他 |
| 量化结果 | 文本 | 可选。数字、百分比、前后对比 |
| 说明 | 多行文本 | 一句话说明做了什么 |
| 完成日期 | 日期 | |

> 分类（work/learn/project）和领域标签通过关联 KR→O 自动继承，不需要在 Worklog 里重复维护。

### Reflect 表字段

| 字段 | 类型 | 说明 |
|------|------|------|
| 标题 | 文本 | `2026Q2 Week 3 Reflect` |
| 周期类型 | 单选 | Weekly / Monthly / Quarterly |
| 关联O | 关联列 → OKR_O | 可选 |
| 做得好 | 文本 | 这周/月/季度做得好的 |
| 待改进 | 文本 | 需要改进的地方 |
| 学到 | 文本 | 学到了什么 |
| 下阶段 | 文本 | 下阶段聚焦什么 |
| 日期 | 日期 | |

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
  → 写入 Worklog 表
  → 可选填写量化结果
```

**与 f-worklog 的关系**：f-logme 是 f-worklog 的升级版。旧的 f-worklog（简单写日志到 Base）仍可用，但推荐用 f-logme，因为它强制关联 KR。

### 3. Reflect 写入

```
用户: "做周反思" / "weekly reflect"
  → 拉取本周 Worklog 记录
  → 拉取关联 KR 的进度
  → 引导填写四个象限：做得好 / 待改进 / 学到 / 下阶段
  → 可选关联 O
```

### 4. SUM 总结生成

```
用户: "生成本季度工作总结"
  → 确定周期（Q1/Q2/H1/2026）和分类（work/learn/project）
  → 拉取 OKR_O（本周期 + 本分类）
  → 拉取 OKR_KR（关联到上述 O）
  → 拉取 Worklog（本周期 + 关联到上述 KR）
  → 拉取 Reflect（本周期 + 本分类）
  → 按模板生成 Markdown
  → **委托 f-doc skill 创建飞书文档**（格式化规则通过 f-doc→lark-doc 链加载）
```

**支持四种总结**：

| 类型 | 触发示例 | 模板侧重 |
|------|---------|---------|
| 周期总结 | "生成本季度工作总结" | 时间维度：做了什么、成果、不足、下阶段 |
| 领域总结 | "生成 AI 领域年度总结" | 领域维度：该领域所有 worklog 聚合 |
| OKR 复盘 | "复盘 Q2 OKR" | O 达成度、KR 评分、经验教训 |
| 综合年报 | "生成年度个人报告" | 三分类汇总 + 成长轨迹 + 新年 OKR |

---

## 模板

### 周期总结模板

```markdown
## {周期} {分类}总结（{时间范围}）

### OKR 达成
| O | KR | 进度 | 评分 |
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

## 命令速查

### Base 操作（lark-cli）

```bash
export LARKSUITE_CLI_CONFIG_DIR="$HOME/.lark-cli-<account>"
export PATH="$HOME/.local/bin:$PATH"
T="L8wjb4CYRa1HeOsGx4BcIOFknyg"

# 拉取 OKR_O
lark-cli base +record-list --base-token $T --table-id tblC4ykRAWqBFGjt --as user

# 拉取 OKR_KR（含关联 O）
lark-cli base +record-list --base-token $T --table-id tblGODTVWxc3fwcI --as user

# 拉取 Worklog
lark-cli base +record-list --base-token $T --table-id tblwuptJB1ZUNZOY --as user --limit 200

# 拉取 Reflect
lark-cli base +record-list --base-token $T --table-id tblFaF3kT7PgGCty --as user

# 写入 Worklog（需关联 KR record ID）
cat > /tmp/wl.json << 'EOF'
{"fields":["标题","关联KR","成果类型","量化结果","说明","完成日期"],
 "rows":[["claudecode xxx",[{"id":"recXXXX"}],"项目交付","","说明","2026-05-29"]]}
EOF
cd /tmp && lark-cli base +record-batch-create --base-token $T --table-id tblwuptJB1ZUNZOY --as user --json @wl.json
```

### SUM 生成流程

**Step 1: 拉取 Base 数据**

```bash
export LARKSUITE_CLI_CONFIG_DIR="$HOME/.lark-cli-<account>"
export PATH="$HOME/.local/bin:$PATH"
T="L8wjb4CYRa1HeOsGx4BcIOFknyg"
D=/tmp/sum_$(date +%s) && mkdir -p $D

lark-cli base +record-list --base-token $T --table-id tblC4ykRAWqBFGjt --as user --format json --limit 200 2>&1 | sed '/^\[lark-cli\]/d' > $D/okr_o.json
lark-cli base +record-list --base-token $T --table-id tblGODTVWxc3fwcI --as user --format json --limit 200 2>&1 | sed '/^\[lark-cli\]/d' > $D/okr_kr.json
lark-cli base +record-list --base-token $T --table-id tblwuptJB1ZUNZOY --as user --format json --limit 200 2>&1 | sed '/^\[lark-cli\]/d' > $D/worklog.json
lark-cli base +record-list --base-token $T --table-id tblFaF3kT7PgGCty --as user --format json --limit 200 2>&1 | sed '/^\[lark-cli\]/d' > $D/reflect.json
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

f-logme 不自己调 `lark-cli docs +create`。将生成的 Markdown 交给 f-doc skill，由其通过 f-doc → lark-doc 链创建文档。f-doc 会自动处理表格宽度（820px）、标题层级（≤H3）、文档父目录等格式化规则。

## 集成点

| 系统 | 关系 |
|------|------|
| f-worklog | 简化版，f-logme 是其升级替代 |
| f-doc | SUM 输出目标：飞书文档，创建前必须加载 lark-doc-style.md 格式化规则 |
| f-ppt | 年度总结可选输出 PPT |
| f-research | 领域总结前可联动做行业调研 |
| lark-cli | 所有 Base 读写通过 lark-cli |

## 文档创建规则

SUM 生成飞书文档时，**必须通过 f-doc skill 创建**（不裸调 lark-cli），原因：
- f-doc → lark-doc → lark-doc-style.md 加载链保证格式化规则完整进 context
- `rules/f-doc.md` 始终加载，提供父目录/标题/表格等基础规则
- 直接裸调会丢失格式化约束，导致编号标题、分割线、窄表格等问题

f-logme 职责：从 Base 聚合数据 → 按模板填 Markdown → 交给 f-doc 创建文档。

## 参考

- John Doerr, *Measure What Matters* (2018)
- Google re:Work OKR Guide
- Perdoo OKR Guide (2026)
- Julia Evans, Brag Documents
- Tiago Forte, PARA Method
