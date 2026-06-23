# forest_moss

> OfficeCLI 内置色板。森林绿主导，自然柔和。

## 设计理念

森林绿（`#2C5F2D`）传递信任、自然、可持续——ESG 报告和环境类内容的天然选择。亮绿辅色（`#97BC62`）提供正向、健康的语义。整体暖调偏冷绿色系，字号适中，适合数据+文字混合内容。

## 色板

| 角色 | 色值 | 名称 | 用法 |
|------|------|------|------|
| **primary** | `#2C5F2D` | Forest Green | **主力色**。封面背景、标题文字、图表系列主色。白底上对比度 6.5:1 |
| **accent** | `#97BC62` | Moss Green | **辅色/正向指标**。亮绿卡片底、图表系列辅色、达成率/正向数据 |
| **dark** | `#2D2D2D` | Near Black | **正文色**（浅色背景） |
| **pure_black** | `#000000` | Pure Black | 封面/结束页背景 |
| **white** | `#FFFFFF` | White | 深色背景文字、卡片底色 |
| **gray** | `#6B8E6B` | Sage Gray | **弱化文字**。偏绿灰色，与绿色系协调 |
| **light_bg** | `#F0F7EE` | Pale Leaf | 目录页卡片底色。取 accent 的 15% 亮度版 |
| **accent_deco** | `#5A8F3C` | Mid Green | focus 页装饰形状 |

### 色板使用规则

1. primary 是唯一深色背景色。accent（`#97BC62`）太亮，**不要**用作全屏背景——只用于卡片底或图表系列
2. 正向数据/达成率用 accent 色，负向/警示用 primary 色或红色（`#990011` 外部引入）
3. 内容页可白底或 `#F0F7EE` 浅绿底
4. 图表建议用 primary + accent + white 三色系列，避免引入与绿色系不协调的其他颜色

## 字体

| 角色 | 字体 | 回退链 |
|------|------|--------|
| **全角色统一** | Noto Sans SC | `"Noto Sans SC", "Microsoft YaHei", sans-serif` |

英文 deck 可用 Trebuchet MS（标题）+ Calibri（正文）。

## 字号阶梯

| 级别 | 字号 | 粗细 | 用途 |
|------|------|------|------|
| **Hero** | 42pt | Regular | 封面大标题 |
| **End** | 38pt | Regular | 结束页 |
| **H1** | 30pt | Regular | 内容页标题 |
| **H2** | 24pt | Regular | 二级标题 |
| **H3** | 22pt | Regular | focus 副标题 |
| **H4** | 20pt | Regular | 卡片标题 |
| **Body** | 18pt | Regular | 正文主力 |
| **Body-S** | 17pt | Regular | 紧凑正文 |
| **Body-XS** | 16pt | Regular | 高密度 |
| **Caption** | 14pt | Regular | 脚注、来源 |

## 封面规格

| 变体 | 背景色 | 标题色 | 标题字号 | 副标题 | 适用 |
|------|--------|--------|---------|--------|------|
| `cover_dark` | `#000000` | `#FFFFFF` | H1 (30pt) | `#6B8E6B` H4 (20pt) | 正式 ESG 报告 |
| `cover_blue` | `#2C5F2D` | `#FFFFFF` | H1 (30pt) | `#97BC62` H4 (20pt) | 品牌展示 |
| `cover_orange` | `#FFFFFF` | `#2C5F2D` | H1 (30pt) | `#6B8E6B` H4 (20pt) | 内部分享 |
| `cover_center` | `#FFFFFF` | `#2C5F2D` | Hero (42pt) | `#5A8F3C` H3 (22pt) | 环境项目标题 |
