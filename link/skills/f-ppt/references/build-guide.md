# OfficeCLI 构建参考手册

> 16:9 = 33.87 × 19.05cm = 960 × 540pt。所有公式基于 OfficeCLI 坐标系统。

## 字号常量

| 常量 | standard | compact | relaxed | 用途 |
|------|---------|---------|---------|------|
| `FT` | 28pt | 26pt | 32pt | 页面标题 |
| `FH` | 20pt | 18pt | 22pt | Section 标题条 |
| `FB` | 18pt | 16pt | 20pt | 正文 |
| `FS` | 15pt | 14pt | 16pt | 小字/注释 |
| `FN` | 13pt | 12pt | 14pt | 脚注/标签 |

封面和章节页字号由各 theme 的 Hero/End 级定义。

## 布局网格（16:9）

边距 1.5cm，间距按密度：

| 密度 | gap | Body | 适用 |
|------|-----|------|------|
| standard | 0.76cm | 18pt | 常规 |
| compact | 0.5cm | 16pt | 密集 |
| relaxed | 1cm | 20pt | 演讲 |

### 多列网格公式

```
col_w = (33.87 - 2×1.5 - (n-1)×gap) / n
x_i   = 1.5 + i × (col_w + gap)       # i ∈ {0..n-1}
```

| n | standard col_w | compact col_w | 适合 |
|---|---------------|---------------|------|
| 1 | 30.87cm | 30.87cm | 全宽正文 |
| 2 | 15.06cm | 15.19cm | 双栏对比 |
| 3 | 9.78cm | 9.95cm | 三栏并列 |
| 4 | 7.08cm | 7.25cm | 2×2 网格 |
| 5 | 5.46cm | 5.63cm | 密集五列 (body→XS) |

n≥5 时正文降为 Body-XS（16pt→14pt/compact），否则文字溢出。

## 页面类型坐标

### 封面 (cover_dark)

```
bg = pure_black (或 theme primary)
标题: x=2cm, y=5cm, w=29.87cm, h=4cm, size=36pt, color=white, align=center
副标题: x=2cm, y=9.5cm, w=29.87cm, h=1.5cm, size=18pt, color=gray, align=center
日期: x=2cm, y=15cm, w=29.87cm, h=1cm, size=16pt, color=gray, align=center
```

### 目录 (TOC)

```
标题: x=1.5cm, y=0.8cm, w=30.87cm, h=2cm, size=28pt, color=primary
条目: 左右两列
  左列: x=1.5cm, 右列: x=17.3cm
  编号: w=1.5cm, size=20pt, color=primary, bold
  标题: w=12cm, size=18pt, color=dark
  每项 y 间距: 2.5cm, 起始 y=3.5cm
```

### 内容页 shell

```
背景: white (#FFFFFF)
标题: x=1.5cm, y=0.8cm, w=30.87cm, h=2cm, size=FT, color=primary
正文区: y_start=3cm, 可用高度=14cm
```

正文区布局由 Q3 列数决定：
- 1 列: 全宽 30.87cm
- 多列: 按网格公式计算 col_w 和 x_i

### 卡片内部（N 列布局）

```
卡片底: preset=roundRect, fill=white (或 light_bg)
卡片标题: y=卡片y+0.5cm, size=FH, color=primary, bold
卡片正文: y=卡片y+2cm, size=FB, color=dark
卡片内边距: 左右 0.5cm
```

### 聚焦页 (focus)

```
背景: white (或 primary/accent 反色)
居中标题: x=4cm, y=6cm, w=25.87cm, h=3cm, size=H2, color=dark
正文: x=4cm, y=9.5cm, w=25.87cm, h=4cm, size=FB, color=dark
```

### 结束页 (end)

```
bg = pure_black (或 theme primary)
文字: "谢谢" (或自定义)
  x=2cm, y=6.5cm, w=29.87cm, h=4cm, size=End, color=white, align=center
副文: x=2cm, y=12cm, w=29.87cm, h=2cm, size=H4, color=gray, align=center
```

## 中文列宽估算

```
col_min_width = 汉字数 × font_size_pt × 1.15 / 72 × 2.54  (cm)
```

粗略: 12 字 × 18pt ≈ 6-7cm。文字多的表格列适当加宽。

## 文字垂直居中

OfficeCLI shape 内文字默认左上对齐。居中通过调整 y 坐标实现：

```
text_y = shape_y + (shape_h - text_lines × line_height) / 2
```

多行文字: 每行 line_height ≈ font_size × 1.5

## 禁止事项

- ❌ 正文 > 密度对应的 FB 上限
- ❌ 表格列宽 < 内容所需最小宽度
- ❌ 封面带副标题（style-rules.md 硬规则）
- ❌ 任何页面出现组织/部门标记
- ❌ 引入 theme 色板外的颜色
- ❌ Shape 内容超过 shape 高度（用 autofit 后处理兜底）

## 内容页坐标统一标准

**所有内容页（含 TOC）标题和分隔线必须在相同位置，不可页间偏移**：

| 元素 | 坐标 | 说明 |
|------|------|------|
| 页面标题 | x=1.5cm, y=1.0cm, w=30.87cm, h=2.4cm | size=FT(28pt), color=dark, bold |
| 分隔线 | x=1.5cm, y=3.0cm, w=30.87cm, h=0.03cm | color=LL(E5E6EB) |
| 正文区起点 | y=3.8cm | 标题+分隔线之后 |
| 正文区可用高度 | 13cm | 3.8cm → 16.8cm |
| 页码 | x=30.5cm, y=17.5cm, w=1.5cm, h=0.6cm | size=FN, color=gray, align=right |

封面和结束页不在此标准内（各自独立坐标）。

## 多段落文本框

**列表类内容（如配置要点、步骤说明）使用单一 textbox + 逐段 add paragraph，不拆成多个独立 textbox**。

```bash
# 创建主文本框（带第一段）
officecli add output.pptx /slide[N] --type textbox \
  --prop text='① 第一项内容' --prop font=Arial --prop size=14 \
  --prop color=1F2329 --prop x=2cm --prop y=3cm --prop width=12cm --prop height=10cm

# 追加段落（共享同一 textbox，用户可统一编辑）
officecli add output.pptx '/slide[N]/shape[M]' --type paragraph \
  --prop text='② 第二项内容'
officecli add output.pptx '/slide[N]/shape[M]' --type paragraph \
  --prop text='③ 第三项内容'
```

**为什么**：独立 textbox 在 PowerPoint 中需逐个选中编辑。多段落 textbox 只需点击一次即选中全部文字，方便后续修改。

## 母版设置

所有 slide 级 shape 不自动出现在母版。需要在 slidemaster/slidelayout 层显式添加：

```bash
# 母版级（所有使用该母版的 slide 继承）
officecli add output.pptx /slidemaster[1] --type shape \
  --prop preset=rect --prop fill=<primary> --prop line=none \
  --prop x=0cm --prop y=0cm --prop width=33.87cm --prop height=0.08cm

# 布局级（使用该布局的 slide 继承）  
officecli add output.pptx /slidelayout[1] --type shape \
  --prop text='' --prop font=Arial --prop size=12 --prop color=808080 \
  --prop x=30.5cm --prop y=17.5cm --prop width=1.5cm --prop height=0.6cm
```

**约束**：OfficeCLI 仅支持 5 个内置 layout（Blank/Title Slide/Title and Content/Two Content/Title Only），不可新建。layout shape 在 slide 的 `childCount` 中不体现（继承渲染），需通过 `officecli get /slidelayout[N]` 验证。
