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
飞书 Slides API 存在严重限制（元素靠像素坐标定位、无布局引擎、内容写入不可靠），不适合程序化批量生成。仅在极简场景（≤5 页纯文本框）或增量编辑已有 slides 时使用。

## 引擎选择

```
用户需求
  ├─ 默认 → OfficeCLI + professional_blue 主题（本 skill 内置，蓝+橙双色，Noto Sans SC）
  ├─ "用模板"/"mckinsey风格"/"专业商务" → ppt-master（9 种布局模板，SVG→DrawingML）
  ├─ "换主题"/"深色"/"科技风"/"金融风" → OfficeCLI 其他内置主题（见下方主题目录）
  ├─ 数据密集/多图表/复杂表格 → python-pptx（图表 API 最成熟）
  ├─ 有现有 PPTX 模板要套用 → ppt-master（pptx_template_import.py）
  ├─ 50+ 页大 deck → OfficeCLI 分批 + 并行 subagent
  └─ 飞书在线协作编辑（非生成） → 飞书 Slides API（+replace-slide 增量改）
```

## PPTX 生成方案矩阵

> 调研时间：2026-06-23。来源：飞书 Slides XML Schema、python-pptx 官方文档、OfficeCLI (iOfficeAI)、ccconfig f-ppt skill 实测。

| 引擎 | 类型 | AI 友好度 | 能力覆盖 | 成本 |
|------|------|----------|---------|------|
| **OfficeCLI** | 单二进制 CLI | ★★★★★ | 全能力（JSON 批量/模板合并/热重载） | 免费 |
| python-pptx | Python 库 | ★★★ | 全能力（图表/表格/图片/SmartArt/动画） | 免费 |
| ppt-master | Python + SVG | ★★★ | 模板驱动 9 种主题 | 免费 |
| PptxGenJS | JS 库 | ★★★ | 图表/表格/图片/超链接 | 免费 |
| Aspose.Slides | 多语言 SDK | ★★★ | 全能力 + AI Agent (GPT 集成) | $3,000/yr |
| SlideForge | REST API + MCP | ★★★★ | 可视化 QA | $0.05/slide |

### OfficeCLI 引擎（默认）

- 单二进制文件，零依赖（33MB），v1.0.112
- 直接操作 OpenXML，AI-native JSON 输出
- 批量模式：一个 JSON 数组完成整份 PPT
- 实时预览热重载（`watch`）
- 7 页 41 形状的 deck 仅 20KB
- 模板合并：`{{key}}` 占位符替换
- 内置设计系统：5 种色板 + 字号规范 + 字体配对 + 12 列网格
- 安装：`curl -fsSL https://d.officecli.ai/install.sh | bash`

### ppt-master 引擎（模板场景）

- 输出原生 DrawingML 可编辑形状（非 PNG 光栅）
- 9 种布局模板（academic_defense、ai_ops、government_blue/red 等）+ 30+ 图表 SVG
- 支持自定义 PPTX 模板提取
- 11 页 PPT 仅 52KB
- 依赖：Python 3 + python-pptx + cairosvg + ppt-master 仓库

## 安装

```bash
# OfficeCLI 引擎（默认，单二进制下载）
bash ccconfig/option-officecli/init.sh --install

# ppt-master 引擎（含 Python 依赖 + 仓库克隆）
bash ccconfig/option-ppt-master/init.sh --install

# 状态检查
bash ccconfig/option-officecli/init.sh --status
bash ccconfig/option-ppt-master/init.sh --status
```

## 推荐工作流

```
源内容（飞书 wiki / Markdown）
  → 内容分析 + 页面规划
  → 引擎选择（默认 OfficeCLI，模板需求用 ppt-master）
  → 生成 .pptx
  → 后处理（autofit）+ 质检（officecli validate）
  → lark-cli drive +upload --wiki-token 上传 wiki 附件
  → 用户在线打开（飞书渲染为在线 Slides 风格）
```

**不同规模策略**：

| 规模 | 方案 | 说明 |
|------|------|------|
| ≤10 页简单 | OfficeCLI 全量 JSON batch | 1 个 JSON 数组完成 |
| 10-30 页标准 | ppt-master 模板驱动 | 9 种布局 + 30+ 图表 SVG |
| 30-50 页中等 | OfficeCLI 分批脚本 | 按章节拆 3-5 个 Part 脚本 |
| 50+ 页大 deck | OfficeCLI 并行 subagent | 5 个 subagent 各写 section 脚本 → 顺序执行 |

---

# 引擎 A：ppt-master（模板驱动）

## 流水线

```
源文档(md/wiki) → Step 1: 内容结构化 → Step 2: 模板匹配 → Step 3: 逐页SVG生成 → Step 4: 质检+导出+上传
```

### Step 1 — 内容结构化

从 md 自动提取页面结构方案：

- 分析 `# ## ###` 标题层级 → 推导章节划分
- 标记 `**粗体**` 核心观点 → `KEY_MESSAGE` 候选
- 表格/列表 → 数据卡片页候选
- 代码块 → 代码展示页候选
- 输出「页面结构方案」：每页的页码、类型、标题、核心要点、内容摘要

**页面规划规则**：

| 页面类型 | 何时用 | 每段内容建议页数 |
|---------|--------|----------------|
| 封面 | 永远第 1 页 | 1 页 |
| 目录 | 永远第 2 页 | 1 页 |
| 章节分隔页 | 每 3-5 页内容后 | 1 页/章节 |
| 内容页 | 正文的每个独立小节 | 1-2 页/小节 |
| 结尾 | 永远最后 | 1 页 |

### Step 2 — 模板匹配

**默认**：`professional_blue`（本 skill 内置主题，蓝 `#0061A8` + 橙 `#F0861C`，Noto Sans SC，详见 §内置主题模板）。

**深色/科技风**：用户说"深色""科技风""暗色"时切换 `anthropic`（深色渐变 + 橙色 `#D97757` 强调）。

模板库：路径见 `conf/f-ppt.json` → `engines.ppt-master.path`，layouts 子目录下 9 种布局。

确认模板后，读取 `design_spec.md` 获取颜色/字体/间距规范，以及 5 个模板 SVG：
`01_cover.svg` `02_toc.svg` `02_chapter.svg` `03_content.svg` `04_ending.svg`

**自定义模板**：

用户提供 PPTX 模板文件 → `python3 skills/ppt-master/scripts/pptx_template_import.py <file>.pptx` → 自动提取 `design_spec.md` + 5 个模板 SVG。

### Step 3 — 逐页生成 SVG

按页面结构方案逐页填充模板 SVG，写入 `svg_final/`。

- 文件名排序决定页码：`01_cover.svg` `02_toc.svg` `03_chapter_1.svg` `04_content_xxx.svg` ...
- viewBox: `0 0 1280 720`（ppt169）
- 用 `<tspan>` 换行，禁止 `<foreignObject>`
- 透明用 `fill-opacity`/`stroke-opacity`，禁止 `rgba()`
- 字体用模板 design_spec 定义的 font-family
- 颜色严格使用模板色板（页眉色、强调色、背景色、文字色）
- 内容页核心观点放在 `KEY_MESSAGE` 条（浅色背景强调）
- 正文用卡片网格或左右分栏布局
- 封面标题中英双语
- 模板 SVG 读取策略：先读 5 个模板理解结构 → 替换 `{{PLACEHOLDER}}` → 写入 `svg_final/`

**代码块渲染**：

wiki markdown 代码块（```）直接渲染为 SVG `<text>`，不用截图。

- 等宽字体：`font-family="DejaVu Sans Mono, Courier New, monospace"`
- 暗色背景卡片：`#1E1E1E`，`rx="8"` 圆角
- 代码区 padding ≥ 24px，行间距（`dy`）18-22px
- 字号 13-15px（内容页正文 16px，代码略小）
- 语法高亮：关键字用模板强调色、字符串 `#10B981`、注释 `#64748B`
- 长代码（>25 行）拆分连续内容页，保持完整不截断
- 代码块上方标注语言标签（`Python` / `Bash`）

### Step 4 — 质检 + 导出 + 上传

```bash
# 质检（校验 viewBox、占位符一致性）
cd $(python3 -c "import json; print(json.load(open('conf/f-ppt.json'))['engines']['ppt-master']['path'])") && \
python3 skills/ppt-master/scripts/svg_quality_checker.py /tmp/pptx_project

# 导出 PPTX（--only native = 纯 DrawingML 可编辑形状）
python3 skills/ppt-master/scripts/svg_to_pptx.py /tmp/pptx_project -s final \
  --only native -t fade -o /tmp/pptx_project/output.pptx

# 上传飞书（作为 wiki 子文件）
cd /tmp/pptx_project && lark-cli drive +upload --file "./output.pptx" --wiki-token <wiki节点token> --as user
```

PPTX 作为 wiki 子文件上传，侧边栏「文件」中可预览编辑，不嵌入 wiki 正文。

### 导出选项速查

| 选项 | 说明 |
|------|------|
| `-s final` | 使用 svg_final/ 目录 |
| `--only native` | 仅原生可编辑形状（推荐） |
| `-t fade\|push\|wipe\|none` | 页间转场效果 |
| `-a mixed` | 元素入场动画（默认 mixed 自动变化） |
| `--no-notes` | 关闭演讲者备注 |

### 依赖

- Python 3 + `python-pptx` + `cairosvg`（通过 `option-ppt-master/init.sh` 安装）
- ppt-master 仓库路径见 `conf/f-ppt.json`
- 无需 Node.js/npm

### 上传要点

- 必须 `cd` 到文件所在目录，用相对路径 `--file "./output.pptx"`
- `--wiki-token` 上传到 wiki 节点下作为子文件
- 不用 `--folder-token`（Drive 文件夹，与 wiki 无关）
- 不用 `/tmp/` 绝对路径

---

# 引擎 B：OfficeCLI（AI 原生）

## 核心命令

```bash
# 创建空白 PPTX
officecli create deck.pptx

# 打开文件（启动常驻进程，加速后续操作）
officecli open deck.pptx

# 添加幻灯片
officecli add deck.pptx / --type slide --prop title="标题" --prop text="副标题" --prop background=#1E2761

# 添加形状
officecli add deck.pptx "/slide[1]" --type shape \
  --prop text="关键指标" --prop font=Georgia --prop size=36 --prop bold=true \
  --prop color=#FFFFFF --prop fill=#4472C4 --prop preset=roundRect \
  --prop x=2cm --prop y=4cm --prop width=12cm --prop height=3cm

# 批量模式（推荐 — 一次创建整个 deck）
officecli batch deck.pptx --input deck_commands.json

# 关闭 + 验证
officecli close deck.pptx
officecli validate deck.pptx

# 查看结构
officecli query deck.pptx slide --json
officecli get deck.pptx "/slide[1]" --depth 1 --json
```

## 批量模式示例

```json
[
  {"command": "add", "parent": "/", "type": "slide", "props": {"title": "封面", "text": "副标题", "background": "#1E2761"}},
  {"command": "add", "parent": "/", "type": "slide", "props": {"title": "内容页", "text": "正文内容"}},
  {"command": "add", "parent": "/slide[2]", "type": "shape", "props": {"text": "要点1", ...}},
  {"command": "add", "parent": "/", "type": "slide", "props": {"title": "结束", "text": "谢谢"}}
]
```

**注意**：批量模式需要文件先存在（先 `create` 再 `batch`）。用 `--input` 传 JSON 文件避免 stdin 冲突。

## 内置主题模板

每个主题是一套完整设计系统：色板 + 字体 + 字号阶梯 + 布局规范。生成 PPT 时直接引用主题名即可，所有色值、字号、字体自动应用。

### 主题目录

| # | 主题 ID | 主色 | 风格 | 适用场景 |
|---|---------|------|------|---------|
| 1 | **professional_blue** ★默认 | `#0061A8` 蓝 | 现代培训/课程 | 通用：课程、汇报、方案、技术分享 |
| 2 | midnight_executive | `#1E2761` 深海军蓝 | 金融高管 | 金融报告、董事会、战略规划 |
| 3 | coral_energy | `#F96167` 珊瑚红 | 产品营销 | 产品发布、营销提案、品牌活动 |
| 4 | forest_moss | `#2C5F2D` 森林绿 | ESG/可持续 | 可持续发展、环境报告、农业 |
| 5 | charcoal_minimal | `#36454F` 炭灰 | 极简企业 | 企业简介、年度总结、内部通讯 |
| 6 | ocean_gradient | `#065A82` 海洋蓝 | 科技数据 | 技术方案、数据分析、SaaS |

---
### 主题 1：professional_blue ★默认

> 提取自 `tpFrancis_Course_20260110.pptx`（35 个 slide layouts），由实际 PPT 模板逆向工程。
> **为什么是默认**：这是唯一由真实 PPT 模板完整提取的主题，其余 5 个为 OfficeCLI 内置色板。它经过了实际演示检验，拥有最完整的布局体系（35 种页面变体），覆盖所有常见场景。

#### 设计理念

蓝橙双色体系。蓝色是理性、专业、技术——适合传递信息和论证；橙色是活力、行动、强调——用来标重点和制造视觉锚点。黑色/深灰背景页（开始、结束）制造仪式感，白底内容页保证可读性。Noto Sans SC 是 Google 与 Adobe 联合开发的中日韩无衬线字体，屏幕可读性优于微软雅黑，开源免授权。

#### 色板

| 角色 | 色值 | 色块 | 名称 | 用法 |
|------|------|------|------|------|
| **primary** | `#0061A8` | ██████ | Francis Blue | **主力品牌色**。封面/章节页背景、内容页标题文字、标题装饰条、focus 页装饰形状。占彩色面积的 ~60%。白底上做标题文字对比度 4.8:1（WCAG AA 通过） |
| **accent** | `#F0861C` | ██████ | Francis Orange | **强调/反色**。`_orange` 变体页整页背景色、数据高亮、警示标注。与 primary 蓝形成 140° 互补色关系，视觉对比强烈。**不要**大面积用于内容页正文背景（刺眼）——仅用于整页反色变体或局部强调 |
| **dark** | `#1F2329` | ██████ | Near Black | **正文色**（浅色背景上）。比纯黑 `#000000` 略浅，降低对比度至舒适范围（13:1），适合大面积阅读。与 `#0061A8` 标题形成明度对比 |
| **pure_black** | `#000000` | ██████ | Pure Black | **仪式感背景**。仅用于开始页（start）、结束页（end）的黑色沉浸式背景。**不要**用于内容页背景或正文——太压抑 |
| **white** | `#FFFFFF` | ██████ | White | 深色/彩色背景上的文字色。内容页卡片底色。与 `#F0861C` 底配白字时对比度 3.2:1（仅限 28pt+ 大字，18pt 正文不可用） |
| **gray** | `#808080` | ██████ | Medium Gray | **弱化文字**。封面副标题、页码、数据来源标注。与白底对比度 3.9:1（仅限 ≥18pt） |
| **light_blue** | `#BBE2FF` | ██████ | Sky Blue | 目录页卡片底色。仅此一处使用，提供视觉变化 |
| **accent_deco** | `#2978B5` | ██████ | Steel Blue | focus 页四角 halfFrame 装饰形状填充。介于 primary 和 light 之间的中间蓝 |

**色板使用规则**：

1. primary、accent、dark、white 是核心四色（每个 PPT 必须出现）；gray、light_blue、accent_deco 是辅助色（按页面类型可选）
2. 内容页白底上用 `dark` 做正文、`primary` 做标题——这是出现频率最高的组合
3. `accent` 橙色在整页反色时作为背景（文字用 white），在局部强调时作为文字或色块（用在白底上）
4. pure_black 背景页上所有文字必须是 white 或 gray，不能出现 primary/accent 文字（看不清）
5. 不要在 `#F0861C` 背景上放 `<18pt` 的 white 文字（对比度不够）——要么放大字号，要么用 `_orange` 变体仅用于标题页

#### 字体

| 角色 | 字体 | 来源 | 回退链 |
|------|------|------|--------|
| **全角色统一** | Noto Sans SC | Google Fonts（开源） | `"Noto Sans SC", "Microsoft YaHei", "PingFang SC", sans-serif` |

**为什么不用微软雅黑**：Noto Sans SC 的屏幕渲染 hinting 优于微软雅黑，小字号（16-18pt）下笔画更清晰；字重覆盖更全（Thin→Black 7 级）；开源免授权，PPT 嵌入不触发字体许可问题。

OfficeCLI 用法：所有 shape 设置 `--prop font="Noto Sans SC"`。

#### 字号阶梯

> 实际 PPT 模板提取的 9 级字号。**Why**：43pt 用于封面是因为 start-center 布局中标题是唯一核心元素；28pt 是内容页标题的甜点——够大能引导视线，不抢占正文；18pt 是投影仪最小可读字号（10 英尺外 18pt ≈ 视力表 20/40）。

| 级别 | 字号 | 粗细 | 用途 | 出现频率 |
|------|------|------|------|---------|
| **Hero** | 43pt | Regular | 封面大标题（start-center 布局） | 极低（仅封面） |
| **End** | 38pt | Regular | 结束页"感谢聆听" | 极低（仅结束） |
| **H1** | 28pt | Regular | 内容页标题、章节名 | 每页 |
| **H2** | 23pt | Regular | 4_full 布局标题 | 低 |
| **H3** | 22pt | Regular | focus 页副标题 | 低 |
| **H4** | 20pt | Regular | `_title` 变体页标题 | 中 |
| **Body** | 18pt | Regular | **正文主力**（330 处 / 555 总，占 60%） | 绝大多数 |
| **Body-S** | 17pt | Regular | 4_title 紧凑正文 | 低 |
| **Body-XS** | 16pt | Regular | 5/5_title 高密度布局 | 低 |
| **Caption** | 15pt | Regular | focus 页装饰角标文字 | 极低 |

**关键规则**：
- 正文 = 18pt 是硬底线。16-17pt 仅在内容过多、卡片放不下时使用
- 标题 (28pt) 与正文 (18pt) 的比例 = 1.55:1，视觉层级清晰
- 所有字号均为 Regular 粗细（模板中未使用 Bold）——层级靠字号差别而非粗细差别

#### 布局体系

> 模板有 35 个 slide layouts，按命名规则自动生成不同页面变体。**Why**：数字 = 内容块数量，`_orange` = 橙色反色底，`_title` = 带独立标题区。这个命名体系让 AI 生成 PPT 时可以根据内容自动选 layout。

**页面类型分类**：

| 类别 | Layout 名称 | 用途 | OfficeCLI 对应 |
|------|-----------|------|---------------|
| 封面 | `start-focus-black` | 黑色沉浸封面，白色大字 | `background=000000` |
| 封面 | `start-focus-blue` | 蓝色品牌封面 | `background=0061A8` |
| 封面 | `start-focus-orange` | 白底橙色强调封面 | `background=FFFFFF` |
| 封面 | `start-center` | 白底居中大标题（43pt） | `background=FFFFFF` |
| 目录 | `index` | 编号列表目录，浅蓝卡片 | 卡片网格 |
| 内容×1 | `1` | 全宽单块内容 | 单 shape 全宽 |
| 内容×1 | `1_orange` | 同上，橙色反色底 | `background=F0861C` |
| 内容×2 | `2` / `2_tilt` / `2_horizon` | 双栏/倾斜/水平两块 | 2 栏网格 |
| 内容×2 | `2_orange` / `2_horizon_orange` | 两块橙色反色 | 同上+反色底 |
| 内容×3 | `3` / `3_full` | 三块/三色卡片（金绿青） | 3 栏网格 |
| 内容×3 | `3_orange` | 三块反色 | 同上+反色底 |
| 内容×4 | `4` / `4_full` / `4_quarter` | 四块/全宽四块/四象限 | 2×2 卡片网格 |
| 内容×4 | `4_orange` / `4_quarter_orange` | 四块反色 | 同上+反色底 |
| 内容×5 | `5` | 五块密集布局 | 5 列 |
| 内容×6 | `6` | 六块密集 | 3×2 网格 |
| 带标题内容 | `1_title` ~ `5_title` | 标题行 + 内容块 | 标题 shape + 内容 shapes |
| 聚焦 | `focus` / `focus_orange` / `focus_blue` / `focus_gray` | 带装饰的重点单页 | 单卡片+角落装饰 |
| 结束 | `end` | 黑色底"感谢聆听" | `background=000000` |

**布局自动选择规则**：

1. 数内容要点数 → 选对应数字的 layout（3 个要点 → `3`，4 个要点 → `4`）
2. 需要强调/警示 → 加 `_orange` 反色变体
3. 内容需要标题说明 → 用 `_title` 变体
4. 单一重点陈述 → `focus` 系列
5. 数据对比 → `4_quarter`（四象限）
6. 三色分类 → `3_full`（金/绿/青三色卡片）

**OfficeCLI 实现**（以 3 块内容为例）：

```bash
# 3 块内容页 — 白底，3 个横向排列卡片
COL_W=9.78cm  # (33.87 - 3 - 1.52) / 3
GAP=0.76cm
MARGIN=1.5cm

officecli add "$F" / --type slide --prop layout=blank --prop background=FFFFFF
# 标题
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="页面标题" --prop font="Noto Sans SC" --prop size=28 \
  --prop color=0061A8 --prop x=1.5cm --prop y=1cm --prop width=30.87cm --prop height=2cm
# 卡片 1
X=1.5cm; officecli add "$F" "/slide[last()]" --type shape \
  --prop preset=roundRect --prop fill=FFFFFF --prop line=none \
  --prop x=$X --prop y=4cm --prop width=$COL_W --prop height=10cm
# 卡片 2  
X=$(echo "1.5 + 9.78 + 0.76" | bc)cm
# ...以此类推
```

**橙色反色页实现**：
```bash
# 背景改 F0861C，所有文字→FFFFFF
officecli add "$F" / --type slide --prop layout=blank --prop background=F0861C
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="标题" --prop font="Noto Sans SC" --prop size=28 --prop color=FFFFFF ...
```

**聚焦页（focus 系列）装饰**：四角放 halfFrame 形状（`preset=halfFrame`），左上右下用 `#2978B5`（蓝），右上左下用 `#F0861C`（橙），`rot=10800000`（旋转 108°），加阴影 `outerShdw`。这是模板的视觉 DNA——在一页纯文字的 deck 里加一页 focus 就能打破单调。

#### 封面规格

| 变体 | 背景色 | 标题色 | 标题字号 | 副标题 | 适用 |
|------|--------|--------|---------|--------|------|
| `start-focus-black` | `#000000` | `#FFFFFF` | 28pt | `#808080` 20pt | 正式汇报、仪式感开场 |
| `start-focus-blue` | `#0061A8` | `#FFFFFF` | 28pt | `#808080` 20pt | 品牌展示、对外提案 |
| `start-focus-orange` | `#FFFFFF` | `#E07B05` | 28pt | `#808080` 20pt | 轻量内部分享 |
| `start-center` | 继承/白 | `#000000` | **43pt** | `#0061A8` 22pt | 课程标题、培训封面 |

#### 与其他主题的色板对比

| 主题 | 主色 | 风格 | 对比 professional_blue |
|------|------|------|-------------------|
| professional_blue | `#0061A8` 蓝 + `#F0861C` 橙 | 现代培训 | — |
| midnight_executive | `#1E2761` 深海军蓝 | 金融高管 | 更严肃、无橙色、深蓝底+白字为主 |
| coral_energy | `#F96167` 珊瑚红 | 产品营销 | 更活泼、红色主导、偏消费品 |
| forest_moss | `#2C5F2D` 森林绿 | ESG/可持续 | 更柔和、绿色自然感 |
| charcoal_minimal | `#36454F` 炭灰 | 极简企业 | 更克制、接近黑白、中性 |
| ocean_gradient | `#065A82` 海洋蓝 | 科技数据 | 更冷、深蓝渐变、偏数据报告 |

---
### 主题 2-6（OfficeCLI 内置色板）

> 以下 5 个主题来自 OfficeCLI 内置设计系统。色板精简（5 色），适合快速生成。

| 主题 | 主色 | 辅色 | 强调色 | 正文 | 适用 |
|------|------|------|--------|------|------|
| midnight_executive | `1E2761` | `CADCFC` | `FFFFFF` | `333333` | 金融、高管报告 |
| coral_energy | `F96167` | `F9E795` | `2F3C7E` | `333333` | 产品发布、营销 |
| forest_moss | `2C5F2D` | `97BC62` | `F5F5F5` | `2D2D2D` | 可持续、ESG |
| charcoal_minimal | `36454F` | `F2F2F2` | `212121` | `333333` | 极简企业风 |
| ocean_gradient | `065A82` | `1C7293` | `21295C` | `2B3A4E` | 科技、数据 |

### 通用设计规范（所有主题适用）

#### 字号规范

| 元素 | 最小 | 典型 |
|------|------|------|
| 幻灯片标题 | ≥ 28pt | 28-43pt（professional_blue 用 28pt） |
| 段落标题 | ≥ 20pt | 20-24pt |
| 正文 | ≥ 18pt | 18-22pt（professional_blue 用 18pt） |
| 脚注/标签 | ≥ 10pt muted | 10-12pt |

**跨主题规则**：正文 18pt 是底线。标题与正文比例 ≥ 1.5:1。不同主题可微调，但不可突破底线。

#### 字体配对

| 标题 | 正文 | 适用 |
|------|------|------|
| Noto Sans SC | Noto Sans SC | professional_blue 默认（中文优先） |
| Georgia | Calibri | 正式商务、金融 |
| Arial Black | Arial | 营销、产品发布 |
| Trebuchet MS | Calibri | 科技、SaaS |
| Consolas | Calibri | 开发者工具 |

**跨主题规则**：中文字体统一用 Noto Sans SC 或 Microsoft YaHei；西文可用衬线/无衬线配对。标题与正文必须同一中文字体家族。

#### 布局网格

Widescreen 16:9 = `33.87 × 19.05cm`，12 列网格：
- 边距 ≥ 1.27cm
- 卡片间距 ≥ 0.76cm
- 3 卡布局：`col = (33.87 - 2×1.5 - 2×0.76) / 3 = 9.78cm`
- professional_blue 实际边距 1.5cm（比通用 1.27cm 略宽，留白更多）

## 模板合并

```bash
# 创建模板（含 {{key}} 占位符）
officecli create template.pptx
officecli add template.pptx / --type slide --prop title="{{title}}" --prop text="{{subtitle}}"

# 合并数据
officecli merge template.pptx output.pptx --data '{"title":"Q4报告","subtitle":"营收增长18%"}'
```

## QA 检查清单

```bash
officecli validate deck.pptx                      # Schema 验证
officecli view deck.pptx issues                    # 溢出/格式问题
officecli view deck.pptx text | grep -iE 'xxxx|lorem|<todo>'  # 占位符残留
officecli query deck.pptx 'picture:no-alt'         # 缺 alt 文本的图片
```

---

# 飞书 Slides API 能力边界

> 2026-06-23 实测结论：API 处于早期阶段，适合增量编辑已有 Slides，**不适合程序化批量生成**。

飞书 Slides 使用 SML 2.0（Slides Markup Language）XML schema，命名空间 `http://www.larkoffice.com/sml/2.0`。所有元素靠绝对像素坐标定位，无布局引擎。

## 核心命令

| 命令 | 用途 | 实测状态 |
|------|------|---------|
| `slides +create --title --slides` | 创建演示文稿（最多 10 页） | ✅ 能创建空壳，内容写入不可靠 |
| `slides xml_presentation.slide.create` | 追加/插入幻灯片页 | ✅ 页面创建成功 |
| `slides +replace-slide --parts` | 替换/插入单个元素（block_replace/block_insert） | ⚠️ block_insert 格式不确定 |
| `slides +media-upload` | 上传图片获取 file_token | ✅ |
| `slides xml_presentations get` | 读取全文 XML | ⚠️ 含 PPTX 导入图形的报 3350001 |

## 元素能力

| 元素 | 能力 | 限制 |
|------|------|------|
| shape | 100+ 种预设形状（几何/箭头/星形/流程图/标注框） | 需手动计算 topLeftX/Y/width/height |
| img | 图片嵌入、裁剪、透明度 | 需先 +media-upload 获取 file_token |
| icon | iconpark 图标库 | 通过 iconType 属性引用 |
| chart | 7 种图表（pie/column/bar/line/area/radar/combo） | 需关联源表格，程序化链路复杂 |
| table | Schema 中存在 | 完整 XML 定义未文档化 |

## 样式系统

- **填充**：纯色 rgb/rgba、4 种渐变（linear/radial/rect/shape）、18 种图案、图片填充
- **边框**：10 种虚线样式、线端样式、连接样式
- **特效**：阴影（8 参数）、倒影（3 参数）、文字描边
- **排版**：5 级语义层级（title→headline→sub-headline→body→caption），字号 6-400px，200+ 字体

## 关键限制

1. **无布局引擎**：所有元素手动计算像素坐标，AI 排版极易溢出或重叠
2. **无模板系统**：仅 master slide，API 不可引用预定义布局
3. **无批量创建**：+create 最多 10 页，超 10 页需逐页 create
4. **图表伪可用**：chart 需关联源表格，数据绑定链路不透明
5. **内容写入不可靠**：`<data>` 内嵌内容被服务器静默丢弃；block_insert 返回 4001000
6. **读回受限**：含 PPTX 导入图形的 slides 读回报 3350001；单页读取 content 始终为空

## 适用场景

**适合**：增量编辑已有在线 Slides（+replace-slide 替换个别元素）、极简信息页（封面+大字，≤5 页）、iconpark 图标加速、白板嵌入

**不适合**：复杂排版、自动化批量生成、数据驱动图表/表格、>10 页 deck

## 仓库

`lark-cli slides` 系列命令，通过 `--as user` 操作在线 slides。

---

# OfficeCLI 测试记录

测试文件位于 `/tmp/ppt-tests/officecli/`：

| 文件 | 内容 | 结果 |
|------|------|------|
| `test1_blank.pptx` | 空白创建 + 添加 slides/shapes | ✅ |
| `test2_batch.pptx` | 批量 6 页创建 | ✅ 6/6 |
| `test3_merged.pptx` | 模板合并 `{{key}}` 替换 | ✅ 3 keys |
| `test5_table.pptx` | CSV → 表格，含样式 | ✅ |
| `test6_chart.pptx` | 图表 + 图片嵌入 | ✅ |
| `demo_full.pptx` | 8 页全功能演示 deck | ✅ 41/41 validate 通过 |

### 已确认的 OfficeCLI 注意事项

1. **文件锁定**：`create`/`add` 自动启动常驻进程锁定文件。批量操作后记得 `close`，或先 `pkill officecli` 清理。
2. **批量输入**：用 `--input file.json` 而非 `--commands "$(...)"` 避免 stdin 冲突警告。
3. **表格数据**：用 `data="H1,H2;R1,R2;R3,R4"` 格式（分号分行，逗号分列），首行为表头。
4. **图表数据**：用 `series1.name=... series1.values="1,2,3" series1.color=...` 格式，不能用 `data=`
5. **图片**：用 `--prop src=/path/to/file.png` 而非 `--prop image=...`
6. **路径引用**：zsh/bash 必须引用 `"/slide[1]"`，防止 glob 展开
7. **`$` 符号**：`--prop text='$15M'` 必须单引号，双引号会被 shell 展开
8. **幻灯片尺寸**：默认 16:9 = 33.87 × 19.05cm
9. **形状 ID**：自定义形状从 `@id=10000` 起，模板占位符用 `@id=2,3,...`
10. **MCP 模式**：`officecli mcp claude` 注册为 MCP server，但在当前 session 中不需要（直接 CLI 调用更高效）
11. **不支持属性**：`borderRadius`（圆角）不被 shape 支持；图表的 `series1.color`/`series2.color`/`legendPos` 不被支持，用默认图表颜色即可
12. **close 失败保护**：`officecli close` 失败会导致文件截断（如 137KB→8KB），此时文件不可恢复。构建完成后必须 `close && validate && ls -lh` 三连确认
13. **常驻进程冲突**：如果上一次 `close` 失败，残留的 officecli 进程仍锁住文件。新 `create` 会成功但实际写入旧文件。重建前必须 `pkill -9 officecli` 清理

### 大 deck 构建策略

50+ 页 PPT 的生成分两个阶段：

| 阶段 | 耗时占比 | 可并行 | 方法 |
|------|---------|--------|------|
| 内容分析 + 脚本编写 | ~90% | **可以** | 按章节拆分，多个 subagent 各自写 section 的 shell 脚本 |
| 脚本执行 | ~10% | 不能 | 单文件单进程，5 个 Part 脚本顺序执行，共约 30 秒 |

**并行化工作流**（以 50 页为例）：

```
1. 读取源文档 → 按章节拆分为 5 个 section
2. 并行启动 5 个 subagent，每个负责 1 个 section 的脚本编写
3. 收集所有脚本 → 顺序执行 Part 1-5
4. officecli close → validate → 确认文件 > 100KB
5. python3 post-process（autofit 等）
```

注意事项：
- 并行前先 `create` + `open` 好文件，所有 subagent 共用同一个文件路径
- subagent 输出 shell 脚本即可，不直接调 officecli（避免进程冲突）
- 每个 Part 脚本 ≤ 10 页，方便调试

### 文本溢出与 autofit

**核心问题**：OfficeCLI 创建 shape 时指定的 `size` 是固定字号，文本多了会溢出 shape 边界。

**OfficeCLI 的 `autoFit` 属性**（`officecli help pptx shape`）：

```
autoFit=normal  →  Shrink text on overflow（对应 OpenXML normAutofit）
autoFit=shape   →  Resize shape to fit text（对应 spAutoFit）
autoFit=none    →  Do not autofit（对应 noAutofit）
```

**关键坑**：`autoFit=normal` 写入的 `<a:normAutofit/>` **不带 `fontScale` 属性时默认值为 100000（100%）**，等于不缩小。PowerPoint 首次打开时不会自动计算缩放比例——文本仍按原大小显示，只有用户点击编辑该形状后才触发重新计算。

**正确做法**：用 python-pptx 后处理，写入带 `fontScale` 的 `normAutofit`：

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
        # 清除已有 autofit
        for tag in [qn('a:normAutofit'), qn('a:spAutoFit'), qn('a:noAutofit')]:
            for el in bodyPr.findall(tag):
                bodyPr.remove(el)
        # fontScale=55000 = 允许缩到 55%，只在溢出时触发
        norm = etree.SubElement(bodyPr, qn('a:normAutofit'))
        norm.set('fontScale', '55000')
prs.save("output.pptx")
```

**为什么不用 `fit_text()`**：python-pptx 的 `TextFrame.fit_text()` 会预计算并写入固定缩小字号，导致文本即使能撑满也被缩小、留大量空白。

**fontScale 取值指南**：

| fontScale | 最小字号比例 | 适用场景 |
|-----------|------------|---------|
| `80000` | 80% | 标题/大字，略微溢出 |
| `65000` | 65% | 卡片正文，中等密度 |
| `55000` | 55% | 列表/表格/高密度内容 |
| `40000` | 40% | 极端密集（此值以下可读性差） |

### 示例文件（`C:\unified-ppt\`）

| 文件 | 页数 | 主题 | 亮点 |
|------|------|------|------|
| `demo1_executive_report.pptx` | 5 | Midnight Executive | 柱状图 + 两栏布局 |
| `demo2_product_launch.pptx` | 5 | Coral Energy | KPI 大数字 + 时间线 |
| `demo3_data_dashboard.pptx` | 6 | Ocean Gradient | 折线图 + 环形图 |
| `系统分析师备考完全指南.pptx` | 50 | Academic Navy | 14 章全覆盖，488 形状 |

### 自定义主题：Academic Navy

用于学术/备考类 deck：
- 主色 `1E3A5F`（深海军蓝）、辅色 `E8EDF2`（浅灰）、强调色 `C4A35A`（金）、正文 `2D2D2D`、弱化 `7A8A94`
- 变体 `2A6291`（中蓝）用于二级卡片
- 警告卡片用 `990011`（深红）+ `FFFFFF` 文字

---
# 如何修改模板

修改场景按频率排序，每个场景给出**改什么 → 怎么改 → 影响范围**。

## 改公司/个人品牌色（最常见）

**场景**：你有自己的品牌色（logo 色、公司 VI 色），想替换 professional_blue 的蓝橙配色。

**改法**：在 §内置主题模板 中修改 `professional_blue` 色板的 primary 和 accent：

```
primary:  #0061A8 → 你的品牌主色
accent:   #F0861C → 你的品牌强调色
dark:     #1F2329 → 保持或改成你的深色（如 #1A1A1A）
```

**连锁修改**（改了 primary/accent 后必须同步改这些）：
1. `accent_deco` → 取 primary 的 70% 亮度版本（如 `#0061A8` → `#2978B5`），用于 focus 页装饰
2. 色板使用规则第 3 条的橙色描述 → 改成你的强调色描述
3. 橙色反色页的 `background=F0861C` → 改成你的 accent 色值
4. `3_full` 的三色点缀（金绿青）可以保留，它们与品牌色无关

**影响范围**：OfficeCLI 生成的 .pptx 全部使用新色。ppt-master 侧如果你用了 layout+brand 组合，brand spec 也需同步改。

## 改字体

**场景**：你想用微软雅黑、思源黑体、或公司购买的商业字体。

**改法**：修改 `professional_blue` 字体行：

```
"Noto Sans SC" → "Microsoft YaHei" 或 "Source Han Sans SC" 或你的字体名
```

**注意事项**：
- 中文字体必须支持 Regular 和 Bold 两个字重（professional_blue 只用 Regular，但其他主题可能需要 Bold）
- 字体名必须与系统安装名一致（`fc-list :lang=zh | cut -d: -f2 | sort -u` 查看已安装中文字体）
- PPTX 嵌入字体需要字体文件支持嵌入许可（Noto Sans SC 的嵌入许可为 "Installable"，安全）
- OfficeCLI 不负责字体嵌入——字体回退链在 `font=` 属性中指定

## 改字号阶梯

**场景**：你的内容密度需要更小/更大的字号，或投影环境要求最小正文 > 18pt。

**改法**：修改字号阶梯表：

| 改动 | 改法 | 影响 |
|------|------|------|
| 正文更大 | Body 18pt → 20pt | 每页容纳内容减少 ~15%，卡片需放大 |
| 标题更大 | H1 28pt → 32pt | 正文也要同比放大保持比例 |
| 密集内容 | Body 18pt → 16pt | 可读性下降，仅用于 >50 页大 deck |
| 比例调整 | 保持 H1/Body ≥ 1.5:1 | 低于此比例视觉层级模糊 |

**关键约束**：不要只改一个数——字号阶梯是体系，改了 Body 就得同步检查 H1~H4 的比例关系。

## 添加新主题

**场景**：你有一个完整的 PPT 模板想加入 f-ppt，供自己和他人使用。

```bash
# 1. 提取设计系统（同前面提取 professional_blue 的流程）
python3 << 'PYEOF'
from pptx import Presentation
# ... 提取色板、字体、字号、布局
PYEOF

# 2. 在 §内置主题模板 中添加新主题条目（编号 7+）
# 格式参照 professional_blue：色板表 + 字体 + 字号阶梯 + 布局体系 + 封面规格

# 3. 在主题目录表中加一行
# | 7 | your_theme | #xxx 主色 | 风格描述 | 适用场景 |

# 4. 更新引擎选择中的主题列表
```

**最少信息**（如果没有时间完整提取）：色板（主色+正文色+强调色）+ 字体 + 标题&正文字号。其余可以从通用设计规范继承。

## 修改现有主题的一个色值

**场景**：你喜欢 midnight_executive 但觉得深蓝太暗了。

**改法**：直接改对应主题的色板表单元格。注意：
- 主色改深了 → 所有用这个颜色的背景、标题、装饰都会同步变深
- 如果主色是背景色 → 检查上面的白色文字对比度（< 3:1 需调整）
- 如果主色是文字色 → 检查在白底上的对比度（< 4.5:1 需调整）

## 改布局（添加/删除内容块变体）

**场景**：你的内容经常需要 7 块布局，但模板最大只有 6。

**OfficeCLI 改法**：在生成脚本中计算网格（n 列通用公式）：
```
col_w = (33.87 - 2×margin - (n-1)×gap) / n
```
margin=1.5cm, gap=0.76cm → 7 列 = (33.87-3-4.56)/7 = 3.76cm/列（太窄，建议换 2 行布局）

**ppt-master 改法**：需要创建新的布局 SVG（`skills/ppt-master/templates/layouts/<name>/03_content.svg`）。

## 改默认主题

**场景**：你希望 f-ppt 默认使用 midnight_executive 而非 professional_blue。

**改法**：
1. §内置主题模板 → 主题目录表中，把 `★默认` 标移到目标主题
2. §引擎选择 → 默认分支文字改为新主题名
3. §引擎 A Step 2 → 默认模板名改为新主题名

## 模板修改的 "不变量"（改不动的）

这些是 OfficeCLI / python-pptx / SVG 的硬限制，无法通过改模板解决：

| 不可变 | 原因 |
|--------|------|
| 幻灯片尺寸 33.87×19.05cm | OfficeCLI 和 ppt-master 都硬编码 16:9 |
| 圆角 borderRadius | OfficeCLI shape 不支持，只能用 `preset=roundRect`（固定圆角半径） |
| 图表系列颜色 | OfficeCLI chart 的 `seriesN.color` 不被支持，用默认色 |
| halfFrame 装饰形状 | 这是 OfficeCLI preset 枚举值之一，换了引擎（如 python-pptx）需手写 SVG path |
| `_orange` 反色命名 | 这是 professional_blue 模板的内部命名约定，换主题后命名逻辑可能不同 |
