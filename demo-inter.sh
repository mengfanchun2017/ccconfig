#!/bin/bash
# demo-inter.sh — interact.sh 全部函数展示（gum fallback 自动）
# 用法: bash demo-inter.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/interact.sh"

echo ""
echo -e "${BOLD}━━━ interact.sh 全部函数演示 ━━━${NC}"
echo ""

section "1. confirm — y/n 确认"
if confirm "安装继续？" y; then ok "选择了是"; else warn "选择了否"; fi

section "2. prompt — 文本输入"
name=$(prompt "输入你的名字" "默认用户")
info "你输入了: $name"

section "3. menu_select — 单选菜单"
choice=$(menu_select "选择颜色" "红色" "蓝色" "绿色")
if [[ -n "$choice" ]]; then info "你选了: $choice"; else warn "未选择"; fi

section "4. menu_multi — 多选 checklist"
selected=$(menu_multi "选择喜欢的颜色" "红色" "蓝色" "绿色" "黄色" "紫色")
if [[ -n "$selected" ]]; then info "你选了: $selected"; else info "未选任何项"; fi

section "5. table — 表格"
table "状态总览" "名称,版本,状态" "ccconfig,1.0,✓" "ccprivate,2.0,✓" "ccpublic,1.5,✗"

section "6. spinner — 等待动画"
spinner "模拟安装中..." sleep 2

section "7. prompt_password — 密码输入"
pw=$(prompt_password "输入密码（不回显）")
if [[ -n "$pw" ]]; then ok "密码已收到"; fi

echo ""
echo -e "${GREEN}━━━ 演示完毕 ━━━${NC}"
echo ""
if command -v gum &>/dev/null; then
  echo -e "  ${GRAY}gum 已安装 → 以上交互使用 gum TUI${NC}"
else
  echo -e "  ${GRAY}gum 未安装 → 以上交互使用纯 sh 回退${NC}"
fi
echo -e "  ${GRAY}提示: interact.sh 自动检测 gum，有 → gum，无 → 纯 sh${NC}"
echo ""