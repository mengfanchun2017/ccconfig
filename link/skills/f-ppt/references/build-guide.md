# ppt-master 构建参考手册

> professional_blue 模板实战验证。所有内容页生成遵守此手册，避免文字溢出和居中偏移。

## 字号常量（1280×720 px SVG）

| 常量 | 值 | 用途 |
|------|-----|------|
| `FT` | 30px | 页面标题（content page title） |
| `FH` | 20px | Section 标题条（蓝底反白单行） |
| `FB` | 18px | 正文（硬上限，不可超过） |
| `FS` | 15px | 小字/注释 |
| `FN` | 13px | 脚注/标签 |

封面和章节页字号由各自模板 SVG 定义，不在上表范围内。

## 形状高度公式

```
shape_height = text_lines × line_height + padding_top + padding_bottom
```

| 元素 | 行高 | 上 padding | 下 padding | 示例 |
|------|------|-----------|-----------|------|
| Section 标题条 | — | 12px | 12px | 单行 20px → h=36px |
| 正文行 | 28px | — | — | 3 行 → 84px + padding |
| 卡片 | 28px | 24px | 16px | 4 行 → 4×28+24+16=152，取 h≥200px |
| 表格行 | 24px | 22px | 14px | 单行 18px → h≥60px |
| 时间线条 | — | 14px | 14px | 双行 15+13px → h≥62px |

## 中文列宽公式

```
col_min_width = 汉字数 × font_size × 1.15
```

1.15 是安全系数。例如「单机月电费（50%/额定）」= 12 字 × 18px × 1.15 ≈ 248px → 列宽 ≥ 250px。

## 文字垂直居中

```
baseline_y = rect_center_y + font_size × 0.35
```

- rect_center_y = rect.top + rect.height / 2
- 系数 0.35 是 Arial/微软雅黑的 cap-height 补偿经验值

实例：标题 bar y=38 h=72 → center=74，font=30 → baseline = 74 + 30×0.35 = 84.5 → 取 85。

## 卡片网格模板

2 列布局（543px 每列，8px gap）：
```
cx = 96 + col × 551   # col ∈ {0, 1}
cy = 182 + row × 248  # row ∈ {0, 1}
cw, ch = 543, 230     # 宽卡（≤5 行正文）
cw, ch = 355, 96      # 窄卡（≤3 行正文）
```

卡片内部布局（宽卡 543×230）：
```
y_title  = cy + 48   # 标题行（20px font）
y_line1  = cy + 82   # 正文第 1 行（18px）
y_line2  = cy + 110  # 正文第 2 行
y_line3  = cy + 138  # 注释行（15px）
```

圆圈编号：`cx+28, cy+42, r=15`，数字 y = cy+42+15×0.35 ≈ cy+48。

## 表格模板

4 列表格，列宽按内容计算：

```python
cols_x = [96, 340, 560, 760]   # 根据列宽调整
cols_w = [235, 210, 190, 430]  # col3 为差异列，加宽
row_h = 60
y_start = 128
for ri, row in enumerate(rows):
    y = y_start + ri * row_h
    # header: bg=blue, fg=white
    # body: bg=light/white 交替, fg=dark, diff col=blue bold
    text_y = y + 38  # 上 padding 22px
```

## 时间线模板

5 节点水平时间线：
```
mw = 195          # 每节点宽度
mgap = 16         # 节点间距
mx = 96 + i × (mw + mgap)
bar: h=62, rx=6
label: y=bar_y+26 (15px font)
desc:  y=bar_y+50 (13px font)
arrow: x=bar_x+mw+2, y=bar_y+36 (20px)
```

## 内容页 shell 函数

```python
def content_page(num, chap, title, body, org=""):
    s = load("03_content.svg")
    s = sub(s, CHAPTER_NUM=chap, PAGE_TITLE=title, PAGE_NUM=num, ORG_SHORT=org)
    return s.replace("{{CONTENT_AREA}}", body)
```

**⚠️ `{{CONTENT_AREA}}` 必须独立**：在 03_content.svg 中位于分隔线和 Footer 之间，不被任何 `<text>`/`<g>` 包裹。body 内容直接替换占位符。

## 禁止事项

- ❌ 正文 > 18px（必然溢出）
- ❌ 表格列宽 < 汉字数 × font × 1.1
- ❌ `{{CONTENT_AREA}}` 放在 `<text>` 标签内
- ❌ 启用 autofit 后处理（编辑时字体跳变）
- ❌ 卡片行数超过容量上限不调整高度
