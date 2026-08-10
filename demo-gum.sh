#!/bin/bash
# demo-gum.sh — gum 原生命令展示（不依赖 colors.sh/interact.sh）
# 用法: bash demo-gum.sh
# 前置: gum 已安装

set -euo pipefail

if ! command -v gum &>/dev/null; then
    echo "❌ gum 未装，先: sudo apt install gum 或 bash lib/init-ubuntu.sh"
    exit 1
fi

gum style --border normal --padding "1 2" --margin "1 0" "━━━ gum 全部功能演示 ━━━"

# ── 1. gum style ──
echo ""
gum style --foreground 212 --bold "1) gum style — 样式化输出"
gum style --foreground 99 --italic "   各种文字样式：加粗/斜体/颜色"

# ── 2. gum confirm ──
echo ""
gum style --foreground 212 --bold "2) gum confirm — 确认对话框"
if gum confirm "安装继续？"; then echo "  ➤ 选择了是"; else echo "  ➤ 选择了否"; fi

# ── 3. gum input ──
echo ""
gum style --foreground 212 --bold "3) gum input — 文本输入"
name=$(gum input --placeholder "输入你的名字" --value "默认用户")
echo "  ➤ 你输入了: $name"

# ── 4. gum input --password ──
echo ""
gum style --foreground 212 --bold "4) gum input --password — 密码输入"
pw=$(gum input --password --placeholder "输入密码")
echo "  ➤ 密码已收到（长度为 ${#pw}）"

# ── 5. gum choose ──
echo ""
gum style --foreground 212 --bold "5) gum choose — 单选菜单"
color=$(gum choose --header "选择颜色" "红色" "蓝色" "绿色")
echo "  ➤ 你选了: $color"

# ── 6. gum choose --no-limit ──
echo ""
gum style --foreground 212 --bold "6) gum choose --no-limit — 多选"
selected=$(gum choose --no-limit --header "选择喜欢的颜色" "红色" "蓝色" "绿色" "黄色" "紫色")
echo "  ➤ 你选了: $(echo "$selected" | tr '\n' ' ')"

# ── 7. gum filter ──
echo ""
gum style --foreground 212 --bold "7) gum filter — 模糊搜索选择"
filtered=$(printf "ccconfig\nccprivate\nccpublic\nccconfig-skill\nccconfig-lark\nccconfig-mcp\n" | gum filter --header "搜索仓库")
echo "  ➤ 你选了: $filtered"

# ── 8. gum table ──
echo ""
gum style --foreground 212 --bold "8) gum table — 表格"
printf "名称,版本,状态\nccconfig,1.0,✓\nccprivate,2.0,✓\nccpublic,1.5,✗\n" | gum table --separator ","

# ── 9. gum spin ──
echo ""
gum style --foreground 212 --bold "9) gum spin — 等待动画"
gum spin --title "模拟安装中..." -- sleep 2

# ── 10. gum pager ──
echo ""
gum style --foreground 212 --bold "10) gum pager — 翻页查看"
echo -e "  展示翻页器（长文本按 q 退出）..."
seq 1 30 | gum pager

# ── 11. gum format ──
echo ""
gum style --foreground 212 --bold "11) gum format — Markdown 渲染"
gum format -- "# 标题\n**加粗文字** *斜体*\n- 列表项1\n- 列表项2"

# ── 12. gum progress ──
echo ""
gum style --foreground 212 --bold "12) gum progress — 进度条"
for i in 0 10 30 50 70 90 100; do echo $i | gum progress; sleep 0.3; done

# ── 13. gum log ──
echo ""
gum style --foreground 212 --bold "13) gum log — 结构化日志"
gum log --level info "信息消息"
gum log --level warn "警告消息"
gum log --level error "错误消息"
gum log --level debug "调试消息"

# ── 14. gum join ──
echo ""
gum style --foreground 212 --bold "14) gum join — 布局"
a=$(gum style --foreground 42 "左侧面板")
b=$(gum style --foreground 99 "右侧面板")
gum join -- "$a" "$b"

echo ""
gum style --border double --padding "1 2" --foreground 212 "━━━ 全部演示完毕 ━━━"
echo ""
echo "  gum 支持: choose, input, confirm, filter, table, spin,"
echo "  pager, format, progress, log, style, join, write, file"
echo ""
echo "  bash <(gum help) 查看全部命令"
echo ""