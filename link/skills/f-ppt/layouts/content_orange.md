# content_orange

**角色**：橙色反色变体。整页 accent 色背景 + 白色文字。

**适用**：强调/警示页、章节分隔页、需要视觉冲击的内容。

**结构**：accent 色全屏背景 → 所有文字白色。内容结构与对应 content_N 完全相同，只换色。

**与普通 content 的唯一区别**：
- `background=${accent}` 替代 `background=${white}`
- 标题和正文的 `color=${white}` 替代 `color=${primary}` / `color=${dark}`
- 卡片 `fill=${accent}` 或 `fill=none`

```bash
officecli add "$F" / --type slide --prop layout=blank --prop background=${accent}

# 标题 — 白色
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${PAGE_TITLE}" --prop font="${FONT}" --prop size=${H1} \
  --prop color=${white} --prop x=1.5cm --prop y=1cm --prop width=30.87cm --prop height=2cm

# 正文 — 白色
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${CONTENT}" --prop font="${FONT}" --prop size=${Body} \
  --prop color=${white} --prop x=1.5cm --prop y=4cm --prop width=30.87cm --prop height=12cm
```

**约束**：accent 底 + white 字的对比度仅 3.2:1（professional_blue 的 `#F0861C` + white）。18pt 以下文字不可用此 layout。如果内容以 18pt 正文为主，要么放大到 20pt，要么改用普通 content_ + 小范围橙色强调。
