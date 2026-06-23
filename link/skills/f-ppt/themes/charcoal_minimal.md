# charcoal_minimal

> OfficeCLI 内置色板。炭灰主导，极简克制。

## 设计理念

炭灰（`#36454F`）是最克制的主色——接近黑白但保留一丝暖度。不靠颜色制造层级，靠留白和字号差别。适合文字量大的企业汇报，内容本身是主角，设计退后。字号偏小（28/18），靠大量负空间建立呼吸感。

## 色板

| 角色 | 色值 | 名称 | 用法 |
|------|------|------|------|
| **primary** | `#36454F` | Charcoal | **主力色**。封面背景、标题文字、分隔线。与白底对比度 9.5:1 |
| **accent** | `#212121` | Near Black | **深黑强调**。重点文字、KPI 数字。仅比 primary 深一级，不跳跃 |
| **dark** | `#333333` | Dark Gray | **正文色**（浅色背景） |
| **pure_black** | `#000000` | Pure Black | 封面/结束页背景 |
| **white** | `#FFFFFF` | White | 深色背景文字、卡片底色 |
| **gray** | `#7A8A94` | Slate Gray | **弱化文字**。偏蓝灰，冷调中性 |
| **light_bg** | `#F2F2F2` | Light Gray | 卡片底色。比 white 略暗，做微妙层级区分 |
| **accent_deco** | `#5A6B77` | Mid Charcoal | focus 页装饰形状 |

### 色板使用规则

1. 整个色板无彩色（全灰阶），视觉差异靠明度而非色相
2. 内容页白底 + dark 正文 + primary 标题——最干净的组合
3. 不要引入任何彩色（包括图表）。图表用 primary + light_bg + gray + dark 四色灰阶
4. 留白是主动设计元素：每页内容不超过 60% 面积
5. 卡片间距比其他主题大 20%（`gap=1cm` 替代 `0.76cm`）

## 字体

| 角色 | 字体 | 回退链 |
|------|------|--------|
| **全角色统一** | Noto Sans SC | `"Noto Sans SC", "Microsoft YaHei", sans-serif` |

英文 deck 可用 Calibri Light（正文）+ Calibri（标题）。

## 字号阶梯

> 偏小字号，靠留白建立层级。标题与正文比例保持 1.5:1。

| 级别 | 字号 | 粗细 | 用途 |
|------|------|------|------|
| **Hero** | 40pt | Regular | 封面大标题 |
| **End** | 36pt | Regular | 结束页 |
| **H1** | 28pt | Regular | 内容页标题 |
| **H2** | 22pt | Regular | 二级标题 |
| **H3** | 20pt | Regular | focus 副标题 |
| **H4** | 18pt | Regular | 卡片标题（与正文同号，靠粗体区分） |
| **Body** | 18pt | Regular | 正文主力 |
| **Body-S** | 17pt | Regular | 紧凑正文 |
| **Body-XS** | 16pt | Regular | 高密度 |
| **Caption** | 12pt | Regular | 脚注（比通用更小，极简风） |

**关键规则**：标题 (28pt) / 正文 (18pt) = 1.55:1。H4 与 Body 同号（18pt），唯一区别是 H4 可用 Bold 或 primary 色。这是刻意设计——减少字号层级数，靠位置和颜色区分。

## 封面规格

| 变体 | 背景色 | 标题色 | 标题字号 | 副标题 | 适用 |
|------|--------|--------|---------|--------|------|
| `cover_dark` | `#000000` | `#FFFFFF` | H1 (28pt) | `#7A8A94` H4 (18pt) | 企业年度报告 |
| `cover_blue` | `#36454F` | `#FFFFFF` | H1 (28pt) | `#F2F2F2` H4 (18pt) | 对外简介 |
| `cover_orange` | `#FFFFFF` | `#36454F` | H1 (28pt) | `#7A8A94` H4 (18pt) | 内部通讯 |
| `cover_center` | `#FFFFFF` | `#212121` | Hero (40pt) | `#36454F` H3 (20pt) | 极简标题页 |
