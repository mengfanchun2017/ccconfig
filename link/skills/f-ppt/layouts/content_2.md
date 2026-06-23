# content_2

**角色**：双栏内容页。对比、并列关系。

**适用**：概念+证据、前后对比、左右分栏。

**结构**：白底 → 标题（28pt primary）→ 两颗卡片并排。

**网格计算**（16:9 = 33.87×19.05cm，边距 1.5cm，间距 0.76cm）：
```
col_w = (33.87 - 2×1.5 - 0.76) / 2 = 15.055cm
x_left = 1.5cm
x_right = 1.5 + 15.055 + 0.76 = 17.315cm
```

```bash
COL_W=15.055cm
GAP=0.76cm

officecli add "$F" / --type slide --prop layout=blank --prop background=${white}

# 标题
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${PAGE_TITLE}" --prop font="${FONT}" --prop size=${H1} \
  --prop color=${primary} --prop x=1.5cm --prop y=1cm --prop width=30.87cm --prop height=2cm

# 左卡片
officecli add "$F" "/slide[last()]" --type shape \
  --prop preset=roundRect --prop fill=${white} \
  --prop x=1.5cm --prop y=4cm --prop width=$COL_W --prop height=12cm

officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${LEFT_TITLE}" --prop font="${FONT}" --prop size=${H4} \
  --prop color=${primary} --prop bold=true \
  --prop x=2cm --prop y=4.5cm --prop width=$(echo "$COL_W - 1" | bc)cm --prop height=1.5cm

officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${LEFT_BODY}" --prop font="${FONT}" --prop size=${Body} \
  --prop color=${dark} \
  --prop x=2cm --prop y=6.5cm --prop width=$(echo "$COL_W - 1" | bc)cm --prop height=9cm

# 右卡片（同上，x=17.315cm）
```

**2_horizon 变体**：卡片改为上下排列（上半图/下半文），x 全宽，高度各占一半。
**2_tilt 变体**：标题区微倾斜装饰（仅在 ppt-master SVG 模板中实现，OfficeCLI 忽略）。
