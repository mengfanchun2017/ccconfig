# 生物科学 MOOC 课程体系

> 基于 QS 2026 生物科学 Top5（Harvard, MIT, Stanford, Oxford, Cambridge）本科+研究生课程体系
> 参考 Stanford Biology Core + MIT Course 7 + Harvard MCB

## 范围说明

- **不做**：数理基础（微积分/线代/化学/物理）——学校课程自然覆盖，MOOC 不加负担
- **只做**：生物专业课（core + advanced + frontier），约 30 门
- **定位**：专业积累 + 兴趣探索，不是替代学校教育

## QS 2026 生物科学 Top 10

| 排名 | 学校 | 国家 |
|------|------|------|
| 1 | Harvard University | US |
| 2 | MIT | US |
| 3 | Stanford University | US |
| 4 | University of Oxford | UK |
| 5 | University of Cambridge | UK |
| 6 | Yale University | US |
| 7 | Johns Hopkins University | US |
| 8 | UC Berkeley | US |
| 9 | UC San Francisco | US |
| 10 | Imperial College London | UK |

## 课程体系总览

```
大一上 ─── 阶段一：数理基础 (foundation)
  ├─ 微积分 I、II
  ├─ 线性代数
  ├─ 概率统计
  ├─ 普通化学
  └─ 有机化学

大一下~大二 ─── 阶段二：核心课程 (core)
  ├─ 生物学导论 ──────────── 先修: 无
  ├─ 生物化学 ────────────── 先修: 生物学导论
  ├─ 遗传学 I、II ────────── 先修: 生物学导论
  ├─ 细胞生物学 ──────────── 先修: 生物学导论 + 生物化学
  ├─ 分子生物学 ──────────── 先修: 生物化学
  └─ 进化生物学 ──────────── 先修: 遗传学 I

大二下~大三 ─── 阶段三：进阶课程 (advanced)
  ├─ 基因组学技术 ────────── 先修: 分子生物学
  ├─ 生物信息学 ──────────── 先修: 统计学 + 分子生物学
  ├─ 神经科学 ───────────── 先修: 细胞生物学
  ├─ 免疫学 ─────────────── 先修: 细胞生物学 + 生物化学
  ├─ 系统生物学 ──────────── 先修: 分子生物学
  ├─ 癌症生物学 ──────────── 先修: 分子生物学 + 遗传学
  ├─ 发育生物学 ──────────── 先修: 遗传学 + 细胞生物学
  └─ 化学生物学 ──────────── 先修: 生物化学

大四+ ─── 阶段四：研究前沿 (frontier)
  ├─ RNA 生物学 / 基因编辑 ── 先修: 分子生物学
  ├─ 精准医疗 ───────────── 先修: 基因组学
  ├─ 蛋白质组学 ──────────── 先修: 生物化学 + 分子生物学
  ├─ 合成生物学 ──────────── 先修: 分子生物学
  ├─ 表观遗传学 ──────────── 先修: 遗传学 + 分子生物学
  └─ 药物发现 ───────────── 先修: 生物化学 + 分子生物学
```

## 先修关系图

```
                    ┌─────────────┐
                    │ 生物学导论    │
                    └──────┬──────┘
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │ 生物化学  │    │ 遗传学 I  │    │ 进化生物学 │
    └────┬─────┘    └────┬─────┘    └──────────┘
         │               │
    ┌────┴────┐    ┌─────┴──────┐
    ▼         ▼    ▼            ▼
┌───────┐ ┌───────┐ ┌────────┐ ┌──────────┐
│细胞生物│ │分子生物│ │遗传学 II│ │表观遗传学 │
└───┬───┘ └───┬───┘ └────────┘ └──────────┘
    │         │
    ▼         ▼
┌───────┐ ┌──────────┐
│ 免疫学 │ │基因组学   │
└───────┘ └────┬─────┘
               │
    ┌──────────┼──────────┐
    ▼          ▼          ▼
┌────────┐ ┌───────┐ ┌──────────┐
│系统生物 │ │精准医疗│ │生物信息学 │
└────────┘ └───────┘ └──────────┘
```

## 中文学术术语对照

| English | 中文 |
|---------|------|
| Molecular Biology | 分子生物学 |
| Cell Biology | 细胞生物学 |
| Biochemistry | 生物化学 |
| Genetics | 遗传学 |
| Genomics | 基因组学 |
| Proteomics | 蛋白质组学 |
| Epigenetics | 表观遗传学 |
| Systems Biology | 系统生物学 |
| Synthetic Biology | 合成生物学 |
| Neuroscience | 神经科学 |
| Immunology | 免疫学 |
| Microbiology | 微生物学 |
| Developmental Biology | 发育生物学 |
| Evolutionary Biology | 进化生物学 |
| Bioinformatics | 生物信息学 |
| Precision Medicine | 精准医疗 |
| CRISPR | 基因编辑 |
| Transcriptomics | 转录组学 |
| Metabolomics | 代谢组学 |
| Structural Biology | 结构生物学 |

## Stanford Biology Core 参考

Stanford 生物本科 6 门 Bio Foundations (80-series)：
1. BIO 81 — Ecology（生态学）
2. BIO 82 — Genetics（遗传学）
3. BIO 83 — Biochemistry and Molecular Biology（生物化学与分子生物学）
4. BIO 84 — Physiology（生理学）
5. BIO 85 — Evolutionary Biology（进化生物学）
6. BIO 86 — Cell Biology（细胞生物学）

学生选 4/6 + 实验课 + 数理化基础。

## MIT Course 7 参考

MIT 生物本科核心：
- 7.00x — Introduction to Biology
- 7.03 — Genetics
- 7.05 — Biochemistry
- 7.06 — Cell Biology
- 7.20 — Molecular Biology
- 7.50/7.51/7.52 — 研究生核心（Method & Logic / Biochemical Analysis / Genetics）

## 学习路线建议

### 标准路线（4 年本科）

| 学期 | 课程数 | 核心课程 |
|------|--------|---------|
| 大一上 | 3 | 微积分I, 普通化学, 普通生物学 |
| 大一下 | 3 | 微积分II, 线性代数, 生物学导论 |
| 大二上 | 3 | 概率统计, 生物化学, 有机化学 |
| 大二下 | 4 | 遗传学I, 细胞生物学, 分子生物学, 进化生物学 |
| 大三上 | 3 | 遗传学II, 基因组学, 神经科学 |
| 大三下 | 3 | 免疫学, 生物信息学, 系统生物学 |
| 大四 | 3-4 | 前沿选修（CRISPR, 精准医疗, 表观遗传学...） |

### 密集路线（2 年）

每周 15h+，跳过部分数理基础，专攻核心+进阶。

### 在职路线（弹性）

每周 5h，拉长到 6 年，每学期 1-2 门。
