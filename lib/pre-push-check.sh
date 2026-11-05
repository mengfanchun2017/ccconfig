#!/bin/bash
# pre-push-check.sh — 推送前密钥扫描（纯代码，供 monitor.sh / maintain.sh 调用）
#
# 用法：
#   source lib/pre-push-check.sh
#   pre_push_check <repo_dir>   # 扫描工作树 + 已跟踪文件，0=干净 1=命中
#
# 开关：~/.claude/.pre-push-check-enabled 存在即开启（maintain.sh 维护）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/secret-patterns.sh"

PRE_PUSH_CHECK_FLAG="$HOME/.claude/.pre-push-check-enabled"

pre_push_check_enabled() {
    [[ -f "$PRE_PUSH_CHECK_FLAG" ]]
}

pre_push_check_toggle() {
    if pre_push_check_enabled; then
        rm -f "$PRE_PUSH_CHECK_FLAG"
        echo "❌ 推送前密钥扫描已关闭"
    else
        touch "$PRE_PUSH_CHECK_FLAG"
        echo "✅ 推送前密钥扫描已开启"
    fi
}

pre_push_check() {
    local repo_dir="$1"
    local blocked=0

    # 已跟踪文件
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [ ! -f "$repo_dir/$f" ] && continue
        if grep -qE "$SECRET_RE" "$repo_dir/$f" 2>/dev/null; then
            echo "  ❌ $f — 疑似包含 API key / token"
            blocked=1
        fi
    done < <(git -C "$repo_dir" ls-files 2>/dev/null)

    # 未跟踪文件（有改动待提交的）
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [ ! -f "$repo_dir/$f" ] && continue
        case "$f" in *.md|*.json|*.yaml|*.yml|*.sh|*.py|*.txt|*.example)
            if grep -qE "$SECRET_RE" "$repo_dir/$f" 2>/dev/null; then
                echo "  ❌ $f — 疑似包含 API key / token"
                blocked=1
            fi
        esac
    done < <(git -C "$repo_dir" status --porcelain 2>/dev/null | awk '{print $2}')

    return $blocked
}
