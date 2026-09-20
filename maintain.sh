#!/bin/bash
# maintain.sh — ccconfig 运维入口（数据驱动菜单）
#
# 用法：
#   bash maintain.sh                  # 交互菜单
#   bash maintain.sh status           # 直接执行子命令
#   bash maintain.sh fix              # 一键修复
#
# 数据层: menu-data-maintain.sh
# 渲染/解析: interact.sh menu_loop
#

set -euo pipefail
# maintain.sh 在 ccconfig 根目录，SCRIPT_DIR 指向根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CCCONFIG_DIR="$SCRIPT_DIR"

source "$LIB_DIR/dry-run.sh"
source "$LIB_DIR/path-helper.sh" 2>/dev/null || true
# find_node_bin 四级回退都可能落空 → 原写法产生 "::" 空段，等于把当前目录塞进 PATH
_nb="$(find_node_bin 2>/dev/null || true)"
export PATH="$HOME/.local/bin${_nb:+:$_nb}:$PATH"
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/interact.sh"
source "$LIB_DIR/menu-data-maintain.sh"
source "$LIB_DIR/menu-feishu.sh"

# ========== 菜单动作 helper ==========
# 需要用户输一个参数的叶子动作（删预设、切账号）。不要为此再开一层菜单 ——
# 一级菜单已经扁平到字母项，再嵌套就又要"返回上层"了。

# ask_run "提示" <cmd...>      → 问一个值，作为**最后一个**参数追加执行
# ask_run_p "提示" <cmd...>    → 同上，但值后面再跟 -p（切换并持久化）
ask_run() {
    local hint="$1"; shift
    local v; v=$(prompt "$hint")
    [[ -n "$v" ]] || { info "已取消"; return 0; }
    bash "$@" "$v"
}

ask_run_p() {
    local hint="$1"; shift
    local v; v=$(prompt "$hint")
    [[ -n "$v" ]] || { info "已取消"; return 0; }
    bash "$@" "$v" -p
}

# ========== 主动能 ==========

do_setup() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ccconfig 一键修复 — 符号链接 + 缺失目录 + auto-sync ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    section "1. 修复符号链接"
    local ccprivate_setup="$ccpriv/setup.sh"
    if [[ -x "$ccprivate_setup" ]]; then
        bash "$ccprivate_setup" 2>/dev/null && ok "符号链接已修复" || warn "符号链接部分失败"
    else
        bash "$LIB_DIR/setup-links.sh"
        info "ccprivate/setup.sh 不可用，仅修复了公开链接"
    fi

    local expected_dirs=("skill" "skill-local" "rules" "agents" "commands" "bin" "usage")
    local created=false
    for d in "${expected_dirs[@]}"; do
        if [[ ! -d "$ccpriv/$d" ]]; then
            mkdir -p "$ccpriv/$d"
            touch "$ccpriv/$d/.gitkeep"
            created=true
        fi
    done
    if $created; then
        ok "缺失 ccprivate 目录已补齐"
    fi

    section "2. 启动 auto-sync"
    if bash "$LIB_DIR/init-autostart.sh" enable; then
        ok "auto-sync 已启动"
    else
        warn "auto-sync 启动失败（可手动: bash $LIB_DIR/monitor.sh start）"
    fi

    section "3. 配置文件归位（settings.json vs .config.json）"
    python3 << 'PYEOF'
import json, os, sys

# 两个文件在 Claude Code 里角色完全不同：
#   ~/.claude/settings.json —— 唯一的用户级【settings 文件】。permissions/
#     hooks/statusLine/model/... 只有放这里才生效。
#   ~/.claude/.config.json —— 全局配置 / 应用状态（官方文档称 ~/.claude.json），
#     存 user scope 的 mcpServers + Claude Code 自己维护的 projects/信任决策/
#     OAuth 会话等。settings 类键写在这里【完全不读】，且静默失效无报错。
# 早期版本把 permissions/hooks/statusLine 放进了 .config.json（方向反了），
# 后果是权限白名单与 WebSearch deny 一直没生效。这里做归位。
sf = os.path.expanduser("~/.claude/settings.json")
cf = os.path.expanduser("~/.claude/.config.json")

SETTINGS_FILE_KEYS = {"permissions", "model", "skillOverrides", "statusLine",
                      "enabledPlugins", "extraKnownMarketplaces", "effortLevel",
                      "autoUpdatesChannel", "skipDangerousModePermissionPrompt",
                      "skipWorkflowUsageWarning", "tui", "hooks", "theme", "verbose"}
GLOBAL_CONFIG_KEYS = {"mcpServers", "disabledMcpServers", "projects"}

def load(p):
    try:
        with open(p) as f: return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None

sd = load(sf)
if sd is None:
    print("  （无 settings.json，跳过）")
    sys.exit(0)
cd = load(cf) or {}

def save(p, d):
    with open(p, "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")

def merge_permissions(a, b):
    """permissions 特判：allow/ask/deny 求并集，标量（defaultMode）以 settings 为准。
    只在 permissions 上做合并 —— 通用深合并会把 hooks 这种
    dict→list→dict 的结构炸掉，也可能把过期条目复活。"""
    out = dict(b)
    out.update(a)
    for key in ("allow", "ask", "deny"):
        la, lb = a.get(key) or [], b.get(key) or []
        if la or lb:
            out[key] = sorted(set(map(str, lb)) | set(map(str, la)))
    return out

moved_to_settings, moved_to_global, merged, discarded, overrode = [], [], [], [], []
for k in SETTINGS_FILE_KEYS:
    if k not in cd:
        continue
    if k not in sd:
        sd[k] = cd.pop(k)
        moved_to_settings.append(k)
        continue
    if k == "permissions" and isinstance(sd[k], dict) and isinstance(cd[k], dict):
        before = sd[k]
        sd[k] = merge_permissions(sd[k], cd.pop(k))
        (merged if sd[k] != before else discarded).append(k)
    elif sd[k] == cd[k]:
        cd.pop(k)
        discarded.append(k)
    else:
        # settings.json 才是生效的那份，但两份内容不同 —— 删掉的副本要报出来
        cd.pop(k)
        overrode.append(k)

for k in GLOBAL_CONFIG_KEYS:
    if k not in sd:
        continue
    if k not in cd:
        cd[k] = sd.pop(k)
        moved_to_global.append(k)
    else:
        sd.pop(k)
        (discarded if sd.get(k) == cd.get(k) else overrode).append(k)

changed = bool(moved_to_settings or moved_to_global or merged or discarded or overrode)
if changed:
    save(sf, sd); save(cf, cd)
    if moved_to_settings:
        print(f"  ✅ 归位到 settings.json（原先在 .config.json 里不生效）: {', '.join(moved_to_settings)}")
    if moved_to_global:
        print(f"  ✅ 归位到 .config.json（settings.json 不读这个键）: {', '.join(moved_to_global)}")
    if merged:
        print(f"  ✅ 合并两份（allow/deny 取并集，标量以 settings.json 为准）: {', '.join(merged)}")
    if discarded:
        print(f"  ✅ 删除完全重复的副本: {', '.join(discarded)}")
    if overrode:
        print(f"  ⚠️  两份内容不同，以 settings.json 为准并删除 .config.json 副本: {', '.join(overrode)}")
        print("      如需保留被删的那份，改动前可从 ~/.claude/backups/ 找回")
else:
    print("  ✓ 两个文件的内容与各自角色相符，无需归位")

# 提示：settings.json 里出现的、Claude Code 只认全局配置的键
GLOBAL_ONLY = {"autoConnectIde", "autoInstallIdeExtension", "copyOnSelect",
               "diffTool", "externalEditorContext"}
wrong = sorted(k for k in sd if k in GLOBAL_ONLY)
if wrong:
    print(f"  ⚠️  {', '.join(wrong)} 只能放在 .config.json，在 settings.json 里无效")
PYEOF

    section "4. 状态总览"

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ccconfig 就绪 🎉${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}日常命令:${NC}"
    echo ""
    echo -e "  ${CYAN}bash maintain.sh${NC}             # 交互菜单（推荐）"
    echo -e "  ${CYAN}bash maintain.sh status --quick${NC}  # 快速状态"
    echo -e "  ${CYAN}bash maintain.sh status${NC}         # 全量状态"
    echo -e "  ${CYAN}bash maintain.sh self all${NC}       # 更新 ccconfig + skill"
    echo -e "  ${CYAN}bash maintain.sh upgrade all${NC}     # 升级系统组件"
    echo ""
}

do_self() {
    local target="${1:-all}"
    case "$target" in
        cc|ccconfig)
            echo -e "${CYAN}── ccconfig 更新 ──${NC}"
            if ! git -C "$SCRIPT_DIR" fetch origin main 2>/dev/null; then
                warn "无法连接远程（网络不通），跳过自更新"
                return 1
            fi
            local local_commit=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null)
            git -C "$SCRIPT_DIR" pull --ff-only origin main 2>/dev/null && {
                local after=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
                [ "$local_commit" != "$after" ] && ok "ccconfig: $local_commit → $after" || ok "ccconfig 已是最新: $local_commit"
            } || { warn "ccconfig 拉取失败（有本地改动？）"; return 1; }
            echo ""
            bash "$LIB_DIR/setup-links.sh"
            # 修复项目级 memory symlink（真实目录→symlink）
            local _mccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
            if [ -x "$_mccpriv/setup.sh" ]; then
                bash "$_mccpriv/setup.sh" 2>/dev/null && ok "memory symlink 已修复" || warn "memory symlink 部分失败"
            fi
            echo -e "  ${YELLOW}提示: memory symlink 修复后需重启 Claude session 才生效（Claude 仅启动时加载 memory 索引）${NC}"
            ;;
        skill)
            echo -e "${CYAN}── Skill 同步 ──${NC}"
            bash "$LIB_DIR/init-skill.sh" sync ;;
        all|"")
            do_self cc
            echo ""
            do_self skill ;;
        *) err "未知 self 目标: $target（可用: cc, skill, all）"; return 1 ;;
    esac
}

fix_monitor() {
    echo -e "${CYAN}━━━ Monitor 修复（inotify-tools + 重启）━━━${NC}"
    echo ""

    source "$LIB_DIR/install-inotify.sh"
    if ! install_inotify; then
        err "inotify-tools 装不上 — 手动: sudo apt install inotify-tools"
        return 1
    fi

    if bash "$LIB_DIR/monitor.sh" stop 2>/dev/null; then
        info "旧 monitor 已停止"
    fi
    pkill -f "inotifywait.*$HOME/git" 2>/dev/null || true

    if bash "$LIB_DIR/monitor.sh" start; then
        echo ""
        ok "Monitor 已修复并重启"
        bash "$LIB_DIR/monitor.sh" status
    else
        err "Monitor 启动失败"
        return 1
    fi
}

# ========== 入口 ==========

# BASH_SOURCE 守卫：被 source 时不执行入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # 测试模式兼容：MAINTAIN_TEST_MODE=1 source 时跳过，但 bash 执行时不受影响
  [[ "${MAINTAIN_TEST_MODE:-0}" == "1" ]] && exit 0
  case "${1:-menu}" in
    menu|"")
        menu_loop "ccconfig 运维中心"
        ;;
    status)  shift; bash "$LIB_DIR/status.sh" "$@" ;;
    self)    shift; do_self "${1:-all}" ;;
    setup|finalize|first|init|fix)
        shift
        case "${1:-all}" in
            monitor) fix_monitor ;;
            all|"")  do_setup ;;
            *)       err "未知 fix 子命令: $1"; exit 1 ;;
        esac ;;
    upgrade) shift; bash "$LIB_DIR/update.sh" "$@" ;;
    sync)    shift; bash "$LIB_DIR/sync.sh" "$@" ;;
    monitor) shift; bash "$LIB_DIR/monitor.sh" "${1:-}" ;;
    deps)    bash "$LIB_DIR/deps-check.sh" ;;
    llm)     shift; bash "$LIB_DIR/init-llm.sh" "$@" ;;
    mcp)     shift; bash "$LIB_DIR/mcp-manager.sh" "$@" ;;
    pat|pat-refresh|gh-auth)
        bash "$CCCONFIG_DIR/bin/refresh-gh-auth.sh" ;;
    token|usage)
        shift; bash "$CCCONFIG_DIR/option-usage/token-usage.sh" "$@" ;;
    feishu)
        ccbridge_test="${CCBRIDGE_HOME:-$HOME/git/ccbridge}/tests/test-feishu.sh"
        if [ -f "$ccbridge_test" ]; then
            bash "$ccbridge_test" "$@"
        else
            info "ccbridge 未安装，测试跳过"
        fi ;;
    example)
        shift; bash "$LIB_DIR/example-sync.sh" "$@" ;;
    upgrade-ccprivate|upgrade-ccpriv|ccpriv-upgrade)
        shift; bash "$LIB_DIR/ccprivate-upgrade.sh" "$@" ;;
    *)
        echo "用法: bash maintain.sh [status|self|setup|upgrade|sync|monitor|deps|llm|mcp|pat|token|feishu|example|upgrade-ccprivate]"
        exit 1 ;;  esac
fi
