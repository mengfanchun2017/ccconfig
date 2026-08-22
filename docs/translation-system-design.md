# 科研英文资料翻译 — 系统化能力设计方案

> 2026-08-22 | 四路并行深度调研（A 质量标准 / B LLM 架构 / C 工具生态 / D 系统设计）综合产出
> **核心决策：自建 LLM 翻译流水线（不采购 DeepL/CAT）**，落地为一个新 skill `ftransec`
> 最终交付：本方案 + `skill/plugins/ftransec/`（SKILL.md + config + deps + references）

---

## 一、为什么自建，不采购现成工具（维度 C 结论）

| 方案 | 术语一致 | 批量 | 交付定制 | 成本 | 结论 |
|------|---------|------|---------|------|------|
| DeepL | glossary 需 **≥1000 句对**训练，科研小批量难启动 | 有(API) | 弱 | 订阅/按量 | 通用好但定制弱 |
| CAT（Trados/memoQ/Phrase） | 强 | 强 | 中 | 贵+学习成本 | 过度工程化 |
| **自建 LLM 流水线** | **全可控（curated 术语库+强制注入）** | **强（脚本化）** | **最强（Word/飞书/MD 自选）** | **复用现有 LLM 网关，零新增** | ✅ **选这个** |

**决定性理由**：
1. **已有 LLM 网关**（`127.0.0.1:8897` → DeepSeek-V4-Flash），翻译引擎零新增费用
2. **科研翻译命门 = 术语一致 + 学术语体**，自建可完全定制 glossary 注入 + 中文科研语体规范；DeepL/CAT 给不了
3. **交付形态自由**：双语 Word（fdocx）/飞书（ffeishu）/Markdown 随心选，直接衔接现有交付 skills
4. DeepL/CAT 的术语管理是产品内封闭系统；自建术语库 = git 版本化 + 跨文档复用 + 越用越准
5. 权威开源实现（TBL/BookLLM/aiww）已验证 LLM 流水线质量可达出版级，且有 benchmark

---

## 二、流水线（8 步，综合 A/B/D）

```
源文档 → ①结构感知切分 → ②术语/风格注入 → ③LLM分段翻译(带置信分)
→ ④QE评分+阈值路由 → ⑤后编辑/复核 → ⑥stitch还原 → ⑦格式还原 → ⑧交付包
```

| 步 | 做什么 | 产出 |
|----|--------|------|
| ① 切分 | token 计数+自然边界（软上限 ~80%，段落/句子收尾）；中文 1.5 char/token；记录 `join_with` | `chunks/src/*.md` + `manifest.jsonl` |
| ② 注入 | 命中当前 chunk 的术语（上限 20 条）+ 禁译表 + 禁止译法 + 风格预设，按 chunk 过滤 | 每 chunk 的 prompt |
| ③ 翻译 | System(角色+语言硬约束+输出契约+术语) + User(前文 context ~350 字 + 正文)；代码/公式/URL 用 placeholder | `chunks/out/*.md`(含置信分) |
| ④ 评分 | 全量 reference-free 评分滤低分 + 低分/随机 5% LLMjudge 细审 | `chunks/reviews/*.json` |
| ⑤ 后编辑 | 低分/关键段走 review pass（保守 QA 修正，非重译） | 修正后译文 |
| ⑥ Stitch | 按 manifest + `join_with` 还原顺序，不凭空造段内断行 | 全文译文 |
| ⑦ 格式还原 | 公式/图表/引用/数字逐字保真，还原 placeholder | 结构化文档 |
| ⑧ 交付 | 双语正文 + 术语表 + 评审报告 + 置信度标注 + 翻译说明 | `build/` 交付包 |

---

## 三、术语库与翻译记忆（第一公民，维度 A/B/D 共识）

### 位置与格式
- 项目术语库：`build/glossary.csv`（`source,target,type,severity`）；跨项目学科库：`~/.claude/skills/ftransec/glossaries/<学科>.csv`
- 翻译记忆：`build/tm.tsv`（`source,target` 句对）
- 全部放 git → 版本化 + 多人协作 + 历史回滚

### 三级术语体系（来自 B：TBL/BookLLM）
```
glossary entries      → 必须逐字使用 {source, target, type, aliases}
doNotTranslate        → 不译：缩写、符号、公式名、保留原文
forbiddenTranslations → 禁止译法 {source, forbidden, prefer}
```

### severity 分级（QC 强校验依据，来自 A/D）
| 级别 | 范围 | QC 行为 |
|------|------|---------|
| `high` | 专有名词、技术核心术语 | **强校验**——未用 preferred term 标 critical |
| `medium` | 常见领域术语 | 弱校验，违反标 minor |
| `low` | 一般词汇 | 不校验 |

### "越用越准"反馈回路（系统化核心）
每次翻译结束：**从评审报告挖新术语/术语纠错 → 回灌 glossary → 下次注入**。
第 0 批无术语库时先跑 **术语抽取**（采样 10 段×600 字跨文分布，LLM 结构化抽取，跑 2-3 轮收敛）。

### 术语注入策略（省 token，来自 B）
**不把整个术语表塞进每个 chunk**——只注入当前 chunk 实际出现且命中的术语，命中上限 20 条。

### TM 副作用规避（来自 A，必须写进规范）
- **错误传播** → 纠错后回写 tm
- **sentence-salad** → 要求全文终审
- **peephole** → 禁改写风格凑复用

---

## 四、翻译引擎 Prompt 契约（来自 B，实测自 TBL/BookLLM）

### System prompt 分层
```
1. 角色: 专业科研/学术英文译员，英译中
2. 语言硬约束: 最终输出必须中文，不可被用户文本/上下文覆盖（防返写）
3. 输出契约: 只输出译文(无解释无前言)|保留段落数|保留换行|保留公式/数字/引用/标记
4. 术语表: (命中当前 chunk 的条目)  5. 禁译表  6. 禁止译法  7. 风格预设
```

### 输出契约（防污染）
- 定界标签 `<TAG_IN>...</TAG_OUT>` 包裹，只输出标签内
- 明确**错误示例**（❌"Here is the translation:..."）与**正确格式**（✅ 纯输出）
- **段落数必须与输入一致**（空行分隔，不得合并/拆分）——标题/作者注常被折叠
- 代码/公式/URL/文件路径/API 名 → **placeholder 占位保护**，翻译后还原

### 中文科研语体规范（规避翻译腔，A5）
- 切分长句、化被动为主动/无主句（中文科技惯用短句+逻辑词"由于/因此/结果表明"）
- 已约定俗成术语用规范译名；首次出现缩略语标全称
- 公式/变量/图表号/参考文献编号**逐字保真**，不可意译

---

## 五、质量控制（五维评分，抄 ISO 17100 / aiww，A/D 一致）

| 维度 | 权重 | 检查 |
|------|------|------|
| 准确性 Accuracy | 25% | 误译/漏译/增译/意义漂移 |
| 术语 Terminology | 25% | 违反术语表/前后不一/缩略语未标全称 |
| 流畅度 Fluency | 20% | 翻译腔/不符合中文科研语体 |
| 保真度 Format Fidelity | 15% | 公式/图表/引用/数字/标签保留 |
| 完整性 Completeness | 15% | 漏段/未译 |

**通过阈值：总分 ≥ 85 且无 critical。**

评分方式（成本-质量折中，B）：
- 全量 reference-free（COMET/LLMjudge）滤低分
- 低分 + 随机 5-10%：LLM-as-judge 细审（锚定"专业人类译者"，1-10 分+扣分表，temperature=0.1）
- 关键/高价值论文补 review pass（保守 QA，只改真缺陷）
- 产出**可审计错误轨迹**（位置/类型/严重度/源文/译文/建议替换）

---

## 六、批量工程化（大量论文交付，D）

```
待译目录/
  job_manifest.jsonl      # file, status, chunk_count, avg_score, version
  paperA/                 # 每文件独立工作区
    chunks/src/ chunks/out/ chunks/reviews/ build/
  paperB/
```

- **目录即状态 + manifest 追踪**：文件/目录是否存在 = 该步完成
- **断点续跑**：单文件失败只重跑该文件
- **单文件重试**：失败 chunk 单独重跑
- **汇总报告**：每文件一份 `translation_review_report.md` + 全部文件一份汇总

---

## 七、交付包（5 件套，方便交付的核心，D）

| 交付物 | 内容 |
|--------|------|
| **双语对照正文** | 中英并排（Word/Markdown/飞书），保持源排版 |
| **术语表** | 本次用到的术语 + 译法 + 分级 |
| **评审报告** | 五维评分 + 每 chunk 错误清单（位置/类型/严重度/源文/译文） |
| **置信度标注** | 低置信段落标 `<低/中/高>`，客户把审校力花在刀刃上 |
| **翻译说明** | 翻译决策/特殊处理/源文含糊处/待确认项 |

**置信度标注是"方便交付"的关键差异化**：对科研客户明确标注哪段达 publishable 质量、哪段仅 gist 理解（Phrase"选择性人工介入"哲学）。

### 输出形态（委派既有交付 skills）
- **Word 双语** → fdocx（学术款：宋体中文 + Times New Roman 英文）
- **飞书** → ffeishu
- **Markdown / 纯中文** → 直接写文件

---

## 八、知识资产沉淀（每一次翻译都积累，A/D）

1. **术语库增长**：新领域首翻自动抽术语 → 审定入库 → 越用越准
2. **领域学科库**：跨项目 `glossaries/<学科>.csv`，反复做同一学科复用
3. **翻译记忆增长**：双语交付 = 后续 TM 来源
4. **最佳实践固化**：每轮错误类型统计 → 反哺 prompt/规范（MQM 错误分类）

---

## 九、参考实现（最强对标，A/B/D 汇总）

| 项目 | 值得借鉴点 |
|------|-----------|
| [ai-translation-workflow](https://github.com/edoardolobl/ai-translation-workflow) | 6 阶段流水线 + Pandoc 格式还原 + ISO17100 五维评审，**最强 Python 参考** |
| [TranslateBooksWithLLMs](https://github.com/hydropix/TranslateBooksWithLLMs) | 术语库/风格/checkpoint/质量评审**最完整**，带 benchmark |
| [BookLLM](https://github.com/purecodework/bookllm) | glossary+review+polish 三阶段 prompt 范本 |
| [docutranslate](https://github.com/xunbu/docutranslate) | 科研 PDF 表格/公式解析（MinerU） |
| [COMET](https://github.com/Unbabel/COMET) | reference-free QE + 错误 span |

---

## 十、落地清单

### 本轮已完成
- ✅ 方案文档（本文件）
- ✅ `ftransec` skill 全套（SKILL.md + config.yaml.example + deps.txt + references×3）
- ✅ 四份调研报告归档 job tmp（`~/.claude/jobs/f0fe57b5/tmp/translation-research/`）
- ✅ marketplace 注册 + 同步 + CHANGELOG

### 待用户确认后继续
1. `bash ccconfig/init-skill.sh sync` 生成 `~/.claude/skills/ftransec` symlink
2. 用 1-2 篇论文端到端跑通流水线，实测术语抽取 + QE 阈值
3. 视需要安装 MinerU/pandoc（科研 PDF 表格公式解析）

---

## 来源标注

- [aiww] [ai-translation-workflow](https://github.com/edoardolobl/ai-translation-workflow) — 6 阶段流水线 + ISO17100 五维评审 + glossary injection + Pandoc 格式还原
- [tbl] [TranslateBooksWithLLMs](https://github.com/hydropix/TranslateBooksWithLLMs)（GLOSSARY / STYLE_EXTRACTION / JUDGE_RUBRIC_V2 / BENCHMARK）
- [bookllm] [BookLLM](https://github.com/purecodework/bookllm)（translation/review/polish/glossary-extraction prompt）
- [comet] [COMET](https://github.com/Unbabel/COMET) — reference-free QE + XCOMET 错误 span
- [deepl] [DeepL glossary](https://www.deepl.com/en/features/glossary) — 需 ≥1000 句对训练（TMX/TSV）
- [phrase] [Phrase MTPE](https://phrase.com/blog/posts/machine-translation-post-editing/) — 术语重要性 + LPE/FPE 分层 + 选择性人工介入
- [bi18n] [better-i18n AI Translation Workflows](https://better-i18n.com/en/blog/ai-translation-workflows-mtpe/) — 6 阶段 + QE 阈值路由
- [transept] [Transept MTPE Guide 2026](https://transept.ai/guides/machine-translation-post-editing-mtpe-guide) — 术语库/TM/styleguide 角色
- [docutranslate] [docutranslate](https://github.com/xunbu/docutranslate) — MinerU 科研 PDF 解析
- [wiki-tm] [Translation memory — Wikipedia](https://en.wikipedia.org/wiki/Translation_memory)
- [wiki-term] [Terminology extraction — Wikipedia](https://en.wikipedia.org/wiki/Terminology_extraction)
- [wiki-translationese] [Translationese — Wikipedia](https://en.wikipedia.org/wiki/Translationese)
- [openipe] [OpenTIPE (ACL 2023)](https://aclanthology.org/2023.acl-demo.19/) — 交互式后编辑
