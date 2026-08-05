#!/bin/bash
# ==============================================
# MCP 管理器 — maintain.sh mcp 子命令
#
# 子命令：
#   bash maintain.sh mcp status    查看 MCP 配置状态
#   bash maintain.sh mcp config    交互式配置 MCP
#
# 依赖：~/.claude/.config.json（读写）
# ==============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/colors.sh"

CONFIG_JSON="$HOME/.claude/.config.json"
SETTINGS_JSON="$HOME/.claude/settings.json"

# ── 辅助函数 ──

py() {
  python3 -c "import json,sys; d=json.load(open('$CONFIG_JSON')); $1" 2>/dev/null || echo "ERR"
}

py_write() {
  python3 -c "
import json
d = json.load(open('$CONFIG_JSON'))
$1
json.dump(d, open('$CONFIG_JSON', 'w'), indent=2, ensure_ascii=False)
" 2>&1 || err "写入 .config.json 失败"
}

# 获取当前项目路径（从 CWD 找最近的 git 仓库）
current_project() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ]; then
      echo "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  echo ""
}

# 获取有项目配置的所有 git 仓库路径（去重，只取 ~/git/ 下的）
list_git_repos() {
  python3 -c "
import json
d = json.load(open('$CONFIG_JSON'))
projects = d.get('projects', {})
seen = set()
for path in projects:
    if not path.startswith('/home/francis/git/'): continue
    if path in seen: continue
    seen.add(path)
    print(path)
" 2>/dev/null
}

# ── 解析 MCP 状态（给 status + config 共用） ──

resolve_mcp_state() {
  local proj_path="${1:-}"
  python3 << EOF
import json
d = json.load(open('$CONFIG_JSON'))

# 全局注册
all_mcps = [s['name'] for s in d.get('mcp_servers', [])]
global_disabled = d.get('disabledMcpServers', [])

# 用户级激活 = 全局注册 - 全局禁用
user_active = [m for m in all_mcps if m not in global_disabled]

# 项目级
proj_path = '${proj_path}'
proj = d.get('projects', {}).get(proj_path, {})
proj_enabled = proj.get('enabledMcpjsonServers', [])
proj_disabled = proj.get('disabledMcpServers', [])

# 项目级激活 = 用户级激活 - 项目关 + 项目开
project_active = [m for m in user_active if m not in proj_disabled]
for m in proj_enabled:
    if m not in project_active:
        project_active.append(m)

final_active = project_active[:]

import sys
sys.stdout.write(json.dumps({
    'all': all_mcps,
    'global_disabled': global_disabled,
    'user_active': user_active,
    'proj_enabled': proj_enabled,
    'proj_disabled': proj_disabled,
    'project_active': project_active,
    'final_active': final_active,
}))
EOF
}

# ── 所有项目完整状态（给 status 一览用） ──

all_projects_status() {
  local current="$1"
  python3 << EOF
import json
d = json.load(open('$CONFIG_JSON'))

all_mcps = [s['name'] for s in d.get('mcp_servers', [])]
global_disabled = d.get('disabledMcpServers', [])
user_active = [m for m in all_mcps if m not in global_disabled]

results = []
seen = set()
for path, p in d.get('projects', {}).items():
    if not path.startswith('/home/francis/git/'): continue
    if path in seen: continue
    seen.add(path)
    name = path.rsplit('/', 1)[-1]
    proj_enabled = p.get('enabledMcpjsonServers', [])
    proj_disabled = p.get('disabledMcpServers', [])
    project_active = [m for m in user_active if m not in proj_disabled]
    for m in proj_enabled:
        if m not in project_active:
            project_active.append(m)
    results.append({
        'name': name,
        'path': path,
        'active': project_active,
        'current': path == '$current',
    })

# 排序：当前排第一，其余按名字
results.sort(key=lambda r: (0 if r['current'] else 1, r['name']))

import sys
sys.stdout.write(json.dumps(results))
EOF
}

# ── status 子命令 ──

cmd_status() {
  local curr="$(current_project)"
  local cur_name="${curr##*/}"
  [ -z "$curr" ] && cur_name="(非 git 目录)"

  local state
  state=$(resolve_mcp_state "$curr")
  local all_mcps=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['all']))")
  local global_disabled=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['global_disabled']))")
  local user_active=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['user_active']))")
  local proj_enabled=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['proj_enabled']))")
  local proj_disabled=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['proj_disabled']))")
  local project_active=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['project_active']))")
  local final_active=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['final_active']))")

  echo -e "\n${CYAN}━━━ MCP 状态━━━${NC}"
  echo -e "  ${GRAY}当前项目:${NC} ${BOLD}${cur_name}${NC} ${GRAY}(${curr:-$PWD})${NC}"
  echo ""

  echo -e "  ${BOLD}用户级注册 MCP:${NC}"
  for m in $all_mcps; do
    echo -e "    ${GREEN}✓${NC} $m"
  done
  echo ""

  echo -e "  ${BOLD}用户级激活 MCP:${NC} ${GRAY}(全注册 - 全局禁用)${NC}"
  if [ -z "$global_disabled" ]; then
    echo -e "    ${GREEN}✓${NC} all"
  else
    for m in $all_mcps; do
      if echo " $global_disabled " | grep -q " $m "; then
        echo -e "    ${RED}✗${NC} $m ${DIM}(全局禁用)${NC}"
      else
        echo -e "    ${GREEN}✓${NC} $m"
      fi
    done
  fi
  echo ""

  echo -e "  ${BOLD}项目级激活 MCP:${NC} ${GRAY}(用户级 + 项目特开 - 项目特关)${NC}"
  if [ -z "$proj_enabled" ] && [ -z "$proj_disabled" ]; then
    echo -e "    ${DIM}此项目无单独 MCP 配置，继承用户级激活${NC}"
  fi
  for m in $all_mcps; do
    if echo " $project_active " | grep -q " $m "; then
      local note=""
      if echo " $proj_enabled " | grep -q " $m "; then note="${DIM}(项目特开)${NC}"; fi
      echo -e "    ${GREEN}✓${NC} $m $note"
    else
      local why="${DIM}(全局禁用)${NC}"
      if echo " $proj_disabled " | grep -q " $m "; then why="${DIM}(项目特关)${NC}"; fi
      echo -e "    ${RED}✗${NC} $m $why"
    fi
  done
  echo ""

  echo -e "  ${BOLD}最终活跃 MCP:${NC}"
  if [ -z "$final_active" ]; then
    echo -e "    ${YELLOW}(无)${NC}"
  else
    local line=""
    for m in $final_active; do
      line="$line ${GREEN}$m${NC}"
    done
    echo -e "   $line"
  fi
  echo ""

  # ── 其他项目一览 ──
  echo -e "  ${BOLD}其他项目一览:${NC}"
  local all_status
  all_status=$(all_projects_status "$curr")
  echo "$all_status" | python3 -c "
import json, sys
data = json.load(sys.stdin)
max_name = max(len(r['name']) for r in data) if data else 10
for r in data:
    active = ' '.join(r['active'])
    marker = '▸' if r['current'] else ' '
    suffix = '  ← 当前' if r['current'] else ''
    print(f'    {marker} {r[\"name\"].ljust(max_name)} │ {active}{suffix}')
" 2>/dev/null
  echo ""

  echo -e "  ${GRAY}用法: bash maintain.sh mcp config → 交互式配置${NC}"
}

# ── config 子命令 ──

cmd_config() {
  local curr="$(current_project)"

  while true; do
    local state
    state=$(resolve_mcp_state "$curr")
    local all_mcps=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['all']))")
    local global_disabled=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['global_disabled']))")
    local user_active=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['user_active']))")

    echo -e "\n${CYAN}━━━ MCP 配置━━━${NC}"
    echo -e "  ${GRAY}当前项目:${NC} ${BOLD}${curr##*/}${NC}"
    echo -e "  当前用户级激活: $user_active"
    echo ""
    echo -e "  ${BOLD}选择操作:${NC}"
    echo -e "  ${CYAN}1${NC}) 注册新的 MCP (全局)"
    echo -e "  ${CYAN}2${NC}) 开启/关闭 用户级 MCP (全局禁用)"
    echo -e "  ${CYAN}3${NC}) 管理项目 MCP (当前项目开/关)"
    echo -e "  ${CYAN}4${NC}) 查看状态"
    echo -e "  ${CYAN}q${NC}) 退出"
    echo -ne "\n  ${BOLD}>${NC} "
    read -r choice
    echo ""

    case "$choice" in
      1) config_register ;;
      2) config_toggle_global "$state" ;;
      3) config_project "$curr" ;;
      4) cmd_status ;;
      q|Q) break ;;
      *) warn "无效选项" ;;
    esac
  done
}

config_register() {
  echo -e "${CYAN}━━━ 注册新 MCP━━━${NC}"
  echo -n -e "  MCP 名称: "
  read -r name
  [ -z "$name" ] && { warn "名称不能为空"; return; }

  echo -n -e "  命令 (如 npx): "
  read -r cmd
  [ -z "$cmd" ] && { warn "命令不能为空"; return; }

  echo -n -e "  参数 (如 -y \@supabase/mcp-server-supabase): "
  read -r args

  py_write "
new = {'name': '$name', 'type': 'stdio', 'command': '$cmd', 'args': '$args'.split(), 'env': {}, 'description': ''}
d.setdefault('mcp_servers', []).append(new)
"
  echo -e "  ${GREEN}已注册: $name${NC}"
}

config_toggle_global() {
  local state="$1"
  local all_mcps=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['all']))")
  local global_disabled=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['global_disabled']))")

  echo -e "${CYAN}━━━ 用户级 MCP 开关━━━${NC}"
  echo -e "  ${GRAY}选数字切换：✓=开启  ✗=关闭 (全局禁用)${NC}"
  echo ""

  local i=1 items=()
  for m in $all_mcps; do
    local status="${GREEN}✓${NC}"
    if echo " $global_disabled " | grep -q " $m "; then
      status="${RED}✗${NC}"
    fi
    echo -e "  ${CYAN}$i${NC}) $status $m"
    items+=("$m")
    ((i++))
  done
  echo -e "  ${CYAN}${i}${NC}) ${DIM}完成${NC}"
  echo -ne "\n  ${BOLD}>${NC} "
  read -r toggle_choice

  if [ "$toggle_choice" = "$i" ] || [ -z "$toggle_choice" ]; then return; fi

  local idx=$((toggle_choice - 1))
  [ "$idx" -lt 0 ] || [ "$idx" -ge "${#items[@]}" ] && { warn "无效选项"; return; }

  local target="${items[$idx]}"
  local currently_disabled=false
  if echo " $global_disabled " | grep -q " $target "; then currently_disabled=true; fi

  if [ "$currently_disabled" = true ]; then
    py_write "
d.setdefault('disabledMcpServers', [])
d['disabledMcpServers'] = [m for m in d['disabledMcpServers'] if m != '$target']
"
    echo -e "  ${GREEN}已开启 $target (移出全局禁用)${NC}"
  else
    py_write "
d.setdefault('disabledMcpServers', [])
if '$target' not in d['disabledMcpServers']:
    d['disabledMcpServers'].append('$target')
"
    echo -e "  ${YELLOW}已关闭 $target (加入全局禁用)${NC}"
  fi
}

config_project() {
  local curr="$1"
  [ -z "$curr" ] && { warn "不在 git 项目目录中，无法配置项目 MCP"; return; }

  local cur_name="${curr##*/}"
  local state
  state=$(resolve_mcp_state "$curr")
  local all_mcps=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['all']))")
  local user_active=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['user_active']))")
  local proj_enabled=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['proj_enabled']))")
  local proj_disabled=$(echo "$state" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['proj_disabled']))")

  echo -e "${CYAN}━━━ 项目 MCP — $cur_name━━━${NC}"
  echo -e "  ${GRAY}选数字切换：✓=项目特开  ✗=项目特关  -=继承用户级${NC}"
  echo ""

  local i=1 items=()
  for m in $all_mcps; do
    local status="${GRAY}-${NC}"
    if echo " $proj_enabled " | grep -q " $m "; then
      status="${GREEN}✓${NC}"
    elif echo " $proj_disabled " | grep -q " $m "; then
      status="${RED}✗${NC}"
    fi
    echo -e "  ${CYAN}$i${NC}) $status $m"
    items+=("$m")
    ((i++))
  done
  echo -e "  ${CYAN}${i}${NC}) ${DIM}完成${NC}"
  echo -ne "\n  ${BOLD}>${NC} "
  read -r toggle_choice

  if [ "$toggle_choice" = "$i" ] || [ -z "$toggle_choice" ]; then return; fi

  local idx=$((toggle_choice - 1))
  [ "$idx" -lt 0 ] || [ "$idx" -ge "${#items[@]}" ] && { warn "无效选项"; return; }

  local target="${items[$idx]}"
  local currently_enabled=false
  local currently_disabled=false
  if echo " $proj_enabled " | grep -q " $target "; then currently_enabled=true; fi
  if echo " $proj_disabled " | grep -q " $target "; then currently_disabled=true; fi

  local escaped_path="${curr//\/\\/}"

  if [ "$currently_enabled" = true ]; then
    # 从项目启用 → 恢复为继承
    py_write "
p = d.setdefault('projects', {}).setdefault('$escaped_path', {})
p['enabledMcpjsonServers'] = [m for m in p.get('enabledMcpjsonServers', []) if m != '$target']
"
    echo -e "  ${YELLOW}$target 改为继承用户级${NC}"
  elif [ "$currently_disabled" = true ]; then
    # 从项目关闭 → 恢复为继承
    py_write "
p = d.setdefault('projects', {}).setdefault('$escaped_path', {})
p['disabledMcpServers'] = [m for m in p.get('disabledMcpServers', []) if m != '$target']
"
    echo -e "  ${YELLOW}$target 改为继承用户级${NC}"
  else
    # 继承用户级 → 循环：选项目特开还是项目特关
    echo -e "  $target 当前继承用户级"
    echo -e "  ${CYAN}1${NC}) 项目特开 (强制启用)"
    echo -e "  ${CYAN}2${NC}) 项目特关 (强制关闭)"
    echo -e "  ${CYAN}3${NC}) 取消"
    echo -ne "  ${BOLD}>${NC} "
    read -r mode
    case "$mode" in
      1)
        py_write "
p = d.setdefault('projects', {}).setdefault('$escaped_path', {})
p.setdefault('enabledMcpjsonServers', []).append('$target')
"
        echo -e "  ${GREEN}$target 已设为项目特开${NC}"
        ;;
      2)
        py_write "
p = d.setdefault('projects', {}).setdefault('$escaped_path', {})
p.setdefault('disabledMcpServers', []).append('$target')
"
        echo -e "  ${RED}$target 已设为项目特关${NC}"
        ;;
      *) return ;;
    esac
  fi
}

# ── 主入口 ──

case "${1:-status}" in
  status|st) cmd_status ;;
  config|cfg|c|conf) cmd_config ;;
  *) echo -e "  ${YELLOW}用法: bash maintain.sh mcp {status|config}${NC}" ;;
esac
