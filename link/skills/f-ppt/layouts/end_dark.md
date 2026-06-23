# end_dark

**角色**：黑色结束页。"感谢聆听"。

**适用**：永远最后一页。

**结构**：pure_black 全屏 → 居中 "感谢聆听"（38pt white）。

```bash
officecli add "$F" / --type slide --prop layout=blank --prop background=${pure_black}

officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${THANKS}" --prop font="${FONT}" --prop size=${End} \
  --prop color=${white} --prop align=center \
  --prop x=2cm --prop y=7cm --prop width=29.87cm --prop height=4cm

officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${SUBTITLE}" --prop font="${FONT}" --prop size=${H4} \
  --prop color=${gray} --prop align=center \
  --prop x=2cm --prop y=12cm --prop width=29.87cm --prop height=2cm
```

**默认值**：`${THANKS}` = "感谢聆听"，`${SUBTITLE}` = 联系方式或 slogan。
