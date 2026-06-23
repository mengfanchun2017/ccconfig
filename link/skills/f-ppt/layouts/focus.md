# focus

**角色**：聚焦重点页。中间一个大标题 + 副标题，四角有装饰形状。

**适用**：单一核心观点、章节引言、关键结论。打破内容页节奏，制造视觉锚点。

**结构**：白/彩色底 → 四角 halfFrame 装饰（accent_deco 色 + accent 色交替）→ 居中大字标题 → 副标题。

**装饰 halfFrame 摆放**：
```
左上：preset=halfFrame, fill=accent_deco, 正常方向
右上：preset=halfFrame, fill=accent, rot=10800000（旋转 108°）
左下：preset=halfFrame, fill=accent, rot=10800000
右下：preset=halfFrame, fill=accent_deco, 正常方向
```

```bash
officecli add "$F" / --type slide --prop layout=blank --prop background=${white}

# 四角装饰
# 左上
officecli add "$F" "/slide[last()]" --type shape \
  --prop preset=halfFrame --prop fill=${accent_deco} --prop line=none \
  --prop x=2.5cm --prop y=1.5cm --prop width=4cm --prop height=4.5cm

# 右上（旋转 108°）
officecli add "$F" "/slide[last()]" --type shape \
  --prop preset=halfFrame --prop fill=${accent} --prop line=none \
  --prop x=27cm --prop y=1.5cm --prop width=4cm --prop height=4.5cm \
  --prop rot=10800000

# 左下
officecli add "$F" "/slide[last()]" --type shape \
  --prop preset=halfFrame --prop fill=${accent} --prop line=none \
  --prop x=2.5cm --prop y=13cm --prop width=4cm --prop height=4.5cm \
  --prop rot=10800000

# 右下
officecli add "$F" "/slide[last()]" --type shape \
  --prop preset=halfFrame --prop fill=${accent_deco} --prop line=none \
  --prop x=27cm --prop y=13cm --prop width=4cm --prop height=4.5cm

# 居中标题 — H3 级（22pt for professional_blue）
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${FOCUS_TITLE}" --prop font="${FONT}" --prop size=${H3} \
  --prop color=${dark} --prop align=center \
  --prop x=4cm --prop y=6cm --prop width=25.87cm --prop height=3cm

# 副标题/正文 — Body 级
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${FOCUS_BODY}" --prop font="${FONT}" --prop size=${Body} \
  --prop color=${dark} --prop align=center \
  --prop x=4cm --prop y=9.5cm --prop width=25.87cm --prop height=4cm
```

**focus 变体**（改背景色，装饰色互换或替换）：
- `focus_orange`：背景 `${accent}`，标题 white，装饰换 white+accent_deco
- `focus_blue`：背景 `${primary}`，标题 white，装饰换 accent+white
- `focus_gray`：背景 `${gray}`，标题 white，装饰换 accent+primary
