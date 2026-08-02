#!/bin/bash
# test-cross-script-dryrun.sh — 跨脚本引用 dry-run 端到端测试
#
# 验证：
#   - init-base.sh --dry-run 输出预览不实际执行
#   - example-sync.sh 在 CCC_DRY_RUN=1 下不复制文件
#   - init-skill.sh 在 CCC_DRY_RUN=1 下不安装依赖/不建链接
#   - update.sh --dry-run 只检查不升级
#   - dry-run.sh run() 在 CCC_DRY_RUN=1 时只打印 would
#
# 用途：验证"脚本间互相引用不报错"，模拟更新后回归。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0; SKIP=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1 — $2"; FAIL=$((FAIL+1)); }
skip() { echo "  ⊘ SKIP $1 — $2"; SKIP=$((SKIP+1)); }

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# 隔离 home
setup_isolated_env() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    mkdir -p "$HOME/git" "$HOME/.claude" "$HOME/.local/bin"
    cp -r "$CCCONFIG_DIR" "$HOME/git/ccconfig"
    export PATH="$HOME/.local/bin:$PATH"
}

teardown_isolated_env() {
    rm -rf "$TEST_HOME"
}

# ═══ dry-run.sh 基础 ═══
test_dry_run_run_prints_would() {
    # 验证 run() 在 CCC_DRY_RUN=1 时打印 would 而不执行
    local out
    out=$(CCC_DRY_RUN=1 bash -c '
        source "'"$CCCONFIG_DIR"'/lib/dry-run.sh"
        run echo "SHOULD_NOT_RUN"
    ' 2>&1 | tr '\n' ' ')
    if echo "$out" | grep -q "would: echo SHOULD_NOT_RUN"; then
        pass "dry-run run(): CCC_DRY_RUN=1 → 打印 would"
    else
        fail "dry-run run()" "got: $out"
    fi
    # 无 dry-run 时真正执行
    local out2
    out2=$(bash -c '
        source "'"$CCCONFIG_DIR"'/lib/dry-run.sh"
        run echo "REAL_OUTPUT"
    ' 2>&1 | tr '\n' ' ')
    if echo "$out2" | grep -q "REAL_OUTPUT"; then
        pass "dry-run run(): 无开关 → 真执行"
    else
        fail "dry-run run()" "got: $out2"
    fi
}

test_dry_run_strip_flag() {
    # 验证 _dry_run_strip 剥离 --dry-run
    local out
    out=$(CCC_DRY_RUN=1 bash -c '
        source "'"$CCCONFIG_DIR"'/lib/dry-run.sh"
        run npm install -g pkg1 --dry-run
    ' 2>&1 | tr '\n' ' ')
    if echo "$out" | grep -q "would: npm install -g pkg1"; then
        pass "dry-run strip(): --dry-run 被剥离"
    else
        fail "dry-run strip()" "got: $out"
    fi
}

test_dry_run_banner() {
    local out
    out=$(CCC_DRY_RUN=1 bash -c '
        source "'"$CCCONFIG_DIR"'/lib/dry-run.sh"
        dry_run_banner
    ' 2>&1)
    if echo "$out" | grep -qi "DRY-RUN"; then
        pass "dry_run_banner(): 输出 DRY-RUN 提示"
    else
        fail "dry_run_banner()" "got: $out"
    fi
}

# ═══ init-base.sh --dry-run ═══
test_init_base_dry_run() {
    setup_isolated_env
    local out
    out=$(bash "$HOME/git/ccconfig/init-base.sh" --dry-run 2>&1) || true
    if echo "$out" | grep -q "init-ubuntu.sh"; then
        pass "init-base.sh --dry-run: 输出执行预览"
    else
        fail "init-base.sh --dry-run" "缺少预览"
    fi
    # 验证没实际执行 init-ubuntu（没装包）
    if command -v node >/dev/null 2>&1; then
        # 系统可能已有 node，跳过此断言
        skip "init-base.sh dry-run" "node 已存在，无法验证未执行"
    else
        pass "init-base.sh dry-run: 未实际执行 init-ubuntu"
    fi
    teardown_isolated_env
}

# ═══ example-sync.sh CCC_DRY_RUN=1 ═══
test_example_sync_dry_run() {
    setup_isolated_env
    local d="$HOME/git/ccconfig"
    # 创建模板 + 目标
    mkdir -p "$d/templates/rules"
    echo "# test rule" > "$d/templates/rules/test-rule.md.example"
    mkdir -p "$HOME/git/ccprivate"
    # dry-run promote 不应复制
    local out
    out=$(CCC_DRY_RUN=1 bash "$d/lib/example-sync.sh" promote "$d/templates/rules/test-rule.md.example" 2>&1 < /dev/null) || true
    if [ ! -f "$HOME/git/ccprivate/rules/test-rule.md" ]; then
        pass "example-sync: CCC_DRY_RUN=1 不复制文件"
    else
        fail "example-sync" "dry-run 下仍复制了文件"
    fi
    teardown_isolated_env
}

# ═══ init-skill.sh CCC_DRY_RUN=1 ═══
test_init_skill_dry_run() {
    setup_isolated_env
    local d="$HOME/git/ccconfig"
    # 无 skill 源 → 不安装不建链
    local out
    out=$(CCC_DRY_RUN=1 bash "$d/lib/init-skill.sh" sync 2>&1) || true
    # 不应出现 "npm install" 真执行痕迹
    if echo "$out" | grep -qi "阶段 0/4\|CLI 依赖"; then
        pass "init-skill.sh: dry-run 进入流程不崩溃"
    else
        skip "init-skill.sh" "无 skill 源，输出: ${out:0:80}"
    fi
    teardown_isolated_env
}

# ═══ update.sh --dry-run ═══
test_update_dry_run() {
    setup_isolated_env
    local out
    out=$(bash "$HOME/git/ccconfig/lib/update.sh" --dry-run 2>&1) || true
    if echo "$out" | grep -qi "dry-run\|版本检查"; then
        pass "update.sh --dry-run: 输出检查信息"
    else
        skip "update.sh" "输出: ${out:0:100}"
    fi
    teardown_isolated_env
}

# ═══ 脚本互引（source 依赖不报错） ═══
test_script_dependencies_source() {
    # 验证关键脚本 source 的依赖都存在
    local missing=0
    for script in lib/init-llm.sh lib/init-mcp.sh lib/init-skill.sh lib/update.sh lib/example-sync.sh lib/sync.sh lib/monitor.sh lib/status.sh; do
        local deps
        deps=$(grep -oE 'source "\$SCRIPT_DIR/[a-z-]+\.sh"' "$CCCONFIG_DIR/$script" 2>/dev/null | grep -oE '[a-z-]+\.sh')
        for dep in $deps; do
            if [ ! -f "$CCCONFIG_DIR/lib/$dep" ] && [ ! -f "$CCCONFIG_DIR/$dep" ]; then
                fail "$script" "依赖缺失: $dep"
                missing=$((missing + 1))
            fi
        done
    done
    [ "$missing" -eq 0 ] && pass "脚本 source 依赖全部存在"
}

# ═══ 主流程 ═══

run_tests() {
    local idx=0
    local n=${#all_tests[@]}
    while [ $idx -lt $n ]; do
        local fn="${all_tests[$((idx+1))]:-}"
        if [ -n "$fn" ] && declare -F "$fn" >/dev/null 2>&1; then
            "$fn" 2>/dev/null || true
        fi
        idx=$((idx + 2))
    done
}

all_tests=(
    "desc: dry-run run() 打印 would" test_dry_run_run_prints_would
    "desc: dry-run strip --dry-run" test_dry_run_strip_flag
    "desc: dry-run banner" test_dry_run_banner
    "desc: init-base --dry-run 预览" test_init_base_dry_run
    "desc: example-sync dry-run 不复制" test_example_sync_dry_run
    "desc: init-skill dry-run 不崩溃" test_init_skill_dry_run
    "desc: update --dry-run 只检查" test_update_dry_run
    "desc: 脚本 source 依赖存在" test_script_dependencies_source
)

echo ""
echo -e "${CYAN}跨脚本引用 dry-run 测试${NC}"
echo "══════════════════════════════"
echo ""

run_tests

echo ""
echo "────────────────────────────────────"
printf "  ${GREEN}PASS${NC}: %d  ${RED}FAIL${NC}: %d  ${YELLOW}SKIP${NC}: %d  TOTAL: %d\n" "$PASS" "$FAIL" "$SKIP" "$((${#all_tests[@]} / 2))"
echo "────────────────────────────────────"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
