# Layout 体系

> 基于 professional_blue 35 个 PPT 模板 layout 提取。所有坐标 16:9 (33.87×19.05cm)。

## 页面类型总览

| 类型 | 用途 | 位置 | 模板原始命名 |
|------|------|------|-------------|
| **封面** | 第 1 页 | — | start-center, start-focus-{black,blue,orange} |
| **目录** | 第 2 页 | — | index |
| **章节分隔** | 每 3-5 页内容后 | — | — (无专用 layout，用 focus 替代) |
| **内容页** | 正文每个独立小节 | — | 1/2/3/4/5/6 + 变体 |
| **聚焦页** | 核心结论强调 | — | focus + _{blue,orange,gray,blank} |
| **结束页** | 最后 | — | end |

---

## 封面

### 变体

| 变体 | 背景色 | 标题色 | 标题字号 | 副标题 | 标题位置 |
|------|--------|--------|---------|--------|---------|
| **dark** | `pure_black` | `white` | Hero | `gray` H4 | x=2cm, y=5cm, w=29.87cm, h=4cm |
| **blue** | `primary` | `white` | Hero | `white` H4 | 同上 |
| **center** | `white` | `dark` | Hero+ | `primary` H3 | x=2cm, y=5cm, w=29.87cm, h=5cm |

各 theme 的 Hero/H3/H4 字号见 theme 文件。

### 封面元素

- 底部日期: x=2cm, y=15cm, w=29.87cm, h=1cm, size=Caption, color=gray, align=center
- 撰稿人: 如有需要，日期上方一行，`AUTHOR="运行维护中心 & AI技术组"`
- 副标题: 默认不显示（style-rules.md 硬规则）

### 原始模板对应

| 模板 layout | 我们的变体 |
|------------|-----------|
| start-center (28) | cover_center |
| start-focus-black (16) | cover_dark |
| start-focus-blue (12) | cover_blue |
| start-focus-orange (4) | (orange theme 已移除) |

---

## 目录

```
标题: x=1.5cm, y=0.8cm, w=30.87cm, h=2cm, size=28pt, color=primary
条目区: y=3.5cm, h=13cm
  左列: x=1.5cm, 右列: x=17.3cm
  每项:
    编号: w=1.5cm, h=1cm, size=20pt, color=primary, bold
    标题: w=12cm, h=1cm, size=18pt, color=dark
    描述: w=12cm, h=1cm, size=15pt, color=gray (可选)
  y 间距: 2.5cm（最多 5 项/列）
```

原始模板: index (21)，2 列布局 (247pt + 284pt)。

---

## 内容页 — 列数体系

### 通用结构

```
背景: white
标题: x=1.5cm, y=0.8cm, w=30.87cm, h=2cm, size=FT, color=primary, bold
正文区: y_start=3cm, 可用高度=14cm, 可用宽度=30.87cm
```

### 列数网格

| 列数 | 每列宽 (standard) | 每列宽 (compact) | 适用 | 模板原始 |
|------|-------------------|------------------|------|---------|
| **1** | 30.87cm (全宽) | 30.87cm | 大段文字、单主题 | layout 1 (17) |
| **2** | 15.06cm | 15.19cm | 对比、并列 | layout 2 (35) |
| **3** | 9.78cm | 9.95cm | 三维度、三方案 | layout 3 (30) |
| **4** | 7.08cm | 7.25cm | 2×2 网格、SWOT | layout 4 (9) |
| **5** | 5.46cm | 5.63cm | 密集五列 (body→XS) | layout 5 (5) |
| **6** | 4.39cm | 4.55cm | 六标签（极窄） | layout 6 (31) |

网格公式:
```
col_w = (33.87 - 2×1.5 - (n-1)×gap) / n
x_i   = 1.5 + i × (col_w + gap)       # i ∈ {0..n-1}
```
gap: standard=0.76cm, compact=0.5cm, relaxed=1cm

### 列数自动选择

| 内容特征 | 推荐列数 |
|---------|---------|
| 单一大段文字 (>200字) | 1 |
| 2 个对立观点/前后对比 | 2 |
| 3 个并列维度/方案 | 3 |
| 2×2 结构 (SWOT/四象限) | 4 |
| 数据表格 | 1 (全宽表格) |
| 5+ 要点列表 | 2 (分两栏) |

### 卡片内部 (多列)

```
卡片底: preset=roundRect, fill=white (或 light_bg), line=none
卡片标题: y=卡片y+0.5cm, x=卡片x+0.5cm, w=col_w-1cm, h=1.5cm, size=FH, color=primary, bold
卡片正文: y=卡片y+2.5cm, x=卡片x+0.5cm, w=col_w-1cm, h=卡片h-3cm, size=FB, color=dark
```

---

## 内容页 — 布局变体

原始模板的变体后缀。按需实现:

### _title 变体
每列有独立标题行（比标准卡片标题更突出）。
- 模板对应: 1_title (23), 2_title (10), 3_title (3), 4_title (32), 5_title (15)

### _orange 变体
整页 accent 色背景 + 白色文字。用于强调/警示页。
- 模板对应: 1_orange (7), 2_orange (29), 3_orange (22), 4_orange (2)
- **约束**: accent 底+white 字对比度需 ≥3.2:1，仅 ≥18pt 正文可用

### _horizon 变体
上下排列非左右。上半图/图表，下半文字说明。
- 模板对应: 2_horizon (8)
- 上区: y=3cm, h=7cm (图表区)
- 下区: y=10.5cm, h=6cm (文字区)

### _full 变体
全高无页标题，每列占满整页高度。
- 模板对应: 3_full (13), 4_full (25)
- 列高 = 19.05cm (全高)

### _quarter 变体
1 大 3 小布局。左/上放主要内容 (占 2/3)，其余三个占 1/3。
- 模板对应: 4_quarter (26), 4_quarter_title (24)
- 大区: w=19.6cm, h=14cm
- 小区: w=10.3cm, h=4.3cm (3 个纵向排列)

---

## 聚焦页

```
背景: white (或 primary/accent 反色)
四角装饰: preset=halfFrame (可选，仅 focus 变体)
  fill=accent_deco (左上+右下), fill=accent (右上+左下)
  尺寸: w=4cm, h=4.5cm
居中标题: x=4cm, y=6cm, w=25.87cm, h=3cm, size=H2, color=dark, align=center
副标题: x=4cm, y=9.5cm, w=25.87cm, h=4cm, size=FB, color=dark, align=center
```

| 变体 | 背景 | 标题色 | 装饰 |
|------|------|--------|------|
| focus (标准) | white | dark | halfFrame: accent_deco+accent |
| focus_blue | primary | white | halfFrame: accent+white |
| focus_gray | gray | white | halfFrame: accent+primary |

原始模板: focus (33), focus_blue (11), focus_orange (20), focus_gray (6), focus_blank (27)

---

## 结束页

```
背景: pure_black (或 primary)
主文字: "谢谢" (或自定义)
  x=2cm, y=6.5cm, w=29.87cm, h=4cm, size=End, color=white, align=center
副文字: x=2cm, y=12cm, w=29.87cm, h=2cm, size=H4, color=gray, align=center
```

原始模板: end (34)

---

## 密度参数速查

| 参数 | standard | compact | relaxed |
|------|---------|---------|---------|
| FT (页面标题) | 28pt | 26pt | 32pt |
| FH (卡片标题) | 20pt | 18pt | 22pt |
| FB (正文) | 18pt | 16pt | 20pt |
| FS (小字) | 15pt | 14pt | 16pt |
| FN (脚注) | 13pt | 12pt | 14pt |
| gap (卡片间距) | 0.76cm | 0.5cm | 1cm |
| 卡片内边距 | 0.5cm | 0.3cm | 0.7cm |
| 行高 | 28px | 24px | 32px |

---

## 与 grill-me Q3 的映射

| Q3 选项 | 页面类型 | 列数 | 密度 | 变体 |
|---------|---------|------|------|------|
| layout=auto | 自动 | auto | Q3密度 | 无 |
| layout=1col | — | 1 | Q3密度 | 无 |
| layout=2col | — | 2 | Q3密度 | 无 |
| density=standard | — | Q3列数 | standard | 无 |
| density=compact | — | Q3列数 | compact | 无 |
| density=relaxed | — | Q3列数 | relaxed | 无 |
| 用户说"强调页" | focus | — | Q3密度 | 按 theme 选变体 |
| 用户说"警示/反色" | content | Q3列数 | Q3密度 | _orange |
| 用户说"上下布局" | content | — | Q3密度 | _horizon |

未显式选择时: `auto + standard + 无变体`。
