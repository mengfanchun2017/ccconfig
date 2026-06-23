# cover_center

**角色**：白底居中大标题封面。标题用最大字号。

**适用**：课程标题、培训封面、书名页。

**结构**：白底 → 43pt 居中大标题（dark）→ 22pt 副标题（primary）。

```bash
officecli add "$F" / --type slide --prop layout=blank --prop background=${white}

# 大标题 — 居中，Hero 级字号（43pt for professional_blue）
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${TITLE}" --prop font="${FONT}" --prop size=${Hero} \
  --prop color=${dark} --prop align=center \
  --prop x=2cm --prop y=5cm --prop width=29.87cm --prop height=5cm

# 副标题 — 居中，primary 色
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${SUBTITLE}" --prop font="${FONT}" --prop size=${H3} \
  --prop color=${primary} --prop align=center \
  --prop x=2cm --prop y=10.5cm --prop width=29.87cm --prop height=2cm
```
