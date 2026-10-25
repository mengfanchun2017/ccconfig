#!/bin/bash
# lib/git-pull.sh — 仓库拉取单点实现
#
# 此前"把仓库从远程拉到最新"散在 6 处，行为不一致：
#   maintain.sh pull_config_repo  --ff-only + 代理注入 + 分支自适应
#   lib/monitor.sh git_pull_rebase --rebase --autostash + 死代理剥 env + 超时
#   lib/sync.sh                   两种混用
#   lib/update.sh self_update     --ff-only 写死 main
#   lib/status.sh git_pull        --rebase 写死 main
#   lib/init-skill.sh             --ff-only 写死 main || true（吞错误）
# 不一致导致：写死 main 的在一台 master 分支仓（ccprivate）上静默失败；
# 吞错误的把"换账号 remote 失效"藏了起来。统一到这里。
#
# 用法：
#   source lib/git-pull.sh
#   git_pull_repo <repo_dir> [选项]
#     选项:
#       --rebase        分叉时 rebase（默认）；不加则 --ff-only
#       --ff-only       只允许快进，分叉即失败
#       --timeout N     单次超时秒数（默认 30）
#       --branch B      指定分支（默认自动探测当前分支）
#       --quiet         不打印进度，只返回码
#     返回: 0 成功（含"已是最新"）/ 1 失败 / 2 有冲突（已 abort 回滚）
#
#   也可只取底层命令串（供 monitor 等需要自己包重试的调用方）：
#       git_pull_cmd <repo_dir> <branch> <mode>   → 打印 argv（每行一项）

# 代理处理：与 monitor 对齐 —— 代理死时剥掉所有 proxy env 直连，而非硬走死代理。
_gp_proxy_env() {
    local p="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
    if [ -n "$p" ]; then
        # 配置了代理：探活（1s TCP），死则剥 env 直连
        local hostport="${p#*://}"
        local host="${hostport%%:*}" port="${hostport##*:}"
        if timeout 2 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
            printf '%s\n' "KEEP"
            return 0
        fi
        printf '%s\n' "STRIP"
        return 0
    fi
    # 未配代理：探测本机 Clash，有则注入
    local q
    for q in 7897 7890; do
        if timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/$q" 2>/dev/null; then
            printf 'SET http://127.0.0.1:%s\n' "$q"
            return 0
        fi
    done
    printf '%s\n' "NONE"
}

git_pull_repo() {
    local repo_dir="" mode="ff" tmo=30 branch="" quiet=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --rebase)   mode="rebase" ;;
            --ff-only)  mode="ff" ;;
            --timeout)  shift; tmo="${1:-30}" ;;
            --branch)   shift; branch="${1:-}" ;;
            --quiet)    quiet=1 ;;
            *)          [ -z "$repo_dir" ] && repo_dir="$1" ;;
        esac
        shift
    done

    [ -n "$repo_dir" ] || { echo "git_pull_repo: 缺 repo_dir" >&2; return 1; }
    [ -d "$repo_dir/.git" ] || return 0

    # 分支自适应：不写死 main（ccprivate 历史是 master）
    if [ -z "$branch" ]; then
        branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null)
        [ -z "$branch" ] && branch="main"   # detached HEAD 兜底
    fi

    # 代理决策
    local penv=() pdec pval
    pdec=$(_gp_proxy_env)
    case "$pdec" in
        KEEP)  : ;;
        STRIP) penv=(env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy) ;;
        SET*)  pval="${pdec#SET }"
               export HTTPS_PROXY="$pval" https_proxy="$pval" HTTP_PROXY="$pval" http_proxy="$pval" ;;
        *)     : ;;
    esac

    local args=(pull)
    [ "$mode" = "rebase" ] && args+=(--rebase --autostash) || args+=(--ff-only)

    # set -e 兼容：调用方可能开着 -e，pull 失败不应直接杀进程
    local had_e=0; case $- in *e*) had_e=1 ;; esac
    set +e
    local out rc
    out=$(timeout --kill-after=5 "$tmo" "${penv[@]}" git -C "$repo_dir" "${args[@]}" origin "$branch" 2>&1)
    rc=$?
    [ "$had_e" = 1 ] && set -e

    if [ $rc -ne 0 ]; then
        # rebase 冲突：abort 回滚，保持仓库干净（别把调用方留在中间态）
        if [ -d "$repo_dir/.git/rebase-merge" ] || [ -d "$repo_dir/.git/rebase-apply" ]; then
            git -C "$repo_dir" rebase --abort 2>/dev/null || true
            [ "$quiet" = 0 ] && printf '%s\n' "$out" >&2
            return 2
        fi
        [ "$quiet" = 0 ] && printf '%s\n' "$out" >&2
        return 1
    fi
    [ "$quiet" = 0 ] && [ -n "$out" ] && printf '%s\n' "$out"
    return 0
}

# 供需要自定义重试/自愈的调用方（monitor）取底层命令
git_pull_cmd() {
    local repo_dir="$1" branch="$2" mode="${3:-rebase}"
    local args=(git -C "$repo_dir" pull)
    [ "$mode" = "rebase" ] && args+=(--rebase --autostash) || args+=(--ff-only)
    printf '%s\n' "${args[@]}" origin "$branch"
}