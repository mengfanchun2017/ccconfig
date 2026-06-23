# midnight_executive

> OfficeCLI 内置色板。深海军蓝主导，金融高管风格。

## 设计理念

深海军蓝（`#1E2761`）传递权威、信任、克制——金融和董事会场景的标准色。冰蓝辅色提供冷静的层级区分。比 professional_blue 更严肃：无橙色跳跃色，字号略大（投影距离较远时保持可读）。深色封面 + 浅色内容页交替，仪式感强。

## 色板

| 角色 | 色值 | 名称 | 用法 |
|------|------|------|------|
| **primary** | `#1E2761` | Deep Navy | **主力色**。封面/章节页背景、内容页标题文字、图表系列主色。白底上做标题对比度 12.5:1（WCAG AAA） |
| **accent** | `#CADCFC` | Ice Blue | **辅色/强调**。浅蓝卡片底、图表系列辅色、KPI 副标签。与 primary 形成 60% 亮度差，层级分明 |
| **dark** | `#333333` | Dark Gray | **正文色**（浅色背景）。接近黑但比纯黑柔和，适合大面积阅读 |
| **pure_black** | `#000000` | Pure Black | **仪式感背景**。封面/结束页沉浸式背景。**不要**用于内容页 |
| **white** | `#FFFFFF` | White | 深色背景文字、内容页卡片底色 |
| **gray** | `#8899BB` | Steel Blue Gray | **弱化文字**。副标题、页码、脚注。与白底对比度 3.5:1 |
| **light_bg** | `#F0F4FF` | Ice Mist | 目录页卡片底色。取 accent 的 15% 亮度版 |
| **accent_deco** | `#3A4FA0` | Mid Navy | focus 页 halfFrame 装饰。介于 primary 和 accent 之间 |

### 色板使用规则

1. primary、accent、dark、white 是核心四色
2. 内容页白底：primary 标题 + dark 正文（最常见）
3. primary `#1E2761` 做背景时，文字用 white 或 accent（`#CADCFC`），**不要**用 dark（看不清）
4. pure_black 背景页：文字只用 white 或 gray
5. 与 professional_blue 的关键区别：**无橙色**，强调靠明度差（深蓝 vs 冰蓝）而非色相对比。数据高亮用 accent（`#CADCFC`）或 white 大字

## 字体

| 角色 | 字体 | 回退链 |
|------|------|--------|
| **全角色统一** | Noto Sans SC | `"Noto Sans SC", "Microsoft YaHei", "PingFang SC", sans-serif` |

纯英文 deck 可改用 Georgia（标题）+ Calibri（正文），回退链 `"Georgia", "Calibri", sans-serif`。

## 字号阶梯

> 偏金融场景字号略大（投影距离远、高管视力）。比 professional_blue 的 28/18 大一号。

| 级别 | 字号 | 粗细 | 用途 |
|------|------|------|------|
| **Hero** | 44pt | Regular | 封面大标题（cover_center） |
| **End** | 40pt | Regular | 结束页 |
| **H1** | 32pt | Regular | 内容页标题 |
| **H2** | 24pt | Regular | 二级标题 |
| **H3** | 22pt | Regular | focus 副标题 |
| **H4** | 20pt | Regular | 卡片标题 |
| **Body** | 20pt | Regular | **正文主力**（比通用 18pt 大，适合投影） |
| **Body-S** | 18pt | Regular | 紧凑正文（底线） |
| **Body-XS** | 16pt | Regular | 高密度、脚注 |
| **Caption** | 14pt | Regular | 图表标注、数据来源 |

**关键规则**：正文 18pt 是底线（Body-S），20pt 是推荐。标题/正文 = 32/20 = 1.6:1。

## 封面规格

| 变体 | 背景色 | 标题色 | 标题字号 | 副标题 | 适用 |
|------|--------|--------|---------|--------|------|
| `cover_dark` | `#000000` | `#FFFFFF` | H1 (32pt) | `#8899BB` H4 (20pt) | 董事会、正式报告 |
| `cover_blue` | `#1E2761` | `#FFFFFF` | H1 (32pt) | `#CADCFC` H4 (20pt) | 品牌展示、对外 |
| `cover_orange` | `#FFFFFF` | `#1E2761` | H1 (32pt) | `#8899BB` H4 (20pt) | 内部分享 |
| `cover_center` | `#FFFFFF` | `#1E2761` | Hero (44pt) | `#3A4FA0` H3 (22pt) | 战略报告标题 |
