# 科研英文资料翻译 — 系统化能力设计方案

> 2026-08-22 | 四路并行深度调研（A 质量标准 / B LLM 架构 / C 工具生态 / D 系统设计）综合产出
>按学科分子库**（分子生物 / 机器学习 / 医学…），避免跨领域术语打架
- severity 分级（QC 强校验依据）：`high` 专有名词强校验 / `medium` 领域术语弱校验 / `low` 一般词汇不校验
- **越用越准反馈回路**：翻译前注入 → QC 强校验 → 交付后从评审报告挖新术语/纠错 → 回灌 glossary → 下次注入
- 第 0 批无术语库时：**术语抽取**（采样 10 段×600 字跨文分布，LLM 结构化抽取，跑 2-3 轮收敛）生成初始库

### 翻译记忆（跨文档复用）
- `build/tm.tsv`（source,target 句对），同领域论文批处理时复用 + 保一致
- **必须规避** TM 副作用：错误传播（纠错后回写）、sentence-salad（要求全文终审）、peephole（禁改写风格凑复用）

---

## 四、翻译引擎（Prompt 契约，来自 B + A）

### System prompt 分层
```
1. 角色: 专业科研/学术英文译员，英译中
2. 语言硬约束: 最终输出必须中文，不可被用户文本/上下文覆盖（防返写）
3. 输出契约: 只输出译文（无解释无前言）| 保留段落数| 保留换行| 保留全部公式/数字/引用/标记
4. 术语表: (命中当前 chunk 的条目)  5. 禁译表  6. 禁止译法  7. 风格预设
```

### 输出契约（防污染）
- 定界标签 `<TAG_IN>...</TAG_OUT>` 包裹，只输出标签内
- 明确**错误示例**（❌"Here is the translation:..."）与**正确格式**（✅ 纯输出）
- **段落数必须与输入一致**（空行分隔，不得合并/拆分）——标题/作者注常被模型折叠
- 代码/公式/URL/文件路径/API 名 → **placeholder 占位保护**，翻译后还原

### 中文科研语体规范（规避翻译腔，来自 A）
- 切分长句、化被动为主动/无主句（中文科技惯用短句+逻辑词"由于/因此/结果表明"）
- 已约定俗成术语用规范译名；首次出现缩略语标注全称
- 公式/变量/图表号/参考文献编号**逐字保真**，不可意译

---

## 五、质量控制（五维评分，抄 ISO 17100 / ai-translation-workflow）

| 维度 | 权重 | 检查 |
|------|------|------|
| 准确性 Accuracy | 25% | 误译/漏译/意义漂移 |
| 术语 Terminology | 25% | 违反术语表/前后不一 |
| 流畅度 Fluency | 20% | 翻译腔/不符合中文科研语体 |
| 保真度 Fidelity | 15% | 公式/图表/引用/数字保留 |
| 完整性 Completeness | 15% | 漏段/未译 |

**通过阈值：总分 ≥ 85 且无 critical。**

评分方式（成本-质量折中，来自 B）：
- 全量：reference-free 自动评分滤低分（COMET cometkiwi 或 LLM-judge）
- 低分 + 随机 5%：LLM-as-judge 细审（锚定"专业人类译者"，1-10 分 + 扣分表，temperature 0.1）
- 关键/高价值论文：补 review pass（保守 QA 修正，只改真缺陷）
- 每 chunk 产出**可审计错误轨迹**（含位置/类型/严重度/源文/译文/建议替换）

---

## 六、批量工程化（大量论文交付）

```
待译目录/
  job_manifest.jsonl      # file, status, chunk_count, avg_score, version
  paperA/                 # 每文件独立工作区
    chunks/src/ chunks/out/ chunks/reviews/ build/
  paperB/
    ...
```

- **目录即状态 + manifest 追踪**：文件/目录是否存在 = 该步是否完成
- **断点续跑**：单文件失败只重跑该文件
- **汇总报告**：每文件一份 `translation_review_report.md` + 全部文件一份总汇总

---

## 七、交付包（5 件套，方便交付的核心）

| 交付物 | 内容 |
|--------|------|
| **双语对照正文** | 中英并排（Word/Markdown/飞书），保持源排版 |
| **术语表** | 本次用到的术语 + 译法 + 分级 |
| **评审报告** | 五维评分 + 每 chunk 错误清单（位置/类型/严重度/源文/译文） |
| **置信度标注** | 低置信段落标 `<低/中/高>`，让客户把审校力花在刀刃上 |
| **翻译说明** | 翻译决策/特殊处理/源文含糊处/待确认项 |

**置信度标注是"方便交付"的关键差异化**：对科研客户明确标注哪段达 publishable 质量、哪段是 gist 级理解，"选择性人工介入"（Phrase 哲学）。

### 输出形态（委派既有交付 skills）
- **Word 双语** → fdocx（198 学术款：宋体中文 + Times New Roman 英文）
- **飞书** → ffeishu
- **Markdown / 纯中文** → 直接写文件

---

## 八、知识资产沉淀（每一次翻译都积累）

1. **术语库增长**：新领域首翻自动抽术语 → 审定入库 → 越用越准
2. **领域学科库**：跨项目 `glossaries/<学科>.csv`，反复做同一学科的翻译时复用
3. **翻译记忆增长**：双语交付 = 后续 TM 来源
4. **最佳实践固化**：每轮翻译的错误类型统计 → 反哺 prompt/规范

---

## 九、参考实现（最强对标）

| 项目 | 值得借鉴点 |
|------|-----------|
| [ai-translation-workflow](https://github.com/edoardolobl/ai-translation-workflow) | 6 阶段流水线，Pandoc 格式还原，**最强 Python 参考** |
| [TranslateBooksWithLLMs](https://github.com/hydropix/TranslateBooksWithLLMs) | 术语库/风格/checkpoint/质量评审**最完整**，带 benchmark |
| [BookLLM](https://github.com/purecodework/bookllm) | glossary+review+polish 三阶段 prompt 范本 |
| [docutranslate](https://github.com/xunbu/docutranslate) | 科研 PDF 表格/公式解析（MinerU） |

---

## 十、落地清单

### 立即（本轮）
- ✅ 方案文档已写（本文件）
- ✅ `ftransec` skill 骨架已建（`plugins/ftransec/SKILL.md`，`references/` `scripts/` 目录）

### 待用户确认后
1. 完成 `ftransec` skill 主体（8 步流水线 + prompt 契约 + 术语库 + QC + 交付包）
2. 注册进 marketplace.json + 同步 description + CHANGELOG
3. `config.yaml.example` + ccprivate 配置注入
4. 补充 `references/`（中文科研语体规范、术语抽取 prompt 模板、QC rubric）
5. `deps.txt` 声明依赖（pandoc/pdftotext/MinerU 按需）
6. 端到端验证：用 1-2 篇论文跑通流水线

---

## 来源标注

- [aiww] [ai-translation-workflow](https://github.com/edoardolobl/ai-translation-workflow) — 6阶段流水线+ISO17100五维评审+glossary injection
- [tbl] [TranslateBooksWithLLMs](https://github.com/hydropix/TranslateBooksWithLLMs)（GLOSSARY/STYLE_EXTRACTION/JUDGE_RUBRIC_V2/BENCHMARK 文档）
- [bookllm] [BookLLM](https://github.com/purecodework/bookllm)（translation/review/polish/glossary-extraction prompt）
- [comet] [COMET](https://github.com/Unbabel/COMET) — reference-free QE + XCOMET 错误 span
- [deepl] DeepL 定价 + glossary（需 ≥1000 句对训练）— www.deepl.com
- [phrase] [Phrase MTPE best practices](https://phrase.com/blog/posts/machine-translation-post-editing/) — 术语重要性 + LPE/FPE 分层
- [bi18n] [better-i18n: AI Translation Workflows](https://better-i18n.com/en/blog/ai-translation-workflows-mtpe/) — 6 阶段 + QE 阈值路由
- [transept] [Transept MTPE Guide 2026](https://transept.ai/guides/machine-translation-post-editing-mtpe-guide) — 术语库/TM/styleguide 角色
- [docutranslate] [docutranslate](https://github.com/xunbu/docutranslate) — MinerU 科研 PDF 解析
- [wiki-tm] [Translation memory — Wikipedia](https://en.wikipedia.org/wiki/Translation_memory)
- [wiki-term] [Terminology extraction — Wikipedia](https://en.wikipedia.org/wiki/Terminology_extraction)
- [opentipe] [OpenTIPE (ACL 2023)](https://aclanthology.org/2023.acl-demo.19/) — 交互式后编辑
