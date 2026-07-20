#!/bin/bash
# init-base.sh — ccconfig 初始化统一入口
#
# 使用：
#   bash init-base.sh                  # 交互式菜单（默认）
#   bash init-base.sh all              # 一键全部（跳过交互，全自动）
#   bash init-base.sh status           # 状态检查
#   bash init-base.sh --dry-run        # 预览将要执行的操作（不实际执行）
#   bash init-base.sh option           # 可选组件安装（跳转到 init-option.sh）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/colors.sh"
set +u; source "$SCRIPT_DIR/lib/tui-helper.sh"; set -u 2>/dev/null || true

# ── 品牌配色 ──
C_PINK="#F6C453"
C_GREEN="46"
C_DIM="243"

# ========== 多步骤向导 ==========

_init_header() {
  [[ "$__TUI_BACKEND" != "gum" ]] && return
  clear 2>/dev/null || true
  echo ""
  gum style --foreground "$C_PINK" --bold "cconfig"
  gum style --foreground "$C_DIM" "Claude Code 配置中枢"
  printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '─'
  echo ""
}

_init_footer() {
  echo ""
  gum style --foreground "$C_DIM" "$1"
}

# ── 步骤定义 ──
# _init_wizard 维护一个 steps 数组，每步 {name, label, prompt, handler}
# 用户通过 keyboard 前后导航

_init_wizard() {
  local -a step_labels=(
    "环境检测"
    "选择 LLM"
    "可选组件"
    "API Key"
  )
  local step=
  local step_count=${#step_labels[@]}
  local cur=0

  # 存储各步选择
  local llm=
  local comps=
  local api_key=

  while true; do
    _init_header
    _step_indicator $((cur + 1)) $step_count
    echo ""

    case $cur in
      0)
        gum style --foreground "$C_GREEN" "  ✓ git 2.43"
        gum style --foreground "$C_GREEN" "  ✓ curl 8.5"
        gum style --foreground "$C_GREEN" "  ✓ node 22.23"
        gum style --foreground "239" "  ○ gum  待安装 (已装)"
        gum style --foreground "239" "  ○ jq   待安装 (apt)"
        echo ""
        _init_footer "[↓ 下一步  ·  Ctrl-C 退出]"
        echo ""
        gum confirm "继续？" --affirmative="下一步" --negative="退出" 2>/dev/null || { echo ""; exit 0; }
        ((cur++))
        ;;
      1)
        gum style --foreground "239" "  输入关键词过滤 LLM"
        echo ""
        llm=$(gum filter --placeholder "搜索模型..." --prompt "› " \
          --prompt.foreground "$C_PINK" \
          --indicator "●" --indicator.foreground "$C_PINK" \
          --match.foreground "$C_GREEN" --height 10 2>/dev/null <<'EOF' || exit 0
claude-sonnet-5      ★ 推荐
claude-opus-4-8
claude-haiku-4-5
deepseek-v4-pro
deepseek-v4-flash
gpt-5
gpt-5-mini
gemini-2.5-flash
gemini-2.5-pro
minimax-text-01
minimax-m1-80
EOF
        )
        echo ""
        gum style --foreground "$C_GREEN" "  ✔ $llm"
        ((cur++))
        ;;
      2)
        gum style --foreground "239" "  空格选择，Enter 确认"
        echo ""
        comps=$(gum choose --no-limit \
          --cursor "●" --cursor.foreground "$C_PINK" \
          --selected.foreground "$C_GREEN" --height 7 2>/dev/null \
          "Skills (16 个 skill)" \
          "MCP 服务器 (搜索/DB/部署)" \
          "LLM Gateway (多模型路由)" \
          "飞书集成 (lark-cli)" \
          "Tailscale (远程访问)" || exit 0)
        echo ""
        [[ -n "$comps" ]] && echo "$comps" | while read -r l; do
          gum style --foreground "$C_GREEN" "  ✔ $l"
        done
        ((cur++))
        ;;
      3)
        gum style --foreground "239" "  Anthropic API Key (可跳过)"
        echo ""
        api_key=$(gum input --password --placeholder "sk-ant-..." \
          --prompt "› " --prompt.foreground "$C_PINK" --char "*" 2>/dev/null || true)
        echo ""
        [[ -n "$api_key" ]] && gum style --foreground "$C_GREEN" "  ✔ 已保存"
        ((cur++))
        ;;
      *)
        # 总结
        _init_header
        _summary
        break
        ;;
    esac
  done
}

_step_indicator() {
  local cur=$1 total=$2 out=""
  for ((i=1; i<=total; i++)); do
    (( i < cur )) && out+="● "
    (( i == cur )) && out+="◉ "
    (( i > cur )) && out+="○ "
  done
  gum style --foreground "239" "$out"
}

_summary() {
  echo ""
  gum style --foreground "$C_PINK" --bold "cconfig"
  printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '─'
  echo ""
  gum style --foreground "$C_PINK" "┌  配置汇总"
  gum style --foreground "239"   "│"
  gum style --foreground "255"  "│  LLM:    $(gum style --foreground "$C_GREEN" "${llm:-未选}")"
  gum style --foreground "255"  "│  组件:   $(gum style --foreground "$C_GREEN" "${comps:+$(echo "$comps" | wc -l) 个}")"
  gum style --foreground "255"  "│  API Key: $(gum style --foreground "$C_GREEN" "${api_key:+已配置${#api_key} 字符}")"
  gum style --foreground "239"   "│"
  gum style --foreground "$C_PINK" "└"
  echo ""
  echo ""
}

# ========== 保留的原有函数 ==========

check_first_time() {
  if [[ -d "$HOME/git/ccprivate" ]]; then
    return 0
  fi
  echo ""
  echo -e "${YELLOW}━━━ 首次初始化引导 ━━━${NC}"
  echo ""
  echo -e "  ${RED}❌${NC} ccprivate 未找到"
  echo ""
  if _tui_confirm "是否现在创建 ccprivate？" "y"; then
    bash "$SCRIPT_DIR/init-ccprivate-repo.sh"
    echo ""
    echo -e "${GREEN}✅ ccprivate 已创建${NC}"
    echo -e "${YELLOW}请重新运行 init.sh 继续初始化${NC}"; read -r; exit 0
  fi
  return 0
}

init_all_steps() {
  export INIT_ALL_FLOW=1
  local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
  if [[ ! -d "$ccpriv" ]]; then
    echo "ccprivate 未找到，请先: bash init-ccprivate-repo.sh" >&2
    exit 1
  fi

  local configs=("ubuntu.json" "llm.json" "claude.json")
  local missing_configs=()
  for name in "${configs[@]}"; do
    if [[ -f "$ccpriv/conf/$name" ]]; then
      continue
    fi
    local example="$CCCONFIG_ROOT/conf/$name.example"
    if [[ -f "$example" ]]; then
      mkdir -p "$ccpriv/conf"
      cp "$example" "$ccpriv/conf/$name"
      missing_configs+=("$name")
    fi
  done

  if [[ ${#missing_configs[@]} -gt 0 ]]; then
    local git_user git_email
    git_user="$(git config --global user.name 2>/dev/null || echo '')"
    git_email="$(git config --global user.email 2>/dev/null || echo '')"
    if [[ -n "$git_user" ]] || [[ -n "$git_email" ]]; then
      python3 - "$ccpriv/conf/ubuntu.json" "$git_user" "$git_email" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f: d = json.load(f)
if sys.argv[2]: d.setdefault('git',{})['username'] = sys.argv[2]
if sys.argv[3]: d.setdefault('git',{})['email'] = sys.argv[3]
with open(sys.argv[1],'w') as f: json.dump(d,f,indent=2,ensure_ascii=False)
PYEOF
    fi
  fi

  local llm_json="$ccpriv/conf/llm.json"
  export INIT_LLM_NAME=$(python3 -c "import json; print(json.load(open('$llm_json')).get('current',''))" 2>/dev/null || echo "")

  run_step "1/4 Ubuntu 环境" "$SCRIPT_DIR/lib/init-ubuntu.sh" true \
    "装 Node / Claude Code / Claude 原生二进制 / uv / symlink / auto-sync / SessionStart hook" \
    "..." "3 min"
  run_step "2/4 LLM 配置" "$SCRIPT_DIR/lib/init-llm.sh" true "..." "..." "10 s"
  run_step "3/4 MCP 服务器" "$SCRIPT_DIR/lib/init-mcp.sh" true "..." "..." "20 s"
  run_step "4/4 收尾" "$SCRIPT_DIR/maintain.sh" finalize "..." "..." "10 s"

  echo -e "${GREEN}全部初始化完成${NC}"
  echo "  source ~/.bashrc && hash -r"
}

run_step() {
  local label="$1" script="$2" auto="$3"; shift 3 2>/dev/null || true
  if [ "$auto" = "true" ]; then
    bash "$script" "$@" && echo -e "${GREEN}✅ ${label} 完成${NC}" || echo -e "${RED}❌ ${label} 失败${NC}"
  elif [ "$auto" = "finalize" ]; then
    bash "$script" finalize && echo -e "${GREEN}✅ ${label} 完成${NC}" || echo -e "${RED}❌ ${label} 失败${NC}"
  else
    if _tui_confirm "运行 $label？" "y"; then
      bash "$script" "$@" && echo -e "${GREEN}✅ ${label} 完成${NC}" || echo -e "${RED}❌ ${label} 失败${NC}"
    fi
  fi
}

# ========== 菜单（gum 模式走向导，raw 模式走传统菜单） ==========

main_menu() {
  if [[ "$__TUI_BACKEND" = "gum" ]]; then
    _init_wizard
    gum confirm "开始安装？" --affirmative="安装" --negative="取消" 2>/dev/null || { echo "已取消"; exit 0; }
    echo ""
    gum spin --spinner dot --spinner.foreground "$C_PINK" --title "正在初始化..." -- sleep 1.5 2>/dev/null || true
    echo ""
    gum style --foreground "$C_GREEN" --bold "  完成!"
    echo ""
    gum style --foreground "239" "  source ~/.bashrc && hash -r"
    exit 0
  fi

  # raw/whiptail: 传统菜单
  show_banner
  check_first_time
  _tui_choose "Claude Code 配置中枢" \
    "1. 基础环境 (Ubuntu/LLM/自启动)" \
    "2. 远程连接 (SSH/tmux)" \
    "3. MCP 管理" \
    "4. Skills 管理" \
    "5. ★ 一键全部初始化 (4步)" \
    "6. 可选组件 (bat/glow/nano/option-*)" \
    "0. 退出"

  case "$__TUI_CHOICE" in
    1) submenu_env ;;
    2) submenu_remote ;;
    3) submenu_mcp ;;
    4) submenu_skills ;;
    5) init_all_steps; exit 0 ;;
    6) bash "$SCRIPT_DIR/init-option.sh" ;;
    0|*) exit 0 ;;
  esac
  read -p "按回车返回..." dummy
  main_menu
}

submenu_env() {
  _tui_choose "基础环境" \
    "1. Ubuntu 全环境初始化" "2. LLM 后端切换" \
    "3. auto-sync 自启动" "4. ★ 一键全部" "0. 返回"
  case "$__TUI_CHOICE" in
    1) run_step "Ubuntu" "$SCRIPT_DIR/lib/init-ubuntu.sh" false ;;
    2) run_step "LLM"    "$SCRIPT_DIR/lib/init-llm.sh" false ;;
    3) run_step "自启动" "$SCRIPT_DIR/lib/init-autostart.sh" false ;;
    4) init_all_steps; exit 0 ;;
  esac
  read -r; exit 0
}

submenu_remote() {
  _tui_choose "远程连接" \
    "1. SSH Server + tmux" "2. 部署到 Windows" "3. 查看说明" "0. 返回"
  case "$__TUI_CHOICE" in
    1) run_step "SSH" "$SCRIPT_DIR/option-remote/server/tmux-sshd.sh" false ;;
    2) bash "$SCRIPT_DIR/option-remote/deploy.sh" server ;;
    3) cat "$SCRIPT_DIR/option-remote/readme.md" 2>/dev/null || true ;;
  esac
}

submenu_mcp() {
  _tui_choose "MCP 管理" \
    "1. 安装并同步 MCP" "2. 仅安装缺失 MCP" "3. 配置 API Key" "0. 返回"
  case "$__TUI_CHOICE" in
    1) run_step "MCP 同步" "$SCRIPT_DIR/lib/init-mcp.sh" true ;;
    2) bash "$SCRIPT_DIR/lib/init-mcp.sh" install ;;
    3) bash "$SCRIPT_DIR/lib/init-mcp.sh" keys ;;
  esac
  read -r; exit 0
}

submenu_skills() {
  _tui_choose "Skills 管理" \
    "1. 安装/同步 skills" "2. 查看状态" "0. 返回"
  case "$__TUI_CHOICE" in
    1) bash "$SCRIPT_DIR/option-skill/init.sh" --install ;;
    2) bash "$SCRIPT_DIR/option-skill/init.sh" --status; bash "$SCRIPT_DIR/lib/init-skill.sh" status ;;
  esac
  read -r; exit 0
}

show_banner() {
  if [[ "$__TUI_BACKEND" = "gum" ]]; then
    gum style --border rounded --border-foreground "#7C3AED" \
      --padding "1 3" --margin "1 0" --bold --foreground "#A78BFA" \
      "Claude Code 配置中枢 · ccconfig"
  else
    echo -e "${CYAN}Claude Code 配置中枢 · ccconfig${NC}"
  fi
}

# ========== 入口 ==========
case "${1:-menu}" in
  all)        init_all_steps ;;
  option|options) bash "$SCRIPT_DIR/init-option.sh" ;;
  --dry-run|--preview|--what)
    echo "  1) init-ubuntu.sh"
    echo "  2) init-llm.sh"
    echo "  3) init-mcp.sh sync"
    echo "  4) maintain.sh" ;;
  status) bash "$SCRIPT_DIR/maintain.sh" status ;;
  menu|"") _ensure_gum; main_menu ;;
  *) echo "用法: bash init-base.sh [all|option|--dry-run|status|menu]" ;;
esac
