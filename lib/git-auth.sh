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

# ── 找 GCM 路径 ──
# 优先级：现有 gitconfig → 常见路径
_find_gcm_path() {
    # 1. 从现有 gitconfig 提取 helper 中的路径
    local helpers
    helpers=$(git config --global --get-all "credential.https://github.com.helper" 2>/dev/null) || true
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # helper 值可能是 !"C:\...\gcm.exe"（带引号，路径含空格时必需），
        # 直接 test -x 会因字面引号失败 → 剥掉首尾引号再判
        local p="${line#!}"
        p="${p#\"}"; p="${p%\"}"
        p="${p%\'}"; p="${p#\'}"
        [[ -x "$p" ]] && { echo "$p"; return 0; }
    done <<< "$helpers"

    # 2. 常见 MinGit 位置（遍历 /mnt/c/Users/ 下的所有目录）
    if [[ -d /mnt/c/Users ]]; then
        for ud in /mnt/c/Users/*/; do
            local p="${ud}AppData/Local/Programs/MinGit/ucrt64/bin/git-credential-manager.exe"
            [[ -x "$p" ]] && { echo "$p"; return 0; }
        done
    fi

    # 3. 全局 Git for Windows
    local p="/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
    [[ -x "$p" ]] && { echo "$p"; return 0; }

    return 1
}

# ── GCM 状态（machine-readable）──
# 输出: ok|not_configured|bad_path
_gcm_status() {
    local gcm_path="${1:-}"
    local github_helper
    github_helper=$(git config --global --get-all "credential.https://github.com.helper" 2>/dev/null | grep -v '^$' | head -1) || true
    [[ -z "$github_helper" ]] && { echo "not_configured"; return; }
    [[ -z "$gcm_path" ]] && { echo "bad_path"; return; }
    echo "ok"
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

# ── 测试远端连通性（返回 0=可达）──
_test_reachability() {
    # 直连。只看 http_code 不看退出码：github.com 直连慢（TLS 握手后大响应体）时
    # curl 会因 --max-time 返回 28，但 -w 已写出 200 —— 判退出码会误报不可达。
    local code
    code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 https://github.com 2>/dev/null || true)
    [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]] && return 0
    # 走代理
    local proxy="http://127.0.0.1:7897"
    code=$(curl -x "$proxy" -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 https://github.com 2>/dev/null || true)
    [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]] && { echo "$proxy"; return 0; }
    return 1
}

# ── git ls-remote 验证（返回 0=认证通过）──
_GITHUB_REPO="https://github.com/mengfanchun2017/ccconfig.git"
_git_verify() {
    local proxy="${1:-}"
    local -a args=()
    [[ -n "$proxy" ]] && args=(-c "http.proxy=$proxy" -c "https.proxy=$proxy")
    local out rc=0
    out=$(timeout 40 git "${args[@]}" ls-remote "$_GITHUB_REPO" HEAD 2>&1) || rc=$?
    if [[ $rc -eq 0 && "$out" =~ ^[0-9a-f]{40} ]]; then
        echo "$out"
        return 0
    fi
    # 直连失败（被墙/慢）→ 用代理重试一次
    if [[ -z "$proxy" ]]; then
        out=$(timeout 40 git -c http.proxy=http://127.0.0.1:7897 -c https.proxy=http://127.0.0.1:7897 \
            ls-remote "$_GITHUB_REPO" HEAD 2>&1) || rc=$?
        [[ $rc -eq 0 && "$out" =~ ^[0-9a-f]{40} ]] && { echo "$out"; return 0; }
    fi
    return 1
}

# ── 配置 GCM ──
_do_gcm_setup() {
    local gcm_path="$1"
    section "配置 Windows GCM"

    echo -e "  GCM 路径: ${CYAN}$gcm_path${NC}"
    echo ""

    # 备份
    local bak
    bak="$HOME/.gitconfig.bak.gitok-$(date +%Y%m%d%H%M%S)"
    cp ~/.gitconfig "$bak"
    echo -e "  ${GRAY}备份: $bak${NC}"
    echo ""

    # 写 helper
    for h in github.com gist.github.com; do
        git config --global --unset-all "credential.https://$h.helper" 2>/dev/null || true
        # 值不能带字面引号：曾写 "\"!...\"" 存成 \"!...\" → git 把 credential-!...
        # 当命令名（实测报 "is not a git command"）。路径含空格也不需引号 ——
        # git 对 ! helper 走 shell 执行，空格安全。
        git config --global --add "credential.https://$h.helper" "!$gcm_path"
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
        warn "远端验证未通过（可能是网络问题，非配置问题）"
        echo -e "  ${GRAY}确认代理/VPN 是否开启，然后重试 verify${NC}"
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
            echo -e "    路径: ${DIM}$gcm_path${NC}"
            ;;
        not_configured)
            echo -e "    状态: ${YELLOW}未配置${NC}"
            ;;
        bad_path)
            echo -e "    状态: ${YELLOW}helper 配置了但 exe 不可达${NC}"
            echo -e "    路径: ${DIM}$(git config --global --get-all "credential.https://github.com.helper" 2>/dev/null | head -1)${NC}"
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

do_interactive() {
    while true; do
        clear 2>/dev/null || true
        do_status

        local items=()
        local gcm_path; gcm_path=$(_find_gcm_path) || true
        local gcm_st; gcm_st=$(_gcm_status "$gcm_path")
        local pat_st; pat_st=$(_pat_status)

        [[ "$gcm_st" != "ok" ]] && items+=("配置 Windows GCM（WSL 借用 Windows 凭据）") \
                                || items+=("配置 Windows GCM（已配，重新配置）")
        [[ "$pat_st" != "logged_in" ]] && items+=("配置 GitHub PAT（gh auth login）") \
                                       || items+=("配置 GitHub PAT（已登录，重新配置）")
        items+=("验证远端连通性")
        items+=("返回")

        local sel
        sel=$(menu_select "选择操作" "${items[@]}") || return 0
        [[ -z "$sel" || "$sel" == "0" ]] && return 0
        (( sel == ${#items[@]} )) && return 0

        case "$sel" in
            1)
                if [[ -z "$gcm_path" ]]; then
                    warn "未找到 Windows GCM（git-credential-manager.exe）"
                    echo -e "  ${GRAY}请先在 Windows 安装 Git（自带 GCM），再跑本配置${NC}"
                    echo ""
                    echo -e "  已知路径: /mnt/c/Users/<你>/AppData/Local/Programs/MinGit/ucrt64/bin/"
                _pause_continue
                    continue
                fi
                _do_gcm_setup "$gcm_path"
                _pause_continue
                ;;
            2)
                _do_pat_setup
                _pause_continue
                ;;
            3)
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
                _pause_continue
                ;;
        esac
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
                err "未找到 Windows GCM"
                echo -e "  ${GRAY}请先在 Windows 安装 Git（自带 GCM）: https://git-scm.com/downloads${NC}"
                exit 1
            fi
            _do_gcm_setup "$gcm_path" ;;
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
            err "用法: bash lib/git-auth.sh [status|gcm|pat|verify|check]"
            exit 1 ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
