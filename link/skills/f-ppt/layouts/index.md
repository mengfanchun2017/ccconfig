# index

**角色**：目录/议程页。列出章节编号和标题。

**适用**：永远第 2 页（封面之后）。

**结构**：白底 → 标题 "目录"（28pt primary）→ N 个目录项，编号用 primary 色、标题用 dark、每项一行。

```bash
officecli add "$F" / --type slide --prop layout=blank --prop background=${white}

# 页标题
officecli add "$F" "/slide[last()]" --type shape \
  --prop text="目录" --prop font="${FONT}" --prop size=${H1} \
  --prop color=${primary} --prop x=1.5cm --prop y=1cm --prop width=30cm --prop height=2cm

# 目录项 — 左右两列，每项：编号（primary 色）+ 标题（dark）+ 描述（gray）
# 左列 x=1.5cm, 右列 x=17cm, 每项 y 间距 2.5cm
# 遍历 ${ITEMS}，每个 item: {num, title, desc}
```

**目录项模板**（每个 item 生成一套）：
```bash
Y_OFFSET=3cm  # 第一项起始 y，每项递增 2.5cm（最多 5 项/列）

officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${ITEM_NUM}" --prop font="${FONT}" --prop size=${H4} --prop bold=true \
  --prop color=${primary} --prop x=1.5cm --prop y=${Y} --prop width=1.5cm --prop height=1cm

officecli add "$F" "/slide[last()]" --type shape \
  --prop text="${ITEM_TITLE}" --prop font="${FONT}" --prop size=${Body} \
  --prop color=${dark} --prop x=3.5cm --prop y=${Y} --prop width=12cm --prop height=1cm
```

> professional_blue 特有：目录项放在浅蓝 `#BBE2FF` 卡片上（`fill=${light_blue}`）。其他 theme 忽略此元素。
