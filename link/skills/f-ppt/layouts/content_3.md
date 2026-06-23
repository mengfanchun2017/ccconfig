# content_3

**角色**：三栏内容页。并列对比、三个要点。

**适用**：三项对比、三个维度、三重优势。

**结构**：白底 → 标题（28pt primary）→ 三张卡片并排。

**网格计算**（边距 1.5cm，间距 0.76cm）：
```
col_w = (33.87 - 2×1.5 - 2×0.76) / 3 = 9.78cm
x_1 = 1.5cm
x_2 = 1.5 + 9.78 + 0.76 = 12.04cm
x_3 = 1.5 + 2×(9.78 + 0.76) = 22.58cm
```

```bash
COL_W=9.78cm
GAP=0.76cm
Y_CONTENT=4cm
CARD_H=12cm

officecli add "$F" / --type slide --prop layout=blank --prop background=${white}

# 标题
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${PAGE_TITLE}" --prop font="${FONT}" --prop size=${H1} \
  --prop color=${primary} --prop x=1.5cm --prop y=1cm --prop width=30.87cm --prop height=2cm

# 遍历 3 张卡片，每张：卡片底 + 卡片标题 + 卡片正文
for i in 1 2 3; do
  case $i in
    1) X=1.5cm ;;
    2) X=12.04cm ;;
    3) X=22.58cm ;;
  esac
  
  officecli add "$F" "/slide[last()]" --type shape \
    --prop preset=roundRect --prop fill=${white} --prop line=none \
    --prop x=$X --prop y=$Y_CONTENT --prop width=$COL_W --prop height=$CARD_H
  
  officecli add "$F" "/slide[last()]" --type shape \
    --prop text="$(eval echo \${CARD${i}_TITLE})" \
    --prop font="${FONT}" --prop size=${H4} --prop bold=true \
    --prop color=${primary} \
    --prop x=$(echo "$X + 0.5" | bc)cm --prop y=$(echo "$Y_CONTENT + 0.5" | bc)cm \
    --prop width=$(echo "$COL_W - 1" | bc)cm --prop height=1.5cm
  
  officecli add "$F" "/slide[last()]" --type shape \
    --prop text="$(eval echo \${CARD${i}_BODY})" \
    --prop font="${FONT}" --prop size=${Body} --prop color=${dark} \
    --prop x=$(echo "$X + 0.5" | bc)cm --prop y=$(echo "$Y_CONTENT + 2.5" | bc)cm \
    --prop width=$(echo "$COL_W - 1" | bc)cm --prop height=$(echo "$CARD_H - 3" | bc)cm
done
```

**3_full 变体**：三张卡片分别用金/绿/青三色填充（`#FFC000`, `#92D050`, `#00B0F0`），文字白色。仅在 professional_blue 的原始 PPT 中存在，其他 theme 可忽略。
