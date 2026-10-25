#!/bin/bash
# 回归测试：lib/git-pull.sh 单点拉取实现
#
# 背景：拉取逻辑曾散在 6 处，行为不一致（有的 --ff-only、有的写死 main、
# 有的 || true 吞错误）。统一后必须锁死四种行为。

set -u
CCCONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CCCONFIG_DIR"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
# 隔离 HOME 后必须给 git 身份：rebase 要重新提交，缺身份会 fatal（测试环境问题，非库问题）
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git config --global user.name t 2>/dev/null; git config --global user.email t@t 2>/dev/null

G="git -c user.email=t@t -c user.name=t -c init.defaultBranch=main"

echo "=== git-pull.sh ==="
[ -f lib/git-pull.sh ] && pass "lib/git-pull.sh 存在" || fail "缺 lib/git-pull.sh"

# 建 origin + 两个 clone
mkdir -p "$T/origin" && cd "$T/origin" && $G init -q .
echo a > f && git add f && $G commit -qm init
cd "$T" && $G clone -q "$T/origin" work1 && $G clone -q "$T/origin" work2

source "$CCCONFIG_DIR/lib/git-pull.sh"

# 1. 已是最新 → 0
git_pull_repo "$T/work1" --quiet; [ $? -eq 0 ] && pass "已是最新返回 0" || fail "已最新应为 0"

# 2. 分叉 + --rebase → 自愈成功，本地提交保留
cd "$T/origin" && echo b >> f && $G commit -qam r1
cd "$T/work1" && echo c > local.txt && git add local.txt && $G commit -qm l1
git_pull_repo "$T/work1" --rebase --quiet; rc=$?
[ $rc -eq 0 ] && pass "分叉 + rebase 自愈成功" || fail "rebase 自愈失败 rc=$rc"
[ -f "$T/work1/local.txt" ] && pass "rebase 后本地提交保留" || fail "本地提交丢失"

# 3. 分叉 + --ff-only → 失败（1）
cd "$T/origin" && echo d >> f && $G commit -qam r2
cd "$T/work2" && echo e > l2.txt && git add l2.txt && $G commit -qm l2
git_pull_repo "$T/work2" --ff-only --quiet 2>/dev/null; rc=$?
[ $rc -eq 1 ] && pass "分叉 + ff-only 返回 1" || fail "ff-only 分叉应返回 1，得到 $rc"

# 4. rebase 冲突 → 返回 2 且回滚干净（不留中间态）
cd "$T/work1" && echo "from-work" > f && git add f && $G commit -qm cw
cd "$T/origin" && echo "from-origin" > f && $G commit -qam co
cd "$T/work1" && git_pull_repo "$T/work1" --rebase --quiet 2>/dev/null; rc=$?
[ $rc -eq 2 ] && pass "冲突返回 2" || fail "冲突应返回 2，得到 $rc"
if [ -d "$T/work1/.git/rebase-merge" ] || [ -d "$T/work1/.git/rebase-apply" ]; then
    fail "冲突后仍留在 rebase 中间态"
else
    pass "冲突后已 abort，仓库干净"
fi

# 5. 分支自适应：master 分支仓也能工作（不写死 main）
mkdir -p "$T/morigin" && cd "$T/morigin" && $G init -q -b master .
echo x > g && git add g && $G commit -qm init
cd "$T" && $G clone -q "$T/morigin" wm 2>/dev/null
cd "$T/morigin" && echo y >> g && $G commit -qam r
git_pull_repo "$T/wm" --quiet; rc=$?
[ $rc -eq 0 ] && pass "master 分支仓正常拉取（分支自适应）" || fail "master 分支仓失败 rc=$rc"

# 6. 已合并的调用点不得再有裸 pull（白名单：git-pull.sh 自身 + monitor 热路径）
stray=$(grep -rn 'git -C .* pull ' --include=*.sh lib/ maintain.sh init-base.sh init-bootstrap.sh 2>/dev/null \
        | grep -v 'lib/git-pull.sh' | grep -v 'lib/monitor.sh' | grep -v '手动' | grep -v '#' | wc -l)
[ "$stray" -eq 0 ] && pass "无残留裸 pull 调用点" || fail "仍有 $stray 处裸 pull 未合并"

echo ""
echo "────────────────────────────────────"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "────────────────────────────────────"
[ "$FAIL" -eq 0 ]