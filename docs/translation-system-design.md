# 科研英文资料翻译 — 系统化能力设计方案

> 2026-08-22 | 四路并行深度调研（A 质量标准 / B LLM 架构 / C 工具生态 / D 系统设计）综合产出
> 核心决策：**自建 LLM 翻译流水线（不做 DeepL/CAT 采购）**，落地为一个新 skill `ftransec`
> 四 包裹，只输出标签内内容
- 明确错误示例（❌"Here is the translation:..."）与正确格式（✅ 纯输出）
- **段落数必须与输入一致**（空行分隔，不得合并/拆分）——标题/作者注常被模型折叠
- 代码/公式/URL/文件路径/API 名 → placeholder 占位保护，翻译后还原

### 中文科研语体规范（A5，规避翻译腔）
- 切分长句、化被动为主动/无主句（中文科技惯用短句+逻辑词"由于/因此/结果表明"）
- 已约定俗成术语用规范译名；首次出现缩略语标注全称
- 公式/变量/图表号/参考文献编号逐字保真，不可意译

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

评分方式（成本-质量折中）：
- 全量：reference-free COMET（cometkiwi）或 LLM-judge 自动评分滤低分
- 低分 + 随机 5%：LLM-as-judge 细审（锚定"专业人类译者"，1-10 分 + 扣分表，temperature 0.1）
- 关键/高价值论文：补 review pass（保守 QA 修正，只改真缺陷）

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
- **单文件重试**：失败 chunk 单独重跑
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

**置信度标注是"方便交付"的关键差异化**：对科研客户明确标注哪段达 publishable 质量、哪段是 gist 级理解（Phrase/"选择性人工介入"）。

### 输出形态（委派既有交付 skills）
- **Word 双语** → fdocx（学术款；宋体中文 + Times New Roman 英文）
- **飞书** → ffeishu
- **Markdown / 纯中文** → 直接写文件

---

## 八、知识资产沉淀（每一次翻译都积累）

1. **术语库增长**：新领域首翻自动抽术语 → 审定入库 → 越用越准
2. **领域学科库**：跨项目 `glossaries/<学科>.csv`，反复做同一学科时复用
3. **翻译记忆增长**：双语交付 = 后续 TM 来源
4. **最佳实践固化**：每轮错误类型统计 → 反哺 prompt/规范（MQM 错误分类）

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

### 本轮已完成
- ✅ 方案文档（本文件）
- ✅ `ftransec` skill 已创建（`plugins/ftransec/SKILL.md` + `references/` `scripts/` 目录）
- ✅ 四份调研报告归档 job tmp

### 待用户确认后继续
1. 完成 `ftransec` skill 主体（8 步流水线 + prompt 契约 + 术语��� + QC + 交付包）
2. 注册 marketplace.json + `sync-marketplace.py --write` + CHANGELOG
3. `config.yaml.example` + ccprivate 配置注入（可选：默认无需私有配置）
4. `references/` 补充（中文科研语体规范、术语抽取 prompt 模板、QC rubric）
5. `deps.txt` 声明依赖（pandoc/pdftotext/MinerU 按需）
6. 端到端验证：用 1-2 篇论文跑通流水线

---

## 来源标注

- [aiww] [ai-translation-workflow](https://github.com/edoardolobl/ai-translation-workflow) — 6阶段流水线 + ISO17100 五维评审 + glossary injection + Pandoc 格式还原
- [tbl] [TranslateBooksWithLLMs](https://github.com/hydropix/TranslateBooksWithLLMs)（GLOSSARY / STYLE_EXTRACTION / JUDGE_RUBRIC_V2 / BENCHMARK 文档）
- [bookllm] [BookLLM](https://github.com/purecodework/bookllm)（translation/review/polish/glossary-extraction prompt）
- [comet] [COMET](https://github.com/Unbabel/COMET) — reference-free QE + XCOMET 错误 span
- [deepl] [DeepL](https://www.deepl.com) 定价 + glossary（需 ≥1000 句对训练）
- [phrase] [Phrase MTPE](https://phrase.com/blog/posts/machine-translation-post-editing/) — 术语重要性 + LPE/FPE 分层 + QE 选择性人工介入
- [bi18n] [better-i18n AI Translation Workflows](https://better-i18n.com/en/blog/ai-translation-workflows-mtpe/) — 6 阶段 + QE 阈值路由
- [transept] [Transept MTPE Guide 2026](https://transept.ai/guides/machine-translation-post-editing-mtpe-guide) — 术语库/TM/styleguide 角色
- [docutranslate] [docutranslate](https://github.com/xunbu/docutranslate) — MinerU 科研 PDF 解析
- [wiki-tm] [Translation memory — Wikipedia](https://en.wikipedia.org/wiki/Translation_memory)
- [wiki-term] [Terminology extraction — Wikipedia](https://en.wikipedia.org/wiki/Terminology_extraction)
- [openpipe] [OpenTIPE (ACL 2023)](https://aclanthology.org/2023.acl-demo.19/) — 交互式后编辑
