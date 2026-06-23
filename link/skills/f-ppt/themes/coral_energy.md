# coral_energy

> OfficeCLI 内置色板。珊瑚红主导，活泼有冲击力。

## 设计理念

珊瑚红（`#F96167`）传递能量、热情、行动——适合需要调动情绪的场合。深蓝（`#2F3C7E`）作为对比强调色，制造冷暖碰撞。字号略大（标题 36pt），KPI 数字可达 60-72pt。色板整体偏暖，避免大面积冷色。

## 色板

| 角色 | 色值 | 名称 | 用法 |
|------|------|------|------|
| **primary** | `#F96167` | Coral Red | **主力色**。封面背景、标题强调、KPI 大数字。与白底对比度 4.0:1（WCAG AA） |
| **accent** | `#2F3C7E` | Deep Navy | **对比强调**。与 primary 形成冷暖碰撞，用于关键数据、对比色块 |
| **dark** | `#333333` | Dark Gray | **正文色**（浅色背景） |
| **pure_black** | `#000000` | Pure Black | 封面/结束页背景。也可用 primary 替代（品牌色封面更活泼） |
| **white** | `#FFFFFF` | White | 深色背景文字、卡片底色 |
| **gray** | `#8B7E6A` | Warm Muted | **弱化文字**。偏暖灰色，与珊瑚红底协调 |
| **light_bg** | `#FFF5F5` | Blush | 目录页卡片底色。取 primary 的 10% 亮度版 |
| **accent_deco** | `#E8878B` | Light Coral | focus 页装饰形状。primary 的 60% 亮度版 |

### 色板使用规则

1. primary 橙色底 + white 字时对比度 4.0:1，≥18pt 正文可用（比 professional_blue 的 `#F0861C` 安全）
2. accent `#2F3C7E` 用于对比元素，**不要**大面积做背景（太暗，与 primary 的暖调冲突）
3. KPI 大数字用 primary 色 + 60-72pt，是此主题的核心视觉记忆点
4. 内容页可浅灰底（`#FFF5F5`）替代纯白底，强化暖调氛围

## 字体

| 角色 | 字体 | 回退链 |
|------|------|--------|
| **全角色统一** | Noto Sans SC | `"Noto Sans SC", "Microsoft YaHei", sans-serif` |

英文 deck 可用 Arial Black（标题）+ Arial（正文），回退链 `"Arial Black", "Arial", sans-serif`。

## 字号阶梯

> 偏营销场景，标题和 KPI 数字偏大。

| 级别 | 字号 | 粗细 | 用途 |
|------|------|------|------|
| **Hero** | 48pt | Bold | 封面大标题（营销活动名） |
| **End** | 40pt | Regular | 结束页 |
| **H1** | 36pt | Regular | 内容页标题 |
| **H2** | 24pt | Regular | 二级标题 |
| **H3** | 22pt | Regular | focus 副标题 |
| **H4** | 20pt | Regular | 卡片标题 |
| **Body** | 18pt | Regular | 正文主力 |
| **Body-S** | 17pt | Regular | 紧凑正文 |
| **Body-XS** | 16pt | Regular | 高密度、标签 |
| **Caption** | 14pt | Regular | 脚注、来源 |

**KPI 大数字**：60-72pt Bold，primary 色。这是此主题区别于其他主题的核心特征。

## 封面规格

| 变体 | 背景色 | 标题色 | 标题字号 | 副标题 | 适用 |
|------|--------|--------|---------|--------|------|
| `cover_dark` | `#000000` | `#FFFFFF` | H1 (36pt) | `#8B7E6A` H4 (20pt) | 正式产品发布 |
| `cover_blue` | `#F96167` | `#FFFFFF` | H1 (36pt) | `#FFFFFF` H4 (20pt) | 品牌活动、营销 |
| `cover_orange` | `#FFFFFF` | `#F96167` | H1 (36pt) | `#8B7E6A` H4 (20pt) | 轻量分享 |
| `cover_center` | `#FFFFFF` | `#F96167` | Hero (48pt) | `#2F3C7E` H3 (22pt) | 产品名/活动名 |
