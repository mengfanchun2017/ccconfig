# content_1

**角色**：单栏全宽内容页。最简单的正文页。

**适用**：单一主题、大段文字、一张图配一段解说。

**结构**：白底 → 标题（28pt primary）→ 全宽内容区（18pt dark）。

```bash
officecli add "$F" / --type slide --prop layout=blank --prop background=${white}

# 标题
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${PAGE_TITLE}" --prop font="${FONT}" --prop size=${H1} \
  --prop color=${primary} --prop x=1.5cm --prop y=1cm --prop width=30.87cm --prop height=2cm

# 正文 — 全宽
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${CONTENT}" --prop font="${FONT}" --prop size=${Body} \
  --prop color=${dark} --prop x=1.5cm --prop y=4cm --prop width=30.87cm --prop height=12cm
```
