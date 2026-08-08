#!/bin/bash
# ccconfig/option-larkbridge/init.sh — 飞书 lark-channel-bridge 管理
#
# 概念:
#   profile = 一个飞书应用（Bot），有 appId/appSecret 和独立配置
#   systemd template = lark-channel-bridge@<profile>.service，每个 profile 一个
#   --run 前台调试 / --start 后台跑 / --profile 管理配置
#
# 用法:
#   init.sh --run [profile]         前台运行（不传交互选）
#   init.sh --start [profile]       后台 systemd 运行（不传交互选）
#   init.sh --stop [profile]        停止（不传交互选）
#   init.sh --restart [profile]     重启（不传交互选）
#   init.sh --status                所有 profile + 运行状态
#   init.sh --logs [profile]        查看日志（不传选一个）
#   init.sh --profile list          列出 profile
#   init.sh --profile add           新增（ccprivate / 扫码）
#   init.sh --profile remove        删除
#   init.sh --profile default       设默认

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_DIR/lib/dry-run.sh"
source "$CCCONFIG_DIR/lib/path-helper.sh" 2>/dev/null || true
source "$CCCONFIG_DIR/lib/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'
    good() { echo -e "${GREEN}$1${NC}"; }
    bad()  { echo -e "${RED}$1${NC}"; }
    warn() { echo -e "${YELLOW}$1${NC}"; }
    info() { echo -e "${GRAY}$1${NC}"; }
}

NODE_BIN="$(find_node_bin 2>/dev/null || echo "")"
export PATH="$HOME/.local/bin:${NODE_BIN}:$PATH"
SERVICE_PREFIX="lark-channel-bridge"
LCONF="$HOME/.lark-channel/config.json"

# ========== 辅助 ==========

_list_profiles() {
  python3 -c "import json,os; d=json.load(open(os.path.expanduser('$LCONF'))); [print(p) for p in d.get('profiles',{}).keys()]" 2>/dev/null || true
}

_get_active() {
  python3 -c "import json,os; print(json.load(open(os.path.expanduser('$LCONF'))).get('activeProfile',''))" 2>/dev/null || echo ""
}

_pick_profile() {
  local prompt="${1:-选择 profile}"
  local profiles; mapfile -t profiles < <(_list_profiles)
  [ ${#profiles[@]} -eq 0 ] && { warn "没有 profile，先运行 --profile add" >&2; return 1; }
  local active; active="$(_get_active)"
  local running; running=$(_get_running_profiles)
  echo -e "${CYAN}── ${prompt} ──${NC}" >&2
  local i=0
  while [ $i -lt ${#profiles[@]} ]; do
    local p="${profiles[$i]}"
    local am=""; [ "$p" = "$active" ] && am=" ${CYAN}← 当前${NC}"
    local rm=""; echo "$running" | grep -qxF "$p" && rm=" ${GREEN}● 运行中${NC}"
    echo -e "  $((i+1))) $p${am}${rm}" >&2
    i=$((i+1))
  done
  echo -e "  0) 取消" >&2
  read -p "  选择 [0-$i]: " sel
  [ -z "$sel" ] || [ "$sel" = "0" ] && return 1
  [ "$sel" -ge 1 ] 2>/dev/null && [ "$sel" -le "$i" ] 2>/dev/null || return 1
  echo "${profiles[$((sel-1))]}"
}

_get_running_profiles() {
  command -v lark-channel-bridge &>/dev/null || return
  lark-channel-bridge profile list 2>/dev/null | awk 'NR>1{print $2}' || true
}

_list_larkbridge_apps() {
  local conf="$1"
  python3 - "$conf" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
  d = json.load(f)
for a in d.get('apps', []):
  lb = a.get('larkbridge', {})
  if lb.get('enabled', False):
    print(f"{a.get('name','?')}|{a.get('appId','')}|{a.get('appSecret','')}")
PYEOF
}

# 从 ccprivate app 读 admin open_id 列表（空字符串 = 无）
_app_admin_openids() {
  local feishu_conf="$1" app_name="$2"
  [ -f "$feishu_conf" ] || return 0
  python3 - "$feishu_conf" "$app_name" << 'PYEOF' 2>/dev/null
import json, sys
p, name = sys.argv[1], sys.argv[2]
with open(p) as f: d = json.load(f)
for a in d.get('apps', []):
    if a.get('name') == name:
        ids = a.get('larkbridge', {}).get('adminOpenIds', []) or []
        print('\n'.join(ids))
        break
PYEOF
}

# 把 admin open_id 注入到 ~/.lark-channel/config.json profiles[name].access.allowedUsers
# 流程: 读 ccprivate adminOpenIds + 已有 allowedUsers → 去重 → 写回
_inject_admin_users() {
  local profile="$1" feishu_conf="$2"
  local root_cfg="$HOME/.lark-channel/config.json"
  [ -f "$root_cfg" ] || return 0
  [ -n "$profile" ] || return 0

  local -a admins
  if [ -n "$feishu_conf" ] && [ -f "$feishu_conf" ]; then
    while IFS= read -r oid; do
      [ -n "$oid" ] && admins+=("$oid")
    done < <(_app_admin_openids "$feishu_conf" "$profile")
  fi

  local existing
  existing=$(python3 - "$root_cfg" "$profile" << 'PYEOF' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
p = d.get('profiles', {}).get(sys.argv[2], {})
print('\n'.join(p.get('access', {}).get('allowedUsers', [])))
PYEOF
)

  local need_prompt=0
  [ ${#admins[@]} -eq 0 ] && [ -z "$existing" ] && need_prompt=1

  if [ $need_prompt -eq 1 ]; then
    warn "  ⚠ ${profile} 没有 admin open_id（ccprivate + profile 都为空）" >&2
    info "  不知道谁能用这个 bot。问用户要一个 open_id：" >&2
    read -p "    请输入你自己的 open_id (留空跳过): " input_oid
    if [ -n "$input_oid" ]; then
      admins+=("$input_oid")
      info "    → 已记下 $input_oid" >&2
      # 同步回 ccprivate（用户下次新建/重装不用再输）
      if [ -n "$feishu_conf" ] && [ -f "$feishu_conf" ]; then
        python3 - "$feishu_conf" "$profile" "$input_oid" << 'PYEOF' 2>/dev/null
import json, sys
p, name, oid = sys.argv[1], sys.argv[2], sys.argv[3]
with open(p) as f: d = json.load(f)
for a in d.get('apps', []):
    if a.get('name') == name:
        lb = a.setdefault('larkbridge', {})
        ids = lb.setdefault('adminOpenIds', [])
        if oid not in ids:
            ids.append(oid)
        break
with open(p,'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
        info "    → 已写回 ccprivate/conf/feishu.json" >&2
      fi
    else
      warn "    跳过 — profile 创建后没 admin，bot 拒绝任何人发消息" >&2
      return 0
    fi
  fi

  # 合并 + 写回
  python3 - "$root_cfg" "$profile" "$(printf '%s\n' "${admins[@]}")" << 'PYEOF' 2>/dev/null
import json, sys
root_cfg, profile, admins_blob = sys.argv[1], sys.argv[2], sys.argv[3]
new_admins = [x for x in admins_blob.split('\n') if x]
with open(root_cfg) as f: d = json.load(f)
p = d.setdefault('profiles', {}).setdefault(profile, {})
acc = p.setdefault('access', {})
existing = acc.get('allowedUsers', []) or []
seen = set(existing)
merged = list(existing)
for a in new_admins:
    if a not in seen:
        merged.append(a); seen.add(a)
acc['allowedUsers'] = merged
with open(root_cfg,'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
if merged:
    print(' | '.join(merged))
PYEOF
}

_run_select_app() {
  local ws="${LARK_WORKSPACE:-$HOME/git}"
  local feishu_conf=""
  if [ -f "$HOME/git/ccprivate/conf/feishu.json" ]; then
    feishu_conf="$HOME/git/ccprivate/conf/feishu.json"
  elif command -v resolve_conf &>/dev/null; then
    feishu_conf=$(resolve_conf feishu.json 2>/dev/null) || true
  fi

  local -a app_names app_ids app_secrets
  if [ -n "$feishu_conf" ]; then
    while IFS='|' read -r name id secret; do
      [ -z "$name" ] && continue
      app_names+=("$name"); app_ids+=("$id"); app_secrets+=("$secret")
    done < <(_list_larkbridge_apps "$feishu_conf")
  fi

  local -a profiles; mapfile -t profiles < <(_list_profiles)
  local active; active="$(_get_active)"
  local running; running=$(_get_running_profiles)

  echo -e "${CYAN}── 选择飞书应用 ──${NC}" >&2

  local idx=1; local -a menu_items=()

  if [ ${#profiles[@]} -gt 0 ]; then
    echo -e "  ${GRAY}--已有 profile--${NC}" >&2
    for p in "${profiles[@]}"; do
      local am=""; [ "$p" = "$active" ] && am=" ${CYAN}← 当前${NC}"
      local rm=""; echo "$running" | grep -qxF "$p" && rm=" ${GREEN}● 运行中${NC}"
      echo -e "  ${idx}) ${p}${am}${rm}" >&2
      menu_items+=("use:$p"); idx=$((idx+1))
    done
  fi

  if [ ${#app_names[@]} -gt 0 ]; then
    echo -e "  ${GRAY}--ccprivate 配置--${NC}" >&2
    local i=0
    while [ $i -lt ${#app_names[@]} ]; do
      local name="${app_names[$i]}"; local id_short="${app_ids[$i]:0:12}..."
      local em=""
      for p2 in "${profiles[@]}"; do [ "$p2" = "$name" ] && em=" ${GRAY}(已存在)${NC}" && break; done
      echo -e "  ${idx}) ${name} (${id_short})${em}" >&2
      [ -z "$em" ] && menu_items+=("create:$name") || menu_items+=("use:$name")
      idx=$((idx+1)); i=$((i+1))
    done
  fi

  echo -e "  ${GRAY}--扫码新建--${NC}" >&2
  echo -e "  ${idx}) ${YELLOW}扫码新建 profile${NC}" >&2
  menu_items+=("scan"); idx=$((idx+1))

  echo -e "  0) 返回" >&2
  local max=$((idx-1))
  read -p "  选择 [0-${max}]: " sel
  [ -z "$sel" ] || [ "$sel" = "0" ] && return 1
  [ "$sel" -ge 1 ] 2>/dev/null || return 1
  [ $((sel-1)) -ge ${#menu_items[@]} ] && return 1
  local chosen="${menu_items[$((sel-1))]}"

  case "$chosen" in
    use:*) echo "${chosen#use:}"; return 0 ;;
    create:*)
      local cname="${chosen#create:}"
      local fi=0; while [ $fi -lt ${#app_names[@]} ]; do [ "${app_names[$fi]}" = "$cname" ] && break; fi=$((fi+1)); done
      lark-channel-bridge profile create "$cname" --agent claude --workspace "$ws" --app-id "${app_ids[$fi]}" --app-secret "${app_secrets[$fi]}" > /dev/null 2>&1
      _inject_admin_users "$cname" "$feishu_conf"
      echo "$cname"; return 0 ;;
    scan)
      read -p "  输入新 profile 名称: " scan_name
      [ -z "$scan_name" ] && { warn "  名称不能为空" >&2; return 1; }
      lark-channel-bridge profile create "$scan_name" --agent claude --workspace "$ws"
      _inject_admin_users "$scan_name" "$feishu_conf"
      echo "$scan_name"; return 0 ;;
  esac
  return 1
}

install() {
  echo -e "${CYAN}── 安装 lark-channel-bridge ──${NC}"
  if command -v lark-channel-bridge &>/dev/null; then
    local ver; ver=$(lark-channel-bridge --version 2>/dev/null | head -1 || echo "?")
    good "  ✓ 已安装: $ver"; return 0
  fi
  echo -n "  安装中 ... "
  if npm install -g lark-channel-bridge 2>&1 | tail -1; then
    local npm_bin; npm_bin="$(npm prefix -g 2>/dev/null)/bin"
    mkdir -p "$HOME/.local/bin"
    [ -x "$npm_bin/lark-channel-bridge" ] && ln -sf "$npm_bin/lark-channel-bridge" "$HOME/.local/bin/lark-channel-bridge"
    good "✅"
  else
    bad "❌ 安装失败"; return 1
  fi
}

run_foreground() {
  local profile="${1:-}"
  [ -z "$profile" ] && profile="$(_run_select_app)"
  [ -z "$profile" ] && return 0
  local ws="${LARK_WORKSPACE:-$HOME/git}"
  echo "" >&2
  good "  ✓ profile「${profile}」已上线（前台运行，Ctrl-C 退出）" >&2
  lark-channel-bridge run --profile "$profile" --workspace "$ws" 2>&1 \
    | grep -v 'sdk.error\|owner_refresh_failed\|chats-fetch-failed\|\[lark-info' || true
  local rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 130 ]; then
    local app_id; app_id="$(_get_profile_app_id "$profile")"
    if _check_scope_errors "$profile" >/dev/null && [ -n "$app_id" ]; then
      _print_scope_hint "$profile" "$app_id"
    fi
  fi
}

_service_file() { echo "$HOME/.config/systemd/user/${SERVICE_PREFIX}@${1}.service"; }

# 飞书 app scope 检测 + 修复提示
# 触发: bridge 日志里出现 "Access denied" + scope list
# 输出: 直跳权限管理链接 + 可粘贴 JSON + 步骤
# JSON 已过滤 2024-09-30 废弃的 im:chat.group_info:readonly / im:message.p2p_msg / im:message.group_at_msg / im:message.groups

_scope_required_json() {
  cat << 'JSONEOF'
{"scopes":{"tenant":["im:message","im:message:send_as_bot","im:message.p2p_msg:readonly","im:message.group_at_msg:readonly","im:message:readonly","im:chat","im:chat:readonly","im:chat:read","im:chat.members:read"],"user":[]}}
JSONEOF
}

_get_profile_app_id() {
  local profile="$1"
  python3 -c "
import json
d=json.load(open('$LCONF'))
p=d.get('profiles',{}).get('$profile',{})
print(p.get('accounts',{}).get('app',{}).get('id',''))
" 2>/dev/null || true
}

_check_scope_errors() {
  local profile="$1"
  local log="$HOME/.lark-channel/profiles/${profile}/logs/"
  [ -d "$log" ] || return 1
  local latest; latest=$(find "$log" -name "*.jsonl" -type f -mtime -1 2>/dev/null | sort -r | head -1)
  [ -z "$latest" ] && return 1
  # 找最近的 Access denied 错误
  grep -E "Access denied|scopes is required|scope_required" "$latest" 2>/dev/null | tail -3 || true
}

_print_scope_hint() {
  local profile="$1"
  local app_id="$2"
  [ -z "$app_id" ] && return 0
  echo "" >&2
  warn "  ⚠ 检测到飞书 app 缺 scope（${profile}）" >&2
  echo "" >&2
  info "  1. 点链接直跳 ${profile} app 权限管理：" >&2
  info "     https://open.feishu.cn/app/${app_id}/permission" >&2
  echo "" >&2
  info "  2. 「批量导入/导出权限」→ 导入 → 粘贴：" >&2
  echo "" >&2
  _scope_required_json | sed 's/^/     /' >&2
  echo "" >&2
  info "  3. 下一步 → 确认开通 → 顶部「创建版本」→ 提交" >&2
  info "  4. 等管理员审批通过 → 重启 bridge：" >&2
  info "     bash ccconfig/option-larkbridge/init.sh --restart ${profile}" >&2
  echo "" >&2
  warn "  ⚠ im:chat.group_info:readonly 等 2024-09-30 已废弃——JSON 已用 im:chat:read 替代" >&2
}

_setup_service() {
  local profile="$1"
  [ -z "$profile" ] && return 1
  if ! systemctl --user daemon-reload 2>/dev/null; then
    warn "  systemd --user 不可用" >&2; return 1
  fi
  loginctl enable-linger "$USER" 2>/dev/null || true
  mkdir -p "$HOME/.config/systemd/user"

  local svc="$(_service_file "$profile")"
  cat > "$svc" << SERVICEOF
[Unit]
Description=Lark Channel Bridge — ${profile}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${HOME}/.local/bin/lark-channel-bridge start --profile ${profile}
Restart=on-failure
RestartSec=15
Environment=PATH=${HOME}/.local/bin:${NODE_BIN}:/usr/local/bin:/usr/bin:/bin
Environment=LARK_CHANNEL_HOME=${HOME}/.lark-channel

[Install]
WantedBy=default.target
SERVICEOF

  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable "${SERVICE_PREFIX}@${profile}" 2>/dev/null || true

  if systemctl --user restart "${SERVICE_PREFIX}@${profile}" 2>&1; then
    good "  ✅ ${profile} 服务运行中"
    echo ""
    info "  管理 ${profile}:"
    info "    状态: systemctl --user status ${SERVICE_PREFIX}@${profile}"
    info "    日志: journalctl --user -u ${SERVICE_PREFIX}@${profile} -f"
    info "    重启: $0 --restart ${profile}"
    info "    停止: $0 --stop ${profile}"
  else
    warn "  ⚠ ${profile} 服务启动失败" >&2
    journalctl --user -u "${SERVICE_PREFIX}@${profile}" --no-pager -n 20 2>/dev/null || true
  fi
}

show_status() {
  local running; running="$(_get_running_profiles)"
  local -a profiles; mapfile -t profiles < <(_list_profiles)
  local ver; ver=$(lark-channel-bridge --version 2>/dev/null | head -1 || echo "?")

  if [ ${#profiles[@]} -eq 0 ]; then
    echo "MISSING lark-channel-bridge $ver (无 profile)"
  elif [ -n "$running" ]; then
    local cnt; cnt=$(echo "$running" | wc -l)
    echo "OK lark-channel-bridge $ver (${cnt} profile(s) 运行中)"
  elif ls "$HOME/.config/systemd/user/${SERVICE_PREFIX}@"*.service &>/dev/null 2>&1; then
    echo "WARN lark-channel-bridge $ver (有 service 但未运行)"
  else
    echo "OK lark-channel-bridge $ver (已安装)"
  fi

  echo -n "  安装 ... "
  command -v lark-channel-bridge &>/dev/null \
    && good "✅ $ver" \
    || echo -e "${YELLOW}○${NC} 未安装"

  echo ""
  echo -e "${CYAN}── Profile 列表 ──${NC}"
  if [ ${#profiles[@]} -eq 0 ]; then
    echo "  无，运行 --profile add 添加"
  else
    printf "  %-20s %-10s %s\n" "PROFILE" "STATUS" "SERVICE"
    for p in "${profiles[@]}"; do
      local status="${GRAY}○ 未启动${NC}"
      echo "$running" | grep -qxF "$p" && status="${GREEN}● 运行中${NC}"
      local svc_indicator="${GRAY}-${NC}"
      [ -f "$(_service_file "$p")" ] && svc_indicator="${GRAY}systemd${NC}"
      local warn_marker=""
      if _check_scope_errors "$p" >/dev/null; then
        warn_marker=" ${YELLOW}⚠ 缺 scope（运行 $0 --run ${p} 看修复提示）${NC}"
      fi
      echo -e "  $(printf '%-20s' "$p") $(printf '%-10b' "$status") $svc_indicator$warn_marker"
    done
  fi

  if [ -f "$LCONF" ]; then
    local active; active="$(_get_active)"
    echo ""
    echo -e "${CYAN}── 配置 ──${NC}"
    echo "  默认 profile: ${CYAN}${active:-（无）}${NC}"
    echo ""
    info "  管理命令:"
    info "    $0 --run <profile>          # 前台调试"
    info "    $0 --start <profile>        # 后台 systemd"
    info "    $0 --profile add            # 新增"
    info "    $0 --profile remove         # 删除"
  fi
}

show_logs() {
  local profile="${1:-}"
  [ -z "$profile" ] && profile="$(_pick_profile "选择 profile 查看日志")" || return 0
  [ -z "$profile" ] && return 0

  if [ -f "$(_service_file "$profile")" ] && systemctl --user is-active "${SERVICE_PREFIX}@${profile}" &>/dev/null 2>&1; then
    journalctl --user -u "${SERVICE_PREFIX}@${profile}" -f
  else
    local log_dir="$HOME/.lark-channel/profiles/"
    if [ -d "$log_dir" ]; then
      local latest; latest=$(find "$log_dir" -name "${profile}*.jsonl" -type f 2>/dev/null | sort -r | head -1)
      if [ -n "$latest" ]; then
        info "日志: $latest"
        tail -f "$latest" | python3 -c "
import json, sys
for line in sys.stdin:
  try:
    d = json.loads(line)
    time = d.get('time','')[:19]; event = d.get('event',''); msg = d.get('message','')
    print(f'{time} [{event}] {msg}')
  except: print(line.rstrip())" 2>/dev/null || tail -f "$latest"
      else
        warn "暂无日志" >&2
      fi
    else
      warn "日志目录不存在" >&2
    fi
  fi
}

profile_list() {
  local running; running="$(_get_running_profiles)"
  local -a profiles; mapfile -t profiles < <(_list_profiles)
  local active; active="$(_get_active)"
  echo -e "${CYAN}── Profile 列表 ──${NC}"
  [ ${#profiles[@]} -eq 0 ] && { echo "  无"; return 0; }
  local i=0
  for p in "${profiles[@]}"; do
    local status="${GRAY}○${NC}"
    echo "$running" | grep -qxF "$p" && status="${GREEN}●${NC}"
    local note=""; [ "$p" = "$active" ] && note="默认"
    echo -e "  $((i+1))) $(printf '%-20s' "$p") $(printf '%-10b' "$status") ${GRAY}${note}${NC}"
    i=$((i+1))
  done
}

profile_add() {
  local ws="${LARK_WORKSPACE:-$HOME/git}"
  local name; name="$(_run_select_app)" || { warn "取消" >&2; return 0; }
  [ -z "$name" ] && return 0
  good "  ✓ profile「${name}」已就绪"
}

profile_remove() {
  local profile; profile="$(_pick_profile "选择要删除的 profile")" || return 0
  [ -z "$profile" ] && return 0
  read -p "  确认删除 profile「${profile}」? [y/N] " confirm
  [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { warn "取消" >&2; return 0; }
  local svc="$(_service_file "$profile")"
  [ -f "$svc" ] && { systemctl --user stop "${SERVICE_PREFIX}@${profile}" 2>/dev/null || true; systemctl --user disable "${SERVICE_PREFIX}@${profile}" 2>/dev/null || true; rm -f "$svc"; }
  lark-channel-bridge profile remove "$profile" --yes 2>/dev/null || true
  good "  ✓ 已删除"
}

profile_default() {
  local profile; profile="$(_pick_profile "设为默认（activeProfile）")" || return 0
  [ -z "$profile" ] && return 0
  lark-channel-bridge profile use "$profile" 2>&1
  good "  ✓ 已切换默认 profile 为「${profile}」"
  info "  重启 service 生效: systemctl --user restart ${SERVICE_PREFIX}@${profile}"
}

main() {
  local cmd="${1:-}"; shift 2>/dev/null || true

  case "$cmd" in
    --run|--start|--logs|--profile|--stop|--restart)
      install ;;
  esac

  case "$cmd" in
    --run)
      run_foreground "${1:-}" ;;
    --start|--start-webui)
      local profile="${1:-}"
      [ -z "$profile" ] && profile="$(_run_select_app)"
      [ -z "$profile" ] && return 0
      _setup_service "$profile" ;;
    --stop)
      local profile="${1:-}"
      [ -z "$profile" ] && profile="$(_pick_profile "选择要停止的 profile")"
      [ -z "$profile" ] && return 0
      if [ -f "$(_service_file "$profile")" ]; then
        systemctl --user stop "${SERVICE_PREFIX}@${profile}" 2>/dev/null \
          && good "✅ ${profile} 已停止" || warn "⚠ ${profile} 停止失败" >&2
      else
        bad "  没有 ${profile} 的 service" >&2
      fi ;;
    --restart)
      local profile="${1:-}"
      [ -z "$profile" ] && profile="$(_pick_profile "选择要重启的 profile")"
      [ -z "$profile" ] && return 0
      if [ -f "$(_service_file "$profile")" ]; then
        systemctl --user restart "${SERVICE_PREFIX}@${profile}" 2>/dev/null \
          && good "✅ ${profile} 已重启" || warn "⚠ ${profile} 重启失败" >&2
      else
        warn "  没有 ${profile} 的 service，先用 --start 启动" >&2
      fi ;;
    --status)
      show_status ;;
    --logs|-l)
      show_logs "${1:-}" ;;
    --profile)
      local sub="${1:-}"; shift 2>/dev/null || true
      case "$sub" in
        list) profile_list ;;
        add)  profile_add ;;
        remove|rm) profile_remove ;;
        default|use) profile_default ;;
        *) echo "用法: $0 --profile {list|add|remove|default}"; exit 1 ;;
      esac ;;
    --help|-h|*)
      echo "用法: bash ccconfig/option-larkbridge/init.sh <command> [args]"
      echo ""
      echo "  运行:"
      echo "    --run [profile]        前台调试（不传交互选）"
      echo "    --start [profile]      后台 systemd（不传交互选）"
      echo ""
      echo "  管理:"
      echo "    --stop [profile]       停止 service"
      echo "    --restart [profile]    重启 service"
      echo "    --status               所有 profile + 状态"
      echo "    --logs [profile]       查看日志"
      echo ""
      echo "  Profile 管理:"
      echo "    --profile list         列表"
      echo "    --profile add          新增（ccprivate / 扫码）"
      echo "    --profile remove       删除"
      echo "    --profile default      设为默认"
      echo ""
      echo "  示例:"
      echo "    $0 --run               交互选 + 前台跑"
      echo "    $0 --run ailab         直接前台跑 ailab"
      echo "    $0 --start ailab       后台 ailab service"
      echo "    $0 --start             交互选 + 后台"
      echo "    $0 --status            看所有"
      ;;
  esac
}

main "$@"
