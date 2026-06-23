# content_n

**角色**：N 块通用公式。5 块及以上用此公式计算。

**适用**：5-6 个要点、多项并列。

**通用网格公式**（n 列，边距 margin，间距 gap）：
```
col_w = (33.87 - 2×margin - (n-1)×gap) / n
x_i = margin + (i-1) × (col_w + gap)
```

**典型值**（margin=1.5cm, gap=0.76cm）：

| n | col_w | 适合 |
|---|-------|------|
| 2 | 15.06cm | 双栏对比 |
| 3 | 9.78cm | 三栏并列 |
| 4 | 7.08cm | 四块 |
| 5 | 5.46cm | 密集五列，推荐 18pt→16pt |
| 6 | 4.39cm | 六列太窄，建议换 2 行 × 3 列 |

**n≥5 时提醒**：正文从 18pt 降为 16pt（Body-XS），否则文字溢出。考虑改用 2 行排列（如 6 块 = 2 行 × 3 列）。

```bash
# 通用 N 列生成（bash 函数）
gen_grid() {
  local N=$1 MARGIN=1.5 GAP=0.76
  local COL_W=$(echo "scale=4; (33.87 - 2*$MARGIN - ($N-1)*$GAP) / $N" | bc)
  
  for i in $(seq 1 $N); do
    local X=$(echo "scale=4; $MARGIN + ($i-1) * ($COL_W + $GAP)" | bc)
    officecli add "$F" "/slide[last()]" --type shape \
      --prop preset=roundRect --prop fill=${white} --prop line=none \
      --prop x=${X}cm --prop y=4cm --prop width=${COL_W}cm --prop height=12cm
  done
}
```
