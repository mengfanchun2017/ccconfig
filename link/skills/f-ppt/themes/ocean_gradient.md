# ocean_gradient

> OfficeCLI 内置色板。海洋蓝主导，冷色调科技感。

## 设计理念

海洋蓝（`#065A82`）传递技术、数据、深度——SaaS 和技术方案的自然选择。深蓝强调色（`#21295C`）制造层次，冷色调贯穿始终。适合数据密集、图表多的内容。字号适中（30/18），图表标注清晰。

## 色板

| 角色 | 色值 | 名称 | 用法 |
|------|------|------|------|
| **primary** | `#065A82` | Ocean Blue | **主力色**。封面背景、标题文字、图表系列主色。白底对比度 7.0:1 |
| **accent** | `#21295C` | Deep Navy | **深蓝强调**。KPI 数字、对比色块、图表系列辅色 |
| **dark** | `#2B3A4E` | Dark Blue-Gray | **正文色**（浅色背景）。偏蓝深灰，与蓝色系协调 |
| **pure_black** | `#000000` | Pure Black | 封面/结束页背景 |
| **white** | `#FFFFFF` | White | 深色背景文字、卡片底色 |
| **gray** | `#6B8FAA` | Ocean Gray | **弱化文字**。偏蓝灰色 |
| **light_bg** | `#EEF5FA` | Ocean Mist | 目录页卡片底色。取 primary 的 8% 亮度版 |
| **accent_deco** | `#1C7293` | Mid Ocean | focus 页装饰形状。primary 与 accent 之间 |

### 色板使用规则

1. primary、accent、dark、white 是核心四色
2. 内容页白底：primary 标题 + dark 正文
3. 图表建议用 primary + accent + light_bg 三色系列，冷色调统一
4. 数据高亮用 accent（`#21295C`），比 primary 深，形成明度对比
5. 可适度用渐变背景（`#065A82-#1C7293` 180°）替代纯色封面，呼应 "Ocean" 主题

## 字体

| 角色 | 字体 | 回退链 |
|------|------|--------|
| **全角色统一** | Noto Sans SC | `"Noto Sans SC", "Microsoft YaHei", sans-serif` |

英文 deck 可用 Trebuchet MS（标题）+ Calibri（正文），科技感更强。

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
| **Body-XS** | 16pt | Regular | 高密度、表格 |
| **Caption** | 14pt | Regular | 图表标注、轴标签 |

**图表标注**：轴标签/Caption 级（14pt），数据标签/Body-XS（16pt），确保投屏时图表可读。

## 封面规格

| 变体 | 背景色 | 标题色 | 标题字号 | 副标题 | 适用 |
|------|--------|--------|---------|--------|------|
| `cover_dark` | `#000000` | `#FFFFFF` | H1 (30pt) | `#6B8FAA` H4 (20pt) | 技术方案、正式 |
| `cover_blue` | `#065A82` | `#FFFFFF` | H1 (30pt) | `#EEF5FA` H4 (20pt) | 产品发布、对外 |
| `cover_orange` | `#FFFFFF` | `#065A82` | H1 (30pt) | `#6B8FAA` H4 (20pt) | 内部分享 |
| `cover_center` | `#FFFFFF` | `#065A82` | Hero (42pt) | `#21295C` H3 (22pt) | 数据分析报告 |
