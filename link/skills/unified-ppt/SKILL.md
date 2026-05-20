---
name: unified-ppt
user-invocable: true
description: |
  统一 PPT 生成 — 从 md/wiki 到飞书 PPTX 子文件。
  4 步流水线：结构化 → 模板匹配 → SVG 生成 → 导出上传。
  默认 mckinsey 模板，支持 22 种模板 + 自定义模板提取。
allowed-tools: Read, Write, Bash, Glob, mcp__minimax__web_search
---

# Unified PPT

从 wiki 文档或 Markdown 生成飞书 PPTX，4 步流水线输出原生可编辑 DrawingML。

## 背景

选用 `hugohe3/ppt-master`（⭐12.9k）作为 PPT 生成引擎。优势：输出原生 DrawingML 可编辑形状（非 PNG 光栅）、21+ 种模板、演讲者备注/转场/旁白。对比 PptxGenJS：11 页 PPT 仅 52KB vs 619KB，11/11 SVG 转换全部成功。

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

模板库：`~/git/_ext/ppt-master/skills/ppt-master/templates/layouts/`（22 种）。

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
cd /home/francis/git/_ext/ppt-master && \
python3 skills/ppt-master/scripts/svg_quality_checker.py /tmp/pptx_project

# 导出 PPTX（--only native = 纯 DrawingML 可编辑形状）
python3 skills/ppt-master/scripts/svg_to_pptx.py /tmp/pptx_project -s final \
  --only native -t fade -o /tmp/pptx_project/output.pptx

# 上传飞书（作为 wiki 子文件，侧边栏「文件」中预览编辑）
cd /tmp/pptx_project && lark-cli drive +upload --file "./output.pptx" --wiki-token <wiki节点token> --as user
```

PPTX 作为 wiki 子文件上传（`--wiki-token`），在飞书 wiki 侧边栏「文件」中可直接预览编辑，**不嵌入** wiki 正文。

飞书 API 不支持创建原生在线 Slides（仅 doc/sheet/bitable），wiki 子文件是唯一方式。

---

# PPT 内容仓库与 Slides API 操作

> 飞书原生 Slides XML API（`larkoffice sml/2.0`）操作能力矩阵。

## 仓库

`https://my.feishu.cn/base/JnXYbjiR9aZOFrsuOGUc09mXnZd`

| 表 | ID | 说明 |
|---|----|------|
| Presentations | `tblgJhdGJlTxf5S7` | PPT 元数据：名称、Wiki URL、Presentation ID、页数、图片数、分类 |
| Slides | `tblORDssdq53f3Mz` | 每页内容：Slide ID、页码、标题、完整文本、图片 Tokens、关联 PPT |

Slides.`所属PPT` → Presentations（双向关联，反向字段 `Slides`）。

## 可行操作

### 读取
| 操作 | 命令 | 说明 |
|------|------|------|
| 读完整 PPT XML | `lark-cli slides xml_presentations get --params '{"xml_presentation_id":"<pid>"}' --format json` | 返回 `code:0` 格式 |
| 读单页 XML | `lark-cli slides xml_presentation.slide.get` | 返回单页 |
| 提取文本 | 正则 `<p>(.*?)</p>` 去标签 | 稳定可靠 |
| 提取图片 token | 正则 `<img[^>]*src="([^"]*)"` | 注意 `<img>` 非自闭合 |

### 创建
| 操作 | 命令 | 说明 |
|------|------|------|
| 新建空 PPT | `lark-cli wiki +node-create --space-id <id> --obj-type slides --title "<name>"` | `obj_token` = presentation_id |
| 新建页 | `lark-cli slides xml_presentation.slide.create` | 支持空页或带 XML |
| 插入文本页 | slide.create + `<shape type="text">` XML | `<p>` `<span>` 富文本 |
| PPTX 上传为 wiki 子文件 | `lark-cli drive +upload --file ./out.pptx --wiki-token <token>` | 侧边栏"文件"中预览编辑 |

### 更新/删除/复制
| 操作 | 命令 | 说明 |
|------|------|------|
| 替换整页 | `lark-cli slides xml_presentation.slide.replace` | 用完整 XML 替换 |
| 删除页 | `lark-cli slides xml_presentation.slide.delete` | 直接删除 |
| 复制 PPT（保留图片） | `lark-cli drive files copy --params '{"file_token":"<src>"}' --data '{"type":"slides","name":"<name>"}'` | **保留所有图片**（内部 media token 随文件复制） |
| 跨 PPT 合并文本页 | drive copy + slide.create 插入 | 纯文本跨 PPT 合并可行 |

### 批量提取
```python
# 关键点:
# 1. API 返回 code:0 (非 ok:true)
# 2. 过滤 [lark-cli] 日志行
# 3. <img> 非自闭合，用 r'<img[^>]*>.*?</img>' 匹配
# 4. ThreadPoolExecutor(6) 并行
```

## 不可行操作

| 操作 | 原因 |
|------|------|
| 跨 PPT 复制图片页 | 图片使用内部 media token → `relation mismatch` (4000030) |
| PPTX 导出 | `export_tasks` 仅支持 doc/sheet/bitable/docx |
| PPTX 导入为在线 Slides | `import_tasks` 不支持 slides |
| Drive 图片插入 slide | slide `<img src>` 必须是内部 media token |

## PPT 合并工作流（推荐）

```
1. drive files copy <含图源文件> → 新 PPT（保留图片）
2. 在新 PPT 上 slide.create 插入文本页 / slide.delete 删除不需要的页
3. 页面重排：slide.replace 调整
```

### 导出选项速查

| 选项 | 说明 |
|------|------|
| `-s final` | 使用 svg_final/ 目录 |
| `--only native` | 仅原生可编辑形状（推荐） |
| `-t fade\|push\|wipe\|none` | 页间转场效果 |
| `-a mixed` | 元素入场动画（默认 mixed 自动变化） |
| `--no-notes` | 关闭演讲者备注 |

### 依赖

- Python 3 + `python-pptx` + `cairosvg`（全局已安装）
- ppt-master 仓库：`~/git/_ext/ppt-master/`
- 无需 Node.js/npm

### 上传要点

- 必须 `cd` 到文件所在目录，用相对路径 `--file "./output.pptx"`
- `--wiki-token` 上传到 wiki 节点下作为子文件（非 Drive 根目录）
- ❌ 不用 `--folder-token`（Drive 文件夹，与 wiki 无关）
- ❌ 不用 `/tmp/` 绝对路径
