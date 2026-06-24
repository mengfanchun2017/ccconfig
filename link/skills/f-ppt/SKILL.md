---
name: f-ppt
user-invocable: true
description: |
  文档→PPT 生成。OfficeCLI 引擎，grill-me 交互选 theme/layout/depth，输出到本地或飞书。
---

# f-ppt — 文档 → PPT

从飞书文档/wiki/Markdown 生成 PPTX。OfficeCLI 单引擎，零外部依赖。

## 调用流程

```
源文档分析 → Grill-me 3问 → 内容结构化 → OfficeCLI 构建 → 后处理 → 输出
```

### 输出规则（硬约束）

- **默认输出**: `C:\ccout`（WSL 路径 `/mnt/c/ccout/`），文件名 `<文档标题>.pptx`
- **飞书上传**: 仅用户明确说"飞书"/"上传飞书"/"同步到飞书"时执行 `lark-cli drive +upload`
- 不在每次生成后自动上传

---

## Grill-me 交互（3 问）

### Q1: Theme & 封面风格

| Theme | 主色 | 风格 | 适用 |
|-------|------|------|------|
| **professional_blue** ★默认 | `#0061A8` 蓝 | 商务专业，蓝橙双色 | 技术方案、内部汇报 |
| **midnight_executive** | `#1E2761` 深海军蓝 | 金融高管，冷静克制 | 正式报告、董事会 |
| **charcoal_minimal** | `#36454F` 炭灰 | 极简灰阶，留白为主 | 文字密集型、企业汇报 |

封面变体（按 theme 支持）: `dark`（深色仪式感）/ `blue`（品牌色背景）/ `center`（白底大标题）

### Q2: 转换深度

| 深度 | 说明 | 保留 | 跳过 |
|------|------|------|------|
| **精细** | 文档全量转换 | 正文+表格+图表+代码+注解+不确定项 | — |
| **核心** ★默认 | 去掉注解和代码 | 正文+表格+结论+洞察 | 代码块、`> 注解`、`[待确认]` 项 |
| **精简** | 每页一个核心观点 | 标题+关键数据+一句结论 | 详细解读、多行表格、脚注 |
| **自定义** | 用户口述偏好 | 按指令过滤 | 按指令排除 |

### Q3: 布局偏好

**列数**: `auto`（根据内容自动） / `1`（全宽） / `2`（对比） / `3`（并列）

**密度**:

| 密度 | 正文字号 | 卡片间距 | 适用 |
|------|---------|---------|------|
| **standard** ★默认 | 18pt | 0.76cm | 常规文档，5-7页 |
| **compact** | 16pt | 0.5cm | 数据密集，同页塞更多内容 |
| **relaxed** | 20pt | 1cm | 演讲/汇报，每页3-4要点 |

---

## 构建流程

### 1. 内容分析

从源文档提取结构：
- `# ## ###` 标题层级 → 章节划分
- `**粗体**` → 核心观点候选
- 表格 → 数据页候选
- 列表 → 卡片页候选
- 代码块 → Q2=精细时保留，否则跳过

### 2. 页面规划

| 页面类型 | 何时用 | 页数 |
|---------|--------|------|
| 封面 | 永远第 1 页 | 1 |
| 目录 | 永远第 2 页 | 1 |
| 章节分隔 | 每 3-5 页内容后 | 1/章节 |
| 内容页 | 正文每个独立小节 | 1-2/小节 |
| 聚焦页 | 核心结论强调 | 0-2 |
| 结束 | 永远最后 | 1 |

### 3. OfficeCLI 构建

**新建 PPTX**:
```bash
officecli create output.pptx
```

**设置主题**（从 theme 文件取色板值）:
```bash
officecli set output.pptx /theme \
  --prop accent1=<primary> --prop accent2=<accent> --prop dk1=<dark> \
  --prop headingFont='<font_h>' --prop bodyFont='<font_b>' \
  --prop headingFont.ea='<font_ea>' --prop bodyFont.ea='<font_ea>'
```

**封面**（以 dark 为例）:
```bash
officecli add output.pptx / --type slide --prop layout='Blank' --prop background=<bg>
officecli add output.pptx '/slide[1]' --type shape \
  --prop text='<TITLE>' --prop font='<font_h>' --prop size=36 --prop color=<white> \
  --prop align=center --prop x=2cm --prop y=5cm --prop width=29.87cm --prop height=4cm
officecli add output.pptx '/slide[1]' --type shape \
  --prop text='<SUBTITLE>' --prop font='<font_b>' --prop size=18 --prop color=<gray> \
  --prop align=center --prop x=2cm --prop y=9.5cm --prop width=29.87cm --prop height=1.5cm
```

**内容页**（1 列 standard 密度）:
```bash
officecli add output.pptx / --type slide --prop layout='Blank' --prop background=FFFFFF
officecli add output.pptx '/slide[N]' --type shape \
  --prop text='<PAGE_TITLE>' --prop font='<font_h>' --prop size=28 \
  --prop color=<primary> --prop x=1.5cm --prop y=0.8cm --prop width=30.87cm --prop height=2cm
officecli add output.pptx '/slide[N]' --type shape \
  --prop text='<BODY>' --prop font='<font_b>' --prop size=18 \
  --prop color=<dark> --prop x=1.5cm --prop y=3cm --prop width=30.87cm --prop height=13cm
```

多列布局用网格公式:
```
col_w = (33.87 - 2×margin - (n-1)×gap) / n     # margin=1.5cm, gap 来自密度
x_i   = margin + (i-1) × (col_w + gap)           # i ∈ {0..n-1}
```

### 4. 后处理 + 验证

```bash
# 文字溢出保护（可选，默认关闭）
python3 skills/f-ppt/tools/autofit_postprocess.py output.pptx 55000

# 验证
officecli validate output.pptx

# 确认大小
ls -lh output.pptx
```

### 5. 飞书上传（仅用户明确要求时）

```bash
cd /mnt/c/ccout && lark-cli drive +upload --file "./output.pptx" \
  --wiki-token <wiki节点token> --as user
```

---

## 样式硬规则

见 `references/style-rules.md`。核心规则：
- **不显示组织标记**（封面/内容页/章节页/结束页 均无部门名）
- **封面无副标题**
- **颜色只用 theme 色板，不引入杂色**
- **链接不用 Markdown 表格**（独占一行 `[标题](URL)`）

---

## Theme 文件格式

每个 theme 文件定义色板 + 字体 + 字号阶梯。示例结构见 `themes/professional_blue.md`。

**色板标准字段**:
`primary` `accent` `dark` `pure_black` `white` `gray` `light_bg` `accent_deco`

**字号阶梯**:
`Hero` `End` `H1` `H2` `H3` `H4` `Body` `Body-S` `Body-XS` `Caption`

**封面变体能力表**: 每个 theme 标注支持的封面类型(dark/blue/center) + 各变体的背景色/标题色/字号。

---

## 参考文件索引

| 文件 | 内容 | 何时用 |
|------|------|--------|
| `themes/professional_blue.md` | ★默认 theme 色板/字体/字号 | 每次构建 |
| `themes/midnight_executive.md` | 金融深蓝 theme | Q1 选择时 |
| `themes/charcoal_minimal.md` | 极简灰阶 theme | Q1 选择时 |
| `references/style-rules.md` | 样式硬规则 + 输出目录 | 每次构建前 |
| `references/layouts.md` | 页面类型+列数+变体完整体系 | 构建每页时 |
| `references/build-guide.md` | 坐标公式/列宽/居中 | 构建内容页时 |
| `tools/autofit_postprocess.py` | 文字溢出保护后处理 | 内容密集时可选 |

---

## 引擎: OfficeCLI

单二进制 CLI（`~/.local/bin/officecli`），直接操作 OpenXML。v1.0.117+。

**关键约束**:
- 操作前 `pkill -9 officecli` 清理残留进程
- 构建完成后 `close && validate && ls -lh` 三连确认
- 路径引用加引号 `'/slide[1]'` 防 glob 展开
- `$` 符号用单引号 `'$15M'`
- 批量操作之间文件被锁定，串行执行

**内置能力**: slidemaster/slidelayout 读写、theme 12色+字体设置、图表/表格/图片/动画/转场、实时预览 `officecli watch`、模板 merge `{{key}}` 替换。

**个人模板支持**（两种方式）:
1. **Merge**: 用户在 PowerPoint 中设计模板→加 `{{KEY}}` 占位符→`officecli merge` 填充内容。设计与数据分离，模板可复用。
2. **Extract+Build**: `officecli get template.pptx /theme` 提取色板→`officecli query slidelayout` 读布局结构→Build 模式生成同风格新文档。
