#!/bin/bash
# tui-helper.sh — TUI 统一封装（gum → whiptail → raw read 三级 fallback）
#
# 使用：
#   source "$SCRIPT_DIR/lib/tui-helper.sh"
#
# 函数：
#   _tui_choose args...     → 全局 __TUI_CHOICE 存选中编号
#   _tui_confirm "提示" [y]  → 退出码 0=yes 1=no
#   _tui_input "标题"        → 全局 __TUI_VALUE 存输入值
#   _tui_multi args...       → 全局 __TUI_SELECTED 数组存选中项
#   _tui_password "标题"     → 全局 __TUI_VALUE 存密码
#
# 核心约束：gum choose / filter / input 等不能 $() 捕获也不能
# > 文件重定向，否则报 "could not open a new TTY"。必须直接调，
# 通过全局变量传值。

# ── 后端检测 ──
if command -v gum &>/dev/null; then
  __TUI_BACKEND="gum"
elif command -v whiptail &>/dev/null; then
  __TUI_BACKEND="whiptail"
else
  __TUI_BACKEND="raw"
fi

# 清空全局变量
__TUI_CHOICE=""
__TUI_VALUE=""
__TUI_SELECTED=()
__TUI_CONFIRMED=""

# ── 单选菜单 → __TUI_CHOICE = 选中编号 ──
_tui_choose() {
  local title="$1" && shift
  local -a items=("$@")
  local choice

  case "$__TUI_BACKEND" in
    gum)
      # gum choose 在非 TTY 下报错。用 filter 替代，stdout 捕获正常
      choice=$(gum filter --placeholder "$title" --height 12 --indicator="●" \
        <<< "$(printf '%s\n' "${items[@]}")")
      __TUI_CHOICE=$(echo "$choice" | sed 's/^[[:space:]]*\([0-9]*\).*/\1/')
      __TUI_CHOICE="${__TUI_CHOICE:-0}"
      ;;
    whiptail)
      local -a args=() tag
      for item in "${items[@]}"; do
        tag=$(echo "$item" | sed 's/^[[:space:]]*\([0-9]*\).*/\1/')
        args+=("$tag" "$item")
      done
      __TUI_CHOICE=$(whiptail --title "$title" --menu "" 0 0 0 "${args[@]}" 3>&1 1>&2 2>&3) || __TUI_CHOICE="0"
      ;;
    *)
      local i=1
      echo ""; echo "  $title"; echo ""
      for item in "${items[@]}"; do
        echo "  $item"
        ((i++))
      done
      echo ""
      read -r -p "选择: " __TUI_CHOICE
      __TUI_CHOICE="${__TUI_CHOICE:-0}"
      ;;
  esac
}

# ── Y/n 确认 → 退出码 0=yes 1=no ──
_tui_confirm() {
  local prompt="$1" default="${2:-y}"

  case "$__TUI_BACKEND" in
    gum)
      if [[ "$default" = "y" ]]; then
        gum confirm --affirmative="Yes" --negative="No" "$prompt"
      else
        gum confirm --affirmative="Yes" --negative="No" --default=no "$prompt"
      fi
      ;;
    whiptail)
      whiptail --yesno "$prompt" 8 50 3>&1 1>&2 2>&3
      ;;
    *)
      local yn
      if [[ "$default" = "y" ]]; then
        read -r -p "$prompt [Y/n]: " yn
        yn="${yn:-y}"
      else
        read -r -p "$prompt [y/N]: " yn
        yn="${yn:-n}"
      fi
      [[ "$yn" =~ ^[Yy]$ ]]
      ;;
  esac
}

# ── 文本输入 → __TUI_VALUE ──
_tui_input() {
  local title="$1" default="${2:-}"

  case "$__TUI_BACKEND" in
    gum)
      __TUI_VALUE=$(gum input --placeholder="$default" --value="$default" \
        --prompt="› " --prompt.foreground="212")
      ;;
    whiptail)
      __TUI_VALUE=$(whiptail --inputbox "$title" 8 50 "$default" 3>&1 1>&2 2>&3) || __TUI_VALUE=""
      ;;
    *)
      read -r -p "$title: " __TUI_VALUE
      __TUI_VALUE="${__TUI_VALUE:-$default}"
      ;;
  esac
}

# ── 密码输入 → __TUI_VALUE ──
_tui_password() {
  local title="$1"

  case "$__TUI_BACKEND" in
    gum)
      __TUI_VALUE=$(gum input --password --placeholder="输入后按回车" --prompt="› " --prompt.foreground="212")
      ;;
    whiptail)
      __TUI_VALUE=$(whiptail --passwordbox "$title" 8 50 3>&1 1>&2 2>&3) || __TUI_VALUE=""
      ;;
    *)
      read -r -s -p "$title: " __TUI_VALUE
      echo "" >&2
      ;;
  esac
}

# ── 多选 → __TUI_SELECTED 数组 ──
_tui_multi() {
  local title="$1" && shift
  local -a items=("$@")

  __TUI_SELECTED=()

  case "$__TUI_BACKEND" in
    gum)
      local raw
      raw=$(gum choose --no-limit \
        --cursor="●" --cursor.foreground="212" \
        --selected.foreground="46" \
        "${items[@]}")
      while IFS= read -r line; do
        __TUI_SELECTED+=("$line")
      done <<< "$raw"
      ;;
    whiptail)
      local -a args=()
      for item in "${items[@]}"; do
        args+=("$item" "" OFF)
      done
      local raw
      raw=$(whiptail --title "$title" --checklist "空格选择, 回车确认" 0 0 0 "${args[@]}" 3>&1 1>&2 2>&3) || raw=""
      while IFS= read -r -d ' ' item; do
        __TUI_SELECTED+=("$item")
      done <<< "$raw"
      ;;
    *)
      local i=1
      echo ""; echo "  $title"; echo ""
      local -a labels=()
      for item in "${items[@]}"; do
        echo "  $i) $item"
        labels+=("$item")
        ((i++))
      done
      echo ""
      local sel
      read -r -p "输入编号 (空格分隔): " sel
      for num in $sel; do
        __TUI_SELECTED+=("${labels[$((num-1))]}")
      done
      ;;
  esac
}

# ── 安装 gum（静默，失败不报错） ──
_ensure_gum() {
  command -v gum &>/dev/null && return 0
  local tmpd="/tmp/gum-install-$$"
  mkdir -p ~/.local/bin "$tmpd"
  if curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v0.17.0/gum_0.17.0_Linux_x86_64.tar.gz" \
    | tar xz -C "$tmpd" 2>/dev/null; then
    local gum_bin
    gum_bin=$(find "$tmpd" -name gum -type f 2>/dev/null | head -1)
    if [[ -n "$gum_bin" ]]; then
      mv "$gum_bin" ~/.local/bin/gum 2>/dev/null || true
      chmod +x ~/.local/bin/gum 2>/dev/null || true
    fi
  fi
  rm -rf "$tmpd"
  return 0
}
