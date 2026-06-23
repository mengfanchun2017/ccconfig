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
  ├─ 默认 → OfficeCLI（AI-native JSON 批量，精确布局）
  ├─ "用模板"/"mckinsey风格"/"专业商务" → ppt-master（9 种布局模板，SVG→DrawingML）
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

**默认**：`mckinsey`（白底 + 深蓝页眉 `#005587` + 琥珀强调 `#F5A623`，专业商务）。

**深色/科技风**：用户说"深色""科技风""暗色"时切换 `anthropic`（深色渐变 + 橙色 `#D97757` 强调）。

模板库：路径见 `conf/f-ppt.json` → `engines.ppt-master.path`，layouts 子目录下 22 种模板。

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

## 设计系统

OfficeCLI 内置设计规范，生成 deck 时直接引用：

### 色板速查

| 主题 | 主色 | 辅色 | 强调色 | 正文 | 适用场景 |
|------|------|------|--------|------|---------|
| Midnight Executive | `1E2761` | `CADCFC` | `FFFFFF` | `333333` | 金融、高管报告 |
| Coral Energy | `F96167` | `F9E795` | `2F3C7E` | `333333` | 产品发布、营销 |
| Forest & Moss | `2C5F2D` | `97BC62` | `F5F5F5` | `2D2D2D` | 可持续、ESG |
| Charcoal Minimal | `36454F` | `F2F2F2` | `212121` | `333333` | 极简企业风 |
| Ocean Gradient | `065A82` | `1C7293` | `21295C` | `2B3A4E` | 科技、数据 |

### 字号规范

| 元素 | 最小 | 典型 |
|------|------|------|
| 幻灯片标题 | ≥ 36pt bold | 36-44pt |
| 段落标题 | ≥ 20pt | 20-24pt |
| 正文 | ≥ 18pt | 18-22pt |
| 脚注/标签 | ≥ 10pt muted | 10-12pt |

### 字体配对

| 标题 | 正文 | 适用 |
|------|------|------|
| Georgia | Calibri | 正式商务、金融 |
| Arial Black | Arial | 营销、产品发布 |
| Trebuchet MS | Calibri | 科技、SaaS |
| Consolas | Calibri | 开发者工具 |

### 布局网格

Widescreen 16:9 = `33.87 × 19.05cm`，12 列网格：
- 边距 ≥ 1.27cm
- 卡片间距 ≥ 0.76cm
- 3 卡布局：`col = (33.87 - 3 - 1.52) / 3 = 9.78cm`

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
