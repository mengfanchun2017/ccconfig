---
name: f-ppt
user-invocable: true
description: |
  统一 PPT 生成 — 从 wiki/md 生成 PPTX 上传飞书 wiki。
  双引擎：OfficeCLI（AI-native JSON，默认）+ ppt-master（SVG 模板）。
  飞书 Slides API 仅适合极简页面+增量编辑，不适合程序化生成。
allowed-tools: Read, Write, Bash, Glob, mcp__minimax__web_search
---

# Unified PPT

从 wiki 文档或 Markdown 生成 PPTX，上传飞书 wiki 作为子文件。

**核心路径**：officecli 生成 .pptx → `lark-cli drive +upload --wiki-token` 上传 wiki 附件。

**模板体系**：Theme（视觉身份：色板+字体+字号）+ Layout（页面结构：位置+网格+形状）。一份 PPT = 选 1 个 Theme + 每页选 1 个 Layout。详见 [§主题目录](#主题目录-theme) 和 [§布局目录](#布局目录-layout)。

## 引擎选择

```
用户需求
  ├─ 默认 → OfficeCLI + professional_blue 主题
  ├─ "用模板"/"mckinsey风格"/"专业商务" → ppt-master（SVG→DrawingML）
  ├─ "换主题"/"深色"/"科技风"/"金融风" → OfficeCLI + 其他主题（见主题目录）
  ├─ 数据密集/多图表/复杂表格 → python-pptx（图表 API 最成熟）
  ├─ 有现有 PPTX 模板要套用 → ppt-master（pptx_template_import.py）
  ├─ 50+ 页大 deck → OfficeCLI 分批 + 并行 subagent
  └─ 飞书在线协作编辑（非生成） → 飞书 Slides API（+replace-slide 增量改）
```

## PPTX 生成方案矩阵

> 调研时间：2026-06-23。

| 引擎 | 类型 | AI 友好度 | 能力覆盖 | 成本 |
|------|------|----------|---------|------|
| **OfficeCLI** | 单二进制 CLI | ★★★★★ | 全能力（JSON 批量/模板合并/热重载） | 免费 |
| python-pptx | Python 库 | ★★★ | 全能力（图表/表格/图片/SmartArt/动画） | 免费 |
| ppt-master | Python + SVG | ★★★ | 模板驱动 9 种布局 | 免费 |
| PptxGenJS | JS 库 | ★★★ | 图表/表格/图片/超链接 | 免费 |
| Aspose.Slides | 多语言 SDK | ★★★ | 全能力 + AI Agent | $3,000/yr |
| SlideForge | REST API + MCP | ★★★★ | 可视化 QA | $0.05/slide |

## 安装

```bash
bash ccconfig/option-officecli/init.sh --install   # OfficeCLI（默认）
bash ccconfig/option-ppt-master/init.sh --install   # ppt-master（模板场景）
bash ccconfig/option-officecli/init.sh --status     # 状态检查
```

## 推荐工作流

```
源内容（飞书 wiki / Markdown）
  → 内容分析 + 页面规划
  → 选 Theme（默认 professional_blue）→ 读 themes/<id>.md
  → 每页选 Layout → 读 layouts/<name>.md
  → Theme 色值/字体/字号 + Layout 位置/命令 → 生成 officecli 命令
  → 执行 → .pptx
  → 后处理（autofit）+ 质检（officecli validate）
  → lark-cli drive +upload --wiki-token 上传 wiki 附件
```

**不同规模策略**：

| 规模 | 方案 | 说明 |
|------|------|------|
| ≤10 页简单 | OfficeCLI 全量 JSON batch | 读 theme + layouts 后手写 |
| 10-30 页标准 | ppt-master 模板驱动 | 7 种 layout SVG + 30+ 图表 SVG |
| 30-50 页中等 | OfficeCLI 分批脚本 | 按章节拆 3-5 个 Part 脚本 |
| 50+ 页大 deck | OfficeCLI 并行 subagent | 5 个 subagent 各写 section 脚本 → 顺序执行 |

---

# 用户交互（Theme + Layout 选择）

f-ppt 开源后，用户通过自然语言描述需求，AI 自动匹配 Theme 和 Layout。无需记忆命令或文件名。

## 自动选择（默认）

用户说"做个 PPT"时，不询问，直接用默认值：
- Theme = `professional_blue`
- 封面 = `cover_dark`
- 内容页 = 按内容块数自动选 content_N

## 用户指定 Theme

用户提到以下关键词时切换 Theme：

| 用户说 | 对应 Theme | 原因 |
|--------|-----------|------|
| "深色"/"深蓝"/"金融风"/"高管"/"正式" | midnight_executive | 深海军蓝，权威感 |
| "活泼"/"营销"/"产品发布"/"红色"/"热情" | coral_energy | 珊瑚红，冲击力 |
| "自然"/"绿色"/"环保"/"ESG"/"可持续" | forest_moss | 森林绿，信任感 |
| "极简"/"简洁"/"黑白"/"灰" | charcoal_minimal | 灰阶，克制 |
| "科技"/"蓝色"/"数据"/"SaaS" | ocean_gradient | 海洋蓝，冷调 |
| "默认"/"通用"/"培训"/"课程" | professional_blue | 蓝橙双色 |

## 用户指定封面

| 用户说 | 对应 Layout |
|--------|------------|
| "黑底封面"/"正式封面" | cover_dark |
| "品牌色封面"/"蓝色封面" | cover_blue |
| "白底大标题"/"居中标题" | cover_center |

## 交互流程

```
用户: "帮我做个 Q3 技术方案 PPT"
  → AI 读 SKILL.md 索引表
  → "技术方案" → ocean_gradient 主题
  → "Q3 方案" → 内容按章节自动匹配 content_N
  → 封面默认 cover_dark
  → 生成

用户: "用深色主题，做个董事会汇报，封面要正式"
  → "深色" + "董事会" → midnight_executive
  → "封面要正式" → cover_dark
  → 生成

用户: "换个主题，太严肃了"
  → 当前是 midnight_executive → 切换到 coral_energy 或 ocean_gradient
  → 给用户两个选择（描述差异），让用户确认

用户: "这个主题有什么颜色？"
  → 读当前 theme 文件的色板表 → 列出角色+色值+用法
```

## 无经验用户快速上手

用户不需要知道 Theme/Layout 文件名。唯一需要说的是**内容主题 + 风格偏好**：

> "帮我做一个关于 <主题> 的 PPT，风格要 <严肃/活泼/自然/极简/科技>"

AI 自动完成：
1. 风格词 → 匹配 Theme
2. 分析内容章节 → 匹配每页 Layout
3. 读 Theme + Layout 文件 → 生成 OfficeCLI 命令
4. 执行 → .pptx → 上传飞书

---

# 主题目录 (Theme)

**Theme = 视觉身份**。定义色板 + 字体 + 字号阶梯。一份 PPT 选一个 Theme，全局统一。

生成 PPT 时：先看下表选 Theme → `Read` 对应文件获取完整色板/字体/字号 → 填入 Layout 命令。

| # | ID | 主色 | 风格 | 适用 | 文件 |
|---|----|------|------|------|------|
| 1 | **professional_blue** ★默认 | `#0061A8` 蓝+橙 | 现代培训/课程 | 通用：汇报、方案、技术分享 | `themes/professional_blue.md` |
| 2 | midnight_executive | `#1E2761` 深海军蓝 | 金融高管 | 金融报告、董事会、战略 | `themes/midnight_executive.md` |
| 3 | coral_energy | `#F96167` 珊瑚红 | 产品营销 | 产品发布、营销提案 | `themes/coral_energy.md` |
| 4 | forest_moss | `#2C5F2D` 森林绿 | ESG/可持续 | 环境报告、农业、健康 | `themes/forest_moss.md` |
| 5 | charcoal_minimal | `#36454F` 炭灰 | 极简企业 | 企业简介、年度总结 | `themes/charcoal_minimal.md` |
| 6 | ocean_gradient | `#065A82` 海洋蓝 | 科技数据 | 技术方案、数据分析、SaaS | `themes/ocean_gradient.md` |

**添加新主题**：在 `themes/` 下新建 `<id>.md`，参照 `professional_blue.md` 格式，至少包含色板+字体+字号。然后在此表加一行。

---

# 布局目录 (Layout)

**Layout = 页面结构**。定义形状位置、网格公式、OfficeCLI 命令模板。每页根据内容选一个 Layout。

生成时：将 Theme 的色值/字体/字号填入 Layout 命令的 `${变量}` 中。

## 封面 (Cover)

| Layout | 说明 | 文件 |
|--------|------|------|
| `cover_dark` | 黑色沉浸封面，white 大字 | `layouts/cover_dark.md` |
| `cover_blue` | primary 色封面，white 大字 | `layouts/cover_blue.md` |
| `cover_center` | 白底居中 Hero 级大标题 | `layouts/cover_center.md` |

## 目录

| Layout | 说明 | 文件 |
|--------|------|------|
| `index` | 编号目录页，双列布局 | `layouts/index.md` |

## 内容 (Content)

| Layout | 块数 | 布局 | 适用 | 文件 |
|--------|------|------|------|------|
| `content_1` | 1 | 全宽单栏 | 单一主题、大段文字 | `layouts/content_1.md` |
| `content_2` | 2 | 双栏并排 | 对比、左右分栏 | `layouts/content_2.md` |
| `content_3` | 3 | 三栏并排 | 三项对比、三要点 | `layouts/content_3.md` |
| `content_4` | 4 | 2×2 网格 | SWOT、四象限 | `layouts/content_4.md` |
| `content_n` | N | N 列通用公式 | ≥5 块或自定义列数 | `layouts/content_n.md` |
| `content_orange` | 任意 | accent 反色变体 | 强调、警示、章节分隔 | `layouts/content_orange.md` |

**布局选择规则**：
1. 数内容要点 → 选对应 content_N（3 要点→content_3，4 要点→content_4）
2. 强调/警示 → 用 `content_orange`（反色变体）
3. 单一大段文字 → `content_1`

## 特殊

| Layout | 说明 | 文件 |
|--------|------|------|
| `focus` | 聚焦页，四角 halfFrame 装饰，居中大字 | `layouts/focus.md` |
| `end_dark` | 黑色结束页，"感谢聆听" | `layouts/end_dark.md` |

**添加新 Layout**：在 `layouts/` 下新建 `<name>.md`，包含角色说明、网格计算、OfficeCLI 命令模板。然后在此表加一行。

---

## 通用设计规范（所有 Theme 适用）

### 字号底线

| 元素 | 最小 | 典型 |
|------|------|------|
| 幻灯片标题 | ≥ 28pt | 28-43pt |
| 段落标题 | ≥ 20pt | 20-24pt |
| 正文 | ≥ 18pt | 18-22pt |
| 脚注/标签 | ≥ 10pt muted | 10-12pt |

标题与正文比例 ≥ 1.5:1。professional_blue 为 28/18 = 1.55:1。

### 字体规则

中文字体统一用 Noto Sans SC 或 Microsoft YaHei。西文可用衬线/无衬线配对。标题与正文必须同一中文字体家族。

### 布局网格

Widescreen 16:9 = `33.87 × 19.05cm`：
- 边距 ≥ 1.27cm（professional_blue 用 1.5cm）
- 卡片间距 ≥ 0.76cm
- N 列公式：`col_w = (33.87 - 2×margin - (N-1)×gap) / N`

---

# 引擎 A：ppt-master（模板驱动）

## 流水线

```
源文档(md/wiki) → Step 1: 内容结构化 → Step 2: 模板匹配 → Step 3: 逐页SVG生成 → Step 4: 质检+导出+上传
```

### Step 1 — 内容结构化

- 分析 `# ## ###` 标题层级 → 推导章节划分
- 标记 `**粗体**` 核心观点 → `KEY_MESSAGE` 候选
- 表格/列表 → 数据卡片页候选
- 输出「页面结构方案」：每页的页码、类型、标题、核心要点

**页面规划**：封面(1页) → 目录(1页) → 章节分隔(每3-5页1页) → 内容(1-2页/小节) → 结尾(1页)

### Step 2 — 模板匹配

**默认**：本 skill 内置的 professional_blue 色板+字体规范（读 `themes/professional_blue.md`），与 ppt-master 的 layouts 组合使用。

**深色/科技风**：用户说"深色""科技风"时切换 anthropic brand（`~/git/_ext/ppt-master/.../templates/brands/anthropic/design_spec.md`）。

模板库：`~/git/_ext/ppt-master/skills/ppt-master/templates/layouts/`（8 种：professional_blue ★默认, academic_defense, ai_ops, government_blue/red, medical_university, pixel_retro, psychology_attachment）。

确认模板后，读 `design_spec.md` + 5 个 SVG：`01_cover.svg` `02_toc.svg` `02_chapter.svg` `03_content.svg` `04_ending.svg`

**自定义模板**：用户提供 PPTX → `python3 skills/ppt-master/scripts/pptx_template_import.py <file>.pptx` → 自动提取 design_spec.md + 5 SVG。

### Step 3 — 逐页生成 SVG

- 文件名排序：`01_cover.svg` `02_toc.svg` `03_chapter_1.svg` `04_content_xxx.svg` ...
- viewBox: `0 0 1280 720`（ppt169）
- `<tspan>` 换行，禁止 `<foreignObject>`
- `fill-opacity`/`stroke-opacity` 做透明，禁止 `rgba()`
- 颜色严格使用 theme 色板 + layout design_spec
- 封面标题中英双语
- 代码块：`font-family="DejaVu Sans Mono"`，`#1E1E1E` 背景，`rx="8"`

**⚠️ `{{CONTENT_AREA}}` 硬规则**：03_content.svg 中的 `{{CONTENT_AREA}}` 占位符**必须**是独立标记（不在任何 `<text>`/`<g>`/`<rect>` 元素内部）。绝对禁止放在 `<text>...</text>` 标签内——`{{CONTENT_AREA}}` 被替换为包含 `<rect>`/`<circle>`/`<text>` 的 body HTML，若嵌套在 `<text>` 内则所有子元素被 SVG 解析器静默丢弃，导致内容页完全空白（2026-06-23 已复现）。正确写法：`    <!-- Content area -->\n    {{CONTENT_AREA}}\n\n    <!-- Footer -->`

### Step 4 — 质检 + 导出 + 上传

```bash
cd ~/git/_ext/ppt-master && \
python3 skills/ppt-master/scripts/svg_quality_checker.py /tmp/pptx_project
python3 skills/ppt-master/scripts/svg_to_pptx.py /tmp/pptx_project -s final \
  --only native -t fade -o /tmp/pptx_project/output.pptx
cd /tmp/pptx_project && lark-cli drive +upload --file "./output.pptx" --wiki-token <token> --as user
```

| 导出选项 | 说明 |
|------|------|
| `-s final` | 使用 svg_final/ 目录 |
| `--only native` | 纯可编辑形状（推荐） |
| `-t fade\|push\|wipe\|none` | 转场效果 |
| `-a mixed` | 入场动画 |

PPTX 作为 wiki 子文件上传，侧边栏「文件」中预览编辑。

---

# 引擎 B：OfficeCLI（AI 原生）

## 核心命令

```bash
officecli create deck.pptx
officecli open deck.pptx
officecli add deck.pptx / --type slide --prop layout=blank --prop background=FFFFFF
officecli add deck.pptx "/slide[1]" --type shape \
  --prop text="标题" --prop font="Noto Sans SC" --prop size=28 --prop bold=true \
  --prop color=0061A8 --prop fill=FFFFFF --prop preset=roundRect \
  --prop x=2cm --prop y=4cm --prop width=12cm --prop height=3cm
officecli batch deck.pptx --input deck_commands.json
officecli close deck.pptx && officecli validate deck.pptx
```

## 批量模式

```json
[
  {"command": "add", "parent": "/", "type": "slide", "props": {"title": "封面", "text": "副标题", "background": "#1E2761"}},
  {"command": "add", "parent": "/", "type": "slide", "props": {"title": "内容页", "text": "正文"}},
  {"command": "add", "parent": "/slide[2]", "type": "shape", "props": {"text": "要点1"}}
]
```

先 `create` 再 `batch`。用 `--input file.json` 避免 stdin 冲突。

## 模板合并

```bash
officecli create template.pptx
officecli add template.pptx / --type slide --prop title="{{title}}" --prop text="{{subtitle}}"
officecli merge template.pptx output.pptx --data '{"title":"Q4报告","subtitle":"营收增长18%"}'
```

## QA

```bash
officecli validate deck.pptx
officecli view deck.pptx issues
officecli view deck.pptx text | grep -iE 'xxxx|lorem|<todo>'
officecli query deck.pptx 'picture:no-alt'
```

---

# 飞书 Slides API 能力边界

> 2026-06-23 实测：API 早期阶段，适合增量编辑已有 Slides，**不适合程序化批量生成**。

**适合**：增量编辑已有在线 Slides、极简信息页（≤5 页）、iconpark 图标加速、白板嵌入。

**不适合**：复杂排版、自动化批量生成、数据驱动图表/表格、>10 页 deck。

关键限制：无布局引擎（元素靠像素坐标）、无模板系统、+create 最多 10 页、内容写入不可靠（`<data>` 被静默丢弃）。

---

# OfficeCLI 注意事项

1. **文件锁定**：批量操作后 `close`。`close` 失败 → 文件截断，必须先 `pkill -9 officecli` 清理残留进程
2. **`$` 符号**：`--prop text='$15M'` 单引号，双引号被 shell 展开
3. **路径引用**：`"/slide[1]"` 必须引号，zsh glob 展开 `[1]`
4. **批量输入**：用 `--input file.json` 不是 `--commands "$(...)"`
5. **表格**：`data="H1,H2;R1,R2"`（分号分行，逗号分列）
6. **图表**：`series1.name=... series1.values="1,2,3"`，不支持 `seriesN.color`
7. **图片**：`--prop src=/path/to/file.png`
8. **`borderRadius`** 不被 shape 支持，用 `preset=roundRect`
9. **幻灯片尺寸** 16:9 = 33.87×19.05cm
10. 构建完成三连：`close && validate && ls -lh`

## 文本溢出（autofit）

```python
from pptx import Presentation
from pptx.oxml.ns import qn
from lxml import etree

prs = Presentation("output.pptx")
for slide in prs.slides:
    for shape in slide.shapes:
        if not shape.has_text_frame:
            continue
        bodyPr = shape.text_frame._txBody.find(qn('a:bodyPr'))
        for tag in [qn('a:normAutofit'), qn('a:spAutoFit'), qn('a:noAutofit')]:
            for el in bodyPr.findall(tag):
                bodyPr.remove(el)
        norm = etree.SubElement(bodyPr, qn('a:normAutofit'))
        norm.set('fontScale', '55000')
prs.save("output.pptx")
```

| fontScale | 比例 | 适用 |
|-----------|------|------|
| `80000` | 80% | 标题略溢出 |
| `65000` | 65% | 卡片正文 |
| `55000` | 55% | 列表/表格（推荐） |
| `40000` | 40% | 极端密集 |

## 大 deck 构建策略（50+ 页）

1. 读源文档 → 按章节拆分 5 个 section
2. 并行 5 个 subagent，各自写 section 的 shell 脚本（不直接调 officecli）
3. 顺序执行 Part 1-5 → close → validate → 确认 >100KB
4. python3 post-process（autofit）

---

# 如何修改模板

## 改品牌色（最常见）

编辑 `themes/<id>.md` 的色板表，改 primary 和 accent 色值。连锁修改：
1. accent_deco → 取 primary 的 70% 亮度版
2. `content_orange` 的 background → 改成新 accent

## 改字体

编辑 theme 文件字体行：`Noto Sans SC` → 你的字体名。确保系统已安装（`fc-list :lang=zh | cut -d: -f2 | sort -u`）。

## 改字号

编辑 theme 文件字号阶梯表。只改 Body 会打破 H1/Body 比例，需同步检查。

## 添加新主题

在 `themes/` 下新建 `<id>.md`（参照 `professional_blue.md` 格式），在 §主题目录 中加一行。

## 添加新布局

在 `layouts/` 下新建 `<name>.md`（网格公式 + bash 模板），在 §布局目录 中加一行。

## 改默认主题

三处：主题目录表 `★默认` 标 → 引擎选择默认分支 → ppt-master Step 2 默认名。

## 不可变限制

| 不可变 | 原因 |
|--------|------|
| 幻灯片尺寸 33.87×19.05cm | OfficeCLI/ppt-master 硬编码 16:9 |
| 圆角 borderRadius | OfficeCLI shape 不支持 |
| 图表系列颜色 | `seriesN.color` 不被支持 |
| halfFrame 装饰 | OfficeCLI preset，换引擎需手写 SVG path |
