# cover_dark

**角色**：黑色沉浸封面。最正式的封面选择。

**适用**：正式汇报、对外提案、仪式感开场。

**结构**：黑色全屏背景 → 居中标题（28pt white）→ 副标题（20pt gray）→ 底部日期/作者（16pt gray）。

> 色值 `${pure_black}`, `${white}`, `${gray}` 来自当前 theme。字号来自 theme 的 H1/Body/Caption 级。

```bash
# cover_dark — 黑色沉浸封面
officecli add "$F" / --type slide --prop layout=blank --prop background=${pure_black}

# 标题 — 居中，28pt
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${TITLE}" --prop font="${FONT}" --prop size=${H1} \
  --prop color=${white} --prop align=center \
  --prop x=2cm --prop y=6cm --prop width=29.87cm --prop height=3cm

# 副标题 — 居中，20pt
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${SUBTITLE}" --prop font="${FONT}" --prop size=${H4} \
  --prop color=${gray} --prop align=center \
  --prop x=2cm --prop y=9.5cm --prop width=29.87cm --prop height=1.5cm

# 底部信息 — 居中，16pt
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${META}" --prop font="${FONT}" --prop size=${Body-XS} \
  --prop color=${gray} --prop align=center \
  --prop x=2cm --prop y=15cm --prop width=29.87cm --prop height=1cm
```

**变量说明**：生成时将 `${TITLE}`, `${SUBTITLE}`, `${META}` 替换为实际内容，`${pure_black}`, `${white}`, `${gray}` 等来自 theme 色板，`${FONT}`, `${H1}`, `${H4}`, `${Body-XS}` 来自 theme 字体/字号。
