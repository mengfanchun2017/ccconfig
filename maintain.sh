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

# 恢复链的步骤执行器：失败只记账、不中断
# 一键恢复不该因为某一步坏掉就半途而废 —— 剩下的步骤照样修，最后统一报账
_fix_failed=0
_fix_step() {
    local desc="$1"; shift
    echo -e "  ${GRAY}→ $desc${NC}"
    local rc=0
    "$@" || rc=$?
    if [[ $rc -eq 0 ]]; then
        ok "$desc"
    else
        warn "$desc 失败（继续后续步骤）"
        _fix_failed=$((_fix_failed + 1))
    fi
    echo ""
}

# 本机当前 LLM 选择是否可用。
# 这条此前**完全无人检查**：status.sh 不查、init-llm show_status 只打印不校验、
# ensure-bridge 读到空 llm-current 直接 return 0。结果是 llm-current 缺失/指向已删预设时，
# 一切看起来正常，直到会话起不来。这里只报不修 —— 换 preset 要走探测，不能替用户瞎选。
check_llm_current() {
    local cur_file="$HOME/.claude/llm-current"
    local cur=""
    [[ -f "$cur_file" ]] && cur="$(tr -d '[:space:]' < "$cur_file")"
    local conf; conf="$(resolve_conf llm.json 2>/dev/null || true)"

    if [[ -z "$cur" ]]; then
        warn "LLM 当前选择未设置（$cur_file 缺失或为空）"
        info "  选一个: ./maintain.sh llm   （菜单 4A）"
        return 1
    fi
    if [[ -n "$conf" ]] && ! python3 -c "
import json,sys
sys.exit(0 if '$cur' in json.load(open('$conf')).get('llms', {}) else 1)
" 2>/dev/null; then
        warn "LLM 当前选择 '$cur' 不在 llm.json 预设里（预设可能已改名/删除）"
        info "  重选: ./maintain.sh llm   （菜单 4A）"
        return 1
    fi
    ok "LLM 当前选择: $cur"
}

# 依赖：装上 auto-sync 必须要的 inotify，其余缺失只报不装
# （node/python/gh 等由 init-ubuntu.sh 负责，那是全机引导，不该塞进一键恢复）
ensure_runtime_deps() {
    source "$LIB_DIR/install-inotify.sh"
    install_inotify || warn "inotify-tools 装不上 — 手动: sudo apt install inotify-tools"

    if ! bash "$LIB_DIR/deps-check.sh" --required >/dev/null 2>&1; then
        warn "核心依赖有缺失 — 跑: bash init-ubuntu.sh"
    fi
    return 0
}

do_setup() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ccconfig 恢复最新功能 ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GRAY}git pull 到新版本后跑这个：把新版本带来的设定一次启用${NC}"
    echo -e "  ${GRAY}结构 → 链接 → 模板 → MCP → Skill → settings → LLM → 服务${NC}"
    echo ""

    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
    _fix_failed=0

    # 顺序要紧：必须先升级 ccprivate 结构与模板，再跑 setup.sh。
    # setup.sh 补 settings 缺键用的是 ccprivate/link/settings.json.example，
    # 那份模板只有 ccprivate-upgrade 会刷新 —— 反过来的话，status 用新模板
    # 报缺键、setup 用旧模板补不上，键看着"修了"其实没进来。
    section "1. ccprivate 结构与模板刷新（前置）"
    _fix_step "ccprivate 结构升级" bash "$LIB_DIR/ccprivate-upgrade.sh" --yes

    section "2. 符号链接 + 缺失目录"
    local ccprivate_setup="$ccpriv/setup.sh"
    if [[ -x "$ccprivate_setup" ]]; then
        _fix_step "重建 ~/.claude 符号链接" bash "$ccprivate_setup"
    else
        _fix_step "重建公开符号链接（ccprivate/setup.sh 不可用）" bash "$LIB_DIR/setup-links.sh"
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
    $created && ok "缺失 ccprivate 目录已补齐"

    section "3. 新配置模板跟进（conf/ + agents/）"
    _fix_step "把新模板复制到 ccprivate" bash "$LIB_DIR/example-sync.sh" sync

    section "4. MCP 注册 + Skill 同步"
    _fix_step "MCP 注册缺失项 + 同步 settings" bash "$LIB_DIR/init-mcp.sh" sync
    _fix_step "Skill 全量同步（链接 + CLI 依赖）" bash "$LIB_DIR/init-skill.sh" sync

    section "5. settings 键归位（.config.json → settings.json）"
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
# 这里**故意不碰** mcpServers / disabledMcpServers / projects：
# 它们是 MCP 模块的地盘，`maintain.sh mcp sync`（菜单 6D）会主动把它们同步进
# settings.json。归位步骤再去删就成了两个模块互拆台 —— 实测同一轮 fix 里
# 第 4 步刚写完、第 5 步就删掉，还打印一句吓人的"两份内容不同"。
# 归位只做真正有害的那个方向：settings 键被错放进 .config.json（那份完全不读）。

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

moved_to_settings, merged, discarded, overrode = [], [], [], []
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

changed = bool(moved_to_settings or merged or discarded or overrode)
if changed:
    save(sf, sd); save(cf, cd)
    if moved_to_settings:
        print(f"  ✅ 归位到 settings.json（原先在 .config.json 里不生效）: {', '.join(moved_to_settings)}")
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

    section "6. LLM 当前选择"
    check_llm_current || true

    section "7. auto-sync 与运行依赖"
    # 已在跑就别再 enable —— enable 会重装系统级 systemd unit（要 sudo）。
    # 一键恢复里弹 sudo 认证很烦，而且非 tty（CI/脚本）下必然失败报错。
    # 先取变量再比，不要写成 `... | grep -q`：grep -q 一匹配就关管道，
    # 写端拿到 EPIPE 退出 141，set -o pipefail 会把整个管道判成失败 →
    # 条件恒假（实测踩过，且失败得很安静）。
    local _mstat=""
    _mstat="$(bash "$LIB_DIR/monitor.sh" status 2>/dev/null || true)"
    if [[ "$_mstat" == *"Monitor loop (PID"* ]]; then
        ok "auto-sync 已在运行，跳过重装"
    else
        _fix_step "启动 auto-sync" bash "$LIB_DIR/init-autostart.sh" enable
    fi
    ensure_runtime_deps

    echo ""
    if [[ "$_fix_failed" -eq 0 ]]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  恢复完成，全部步骤成功 🎉${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}  恢复完成，但有 ${_fix_failed} 步失败（上面标 ⚠ 的）${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
    echo ""
    echo -e "  ${BOLD}接着做:${NC}"
    echo -e "  ${CYAN}./maintain.sh status${NC}   # 复查（1A）"
    echo -e "  ${CYAN}./maintain.sh${NC}          # 交互菜单"
    echo ""

    # 内存/软链改动要新开会话才生效，漏了这句用户会以为没生效
    echo -e "  ${YELLOW}提示: 链接与 memory 修复后需重启 Claude session 才生效${NC}"
    echo ""

    [[ "$_fix_failed" -eq 0 ]]
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
    example)
        shift; bash "$LIB_DIR/example-sync.sh" "$@" ;;
    upgrade-ccprivate|upgrade-ccpriv|ccpriv-upgrade)
        shift; bash "$LIB_DIR/ccprivate-upgrade.sh" "$@" ;;
    *)
        echo "用法: bash maintain.sh [status|self|setup|upgrade|sync|monitor|deps|llm|mcp|pat|token|example|upgrade-ccprivate]"
        exit 1 ;;  esac
fi
