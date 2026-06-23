# cover_blue

**角色**：品牌色封面。用 theme primary 色做全屏背景。

**适用**：品牌展示、对外提案、公司介绍。

**结构**：primary 色全屏 → 居中标题（28pt white）→ 副标题（20pt gray/white）→ 底部日期。

```bash
officecli add "$F" / --type slide --prop layout=blank --prop background=${primary}

officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${TITLE}" --prop font="${FONT}" --prop size=${H1} \
  --prop color=${white} --prop align=center \
  --prop x=2cm --prop y=6cm --prop width=29.87cm --prop height=3cm

officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${SUBTITLE}" --prop font="${FONT}" --prop size=${H4} \
  --prop color=${white} --prop align=center \
  --prop x=2cm --prop y=9.5cm --prop width=29.87cm --prop height=1.5cm
```
