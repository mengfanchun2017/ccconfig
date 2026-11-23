#!/bin/bash
# lib/git-auth.sh — GitHub 认证管理（GCM + PAT 双模式）
#
# 两种认证方式：
#   1. Windows GCM（推荐）: WSL 通过 interop 借用 Windows Git Credential Manager
#      密钥存在 Windows 凭据管理器（DPAPI 加密），WSL 磁盘零密钥
#   2. GitHub PAT: 传统 gh auth login，token 存在 ~/.config/gh/hosts.yml
#
# 用法：
#   bash lib/git-auth.sh               # 交互菜单
#   bash lib/git-auth.sh status         # 只读状态
#   bash lib/git-auth.sh gcm            # 配置 GCM（已配则报告，未配则引导）
#   bash lib/git-auth.sh pat            # 配置 PAT（已配则报告，未配则引导配置）
#   bash lib/git-auth.sh verify         # 远端连通性验证
#   bash lib/git-auth.sh check          # 非交互检查（返回 0=任一方式可用）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/interact.sh"

# 暂停让用户看清输出（菜单风格的"按回车继续"）
_pause_continue() {
    echo ""
    printf "  按回车继续..."
    read -r dummy < /dev/tty 2>/dev/null || true
    echo ""
}

# ── 路径脱敏 ──
# 公开仓库的输出不应带 Windows 用户名（/mnt/c/Users/<用户名>/...）。
# 只把用户名段换成 <user>，其余原样，便于排查。
_redact_user() {
    printf '%s' "$1" | sed -E 's#/mnt/c/Users/[^/]+#/mnt/c/Users/<user>#'
}

# ── 路径工具 ──
# Windows 绝对路径 → WSL /mnt/c/... 形式
_win_to_wsl() {
    local p="${1//\\//}"
    if [[ "$p" =~ ^([A-Za-z]):/(.*) ]]; then
        echo "/mnt/${BASH_REMATCH[1],,}/${BASH_REMATCH[2]}"
    else
        echo "$p"
    fi
}

# 候选 exe 名（2.3.0 前旧别名 manager-core 也认，老机器可能还在用）
_GCM_EXES=(git-credential-manager.exe git-credential-manager-core.exe)

# 在候选目录里找第一个可达 exe
_find_gcm_in_dirs() {
    local dir exe
    for dir in "$@"; do
        [[ -n "$dir" && -d "$dir" ]] || continue
        for exe in "${_GCM_EXES[@]}"; do
            [[ -x "$dir/$exe" ]] && { echo "$dir/$exe"; return 0; }
        done
    done
    return 1
}

# 候选目录：MinGit / Git for Windows / GCM 独立包 / dotnet tools。
# 排除 Default/Public/All Users/Default User —— Windows 模板/公共目录，
# 凭据按当前 Windows 用户 DPAPI 存取，选错目录会取不到凭据。
_gcm_candidate_dirs() {
    local -a dirs=()
    local ud udn u
    for ud in /mnt/c/Users/*/; do
        udn=$(basename "$ud")
        case "$udn" in
            "Default"|"Default User"|"Public"|"All Users") continue ;;
        esac
        u="${ud%/}"
        dirs+=(
            "$u/AppData/Local/Programs/MinGit/ucrt64/bin"
            "$u/AppData/Local/Programs/MinGit/bin"
            "$u/AppData/Local/Programs/Git/ucrt64/bin"
            "$u/AppData/Local/Programs/Git/mingw64/bin"
            "$u/AppData/Local/Programs/Git/bin"
            "$u/AppData/Local/Programs/Git Credential Manager"
            "$u/AppData/Local/Programs/Git Credential Manager/bin"
            "$u/.dotnet/tools"
        )
    done
    dirs+=(
        "/mnt/c/Program Files/Git/ucrt64/bin"
        "/mnt/c/Program Files/Git/mingw64/bin"
        "/mnt/c/Program Files/Git/bin"
        "/mnt/c/Program Files (x86)/Git/ucrt64/bin"
        "/mnt/c/Program Files (x86)/Git/mingw64/bin"
        "/mnt/c/Program Files/Git Credential Manager"
        "/mnt/c/Program Files (x86)/Git Credential Manager"
    )
    printf '%s\n' "${dirs[@]}"
}

# ── 找 GCM 路径（快，纯文件系统，无子进程）──
# 优先级：现有 gitconfig → 文件系统候选
_find_gcm_path() {
    # 1. 从现有 gitconfig 提取 helper 中的路径
    local helpers
    helpers=$(git config --global --get-all "credential.https://github.com.helper" 2>/dev/null) || true
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # helper 值形如 !"/mnt/c/Program Files/.../gcm.exe"（带引号，路径含空格时必需）。
        # 先剥 ! 再剥引号；引号是 shell 语法的一部分，test -x 必须拿到裸路径。
        local p="${line#!}"
        p="${p#\"}"; p="${p%\"}"
        p="${p%\'}"; p="${p#\'}"
        [[ -x "$p" ]] && { echo "$p"; return 0; }
    done <<< "$helpers"

    # 2. 文件系统候选
    local -a dirs
    mapfile -t dirs < <(_gcm_candidate_dirs)
    local hit
    hit=$(_find_gcm_in_dirs "${dirs[@]}") && { echo "$hit"; return 0; }

    return 1
}

# ── 慢速兜底：问 Windows git / 注册表（有子进程，仅快探测落空时用）──
# 放在 status 之外：cmd.exe/powershell 启动 1-2s，会把菜单卡住。
_find_gcm_path_slow() {
    local raw ep hit root ps
    # ① Windows git --exec-path（cmd.exe interop；cwd 不能在 UNC，故 cd /mnt/c）
    raw=$(cd /mnt/c 2>/dev/null && timeout 8 cmd.exe /c "git --exec-path" 2>/dev/null | tr -d '\r') || true
    if [[ -n "$raw" ]]; then
        ep=$(_win_to_wsl "$raw")
        local -a cands=("$ep")
        [[ "$ep" == */libexec/git-core ]] && cands+=("${ep%/libexec/git-core}/bin")
        hit=$(_find_gcm_in_dirs "${cands[@]}") && { echo "$hit"; return 0; }
    fi
    # ② 注册表 GitForWindows InstallPath（HKLM → HKCU）
    for hive in HKLM HKCU; do
        ps="(Get-ItemProperty '${hive}:\SOFTWARE\GitForWindows' -ErrorAction SilentlyContinue).InstallPath"
        raw=$(cd /mnt/c 2>/dev/null && timeout 8 powershell.exe -NoProfile -NonInteractive \
            -Command "$ps" 2>/dev/null | tr -d '\r') || true
        [[ -n "$raw" ]] || continue
        root=$(_win_to_wsl "$raw")
        local -a cands=(
            "$root"
            "$root/ucrt64/bin" "$root/mingw64/bin" "$root/bin" "$root/libexec/git-core"
        )
        hit=$(_find_gcm_in_dirs "${cands[@]}") && { echo "$hit"; return 0; }
    done
    return 1
}

# ── GCM 状态（machine-readable）──
# 输出: ok|not_configured|bad_path
_gcm_status() {
    local gcm_path="${1:-}"
    local helpers
    helpers=$(git config --global --get-all "credential.https://github.com.helper" 2>/dev/null) || true
    # 过滤空行与 gh helper。gh auth setup-git 写的值是 `!gh auth git-credential`
    # （无 .exe 后缀），GCM 是 `!.../git-credential-manager.exe`，按可执行名区分。
    # 注意 `[[ ... ]] && continue` 在 set -e 下假值会中断函数 → 用 if 包裹。
    local gh_lines=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" == *"gh-auth"* || "$line" == *"gh.exe"* || "$line" == *"gh auth git-credential"* ]]; then
            continue
        fi
        gh_lines+=("$line")
    done <<< "$helpers"
    [[ ${#gh_lines[@]} -eq 0 ]] && { echo "not_configured"; return; }
    [[ -z "$gcm_path" ]] && { echo "bad_path"; return; }
    # 校验配置里的 helper 值是否真能解析到可达路径 —— 只看「配置非空」会把
    # 指向已卸载/改名 exe 的坏 helper 误报 ok（bad_path 此前不可达正是这个漏洞）
    local line p
    for line in "${gh_lines[@]}"; do
        p="${line#!}"; p="${p#\"}"; p="${p%\"}"; p="${p%\'}"; p="${p#\'}"
        [[ -x "$p" ]] && { echo "ok"; return; }
    done
    echo "bad_path"
}

# ── PAT 状态（machine-readable）──
# 输出: logged_in|not_logged_in
_pat_status() {
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        echo "logged_in"
    else
        echo "not_logged_in"
    fi
}

# ── 取 github.com 可用代理（复用 net.sh，单点真相源）──
# 返回代理 URL 或空。net_gh_proxy：env → 本机 Clash 7897/7890 探测。
_gh_proxy() {
    if [ -f "$SCRIPT_DIR/net.sh" ]; then
        source "$SCRIPT_DIR/net.sh" >/dev/null 2>&1 || true
        declare -F net_gh_proxy >/dev/null 2>&1 && { net_gh_proxy; return; }
    fi
    local p="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
    [ -n "$p" ] && { echo "$p"; return; }
    for q in 7897 7890; do
        timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/$q" 2>/dev/null && { echo "http://127.0.0.1:$q"; return; }
    done
    echo ""
}

# ── 测试远端连通性（返回 0=可达）──
_test_reachability() {
    # 直连。只看 http_code 不看退出码：github.com 直连慢（TLS 握手后大响应体）时
    # curl 会因 --max-time 返回 28，但 -w 已写出 200 —— 判退出码会误报不可达。
    local code
    code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 https://github.com 2>/dev/null || true)
    [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]] && return 0
    # 走代理（net.sh 探测结果）
    local proxy; proxy=$(_gh_proxy)
    [ -n "$proxy" ] || return 1
    code=$(curl -x "$proxy" -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 https://github.com 2>/dev/null || true)
    [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]] && { echo "$proxy"; return 0; }
    return 1
}

# ── 验证用仓库：优先当前仓库 origin（fork 友好），回落默认公开仓 ──
_verify_repo() {
    local root u=""
    root="$(dirname "$SCRIPT_DIR")"   # git-auth.sh 在 lib/ 下，仓库根是其父目录
    u=$(git -C "$root" remote get-url origin 2>/dev/null) || u=""
    if [ -n "$u" ]; then echo "$u"; return; fi
    echo "https://github.com/mengfanchun2017/ccconfig.git"
}

# ── git ls-remote 验证（返回 0=认证通过）──
_git_verify() {
    local proxy="${1:-}"
    local repo; repo=$(_verify_repo)
    local -a args=()
    [[ -n "$proxy" ]] && args=(-c "http.proxy=$proxy" -c "https.proxy=$proxy")
    local out rc=0
    out=$(timeout 40 git "${args[@]}" ls-remote "$repo" HEAD 2>&1) || rc=$?
    _GIT_VERIFY_OUT="$out"
    if [[ $rc -eq 0 && "$out" =~ ^[0-9a-f]{40} ]]; then
        echo "$out"
        return 0
    fi
    # 直连失败（被墙/慢）→ 用 net.sh 探测到的代理重试一次
    if [[ -z "$proxy" ]]; then
        local p2; p2=$(_gh_proxy)
        if [ -n "$p2" ]; then
            out=$(timeout 40 git -c "http.proxy=$p2" -c "https.proxy=$p2" \
                ls-remote "$repo" HEAD 2>&1) || rc=$?
            _GIT_VERIFY_OUT="$out"
            [[ $rc -eq 0 && "$out" =~ ^[0-9a-f]{40} ]] && { echo "$out"; return 0; }
        fi
    fi
    return 1
}

# ── 配置 GCM ──
_do_gcm_setup() {
    local gcm_path="$1"
    section "配置 Windows GCM"

    echo -e "  GCM 路径: ${CYAN}$(_redact_user "$gcm_path")${NC}"
    echo ""

    # 备份（.gitconfig 可能不存在；失败不阻断）
    local bak
    bak="$HOME/.gitconfig.bak.gitok-$(date +%Y%m%d%H%M%S)"
    if cp ~/.gitconfig "$bak" 2>/dev/null; then
        chmod 600 "$bak" 2>/dev/null || true
        echo -e "  ${GRAY}备份: ${bak/#$HOME/~}${NC}"
    else
        echo -e "  ${GRAY}无 ~/.gitconfig，跳过备份${NC}"
    fi
    echo ""

    # 写 helper。值必须是 !"<路径>" 带引号：git 对 ! helper 走 shell 执行，
    # 路径含空格（如 /mnt/c/Program Files/... 或用户名含空格）不引号会被拆词
    # 调空命令（实测 "fake: not found"）。find 时 _find_gcm_path 会剥引号还原。
    for h in github.com gist.github.com; do
        git config --global --unset-all "credential.https://$h.helper" 2>/dev/null || true
        git config --global --add "credential.https://$h.helper" "!\"$gcm_path\""
        echo -e "  ${GREEN}✓${NC} credential.https://$h.helper"
    done
    echo ""

    # 验证
    local proxy
    proxy=$(_test_reachability) || true
    local sha
    sha=$(_git_verify "$proxy") && {
        ok "GCM 验证通过（SHA: ${sha:0:12}...）"
        echo -e "  ${GRAY}密钥仅存 Windows 凭据管理器（DPAPI 加密），WSL 无明文${NC}"
        return 0
    } || {
        # 区分「没登录」与「网络问题」：前者是 GCM 里没凭据，后者是链路不通。
        if [[ "$_GIT_VERIFY_OUT" =~ (Authentication failed|could not read Username|401|Terminal prompts disabled|Bad credentials|not authorized) ]]; then
            warn "认证未通过 —— 很可能是 GCM 里还没登录 GitHub"
            echo -e "  ${GRAY}跑「登录 GitHub」（菜单第 2 项）或: bash lib/git-auth.sh login${NC}"
        else
            warn "远端验证未通过（可能是网络问题，非配置问题）"
            echo -e "  ${GRAY}确认代理/VPN 是否开启，然后重试 verify${NC}"
        fi
        return 1
    }
}

# ── 配置 PAT ──
_do_pat_setup() {
    section "配置 GitHub PAT"
    echo ""
    echo -e "  把 GitHub PAT 粘贴到下面（不回显）"
    echo -e "  获取 PAT: ${CYAN}https://github.com/settings/tokens${NC}"
    echo ""

    local new_token
    new_token=$(prompt_password "PAT（直接回车=取消）")
    [[ -z "$new_token" ]] && { info "已取消"; return 1; }

    echo ""
    echo -e "  ${GRAY}配置 gh auth...${NC}"
    if ! echo "$new_token" | gh auth login --with-token --hostname github.com >/dev/null 2>&1; then
        err "gh auth login 失败 — PAT 可能无效"
        return 1
    fi
    ok "gh auth login 成功"

    gh auth setup-git >/dev/null 2>&1 || true
    ok "git credential helper 已配置"

    # 验证
    local user
    user=$(gh api user --jq '.login' 2>/dev/null) || { err "验证失败"; return 1; }
    ok "验证通过 ($user)"

    rm -f "$HOME/.local/share/ccconfig/pat-warn" "$HOME/.local/share/ccconfig/pat-status"
}

# ── 触发 GCM 登录（浏览器/设备码）──
# 用 GCM 的 get 触发一次交互：没凭据时它会弹浏览器/设备码。
# 只读 username 行，password 不落盘、不回显。
_do_login() {
    local gcm_path="$1" host="${2:-github.com}"
    section "登录 $host（GCM）"
    echo -e "  ${GRAY}GCM 会打开浏览器（或给设备码），完成即存入 Windows 凭据管理器${NC}"
    echo -e "  ${GRAY}密钥不经过本脚本、不落 WSL 磁盘${NC}"
    echo ""

    local out rc=0
    out=$(printf "protocol=https\nhost=%s\n\n" "$host" | timeout 300 "$gcm_path" get 2>&1) || rc=$?
    if [[ $rc -eq 0 ]] && grep -q '^username=' <<< "$out"; then
        local u
        u=$(grep -m1 '^username=' <<< "$out" | cut -d= -f2-)
        ok "登录成功（$u）"
        echo -e "  ${GRAY}凭据由 GCM 存入 Windows 凭据管理器（DPAPI）${NC}"
        return 0
    fi
    err "登录未完成（rc=$rc）"
    local line
    while IFS= read -r line; do
        [[ "$line" == password=* || -z "$line" ]] && continue
        echo "  $line"
    done <<< "$out"
    echo ""
    echo -e "  ${GRAY}常见原因：代理/VPN 未开（GCM 要访问 github.com）、浏览器未弹、超时${NC}"
    return 1
}

# ── 未装 GCM：给安装命令（不自动执行，用户自己在 Windows 侧跑）──
# 推荐 GCM（密钥只在 Windows），但 PAT 作为备选也给出，不强制。
do_install_hint() {
    section "安装 Windows GCM（未装）"
    echo ""
    echo -e "  ${BOLD_GRAY}GCM 是推荐方式：密钥由 Windows 凭据管理器加密，WSL 磁盘零明文、无过期。${NC}"
    echo ""
    echo -e "  ${GREEN}方式一（推荐）${NC} — GCM 独立包，用户级、免管理员："
    echo -e "    ${CYAN}winget install --id Git.GCM${NC}"
    echo ""
    echo -e "  ${BOLD_GRAY}方式二${NC} — 完整 Git for Windows（自带 GCM）："
    echo -e "    ${CYAN}winget install --id Git.Git -e${NC}"
    echo -e "    ${GRAY}或下载: https://git-scm.com/downloads${NC}"
    echo ""
    echo -e "  ${BOLD_GRAY}无 winget 兜底${NC} — MinGit 便携版（解压即用，自带 GCM）："
    echo -e "    ${CYAN}https://github.com/git-for-windows/git/releases${NC} ${GRAY}→ MinGit-*-64-bit.zip${NC}"
    echo ""
    echo -e "  ${BOLD_GRAY}方式三（备选）${NC} — 改用 GitHub PAT："
    echo -e "    菜单选「配置 GitHub PAT」，或: ${CYAN}gh auth login${NC}"
    echo -e "    ${GRAY}token 会明文落 ~/.config/gh/hosts.yml，有过期${NC}"
    echo ""
    echo -e "  装完回来跑: ${CYAN}bash maintain.sh git-auth${NC}（或重跑本菜单第 1 项）"
    echo ""
}

# ── 公共入口 ──

do_status() {
    local gcm_path
    gcm_path=$(_find_gcm_path) || true
    local gcm_st; gcm_st=$(_gcm_status "$gcm_path")
    local pat_st; pat_st=$(_pat_status)

    section "GitHub 认证状态"

    echo -e "  ${BOLD_GRAY}Windows GCM（WSL interop，推荐）${NC}"
    case "$gcm_st" in
        ok)
            echo -e "    状态: ${GREEN}已配置${NC}"
            echo -e "    路径: ${DIM}$(_redact_user "$gcm_path")${NC}"
            ;;
        not_configured)
            echo -e "    状态: ${YELLOW}未配置${NC}"
            if [[ -z "$gcm_path" ]]; then
                echo -e "    ${GRAY}未找到 GCM → 菜单「安装 Windows GCM」看命令${NC}"
            else
                echo -e "    ${GRAY}已找到 GCM → 菜单「配置 Windows GCM」写入 helper${NC}"
            fi
            ;;
        bad_path)
            echo -e "    状态: ${YELLOW}helper 配置了但 exe 不可达${NC}"
            echo -e "    路径: ${DIM}$(_redact_user "$(git config --global --get-all "credential.https://github.com.helper" 2>/dev/null | head -1)")${NC}"
            ;;
    esac
    echo ""

    echo -e "  ${BOLD_GRAY}GitHub PAT（gh auth）${NC}"
    case "$pat_st" in
        logged_in)
            echo -e "    状态: ${GREEN}已登录${NC}  ${DIM}（token 是否有效需联网，选下方验证）${NC}"
            ;;
        not_logged_in)
            echo -e "    状态: ${YELLOW}未登录${NC}"
            ;;
    esac
    echo ""

    # 这里刻意不跑网络：do_status 每次进菜单/刷新都要调，curl 直连+代理最坏要 30s，
    # 会把菜单卡住（实测"状态 OK 但菜单半天才出"）。联网实测只走下方「验证连通性」。
    echo -e "  ${DIM}远端连通性：未检测 —— 选「验证连通性」做端到端实测（耗时较长）${NC}"

    # 综合结论
    echo ""
    if [[ "$gcm_st" == "ok" || "$pat_st" == "logged_in" ]]; then
        echo -e "  ${GREEN}✓ GitHub 认证可用${NC}"
    else
        echo -e "  ${YELLOW}⚠ GitHub 认证未配置${NC}"
        echo -e "  ${GRAY}选下方任一方式配置${NC}"
    fi
    echo ""
}

# 验证远端连通性（交互菜单用）
_verify_interactive() {
    echo -e "  ${YELLOW}端到端实测耗时较长（直连 + 代理，最坏 ~30s）...${NC}"
    local proxy="" rc=0
    proxy=$(_test_reachability) || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo ""
        [[ -n "$proxy" ]] \
            && ok "GitHub 可达（走代理 $proxy）" \
            || ok "GitHub 可达（直连）"
        echo ""
        local sha
        sha=$(_git_verify "$proxy") && {
            ok "git ls-remote 验证通过（SHA: ${sha:0:12}...）"
        } || {
            warn "git ls-remote 未通过（认证或网络问题）"
        }
    else
        warn "GitHub 网络不可达 — 检查 VPN/代理"
    fi
}

do_interactive() {
    while true; do
        clear 2>/dev/null || true
        do_status

        local gcm_path; gcm_path=$(_find_gcm_path) || true
        # 快探测落空时慢探测一次（问 Windows git / 注册表）——用户在场，可接受 1-2s；
        # status 刻意不做，避免卡菜单。
        [[ -z "$gcm_path" ]] && gcm_path=$(_find_gcm_path_slow) || true
        local gcm_st; gcm_st=$(_gcm_status "$gcm_path")
        local pat_st; pat_st=$(_pat_status)

        local items=()
        if [[ -z "$gcm_path" ]]; then
            items+=("安装 Windows GCM（未装，显示安装命令）")
            items+=("配置 GitHub PAT（备选，gh auth login）")
            items+=("验证远端连通性")
        else
            [[ "$gcm_st" != "ok" ]] && items+=("配置 Windows GCM（借用 Windows 凭据）") \
                                    || items+=("配置 Windows GCM（已配，重新配置）")
            items+=("登录 GitHub（GCM 浏览器/设备码）")
            [[ "$pat_st" != "logged_in" ]] && items+=("配置 GitHub PAT（备选，gh auth login）") \
                                           || items+=("配置 GitHub PAT（已登录，重新配置）")
            items+=("验证远端连通性")
        fi
        items+=("返回")

        local sel
        sel=$(menu_select "选择操作" "${items[@]}") || return 0
        [[ -z "$sel" || "$sel" == "0" ]] && return 0
        (( sel == ${#items[@]} )) && return 0

        if [[ -z "$gcm_path" ]]; then
            case "$sel" in
                1) do_install_hint ;;
                2) _do_pat_setup ;;
                3) _verify_interactive ;;
                *) continue ;;
            esac
        else
            case "$sel" in
                1) _do_gcm_setup "$gcm_path" ;;
                2) _do_login "$gcm_path" ;;
                3) _do_pat_setup ;;
                4) _verify_interactive ;;
                *) continue ;;
            esac
        fi
        _pause_continue
    done
}

do_check() {
    local gcm_path; gcm_path=$(_find_gcm_path) || true
    local gcm_st; gcm_st=$(_gcm_status "$gcm_path")
    local pat_st; pat_st=$(_pat_status)
    [[ "$gcm_st" == "ok" || "$pat_st" == "logged_in" ]] && exit 0 || exit 1
}

# ========== 入口 ==========
main() {
    local cmd="${1:-interactive}"
    case "$cmd" in
        interactive|"")  do_interactive ;;
        status)          do_status ;;
        gcm)
            local gcm_path; gcm_path=$(_find_gcm_path) || true
            if [[ -z "$gcm_path" ]]; then
                gcm_path=$(_find_gcm_path_slow) || true
            fi
            if [[ -z "$gcm_path" ]]; then
                err "未找到 Windows GCM"
                echo -e "  ${GRAY}先装 GCM（看安装命令）: bash lib/git-auth.sh install${NC}"
                exit 1
            fi
            _do_gcm_setup "$gcm_path" ;;
        login)
            local gcm_path; gcm_path=$(_find_gcm_path) || true
            if [[ -z "$gcm_path" ]]; then
                gcm_path=$(_find_gcm_path_slow) || true
            fi
            if [[ -z "$gcm_path" ]]; then
                err "未找到 Windows GCM"
                echo -e "  ${GRAY}先装 GCM（看安装命令）: bash lib/git-auth.sh install${NC}"
                exit 1
            fi
            _do_login "$gcm_path" "${2:-github.com}" ;;
        install)         do_install_hint ;;
        pat)             _do_pat_setup ;;
        verify)
            local proxy="" rc=0
            proxy=$(_test_reachability) || rc=$?
            if [[ $rc -ne 0 ]]; then
                err "GitHub 网络不可达"
                exit 1
            fi
            local sha; sha=$(_git_verify "$proxy") && {
                ok "验证通过（SHA: ${sha:0:12}...）"
            } || {
                err "验证失败"
                exit 1
            } ;;
        check)           do_check ;;
        *)
            err "用法: bash lib/git-auth.sh [status|gcm|login|install|pat|verify|check]"
            exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
