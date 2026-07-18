#!/bin/bash
# tui-helper.sh — TUI 统一封装（gum → whiptail → raw read 三级 fallback）
#
# 使用：
#   source "$SCRIPT_DIR/lib/tui-helper.sh"
#
# 函数：
#   _tui_choose   "标题" "1. 选项A" "2. 选项B" ...  → stdout: 选中编号 (如 "1")
#   _tui_confirm  "提示" ["y"]                        → 退出码 0=yes 1=no
#   _tui_input    "标题" ["默认值"]                    → stdout: 输入文本
#   _tui_multi    "标题" "选项A" "选项B" ...          → stdout: 选中项 (每行一个)
#   _tui_password "标题"                              → stdout: 密码文本

# 配色（OpenClaw 风格）
TUI_PRIMARY="#7C3AED"
TUI_ACCENT="#A78BFA"
TUI_SUCCESS="#10B981"
TUI_WARN="#F59E0B"
TUI_DIM="#6B7280"

# ── 后端检测（source 时缓存在全局变量，避免 subshell 嵌套） ──
if command -v gum &>/dev/null; then
  __TUI_BACKEND="gum"
elif command -v whiptail &>/dev/null; then
  __TUI_BACKEND="whiptail"
else
  __TUI_BACKEND="raw"
fi

# ── 提取编号（从 "1. Foo bar" 中提取 "1"） ──
_tui_extract_num() { echo "$1" | sed 's/^[[:space:]]*\([0-9]*\).*/\1/'; }

# ── 单选菜单 → stdout: 编号 ──
_tui_choose() {
  local title="$1" && shift
  local -a items=("$@")
  local sel tmpf

  case "$__TUI_BACKEND" in
    gum)
      tmpf=$(mktemp) || { echo "0"; return 0; }
      gum choose --header="$title" --header.foreground="$TUI_ACCENT" \
        --cursor="●" --cursor.foreground="$TUI_PRIMARY" \
        --selected.foreground="$TUI_SUCCESS" \
        "${items[@]}" > "$tmpf" || true
      sel=$(cat "$tmpf" 2>/dev/null || true)
      rm -f "$tmpf"
      if [[ -z "$sel" ]]; then echo "0"; return 0; fi
      _tui_extract_num "$sel"
      ;;
    whiptail)
      local -a args=() tag
      for item in "${items[@]}"; do
        tag=$(_tui_extract_num "$item")
        args+=("$tag" "$item")
      done
      sel=$(whiptail --title "$title" --menu "" 0 0 0 "${args[@]}" 3>&1 1>&2 2>&3) || { echo "0"; return 0; }
      echo "$sel"
      ;;
    *)
      local i=1
      echo ""; echo "  $title"; echo ""
      for item in "${items[@]}"; do
        echo "  $item"
        ((i++))
      done
      echo ""
      local c
      read -r -p "选择: " c
      echo "${c:-0}"
      ;;
  esac
}

# ── Y/n 确认 → 退出码 0=yes 1=no ──
_tui_confirm() {
  local prompt="$1" default="${2:-y}"

  case "$__TUI_BACKEND" in
    gum)
      if [[ "$default" = "y" ]]; then
        gum confirm --affirmative="Yes" --negative="No" "$prompt" || return 1
      else
        gum confirm --affirmative="Yes" --negative="No" --default=no "$prompt" || return 1
      fi
      ;;
    whiptail)
      if whiptail --yesno "$prompt" 8 50 3>&1 1>&2 2>&3; then return 0; else return 1; fi
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

# ── 文本输入 → stdout: 输入值 ──
_tui_input() {
  local title="$1" default="${2:-}"

  case "$__TUI_BACKEND" in
    gum)
      gum input --header="$title" --header.foreground="$TUI_ACCENT" \
        --placeholder="$default" --value="$default" \
        --prompt="→ " --prompt.foreground="$TUI_ACCENT" || echo ""
      ;;
    whiptail)
      local val
      val=$(whiptail --inputbox "$title" 8 50 "$default" 3>&1 1>&2 2>&3) || { echo ""; return 0; }
      echo "$val"
      ;;
    *)
      local val
      read -r -p "$title: " val
      echo "${val:-$default}"
      ;;
  esac
}

# ── 密码输入 → stdout: 密码 ──
_tui_password() {
  local title="$1"

  case "$__TUI_BACKEND" in
    gum)
      gum input --password --header="$title" --header.foreground="$TUI_ACCENT" \
        --placeholder="输入后按回车" --prompt="→ " --prompt.foreground="$TUI_ACCENT" || echo ""
      ;;
    whiptail)
      local val
      val=$(whiptail --passwordbox "$title" 8 50 3>&1 1>&2 2>&3) || { echo ""; return 0; }
      echo "$val"
      ;;
    *)
      local val
      read -r -s -p "$title: " val
      echo "" >&2
      echo "$val"
      ;;
  esac
}

# ── 多选 → stdout: 选中项 (每行一个) ──
_tui_multi() {
  local title="$1" && shift
  local -a items=("$@")

  case "$__TUI_BACKEND" in
    gum)
      gum choose --no-limit --header="$title" --header.foreground="$TUI_ACCENT" \
        --cursor="●" --cursor.foreground="$TUI_PRIMARY" \
        --selected.foreground="$TUI_SUCCESS" \
        "${items[@]}" || true
      ;;
    whiptail)
      local -a args=()
      for item in "${items[@]}"; do
        args+=("$item" "" OFF)
      done
      whiptail --title "$title" --checklist "空格选择, 回车确认" 0 0 0 "${args[@]}" 3>&1 1>&2 2>&3 || true
      ;;
    *)
      local i=1
      echo ""; echo "  $title"; echo ""
      for item in "${items[@]}"; do
        echo "  $i) $item"
        ((i++))
      done
      echo ""
      local sel
      read -r -p "输入编号 (空格分隔): " sel
      for num in $sel; do
        echo "${items[$((num-1))]}"
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
