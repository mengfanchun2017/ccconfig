---
name: f-moocrec
description: MOOC 课程推荐助手 — 基于 QS 世界排名顶级学府课程体系，为学生生成个性化 MOOC 学习路径。课程数据存 Supabase（共享），学生画像/进度存飞书 Wiki + Base（个人持久化）。Use when 用户说"课程推荐"/"MOOC"/"在线课程"/"自学路径"/"学习规划"、问"有什么好的网课"/"想系统学生物"。
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Agent, WebSearch, WebFetch, mcp__tavily__tavily_search, mcp__minimax__web_search, mcp__supabase__execute_sql
---

# f-moocrec — MOOC 课程推荐助手

> 用全球最好大学的 MOOC 重建生物科学教育。无论在哪所学校，真心喜欢这个专业的同学都可以学到最好的知识。

## 架构

```
Supabase (共享课程数据)              飞书 (学生个人数据)
┌──────────────────────┐           ┌──────────────────────────┐
│ courses 表             │──SQL查询→│ 学生画像 Wiki Doc          │
│ 40+ 门课元数据          │          │ 学习路径 Wiki Doc          │
│ 定期更新/多学生共享     │          │ 学习进度 Base Table        │
└──────────────────────┘           └──────────────────────────┘
```

**资源配置**: `conf/f-moocrec.json` — 飞书 token（wiki node、doc tokens、base token、table ID）

### 配置文件管理（硬规则）

`conf/*.json` 含真实 token → **只能存 ccprivate/conf/，通过 symlink 覆盖**。ccconfig 只提交 `*.example` 模板。

```
真实配置: ccprivate/conf/f-moocrec.json
模板:     ccconfig/conf/f-moocrec.json.example（可提交）
运行时:   ccconfig/conf/f-moocrec.json → symlink → ccprivate/conf/f-moocrec.json
```

**更新配置后**：
- ❌ 绝不 `git add conf/f-moocrec.json`（symlink 被 pre-commit hook 阻止）
- ✅ 只在 ccprivate 仓库提交真实配置
- ✅ ccconfig 只提交 `.example` 模板更新

## 快速决策树

```
用户: /f-moocrec
  ├─ conf/f-moocrec.json 不存在 或 docs.profile 为空
  │   → 工作流 0: 首次使用 — grill me + 创建飞书资源
  │
  ├─ 已有配置
  │   ├─ "推荐课程"/"下一门"/"接下来学什么"
  │   │   → 工作流 1: 课程推荐
  │   ├─ "完成了"/"拿到证书了"/"学完了"
  │   │   → 工作流 2: 记录进度
  │   ├─ "更新画像"/"改了方向"/"换了兴趣"
  │   │   → 工作流 3: 更新画像
  │   ├─ "进度"/"学了哪些"/"还差多少"
  │   │   → 工作流 4: 查看进度
  │   └─ "证书"/"背书"/"认证"
  │       → 工作流 5: 证书建议
```

## 工作流 0: 首次使用 — Grill Me

**触发**: `conf/f-moocrec.json` 无有效个人配置

### Step 0.1: Grill 问答

逐题提问，等用户回答后再问下一题：

```
Q1: 你叫什么名字？在哪个学校？几年级？（大一/大二/大三/大四/研究生）
Q2: 生物科学里你最感兴趣的方向？
    选项: 分子生物学 / 遗传学 / 细胞生物学 / 生物化学 / 神经科学
         / 免疫学 / 微生物学 / 生态与进化 / 生物信息学 / 不确定先都看看
Q3: 英语水平？能跟上全英文授课吗？
    选项: 完全没问题 / 需要中文字幕辅助 / 最好中文课程
Q4: 每周能投入多少小时学 MOOC？
    选项: 3-5h / 5-10h / 10-15h / 15h+
Q5: 职业方向？
    选项: 科研（读博） / 医学院（临床） / 生物技术公司 / 教育 / 不确定
Q6: 预算偏好？
    选项: 完全免费（旁听为主） / 关键课程愿意付费拿证书 / 证书对我很重要适度付费 / 不限预算
```

根据答案推导 `subject_areas`（兴趣→课程领域映射）：

| 兴趣方向 | subject_area 筛选 |
|---------|------------------|
| 分子生物学 | molecular_biology, biochemistry, cell_biology |
| 遗传学 | genetics, genomics, epigenetics |
| 细胞生物学 | cell_biology, molecular_biology, biochemistry |
| 生物化学 | biochemistry, chemical_biology, proteomics |
| 神经科学 | neuroscience, cell_biology |
| 免疫学 | immunology, cell_biology, molecular_biology |
| 微生物学 | microbiology, molecular_biology, genetics |
| 生态与进化 | evolution, ecology |
| 生物信息学 | bioinformatics, genomics, computational_biology |

### Step 0.2: 查询 Supabase 课程

```bash
# 用 Python 调 Supabase 管理 API 查询（mcp__supabase__execute_sql 可能不可用时的 fallback）
python3 -c "
import json, requests
sql = '''SELECT name, name_zh, university, platform, url, subject_area, stage, difficulty,
         duration_weeks, hours_per_week, language, has_chinese_subtitle,
         free_option, certificate_option, certificate_price_usd, certificate_platform,
         rating, prerequisites
         FROM courses WHERE is_active = true AND stage IN (''foundation'',''core'')
         ORDER BY stage, id'''
r = requests.post('https://api.supabase.com/v1/projects/<your-supabase-project-id>/database/query',
    headers={'Authorization': 'Bearer <your-supabase-access-token>',
             'Content-Type': 'application/json'},
    json={'query': sql}, timeout=15)
print(json.dumps(r.json(), ensure_ascii=False))
"
```

按学生画像筛选：
- 英语弱 → 优先 `language='zh'` 或 `has_chinese_subtitle=true`
- 时间少 → 优先 `duration_weeks` 短 + `difficulty='beginner'`
- 特定兴趣 → `WHERE subject_area IN (...)` 
- 预算敏感 → `ORDER BY certificate_price_usd ASC NULLS FIRST`

### Step 0.3: 创建飞书个人空间

**必须先调 f-doc Skill**（飞书规则硬前置条件）。

创建资源顺序：

1. **创建 Base + 进度表**
```bash
export LARKSUITE_CLI_CONFIG_DIR="$HOME/.lark-cli-<account>"
export PATH="$HOME/.local/bin:$PATH"

# 创建 Base
lark-cli base +base-create --name "MOOC学习进度" --as user 2>&1 | sed '/^\[lark-cli\]/d'
# 保存 base_token

# 重命名默认表为 progress
lark-cli base +table-update --base-token $BASE_TOKEN --table-id "数据表" --name "进度" --as user

# 添加字段（逐个）
lark-cli base +field-create --base-token $BASE_TOKEN --table-id $TBL --json '{"field_name":"平台","type":"select","options":[{"name":"Coursera","color":0},{"name":"edX","color":1},{"name":"MIT OCW","color":2},{"name":"中国大学MOOC","color":3},{"name":"其他","color":4}]}'
# ... 其他字段见 Step 0.4
```

2. **创建 Wiki 节点**（在已有 Wiki space 下）
```bash
lark-cli wiki +node-create --space-id $SPACE_ID --parent-node-token $ROOT_NODE \
  --title "MOOC 生物科学" --obj-type docx --as user
# 保存 wiki_node token
```

3. **创建学生画像 Wiki Doc**
```bash
cat << 'EOF' | lark-cli docs +create --api-version v2 \
  --parent-token $WIKI_NODE --as user --doc-format markdown --content - \
  --title "学生画像 - <姓名>"

# 学生画像 - <姓名>

| 字段 | 值 |
|------|-----|
| 姓名 | ... |
| 专业 | 生物科学 |
| 年级 | ... |
| 学校 | ... |
| 兴趣方向 | ... |
| 英语水平 | ... |
| 每周时间 | ... |
| 职业目标 | ... |
| 预算偏好 | ... |
| 创建日期 | YYYY-MM-DD |
EOF
```

4. **创建学习路径 Wiki Doc**
```bash
cat << 'EOF' | lark-cli docs +create --api-version v2 \
  --parent-token $WIKI_NODE --as user --doc-format markdown --content - \
  --title "生物科学 MOOC 学习路径"

# 生物科学 MOOC 学习路径

> 基于 QS 2026 生物科学 Top5 课程体系
> 学生: <姓名> | 生成日期: YYYY-MM-DD

## 阶段一：数理基础

| # | 课程 | 学校 | 平台 | 免费方案 | 证书方案 | 价格 | 时间 |
|---|------|------|------|---------|---------|------|------|
...
EOF
```

### Step 0.4: 进度 Base Table 字段定义

| 字段名 | 类型 | options/配置 |
|--------|------|-------------|
| 课程名称 | text (主字段) | — |
| 平台 | select | Coursera, edX, MIT OCW, 中国大学MOOC, 其他 |
| 大学 | text | — |
| 阶段 | select | 基础, 核心, 进阶, 前沿 |
| 领域 | select | 生物化学, 遗传学, 分子生物学, 细胞生物学, 神经科学, 免疫学, 生物信息学, 进化生物学, 基因组学, 其他 |
| 状态 | select | 📋计划中, 📖学习中, ✅已完成, ❌已放弃 |
| 轨道 | select | 免费旁听, 付费证书 |
| 开始日期 | datetime | — |
| 完成日期 | datetime | — |
| 证书URL | url | — |
| 投入时间 | number | 小时 |
| 评分 | rating (1-5) | — |
| 备注 | text | — |

### Step 0.5: 写配置

```python
# 更新 conf/f-moocrec.json
config = {
    "lark_cli": {"config_dir": "~/.lark-cli-<account>"},
    "tenant_domain": "<your-tenant>.feishu.cn",
    "space_id": "<space_id>",
    "wiki_node": "<wiki_node_token>",
    "docs": {
        "profile": "<profile_doc_token>",
        "path": "<learning_path_doc_token>"
    },
    "base": {
        "token": "<base_token>",
        "tables": {"progress": "<table_id>"}
    }
}
```

### Step 0.6: 输出

展示：
1. 学习路径概要（4 阶段结构 + 推荐第一门课）
2. 所有飞书文档链接
3. "下次输入 `/f-moocrec` 即可查看进度或获取推荐"

---

## 工作流 1: 课程推荐

**触发**: 用户已有配置，想要课程推荐

### 1.1 读取当前状态

```bash
# 读 Supabase 获取全部活跃课程
# 读飞书 Base 获取已有进度 → 排除已完成的课
# 读飞书 Wiki 获取学生画像 → 获取兴趣/英语/时间
```

### 1.2 推荐逻辑

```
已完成的课 → 标记 ✅，不重复推荐
正在学的课 → 标记 📖，询问是否继续还是跳过
尚未开始的课 → 按画像排序推荐
```

推荐优先级：
1. **先修课已完成** → 排在前面
2. **匹配兴趣方向** → 加权
3. **难度匹配**（beginner 适合新生） → 加权
4. **时间合适** → 加权
5. **语言匹配** → 加权

输出格式：
```
📚 下一阶段推荐：

**优先推荐**（先修条件已满足）：
1. ⭐ <课程名> — <学校> · <平台>
   难度: beginner | 时间: 6周×5h | 语言: 英文(中字)
   免费: <免费方案>
   证书: <证书方案> — $XX (Credly 徽章)
   为什么推荐: <理由>

**可选**（匹配你的兴趣但需先修）：
...

每门课可以深入问："/f-moocrec <课程名> 详情"
```

---

## 工作流 2: 记录学习进度

**触发**: 用户说完成了某门课 / 拿到了证书

### 2.1 确认信息

```
确认: MITx 7.00x Introduction to Biology
- 完成日期？
- 是免费旁听还是付费证书？
- 有证书链接吗？
- 投入了多少小时？
- 1-5 分打几分？
```

### 2.2 写飞书 Base

```bash
lark-cli base +record-batch-create --base-token $B --table-id $T \
  --json '{"fields":["课程名称","平台","大学","阶段","领域","状态","轨道","完成日期","证书URL","投入时间","评分"],"rows":[["Introduction to Biology - The Secret of Life","edX","MIT","core","general_biology","✅已完成","付费证书","2026-08-15","https://...",96,5]]}'
```

### 2.3 更新学习路径 doc

用 `lark-cli docs +update --command str_replace` 在路径 doc 中标记完成状态：
```bash
# 找到对应课程行，替换状态标记
lark-cli docs +update --api-version v2 --doc $PATH_DOC \
  --command str_replace --pattern "⬜ <课程名>" --content "✅ <课程名>" --as user
```

### 2.4 推荐下一门

自动触发工作流 1（课程推荐）。

---

## 工作流 3: 更新学生画像

**触发**: 用户想改画像信息

读现有画像 doc → 只更新变化的字段 → `lark-cli docs +update --command str_replace`
```bash
lark-cli docs +fetch --api-version v2 --doc $PROFILE --detail simple
# 定位要更新的行 → str_replace
lark-cli docs +update --api-version v2 --doc $PROFILE \
  --command str_replace --pattern "| 兴趣方向 | 旧值 |" --content "| 兴趣方向 | 新值 |" --as user
```

---

## 工作流 4: 查看学习进度

**触发**: 用户想看整体进度

### 4.1 查询 Base

```bash
lark-cli base +record-list --base-token $B --table-id $T --format json --limit 200
```

### 4.2 统计汇总

```
📊 学习进度总览

总课程: 38 门（Supabase 课程库）
已完成: X 门 | 进行中: Y 门 | 计划中: Z 门

阶段完成度:
  基础 ████████░░ 6/8
  核心 ████░░░░░░ 3/14
  进阶 ██░░░░░░░░ 1/10
  前沿 ░░░░░░░░░░ 0/6

证书获取: N 门付费证书，总花费 $XXX
总投入: XXX 小时
```

---

## 工作流 5: 证书背书建议

**触发**: 用户询问证书相关

### 5.1 证书分级

| 级别 | 建议 | 哪些课 |
|------|------|--------|
| ⭐⭐⭐ 强烈建议付费 | 核心主干课，证书对求职/升学有明显背书 | MITx 7.00x, HarvardX Biochemistry, MITx Genetics |
| ⭐⭐ 值得考虑 | 进阶课，领域内知名度高 | Duke Neuroscience, JH Genomics |
| ⭐ 免费足够 | 数理基础课、补充课 | MIT OCW 数学, 中国大学MOOC |

### 5.2 证书验证机制

- **edX**: 每张证书有唯一 URL（`https://courses.edx.org/certificates/...`），任何人可点击验证
- **Coursera + Credly**: 徽章含区块链哈希，可在 Credly 平台永久验证，可一键挂 LinkedIn
- **中国大学MOOC**: 证书在 icourse163.org 可查询

### 5.3 LinkedIn 展示

指导用户：
1. edX 证书 → Dashboard → "Share on LinkedIn"
2. Credly 徽章 → Accept badge → "Add to Profile"
3. 手动添加 → LinkedIn "Licenses & Certifications" → 填入证书 URL

---

## 课程推荐格式约束

生成学习路径/课程推荐时：

1. **表格必须 XML + colgroup=822**（飞书 Wiki 渲染要求）
2. **不手动编号**（飞书自动编号）
3. **不用 H4+**（最深 H3）
4. **不用 `---` 分割线**
5. **课程链接必须是完整可点击 URL**
6. **每门课必须同时列出免费方案和证书方案**（双轨）
7. **证书信息必须包含验证方式**

## 飞书操作委派规则

| 操作 | 执行者 | 命令/工具 |
|------|--------|----------|
| 创建 wiki doc | f-doc skill（先调 Skill） | `lark-cli docs +create` |
| 更新 wiki doc | f-doc skill（先调 Skill） | `lark-cli docs +update --command str_replace` |
| 创建 Base/表 | f-moocrec 直接 | `lark-cli base +base-create` |
| 写进度记录 | f-moocrec 直接 | `lark-cli base +record-batch-create` |
| 读进度记录 | f-moocrec 直接 | `lark-cli base +record-list --format json` |
| 课程查询 | f-moocrec 直接 | Supabase API 或 `mcp__supabase__execute_sql` |
| 课程搜索/更新 | f-moocrec 直接 | Tavily/WebSearch |

**关键**: 写飞书 doc 前必须先调 `f-doc` Skill（全局飞书规则硬前置条件）。Base 操作不需要。

## 常见陷阱

| ❌ 错误 | ✅ 正确 |
|---------|--------|
| `lark-cli docs +create --markdown` | `--doc-format markdown --content -` |
| `--folder-token` 用于 wiki | `--parent-token` + wiki node token |
| 不调 f-doc 直接裸调 lark-cli docs | 先 `Skill("f-doc")` 再执行 lark-cli |
| Supabase REST API 直连 | 用管理 API (`api.supabase.com`) + access token |
| stderr 被当作错误 | lark-cli 日志行在 stdout，WSL 注入行需过滤 |
| `--content` 中换行符直接写 | 用 heredoc `cat << 'EOF' \| lark-cli ...` |

## 课程数据库维护

### 查询 Supabase

```bash
# 管理 API（推荐，因为 service_role key 不在本地）
curl -s "https://api.supabase.com/v1/projects/<your-supabase-project-id>/database/query" \
  -H "Authorization: Bearer <your-supabase-access-token>" \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT * FROM courses WHERE stage='\''core'\'' ORDER BY id;"}'
```

### 添加新课程

```sql
INSERT INTO courses (...) VALUES (...);
```

### 刷新课程状态

```sql
UPDATE courses SET is_active = true, last_verified_date = CURRENT_DATE WHERE url LIKE '%edx.org%';
```

## 参考文件

- `references/bio-curriculum.md` — 完整课程体系 + 先修关系图
- `references/certificate-guide.md` — 证书获取、验证、LinkedIn 挂载
- `references/platform-guide.md` — 平台定价、免费策略、语言支持对比
- `scripts/bio-progress.py` — Base 进度读写 Python 工具
- `scripts/seed-courses.sql` — 课程表初始化 SQL
