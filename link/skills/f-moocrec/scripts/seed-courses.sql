CREATE TABLE IF NOT EXISTS courses (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  name_zh TEXT,
  university TEXT NOT NULL,
  university_qs_rank INTEGER,
  platform TEXT NOT NULL,
  url TEXT NOT NULL UNIQUE,
  subject_area TEXT NOT NULL,
  stage TEXT NOT NULL,
  difficulty TEXT NOT NULL DEFAULT 'intermediate',
  duration_weeks INTEGER,
  hours_per_week INTEGER,
  language TEXT NOT NULL DEFAULT 'en',
  has_chinese_subtitle BOOLEAN DEFAULT false,
  free_option TEXT,
  certificate_option TEXT,
  certificate_price_usd INTEGER,
  certificate_platform TEXT,
  certificate_verification TEXT,
  rating REAL,
  prerequisites TEXT[],
  is_active BOOLEAN DEFAULT true,
  last_verified_date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_courses_stage ON courses(stage);
CREATE INDEX IF NOT EXISTS idx_courses_subject ON courses(subject_area);
CREATE INDEX IF NOT EXISTS idx_courses_platform ON courses(platform);
CREATE INDEX IF NOT EXISTS idx_courses_language ON courses(language);

INSERT INTO courses (name, name_zh, university, university_qs_rank, platform, url, subject_area, stage, difficulty, duration_weeks, hours_per_week, language, has_chinese_subtitle, free_option, certificate_option, certificate_price_usd, certificate_platform, certificate_verification, rating, prerequisites, is_active, last_verified_date) VALUES
-- Foundation: Math & Science Prerequisites
('Single Variable Calculus', '单变量微积分', 'MIT', 2, 'MIT OCW', 'https://ocw.mit.edu/courses/18-01sc-single-variable-calculus-fall-2010/', 'mathematics', 'foundation', 'beginner', 16, 6, 'en', true, 'MIT OCW 全部免费，含视频、习题、考试', null, null, null, null, 4.8, null, true, '2026-06-29'),
('Multivariable Calculus', '多变量微积分', 'MIT', 2, 'MIT OCW', 'https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/', 'mathematics', 'foundation', 'intermediate', 15, 6, 'en', true, 'MIT OCW 全部免费', null, null, null, null, 4.7, ARRAY['Single Variable Calculus'], true, '2026-06-29'),
('Linear Algebra', '线性代数', 'MIT', 2, 'MIT OCW', 'https://ocw.mit.edu/courses/18-06sc-linear-algebra-fall-2011/', 'mathematics', 'foundation', 'beginner', 14, 6, 'en', true, 'MIT OCW 全部免费，Gilbert Strang 经典课程', null, null, null, null, 4.9, null, true, '2026-06-29'),
('Introduction to Probability and Statistics', '概率论与数理统计', 'MIT', 2, 'edX', 'https://www.edx.org/learn/probability/massachusetts-institute-of-technology-probability-the-science-of-uncertainty-and-data', 'mathematics', 'foundation', 'intermediate', 16, 6, 'en', false, '免费旁听所有内容', 'edX Verified Certificate', 50, 'edX', 'edX 唯一验证 URL', 4.6, null, true, '2026-06-29'),
('Principles of Chemical Science', '化学原理', 'MIT', 2, 'MIT OCW', 'https://ocw.mit.edu/courses/5-111sc-principles-of-chemical-science-fall-2014/', 'chemistry', 'foundation', 'beginner', 16, 6, 'en', true, 'MIT OCW 全部免费', null, null, null, null, 4.7, null, true, '2026-06-29'),
('Organic Chemistry', '有机化学', 'Yale', 1, 'Open Yale', 'https://oyc.yale.edu/chemistry/chem-125a', 'chemistry', 'foundation', 'intermediate', 13, 5, 'en', false, 'Open Yale 免费视频+讲义', null, null, null, null, 4.5, ARRAY['Principles of Chemical Science'], true, '2026-06-29'),

-- Core: Introduction to Biology
('Introduction to Biology - The Secret of Life', '生物学导论——生命的秘密', 'MIT', 2, 'edX', 'https://www.edx.org/learn/biology/massachusetts-institute-of-technology-introduction-to-biology-the-secret-of-life', 'general_biology', 'core', 'beginner', 12, 8, 'en', true, '免费旁听所有视频和习题', 'edX Verified Certificate — 含 MITx 标志', 100, 'edX', 'edX 唯一验证 URL + LinkedIn 可挂', 4.9, null, true, '2026-06-29'),

-- Core: Biochemistry
('Principles of Biochemistry', '生物化学原理', 'Harvard', 1, 'edX', 'https://www.edx.org/learn/biochemistry/harvard-university-principles-of-biochemistry', 'biochemistry', 'core', 'intermediate', 15, 6, 'en', false, '免费旁听所有内容', 'edX Verified Certificate — 含 Harvard 标志', 149, 'edX', 'edX 唯一验证 URL', 4.8, ARRAY['Introduction to Biology - The Secret of Life'], true, '2026-06-29'),

-- Core: Genetics
('Genetics: The Fundamentals', '遗传学：基础', 'MIT', 2, 'edX', 'https://www.edx.org/learn/genetics/massachusetts-institute-of-technology-genetics-the-fundamentals', 'genetics', 'core', 'intermediate', 8, 6, 'en', false, '免费旁听', 'edX Verified Certificate', 50, 'edX', 'edX 唯一验证 URL', 4.7, ARRAY['Introduction to Biology - The Secret of Life'], true, '2026-06-29'),
('Genetics: Analysis and Applications', '遗传学：分析与应用', 'MIT', 2, 'edX', 'https://www.edx.org/learn/genetics/massachusetts-institute-of-technology-genetics-analysis-and-applications', 'genetics', 'core', 'intermediate', 8, 6, 'en', false, '免费旁听', 'edX Verified Certificate', 50, 'edX', 'edX 唯一验证 URL', 4.6, ARRAY['Genetics: The Fundamentals'], true, '2026-06-29'),

-- Core: Cell & Molecular Biology
('Cell Biology: Mitochondria', '细胞生物学：线粒体', 'Harvard', 1, 'edX', 'https://www.edx.org/learn/cell-biology/harvard-university-cell-biology-mitochondria', 'cell_biology', 'core', 'intermediate', 4, 5, 'en', false, '免费旁听', 'edX Verified Certificate', 50, 'edX', 'edX 唯一验证 URL', 4.5, ARRAY['Introduction to Biology - The Secret of Life', 'Principles of Biochemistry'], true, '2026-06-29'),
('Molecular Biology', '分子生物学', 'MIT', 2, 'edX', 'https://www.edx.org/learn/molecular-biology/massachusetts-institute-of-technology-molecular-biology', 'molecular_biology', 'core', 'intermediate', 12, 8, 'en', false, '免费旁听', 'edX Verified Certificate', 100, 'edX', 'edX 唯一验证 URL', 4.7, ARRAY['Introduction to Biology - The Secret of Life', 'Principles of Biochemistry'], true, '2026-06-29'),
('Chemical Biology', '化学生物学', 'University of Geneva', 50, 'Coursera', 'https://www.coursera.org/learn/chemical-biology', 'biochemistry', 'core', 'intermediate', 7, 3, 'en', true, 'Coursera 免费预览（首个模块）', 'Coursera Certificate + Credly 数字徽章', 49, 'Credly', 'Credly 徽章可挂 LinkedIn + 区块链验证', 4.6, ARRAY['Principles of Biochemistry'], true, '2026-06-29'),

-- Core: Evolution
('Introduction to Genetics and Evolution', '遗传学与进化导论', 'Duke University', 30, 'Coursera', 'https://www.coursera.org/learn/genetics-evolution', 'evolution', 'core', 'beginner', 10, 5, 'en', true, 'Coursera 免费预览', 'Coursera Certificate + Credly 徽章', 49, 'Credly', 'Credly 徽章可验证', 4.7, ARRAY['Introduction to Biology - The Secret of Life'], true, '2026-06-29'),

-- Advanced: Genomics & Bioinformatics
('Introduction to Genomic Technologies', '基因组技术导论', 'Johns Hopkins University', 3, 'Coursera', 'https://www.coursera.org/learn/introduction-genomics', 'genomics', 'advanced', 'beginner', 4, 5, 'en', true, 'Coursera 免费预览', 'Coursera Certificate + Credly 徽章', 49, 'Credly', 'Credly 徽章可验证', 4.6, ARRAY['Introduction to Biology - The Secret of Life'], true, '2026-06-29'),
('Algorithms for DNA Sequencing', 'DNA 测序算法', 'Johns Hopkins University', 3, 'Coursera', 'https://www.coursera.org/learn/dna-sequencing', 'bioinformatics', 'advanced', 'advanced', 4, 6, 'en', false, 'Coursera 免费预览', 'Coursera Certificate + Credly 徽章', 49, 'Credly', 'Credly 徽章可验证', 4.7, ARRAY['Introduction to Genomic Technologies'], true, '2026-06-29'),
('Bioinformatics Specialization', '生物信息学专项课程', 'UC San Diego', 15, 'Coursera', 'https://www.coursera.org/specializations/bioinformatics', 'bioinformatics', 'advanced', 'intermediate', 32, 5, 'en', false, 'Coursera 免费预览', 'Coursera Specialization Certificate + Credly', 49, 'Credly', 'Credly 专项徽章可验证', 4.5, ARRAY['Introduction to Biology - The Secret of Life'], true, '2026-06-29'),

-- Advanced: Neuroscience
('Medical Neuroscience', '医学神经科学', 'Duke University', 30, 'Coursera', 'https://www.coursera.org/learn/medical-neuroscience', 'neuroscience', 'advanced', 'advanced', 10, 10, 'en', true, 'Coursera 免费预览', 'Coursera Certificate + Credly 徽章', 49, 'Credly', 'Credly 徽章可验证', 4.9, ARRAY['Introduction to Biology - The Secret of Life'], true, '2026-06-29'),
('Fundamentals of Neuroscience', '神经科学基础', 'Harvard', 1, 'edX', 'https://www.edx.org/learn/neuroscience/harvard-university-fundamentals-of-neuroscience', 'neuroscience', 'advanced', 'intermediate', 15, 5, 'en', false, '免费旁听', 'edX Verified Certificate', 149, 'edX', 'edX 唯一验证 URL', 4.8, ARRAY['Introduction to Biology - The Secret of Life'], true, '2026-06-29'),

-- Advanced: Immunology & Microbiology
('Immunology', '免疫学', 'Harvard', 1, 'edX', 'https://www.edx.org/learn/immunology/harvard-university-immunology', 'immunology', 'advanced', 'intermediate', 12, 5, 'en', false, '免费旁听', 'edX Verified Certificate', 149, 'edX', 'edX 唯一验证 URL', 4.6, ARRAY['Introduction to Biology - The Secret of Life', 'Principles of Biochemistry'], true, '2026-06-29'),

-- Advanced: Systems Biology
('Introduction to Systems Biology', '系统生物学导论', 'Icahn School of Medicine at Mount Sinai', 60, 'Coursera', 'https://www.coursera.org/learn/systems-biology', 'systems_biology', 'advanced', 'advanced', 8, 5, 'en', false, 'Coursera 免费预览', 'Coursera Certificate + Credly 徽章', 49, 'Credly', 'Credly 徽章可验证', 4.5, ARRAY['Introduction to Biology - The Secret of Life', 'Molecular Biology'], true, '2026-06-29'),

-- Advanced: Cancer
('Introduction to the Biology of Cancer', '癌症生物学导论', 'Johns Hopkins University', 3, 'Coursera', 'https://www.coursera.org/learn/cancer', 'cancer_biology', 'advanced', 'beginner', 6, 4, 'en', true, 'Coursera 免费预览', 'Coursera Certificate + Credly 徽章', 49, 'Credly', 'Credly 徽章可验证', 4.7, ARRAY['Introduction to Biology - The Secret of Life'], true, '2026-06-29'),

-- Frontier: CRISPR & Gene Editing
('RNA Biology with Eterna', 'RNA 生物学', 'Stanford University', 3, 'Coursera', 'https://www.coursera.org/learn/rna-biology', 'molecular_biology', 'frontier', 'beginner', 4, 3, 'en', false, 'Coursera 免费预览', 'Coursera Certificate + Stanford + Credly', 49, 'Credly', 'Credly 徽章可验证', 4.4, ARRAY['Molecular Biology'], true, '2026-06-29'),

-- Frontier: Precision Medicine
('Precision Medicine', '精准医疗', 'University of Geneva', 50, 'Coursera', 'https://www.coursera.org/learn/precision-medicine', 'precision_medicine', 'frontier', 'intermediate', 5, 5, 'en', false, 'Coursera 免费预览', 'Coursera Certificate + Credly 徽章', 49, 'Credly', 'Credly 徽章可验证', 4.4, ARRAY['Introduction to Genomic Technologies'], true, '2026-06-29'),

-- Frontier: Drug Discovery
('Drug Discovery', '药物发现', 'UC San Diego', 15, 'Coursera', 'https://www.coursera.org/learn/drug-discovery', 'pharmacology', 'frontier', 'intermediate', 4, 5, 'en', false, 'Coursera 免费预览', 'Coursera Certificate + Credly', 49, 'Credly', 'Credly 徽章可验证', 4.5, ARRAY['Principles of Biochemistry', 'Molecular Biology'], true, '2026-06-29'),

-- Frontier: Epigenetics
('Epigenetic Control of Gene Expression', '基因表达的表观遗传调控', 'University of Melbourne', 35, 'Coursera', 'https://www.coursera.org/learn/epigenetics', 'epigenetics', 'frontier', 'intermediate', 6, 4, 'en', false, 'Coursera 免费预览', 'Coursera Certificate + Credly 徽章', 49, 'Credly', 'Credly 徽章可验证', 4.6, ARRAY['Genetics: The Fundamentals', 'Molecular Biology'], true, '2026-06-29'),

-- Chinese MOOC supplements (中国大学MOOC)
('生物化学', '生物化学', '北京大学', 14, '中国大学MOOC', 'https://www.icourse163.org/course/PKU-1003063001', 'biochemistry', 'core', 'intermediate', 16, 6, 'zh', false, '完全免费', '中国大学MOOC 认证证书（需申请）', 0, '中国大学MOOC', '证书可在 icourse163.org 查询', 4.5, ARRAY['生物学导论'], true, '2026-06-29'),
('分子生物学', '分子生物学', '华中农业大学', 300, '中国大学MOOC', 'https://www.icourse163.org/course/HZAU-1003019010', 'molecular_biology', 'core', 'intermediate', 18, 4, 'zh', false, '完全免费', '中国大学MOOC 认证证书', 0, '中国大学MOOC', '证书可在 icourse163.org 查询', 4.4, ARRAY['生物化学', '细胞生物学'], true, '2026-06-29'),
('遗传学', '遗传学', '武汉大学', 200, '中国大学MOOC', 'https://www.icourse163.org/course/WHU-1002698021', 'genetics', 'core', 'intermediate', 16, 5, 'zh', false, '完全免费', '中国大学MOOC 认证证书', 0, '中国大学MOOC', '证书可在 icourse163.org 查询', 4.5, ARRAY['生物化学'], true, '2026-06-29'),
('分子生物学简明教程', '分子生物学简明教程', '华东理工大学', 350, '中国大学MOOC', 'https://www.icourse163.org/course/ECUST-1002990002', 'molecular_biology', 'core', 'beginner', 12, 3, 'zh', false, '完全免费，适合工科背景', '中国大学MOOC 认证证书', 0, '中国大学MOOC', '证书可在 icourse163.org 查询', 4.3, ARRAY['微生物学', '生物化学'], true, '2026-06-29'),

-- Core supplements
('Cell Biology: Transport and Signaling', '细胞生物学：运输与信号', 'MIT', 2, 'edX', 'https://www.edx.org/learn/cell-biology/massachusetts-institute-of-technology-cell-biology-transport-and-signaling', 'cell_biology', 'core', 'intermediate', 4, 5, 'en', false, '免费旁听', 'edX Verified Certificate', 50, 'edX', 'edX 唯一验证 URL', 4.5, ARRAY['Introduction to Biology - The Secret of Life'], true, '2026-06-29'),
('Developmental Biology', '发育生物学', 'MIT', 2, 'MIT OCW', 'https://ocw.mit.edu/courses/7-013-introductory-biology-spring-2018/', 'developmental_biology', 'advanced', 'intermediate', 14, 6, 'en', false, 'MIT OCW 全部免费', null, null, null, null, 4.5, ARRAY['Introduction to Biology - The Secret of Life', 'Genetics: The Fundamentals'], true, '2026-06-29'),
('Quantitative Biology Workshop', '定量生物学', 'MIT', 2, 'edX', 'https://www.edx.org/learn/biology/massachusetts-institute-of-technology-quantitative-biology-workshop', 'computational_biology', 'advanced', 'intermediate', 6, 5, 'en', false, '免费旁听', 'edX Verified Certificate', 50, 'edX', 'edX 唯一验证 URL', 4.4, ARRAY['Introduction to Biology - The Secret of Life'], true, '2026-06-29'),

-- Foundation: Statistics for Biology
('Statistics for Genomic Data Science', '基因组数据科学统计', 'Johns Hopkins University', 3, 'Coursera', 'https://www.coursera.org/learn/statistical-genomics', 'statistics', 'foundation', 'intermediate', 4, 5, 'en', false, 'Coursera 免费预览', 'Coursera Certificate + Credly', 49, 'Credly', 'Credly 徽章可验证', 4.5, ARRAY['Introduction to Probability and Statistics'], true, '2026-06-29'),
('Statistics in Medicine', '医学统计', 'Stanford University', 3, 'Stanford Online', 'https://online.stanford.edu/courses/som-xche0002-statistics-medicine', 'statistics', 'foundation', 'beginner', 10, 3, 'en', false, 'Stanford Online 免费', 'Stanford CME Certificate', 0, 'Stanford Online', 'Stanford 证书可查询', 4.6, null, true, '2026-06-29'),

-- Frontier: more advanced topics
('Proteomics and Beyond', '蛋白质组学及其他', 'Technical University of Denmark', 120, 'Coursera', 'https://www.coursera.org/learn/proteomics', 'proteomics', 'frontier', 'advanced', 5, 4, 'en', false, 'Coursera 免费预览', 'Coursera Certificate + Credly', 49, 'Credly', 'Credly 徽章可验证', 4.3, ARRAY['Molecular Biology', 'Principles of Biochemistry'], true, '2026-06-29'),
('Synthetic Biology', '合成生物学', 'MIT', 2, 'MIT OCW', 'https://ocw.mit.edu/courses/20-020-introduction-to-biological-engineering-design-spring-2009/', 'synthetic_biology', 'frontier', 'advanced', 14, 6, 'en', false, 'MIT OCW 免费', null, null, null, null, 4.4, ARRAY['Molecular Biology', 'Introduction to Biology - The Secret of Life'], true, '2026-06-29'),

-- Foundational: Biology Intro (Chinese)
('普通生物学', '普通生物学', '北京大学', 14, '中国大学MOOC', 'https://www.icourse163.org/course/PKU-1000000001', 'general_biology', 'core', 'beginner', 16, 5, 'zh', false, '完全免费', '中国大学MOOC 认证证书', 0, '中国大学MOOC', '证书可在 icourse163.org 查询', 4.6, null, true, '2026-06-29');
