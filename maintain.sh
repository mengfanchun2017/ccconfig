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
source "$LIB_DIR/net.sh"
source "$LIB_DIR/git-pull.sh"
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
# 校验对象是三层合并后的预设全集（llmnormal + llmprivate + llm.json），
# 不是纯 key 文件 —— 内置预设的 key 未录入 llm.json 时它也不在，但预设本身有效。
check_llm_current() {
    local cur_file="$HOME/.claude/llm-current"
    local cur=""
    [[ -f "$cur_file" ]] && cur="$(tr -d '[:space:]' < "$cur_file")"
    local conf; conf="$(resolve_conf llm.json 2>/dev/null || true)"
    local normal_f="$SCRIPT_DIR/conf/llmnormal.json"
    local private_f="${CCPRIVATE_HOME:-$HOME/git/ccprivate}/conf/llmprivate.json"

    if [[ -z "$cur" ]]; then
        warn "LLM 当前选择未设置（$cur_file 缺失或为空）"
        info "  选一个: ./maintain.sh llm   （菜单 3A）"
        return 1
    fi
    if ! CUR="$cur" python3 - "$normal_f" "$private_f" "$conf" <<'PYEOF' 2>/dev/null
import json, sys
cur = __import__('os').environ['CUR']
names = set()
for f in sys.argv[1:]:
    if not f: continue
    try: names.update(json.load(open(f)).get('llms', {}).keys())
    except Exception: pass
sys.exit(0 if cur in names else 1)
PYEOF
    then
        warn "LLM 当前选择 '$cur' 不在任何预设定义里（预设可能已改名/删除）"
        info "  重选: ./maintain.sh llm   （菜单 3A）"
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

# 5G botmux 桥状态。吞掉 option 的三态退出码（OK=0/WARN=1/MISSING=2）——
# WARN 是「已装未配置/daemon 没跑」的正常表述，不是失败，不该让菜单报
# 「执行失败」（见 SH-MENU-CONVENTIONS 的 set -e 陷阱）。
do_botmux_status() {
    bash "$CCCONFIG_DIR/option-botmux/init.sh" --status || true
}

# 1C 高权限开启：claudeby 说明 + 本机 alias 状态检查。
# 不自动改用户文件 —— 打印该有的行，让用户自己加/更新（老版本手写在 bashrc 的旧定义尤其要手工换）。
do_highpriv() {
    local new_alias="alias claudeby='claude agents --dangerously-skip-permissions'"
    local new_alias_s="alias claudebys='claude --dangerously-skip-permissions'"
    local si="$HOME/.claude/shell_init.sh"
    local bc="$HOME/.bashrc"

    section "高权限启动（claudeby / claudebys）"
    echo -e "  ${CYAN}alias:${NC} $new_alias"
    echo -e "         $new_alias_s"
    echo -e "  ${GRAY}claudeby  → 直进 FleetView，bypassPermissions 作派发 session 默认模式${NC}"
    echo -e "  ${GRAY}claudebys → 就地起一个 bypassPermissions 会话（不经 FleetView）${NC}"
    echo -e "  ${GRAY}定义位置: ~/.claude/shell_init.sh（symlink → ccconfig/lib/shell_init.sh，随仓库自动更新）${NC}"
    echo ""

    if [[ -L "$si" && -e "$si" ]] && grep -qF "claude agents --dangerously-skip-permissions" "$si" 2>/dev/null; then
        ok "shell_init.sh 已是新版 claudeby"
    elif [[ -f "$si" ]] && grep -qF "alias claudeby=" "$si" 2>/dev/null; then
        warn "shell_init.sh 还是旧版 claudeby（claude --dangerously-skip-permissions）"
        info "  更新仓库: ./maintain.sh self config（3A），再 source ~/.bashrc"
    else
        warn "shell_init.sh 未定义 claudeby — 手动加一行: $new_alias"
    fi

    if [[ -f "$si" ]] && grep -qF "alias claudebys=" "$si" 2>/dev/null; then
        ok "shell_init.sh 已定义 claudebys"
    else
        warn "shell_init.sh 未定义 claudebys — 手动加一行: $new_alias_s"
    fi

    # bashrc 里手写的 claudeby 会盖住 shell_init 的定义（后加载者胜），老版本用户常有
    local legacy
    legacy="$(grep -n "^alias claudeby=" "$bc" 2>/dev/null || true)"
    if [[ -n "$legacy" ]]; then
        warn "~/.bashrc 有手写 claudeby，会覆盖新定义（第 ${legacy%%:*} 行）:"
        echo -e "      ${GRAY}$legacy${NC}"
        info "  改成: $new_alias"
    fi

    if ! grep -q "shell_init" "$bc" 2>/dev/null; then
        warn "~/.bashrc 未加载 shell_init.sh — 手动添加: source ~/.claude/shell_init.sh"
    fi

    # 运行时检查：文件对 ≠ 生效。alias 只在 shell 启动时装载，老 shell 里 claudeby 展开仍是旧命令。
    # 判据看进程 argv（不看 ps 显示，xxd /proc/pid/cmdline 才是真相）：新式必含 `agents` 子命令。
    local old_procs new_procs
    old_procs="$(ps -eo pid=,args= | grep -E '[c]laude --dangerously-skip-permissions' | grep -v ' claude agents ' || true)"
    new_procs="$(ps -eo pid=,args= | grep -E '[c]laude agents --dangerously-skip-permissions' || true)"
    echo ""
    if [[ -n "$old_procs" ]]; then
        warn "以下 claude 进程是旧式启动（argv 无 agents 子命令）— 它派发的新 session 不继承 bypass:"
        echo "$old_procs" | awk '{printf "      PID %s\n", $1}'
        info "  修复: 退出这些 session → 所在终端 source ~/.bashrc → 重新 claudeby"
        info "  为何: alias 改动后老 shell 不自动重载（启动时装载），文件绿但 shell 内存是旧的"
    fi
    if [[ -n "$new_procs" ]]; then
        ok "新式 claude agents 进程: $(echo "$new_procs" | wc -l | tr -d ' ') 个"
    fi
    if [[ -z "$old_procs" && -z "$new_procs" ]]; then
        info "当前无运行中的 claude 进程（下次 claudeby 前先 source ~/.bashrc）"
    fi

    echo ""
    echo -e "  ${YELLOW}提示: 改完 source ~/.bashrc 或开新终端生效 — 老 shell 不会自动重载 alias${NC}"
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

    # 顺序要紧：必须先升级 ccprivate 结构，再跑 setup.sh（setup.sh 本身来自
    # templates/ccprivate-setup.sh，由本步 cp 刷新）。
    # 本机文件模板唯一真相源是 ccconfig/templates/*.example，setup.sh 直接从那里取；
    # 此前 link/*.example 是独立副本，两边会漂移（status 用新模板报缺键、setup 用旧
    # 模板补不上），2026-10-27 已删副本，这个失配面随之消失。
    section "1. ccprivate 结构与模板刷新（前置）"
    _fix_step "ccprivate 结构升级" bash "$LIB_DIR/ccprivate-upgrade.sh" --yes

    section "2. 符号链接 + 缺失目录"
    local ccprivate_setup="$ccpriv/setup.sh"
    if [[ -x "$ccprivate_setup" ]]; then
        _fix_step "重建 ~/.claude 符号链接" bash "$ccprivate_setup"
    else
        _fix_step "重建公开符号链接（ccprivate/setup.sh 不可用）" bash "$LIB_DIR/setup-links.sh"
    fi

    local expected_dirs=("skill" "rules" "agents" "commands" "bin")
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
    # 本机配置模板水位：把 ~/.claude 三件套补到当前模板（只补缺键，不覆盖已有），
    # 并刷新 ~/.claude/.ccconfig-init 代次。此前只有跑 setup.sh 才补，fix 不管。
    if [ -x "${CCPRIVATE_HOME:-$HOME/git/ccprivate}/setup.sh" ]; then
        _fix_step "本机配置补到当前模板（settings/.config/.claudeignore）" \
            bash "${CCPRIVATE_HOME:-$HOME/git/ccprivate}/setup.sh"
    fi

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

    section "7. bridge 守护与运行态一致性"
    # ① 先把守护服务装上/启用（老用户 git pull 后跑到这里即完成迁移）。
    #    此前 bridge 只有 setsid 孤儿 watchdog 守护，重启后与 bridge 同死，留下自愈空窗。
    # ② 再做运行态一致性检查（孤儿 bridge / 该起没起 / 无守护），--fix 直接修。
    # 顺序要紧：先装服务再检查，否则 checker 会把"没有守护"当成待修问题，
    # 而它自己的修复手段（起 shell watchdog）在新体系下不该再被使用。
    if bash "$LIB_DIR/bridge-service.sh" sync &>/dev/null; then
        ok "bridge 守护服务已启用（systemd user）"
    else
        info "  bridge 守护服务不可用（systemd 缺失），回退 shell watchdog"
    fi

    local _mcfg="$HOME/.cache/llm-merged.json"
    [[ -f "$_mcfg" ]] || bash "$LIB_DIR/init-llm.sh" merge >/dev/null 2>&1 || true
    if [[ -f "$_mcfg" ]]; then
        source "$LIB_DIR/ensure-bridge.sh"
        bridge_state_check --fix "$_mcfg" && ok "bridge 与当前 preset 一致"
    else
        info "  无 merged 缓存，跳过"
    fi

    # tailscale accept-routes 防护：tailnet 上若有节点广告单位内网段，本机开着
    # accept-routes 会把去网关的流量拐进隧道 → 静默超时（ADR 0051）。老用户 git pull
    # 后跑到这里即完成迁移；只对"内网型 upstream"生效，公网/tailnet 端点跳过。
    source "$LIB_DIR/tailscale-guard.sh"
    local _ts_url="" _ts_hh=""
    if [[ -f "$HOME/.claude/llm-current" && -f "$_mcfg" ]]; then
        IFS=$'\t' read -r _ts_url _ts_hh < <(python3 -c "
import json
try:
    d=json.load(open('$_mcfg')); p=open('$HOME/.claude/llm-current').read().strip()
    l=d.get('llms',{}).get(p,{})
    print((l.get('base_url','') or '')+'\t'+(l.get('host_header','') or ''))
except Exception: print('\t')
")
        if [[ -n "$_ts_url" ]] && _upstream_is_private_intranet "$_ts_url" "$_ts_hh"; then
            tailscale_guard_intranet_upstream "$_ts_url" "$_ts_hh" && ok "tailscale 防护已就绪" || true
        else
            info "  tailscale 防护：当前 upstream 非内网型，跳过"
        fi
    fi

    section "8. auto-sync 与运行依赖"
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

    # uv 镜像：deps-check 只看 uv 二进制在不在，不看 PyPI 装包快不快。直连 pypi
    # 掉速会让 uvx 拉 MCP（mineru ~110MB）超过 Claude Code 的 30s 连接超时，
    # MCP 面板恒显 ✘ —— 光有 uv 救不了。这里显式跑一次（幂等：已有 [[index]] 则跳过）。
    source "$LIB_DIR/ensure-uv.sh"
    _fix_step "uv 镜像（PyPI 下载提速）" ensure_uv

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

    # 未自动修项：fix 链修不了的、需要用户决策的，在这里点出。
    # 否则 status 复查又报一遍，用户还得回头翻命令。
    section "未自动修项（需你决策）"
    local _manual=0
    # PAT：失效要重新登录，必须本人给 token（或走 gh 交互）
    if ! gh auth status &>/dev/null 2>&1; then
        warn "GitHub PAT 未登录/失效 → ./maintain.sh pat"
        _manual=$((_manual + 1))
    fi
    # getnote CLI 授权检查：未装/未授权列入需决策项（OAuth 必须本人在浏览器确认）
    if command -v getnote >/dev/null 2>&1; then
        if ! getnote auth status 2>/dev/null | grep -q "Authenticated"; then
            warn "getnote CLI 未授权 → bash ccconfig/option-getnote/init.sh auth"
            _manual=$((_manual + 1))
        fi
    else
        warn "getnote CLI 未安装 → bash ccconfig/option-getnote/init.sh install"
        _manual=$((_manual + 1))
    fi
    # 各 git 仓库 memory/CLAUDE.md 断链：ccprivate/setup.sh 只管 ccconfig 自己
    local _git_dir
    for _git_dir in "$HOME/git"/*/; do
        [ -d "${_git_dir}.git" ] || continue
        local _name=$(basename "$_git_dir")
        [ "$_name" = "ccprivate" ] && continue
        if { [ -L "${_git_dir}CLAUDE.md" ] && [ ! -e "${_git_dir}CLAUDE.md" ]; }; then
            warn "$_name: CLAUDE.md 断链（手动: 重跑该仓库的 setup 或重建链接）"
            _manual=$((_manual + 1))
        fi
        local _rel="${_git_dir#/}"; _rel="${_rel%/}"
        local _mem="$HOME/.claude/projects/-${_rel//\//-}/memory"
        if [ -L "$_mem" ] && [ ! -d "$_mem" ]; then
            warn "$_name: memory 断链（手动: 重建 ~/.claude/projects/-${_rel//\//-}/memory）"
            _manual=$((_manual + 1))
        fi
    done
    if [ "$_manual" -eq 0 ]; then
        info "无需手动项，全部干净"
    fi
    echo ""

    # 内存/软链改动要新开会话才生效，漏了这句用户会以为没生效
    echo -e "  ${YELLOW}提示: 链接与 memory 修复后需重启 Claude session 才生效${NC}"
    echo ""

    [[ "$_fix_failed" -eq 0 ]]
}

# 拉取一个配置仓库（ccconfig / ccprivate / skill），stderr 透明，失败给真实原因。
# 3A 包办 3 个配置仓库的拉取（原 3C 并入）；sync.sh 保留供单独命令行调用。
# 底层走单点实现 lib/git-pull.sh（代理注入/剥死代理 + 分支自适应 + 冲突回滚）。
pull_config_repo() {
    local dir="$1" name="$2"
    local _branch
    _branch=$(git -C "$dir" branch --show-current 2>/dev/null) || _branch=main
    echo -e "${CYAN}── $name 更新 ──${NC}"
    local _cur _after _rc=0
    _cur=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    git_pull_repo "$dir" --ff-only 2>&1 || _rc=$?
    if [ "$_rc" -eq 0 ]; then
        _after=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
        [ "$_cur" != "$_after" ] && ok "$name: $_cur → $_after" || ok "$name 已是最新: $_cur"
    else
        warn "$name 拉取失败（上方红字为真实原因；本地脏/分叉先处理）"
        # 分叉（本地有独有提交/改动）时给出可执行处理：读仓库不改则重置，改了则保留并 rebase
        echo -e "  ${DIM}处理：本地没要保留的改动 → ${NC}git -C $dir reset --hard origin/$_branch"
        echo -e "  ${DIM}本地有改动/提交要保留 → ${NC}git -C $dir stash && git -C $dir rebase origin/$_branch"
        return 1
    fi
}

do_self() {
    local target="${1:-all}"
    case "$target" in
        config)
            # 分区 1：仓库更新 + 本机链接。do_self cc 内含 setup.sh（符号链接/用户级/记忆/
            # 运行时 + 技能 link-only），ccprivate 先拉最新再做结构检查（避免旧副本误报缺目录）。
            # 分区 2：技能工具同步（sync-lite）—— setup.sh 已做过技能 symlink，这里只补
            # CLI 依赖 + ccprivate 配置覆盖 + lark-cli，不重复扫描技能。
            echo -e "${CYAN}━━ 配置仓库更新（ccconfig / ccprivate / skill）━━${NC}"
            echo ""
            do_self cc || true
            echo ""
            # 用 $CCPRIVATE_HOME（path-helper 已 export）而非硬编码 —— 与本文件其余
            # 5 处及 path-helper 的 resolve_conf 保持同一口径；自定义路径时才不会拉错目录
            pull_config_repo "${CCPRIVATE_HOME:-$HOME/git/ccprivate}" "ccprivate" || true
            echo ""
            bash "$LIB_DIR/ccprivate-upgrade.sh" --yes || warn "ccprivate 结构检查异常，继续"
            echo ""
            pull_config_repo "$HOME/git/skill" "skill" || true
            echo ""
            echo -e "${CYAN}━━ 技能工具同步（CLI 依赖 + 配置覆盖 + lark-cli）━━${NC}"
            echo ""
            bash "$LIB_DIR/init-skill.sh" sync-lite
            echo ""
            # bridge 守护服务：ccconfig 拉到新版后，老机器需要补装这个 systemd 服务
            # （bridge 此前只有 setsid 孤儿 watchdog，重启后与 bridge 同死）。
            # 幂等：已装且内容一致时不重写 unit、不弹 sudo。
            bash "$LIB_DIR/bridge-service.sh" sync &>/dev/null \
                && ok "bridge 守护服务已就绪" \
                || warn "bridge 守护服务未启用（systemd 不可用，回退 shell watchdog）"
            ;;
        cc|ccconfig)
            pull_config_repo "$SCRIPT_DIR" "ccconfig"
            echo ""
            # 链接统一由 ccprivate/setup.sh 承担（内含 setup-links.sh + 私有链接 + 技能 link-only），
            # 不再单独调 setup-links.sh，避免公开链接建两遍。ccprivate 缺失时 fallback 到公开链接。
            local _mccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
            if [ -x "$_mccpriv/setup.sh" ]; then
                # 不吞 stderr：setup.sh 里的 warn（如 lark 目标缺失）要透传给用户，
                # 而非静默。setup.sh 无「memory 是否真修」的返回码区分，只报完成。
                bash "$_mccpriv/setup.sh" && ok "ccprivate setup 完成（memory 等符号链接已核对）" || warn "ccprivate setup 部分失败"
            else
                bash "$LIB_DIR/setup-links.sh"
            fi
            echo -e "  ${YELLOW}提示: memory symlink 新建后需重启 Claude session 才生效（Claude 仅启动时加载 memory 索引）${NC}"
            ;;
        skill)
            echo -e "${CYAN}── Skill 同步 ──${NC}"
            bash "$LIB_DIR/init-skill.sh" sync ;;
        all|"")
            do_self cc
            echo ""
            do_self skill ;;
        *) err "未知 self 目标: $target（可用: config, cc, skill, all）"; return 1 ;;
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

    # systemd 托管：手动 stop+start 失效（systemd Restart=always 拉起 +
    # start_watch 看 /run PIDFile 已活 → Already running → 不启动 inotify）。
    # 必须走 systemctl restart 让 systemd 拉一个全新的 monitor loop。
    if [ -f /run/claude-auto-sync/monitor.pid ] \
        && kill -0 "$(cat /run/claude-auto-sync/monitor.pid)" 2>/dev/null; then
        info "auto-sync 由 systemd 托管 → systemctl restart"
        if sudo systemctl restart claude-auto-sync; then
            ok "systemd service 已重启"
        else
            err "sudo 失败（无密码/权限不足），手动:"
            echo -e "  ${GRAY}sudo systemctl restart claude-auto-sync${NC}"
        fi
        bash "$LIB_DIR/monitor.sh" status
        return 0
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
    highpriv) do_highpriv ;;
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
    botmux)  shift; bash "$CCCONFIG_DIR/option-botmux/init.sh" "$@" ;;
    pat|pat-refresh|gh-auth)
        bash "$CCCONFIG_DIR/bin/refresh-gh-auth.sh" ;;
    example)
        shift; bash "$LIB_DIR/example-sync.sh" "$@" ;;
    upgrade-ccprivate|upgrade-ccpriv|ccpriv-upgrade)
        shift; bash "$LIB_DIR/ccprivate-upgrade.sh" "$@" ;;
    *)
        # 交互菜单编号也能命令行直调: ./maintain 2e / 1A / t / s —— 复用 menu_parse
        # 此前任何非子命令输入都落进 *) 只打印 usage 就 exit，动作静默不执行，
        # 表现为「选了没反应」。menu_parse 返回 0=已执行/1=刷新/2=退出，3=无效。
        _rc=0
        menu_parse "${1:-}" || _rc=$?
        if [[ $_rc -eq 3 ]]; then
            echo "用法: bash maintain.sh [status|self|setup|upgrade|sync|monitor|deps|llm|mcp|botmux|pat|example|upgrade-ccprivate|highpriv]"
            echo "      或菜单编号（如 2e）直接执行对应项"
            exit 1
        fi
        exit 0 ;;  esac
fi
