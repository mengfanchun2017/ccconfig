#!/bin/bash
# ==============================================
# MCP 管理器 — maintain.sh mcp 子命令
#
# 子命令：
#   bash maintain.sh mcp status    查看 MCP 配置状态
#   bash maintain.sh mcp config    交互式配置 MCP
#   bash maintain.sh mcp keys      交互填 Key（串联 init-mcp.sh keys）
#
# 依赖：~/.claude/.config.json（读写）
# ==============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/dry-run.sh"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/interact.sh"

CONFIG_JSON="$HOME/.claude/.config.json"
SETTINGS_JSON="$HOME/.claude/settings.json"
CONF_TEMPLATE="$(find "$HOME/git" -maxdepth 3 -path '*/conf/mcp-servers.json' 2>/dev/null | head -1)"
[ -z "$CONF_TEMPLATE" ] && CONF_TEMPLATE="${CCPRIVATE_HOME:-$HOME/git/ccprivate}/conf/mcp-servers.json"

# ── 辅助函数 ──

py_write() {
  python3 -c "
import json
d = json.load(open('$CONFIG_JSON'))
$1
json.dump(d, open('$CONFIG_JSON', 'w'), indent=2, ensure_ascii=False)
" 2>&1 || err "写入 .config.json 失败"
}

# 同步 projects 配置到 settings.json
sync_projects_to_settings() {
  python3 -c "
import json, os
cfg = json.load(open('$CONFIG_JSON'))
try:
    stg = json.load(open('$SETTINGS_JSON'))
except:
    stg = {}

stg['disabledMcpServers'] = cfg.get('disabledMcpServers', [])

projects = cfg.get('projects', {})
sync = {}
for path, p in projects.items():
    if not path.startswith(os.path.expanduser('~/git/')): continue
    sp = {}
    if p.get('enabledMcpjsonServers'):
        sp['enabledMcpjsonServers'] = p['enabledMcpjsonServers']
    sp['disabledMcpServers'] = p.get('disabledMcpServers', [])
    sync[path] = sp
stg['projects'] = stg.get('projects', {}) | sync

import os
tmp = '$SETTINGS_JSON' + '.tmp'
with open(tmp, 'w') as f: json.dump(stg, f, indent=2)
os.replace(tmp, '$SETTINGS_JSON')
print('ok')
" 2>/dev/null && return 0 || return 1
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
import json, os
d = json.load(open('$CONFIG_JSON'))
projects = d.get('projects', {})
seen = set()
for path in projects:
    if not path.startswith(os.path.expanduser('~/git/')): continue
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

# 全局注册 — mcpServers 是 Claude Code 的注册表；mcp_servers 是 ccconfig 自有元数据，会滞后
all_mcps = list(d.get('mcpServers', {}))
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

all_mcps = list(d.get('mcpServers', {}))
global_disabled = d.get('disabledMcpServers', [])
user_active = [m for m in all_mcps if m not in global_disabled]

results = []
seen = set()
for path, p in d.get('projects', {}).items():
    if not path.startswith('$HOME/git/'): continue
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

  # 对比模板看差异
  if [ -f "$CONF_TEMPLATE" ]; then
    local missing
    missing=$(python3 -c "
import json
cfg = json.load(open('$CONFIG_JSON'))
conf = json.load(open('$CONF_TEMPLATE'))
cfg_names = set(cfg.get('mcpServers', {}))
conf_names = {s['name'] for s in conf.get('mcp_servers', []) if not s.get('disabled')}
diff = conf_names - cfg_names
if diff: print(' '.join(sorted(diff)))
" 2>/dev/null)
    if [ -n "$missing" ]; then
      echo ""
      echo -e "  ${GRAY}模板有但未注册:${NC}"
      for m in $missing; do
        echo -e "    ${YELLOW}○${NC} $m ${DIM}(bash init-mcp.sh sync)${NC}"
      done
    fi
  fi
  echo ""
  echo -e "  ${GRAY}入口: maintain.sh mcp config → 配置 | init-mcp.sh keys → 填 Key${NC}"
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
    local choice; choice=$(menu_select "MCP 配置" \
        "注册新的 MCP (全局)" \
        "开启/关闭 用户级 MCP (全局禁用)" \
        "管理项目 MCP (当前项目开/关)" \
        "配置 Key (交互填占位符)" \
        "查看状态" \
        "退出")
    [[ "$choice" == "0" || -z "$choice" ]] && break  # EOF → 直接退出 submenu

    case "$choice" in
      1) config_register ;;
      2) config_toggle_global "$state" ;;
      3) config_project "$curr" ;;
      4) bash "$(dirname "$SCRIPT_DIR")/lib/init-mcp.sh" keys ;;
      5) cmd_status ;;
      6) break ;;
      *) warn "无效选项" ;;
    esac
  done
}

config_register() {
  echo -e "${CYAN}━━━ 注册新 MCP━━━${NC}"
  local name cmd args_raw desc
  name=$(prompt "MCP 名称")
  [ -z "$name" ] && { warn "名称不能为空"; return; }

  cmd=$(prompt "启动命令 (如 npx)")
  [ -z "$cmd" ] && { warn "命令不能为空"; return; }

  args_raw=$(prompt "参数 (如 -y @supabase/...)")
  desc=$(prompt "描述 (可选)")

  if ! command -v claude &>/dev/null; then
    warn "claude 命令未安装"
    return
  fi

  # 用 claude mcp add 写入（保证 .config.json 格式正确）
  if claude mcp add -s user "$name" -- $cmd $args_raw 2>&1; then
    [ -n "$desc" ] && py_write "
for s in d.get('mcp_servers', []):
    if s.get('name') == '$name':
        s['description'] = '$desc'
        break
"
    echo -e "  ${GREEN}✅ $name 已注册${NC}"
  else
    if claude mcp list 2>/dev/null | grep -q "^${name}:"; then
      info "  $name 已存在，跳过"
    else
      err "注册 $name 失败"
    fi
  fi
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
  sync_projects_to_settings && info "  settings.json 已同步"
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
    local mode; mode=$(menu_select "选择" "项目特开 (强制启用)" "项目特关 (强制关闭)" "取消")
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
  sync_projects_to_settings && info "  settings.json 已同步"
}

# ── 主入口 ──

case "${1:-status}" in
  status|st) cmd_status ;;
  config|cfg|c|conf) cmd_config ;;
  keys) bash "$(dirname "$SCRIPT_DIR")/lib/init-mcp.sh" keys ;;
  sync) sync_projects_to_settings && echo -e "  ${GREEN}settings.json 已同步${NC}" || err "同步失败" ;;
  *) echo -e "  ${YELLOW}用法: bash maintain.sh mcp {status|config|keys|sync}${NC}" ;;
esac
