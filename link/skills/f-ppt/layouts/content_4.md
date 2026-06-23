# content_4

**角色**：四块内容页。2×2 网格。

**适用**：SWOT 分析、四象限、四维度、四方案对比。

**结构**：白底 → 标题（28pt primary）→ 2×2 卡片网格。

**网格计算**（边距 1.5cm，间距 0.76cm）：
```
col_w = (33.87 - 2×1.5 - 0.76) / 2 = 15.055cm
row_h = (可用高度 14cm - 0.76) / 2 = 6.62cm
x_left=1.5cm, x_right=17.315cm
y_top=4cm, y_bottom=11.38cm
```

```bash
COL_W=15.055cm
ROW_H=6.62cm
GAP=0.76cm

officecli add "$F" / --type slide --prop layout=blank --prop background=${white}

officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${PAGE_TITLE}" --prop font="${FONT}" --prop size=${H1} \
  --prop color=${primary} --prop x=1.5cm --prop y=1cm --prop width=30.87cm --prop height=2cm

# 左上 (1,1)
X=1.5cm; Y=4cm
officecli add "$F" "/slide[last()]" --type shape \
  --prop preset=roundRect --prop fill=${white} --prop line=none \
  --prop x=$X --prop y=$Y --prop width=$COL_W --prop height=$ROW_H

# 右上 (1,2)
X=17.315cm; Y=4cm   # x_right

# 左下 (2,1)  
X=1.5cm; Y=11.38cm  # y_bottom

# 右下 (2,2)
X=17.315cm; Y=11.38cm
```

**4_quarter 变体**：左上放大（占 2/3 宽），其余三个平分剩余 1/3 宽。适合一主三辅。
**4_full 变体**：四块纵向堆叠，全宽，适合流程/时间线。
