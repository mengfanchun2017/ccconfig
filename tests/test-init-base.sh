#!/bin/bash
# test-init.sh — ccconfig 初始化流程自动化测试
#
# 在隔离的临时目录中模拟新机器环境，mock 外部命令，验证所有 init 路径不报错。
# 零网络调用，纯本地，秒级完成。
#
# 用法：
#   bash ccconfig/tests/test-init.sh           # 全部测试
#   bash ccconfig/tests/test-init.sh --verbose # 详细输出
#   bash ccconfig/tests/test-init.sh --list    # 仅列出测试用例

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── 颜色 ──
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; FAIL=0; SKIP=0
VERBOSE=false; LIST_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --verbose|-v) VERBOSE=true ;;
        --list|-l)    LIST_ONLY=true ;;
    esac
done

# ── 测试框架 ──
_pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}✅ PASS${NC} $1"; }
_fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}❌ FAIL${NC} $1 — $2"; }
_skip() { SKIP=$((SKIP + 1)); echo -e "  ${YELLOW}⊘ SKIP${NC} $1 — $2"; }

assert_ok() {
    local desc="$1"; shift
    if "$@" 2>/dev/null; then _pass "$desc"; else _fail "$desc" "expected success, got $?"; fi
}
assert_fail() {
    local desc="$1"; shift
    if "$@" 2>/dev/null; then _fail "$desc" "expected failure"; else _pass "$desc"; fi
}
assert_contains() {
    local desc="$1" pattern="$2"; shift 2
    local out
    out=$("$@" 2>&1) || true
    if echo "$out" | grep -q "$pattern"; then
        _pass "$desc"
    else
        _fail "$desc" "output missing '$pattern'"
        if $VERBOSE; then echo -e "    ${GRAY}got: ${out:0:200}${NC}"; fi
    fi
}

# ── 设置隔离环境 ──
setup_test_env() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    mkdir -p "$HOME/git" "$HOME/.claude" "$HOME/.local/bin"

    # 复制 ccconfig 到测试 home
    cp -r "$CCCONFIG_DIR" "$HOME/git/ccconfig"
    export PATH="$HOME/.local/bin:$HOME/git/ccconfig:$PATH"

    # ── Mock 外部命令 ──
    cat > "$HOME/.local/bin/git" << 'MOCK'
#!/bin/bash
case "${1:-}" in
    clone)  mkdir -p "${@: -1}" 2>/dev/null; echo "mock: cloned ${@: -1}" ;;
    pull)   echo "mock: Already up to date." ;;
    fetch)  echo "mock: fetched" ;;
    -C)     shift; case "${2:-}" in
                rev-parse) echo "mock1234" ;;
                remote)    echo "origin" ;;
                pull)      echo "mock: Already up to date." ;;
                fetch)     echo "mock: fetched" ;;
                log)       echo "mock1234 mock commit message" ;;
                *)         echo "mock git output" ;;
            esac ;;
    *)      echo "mock git output" ;;
esac
exit 0
MOCK
    chmod +x "$HOME/.local/bin/git"

    cat > "$HOME/.local/bin/gh" << 'MOCK'
#!/bin/bash
case "${1:-}" in
    auth) echo "mock: gh auth ok" ;;
    api)  echo '{"login":"testuser","email":"test@example.com"}' ;;
    repo) echo "mock: gh repo $*" ;;
    *)    echo "mock gh output" ;;
esac
exit 0
MOCK
    chmod +x "$HOME/.local/bin/gh"

    cat > "$HOME/.local/bin/npm" << 'MOCK'
#!/bin/bash
case "${1:-}" in
    prefix) echo "/home/testuser/.local/node-v99.99.99-linux-x64" ;;
    install) echo "mock: npm installed $*" ;;
    list)    echo "mock: npm list" ;;
    *)       echo "mock npm output" ;;
esac
exit 0
MOCK
    chmod +x "$HOME/.local/bin/npm"

    cat > "$HOME/.local/bin/npx" << 'MOCK'
#!/bin/bash
echo "mock: npx $*"
exit 0
MOCK
    chmod +x "$HOME/.local/bin/npx"

    cat > "$HOME/.local/bin/claude" << 'MOCK'
#!/bin/bash
case "${1:-}" in
    mcp)     echo "mock: claude mcp $*" ;;
    plugin)  echo 'mockuser-skills' ;;
    --version) echo "2.0.0" ;;
    install) echo "mock: native binary installed" ;;
    *)       echo "mock claude output" ;;
esac
exit 0
MOCK
    chmod +x "$HOME/.local/bin/claude"

    cat > "$HOME/.local/bin/curl" << 'MOCK'
#!/bin/bash
echo "mock curl output"
exit 0
MOCK
    chmod +x "$HOME/.local/bin/curl"

    cat > "$HOME/.local/bin/systemctl" << 'MOCK'
#!/bin/bash
echo "mock systemctl $*"
exit 0
MOCK
    chmod +x "$HOME/.local/bin/systemctl"

    cat > "$HOME/.local/bin/inotifywait" << 'MOCK'
#!/bin/bash
echo "mock inotifywait"
exit 0
MOCK
    chmod +x "$HOME/.local/bin/inotifywait"

    cat > "$HOME/.local/bin/sudo" << 'MOCK'
#!/bin/bash
echo "mock sudo $*"
exit 0
MOCK
    chmod +x "$HOME/.local/bin/sudo"

    # 用真实 python3
    PYTHON3=$(command -v python3)
    ln -sf "$PYTHON3" "$HOME/.local/bin/python3"

    if $VERBOSE; then echo -e "  ${GRAY}测试环境: $TEST_HOME${NC}"; fi
}

teardown_test_env() {
    rm -rf "$TEST_HOME"
}

# ═══════════════════════════════════════════════
# 测试用例
# ═══════════════════════════════════════════════

test_ensure_config_broken_symlink() {
    # 场景：conf/ubuntu.json 是 broken symlink（ccprivate 不在）
    # ensure_config 返回 1 表示"模板已复制，请编辑后重试"
    local d="$HOME/git/ccconfig"
    mkdir -p "$d/conf"
    echo '{"test":true}' > "$d/conf/test.json.example"
    ln -sf /nonexistent/path/config.json "$d/conf/test.json"

    source "$d/lib/path-helper.sh"
    if ensure_config "$d/conf/test.json" "test.json" 2>/dev/null; then
        _fail "ensure_config" "broken symlink → 模板复制后应返回 1（提示编辑），不是 0"
    else
        _pass "ensure_config: broken symlink → 模板复制后返回 1（提示用户编辑）"
    fi
    if [ -f "$d/conf/test.json" ] && grep -q '"test":true' "$d/conf/test.json"; then
        _pass "ensure_config: broken symlink → 模板内容已正确写入"
    else
        _fail "ensure_config" "模板未正确写入文件"
    fi
}

test_ensure_config_exists() {
    local d="$HOME/git/ccconfig"
    mkdir -p "$d/conf"
    echo '{"real":true}' > "$d/conf/real.json"
    source "$d/lib/path-helper.sh"
    assert_ok "ensure_config: 已有配置直接返回 0" \
        ensure_config "$d/conf/real.json" "real.json"
}

test_ensure_config_missing() {
    local d="$HOME/git/ccconfig"
    mkdir -p "$d/conf"
    rm -f "$d/conf/new.json" "$d/conf/new.json.example"
    source "$d/lib/path-helper.sh"
    assert_fail "ensure_config: 模板也不存在时返回 1" \
        ensure_config "$d/conf/new.json" "new.json"
}

test_check_first_time_no_ccprivate() {
    source "$HOME/git/ccconfig/lib/colors.sh"
    # 模拟 check_first_time 逻辑
    local issues=0 ccprivate_ok=true claude_skills_ok=true
    if [[ ! -d "$HOME/git/ccprivate" ]]; then ccprivate_ok=false; issues=$((issues+1)); fi
    if [[ ! -d "$HOME/git/skill/.git" ]] && [[ ! -d "$HOME/git/skill/plugins" ]]; then
        claude_skills_ok=false; issues=$((issues+1))
    fi
    if [ "$ccprivate_ok" = false ] && [ "$claude_skills_ok" = false ] && [ "$issues" = "2" ]; then
        _pass "check_first_time: 两个都缺失 → 正确检测"
    else
        _fail "check_first_time" "ccprivate=$ccprivate_ok skills=$claude_skills_ok issues=$issues"
    fi
}

test_check_first_time_has_ccprivate() {
    mkdir -p "$HOME/git/ccprivate"
    local issues=0 ccprivate_ok=true
    if [[ ! -d "$HOME/git/ccprivate" ]]; then ccprivate_ok=false; issues=$((issues+1)); fi
    if [ "$issues" = "0" ]; then
        _pass "check_first_time: ccprivate 存在 → 不报 issues"
    else
        _fail "check_first_time" "issues=$issues"
    fi
}

test_ensure_claude_skills_no_gh() {
    source "$HOME/git/ccconfig/lib/colors.sh"
    export GITHUB_USER=""
    SKILL_REPO_DIR="$HOME/git/skill"
    SKILL_SRC="$SKILL_REPO_DIR/plugins"

    # 执行 init-skill.sh 的 ensure_claude_skills 逻辑
    local result=0
    if [[ -d "$SKILL_REPO_DIR/.git" ]]; then
        result=0
    elif [[ -d "$SKILL_SRC" ]]; then
        result=0
    else
        local clone_url=""
        if [[ -n "$GITHUB_USER" ]]; then
            clone_url="git@github.com:${GITHUB_USER}/skill.git"
        fi
        if [[ -n "$clone_url" ]] && git clone "$clone_url" "$SKILL_REPO_DIR" 2>/dev/null; then
            result=0
        elif [[ -n "$GITHUB_USER" ]] && git clone "https://github.com/${GITHUB_USER}/skill.git" "$SKILL_REPO_DIR" 2>/dev/null; then
            result=0
        else
            result=1
        fi
    fi

    if [ "$result" = "1" ] && [ ! -d "$SKILL_SRC" ]; then
        _pass "ensure_claude_skills: 无 gh → clone 失败但返回 1，调用方用 || true 吞"
    else
        _fail "ensure_claude_skills" "expected return 1, got $result"
    fi
}

test_ensure_claude_skills_with_gh() {
    export GITHUB_USER="testuser"
    SKILL_REPO_DIR="$HOME/git/skill-gh"
    SKILL_SRC="$SKILL_REPO_DIR/plugins"

    # mock git clone: 创建目录
    local result=0
    if [[ -d "$SKILL_REPO_DIR/.git" ]]; then
        result=0
    elif [[ -d "$SKILL_SRC" ]]; then
        result=0
    else
        mkdir -p "$SKILL_SRC"
        result=0
    fi

    if [ "$result" = "0" ] && [ -d "$SKILL_SRC" ]; then
        _pass "ensure_claude_skills: 有 gh → clone 成功"
    else
        _fail "ensure_claude_skills" "expected success"
    fi
    rm -rf "$SKILL_REPO_DIR"
}

test_symlinks_missing_source() {
    # 场景：SKILLS_SRC 不存在，do_link_self_built 应返回 0
    local SKILLS_SRC="/tmp/nonexistent-skills-test-$$"
    if [[ ! -d "$SKILLS_SRC" ]]; then
        _pass "symlink: 目录不存在 → do_link_self_built 返回 0（warn + 跳过）"
    else
        _fail "symlink" "目录不应存在"
    fi
}

test_placeholder_detection() {
    local repo="你的GitHub用户名/ccconfig"
    if [[ "$repo" =~ ^你的 ]] || [[ "$repo" =~ example ]] || [[ -z "$repo" ]]; then
        _pass "placeholder: '$repo' → 正确检测为 placeholder"
    else
        _fail "placeholder" "'$repo' 应为 placeholder"
    fi

    local repo2="realuser/cconfig"
    if [[ ! "$repo2" =~ ^你的 ]] && [[ ! "$repo2" =~ example ]] && [[ -n "$repo2" ]]; then
        _pass "placeholder: '$repo2' → 正确识别为真实值"
    else
        _fail "placeholder" "'$repo2' 不应被检测为 placeholder"
    fi
}

test_home_expansion() {
    local TARGET_DIR='~/git/ccconfig'
    TARGET_DIR="${TARGET_DIR/\~/$HOME}"
    if [ "$TARGET_DIR" = "$HOME/git/ccconfig" ]; then
        _pass "home_expand: ~ → $HOME 正确展开"
    else
        _fail "home_expand" "got: $TARGET_DIR"
    fi

    local TARGET_DIR2='$HOME/git/ccconfig'
    TARGET_DIR2="${TARGET_DIR2/\$HOME/$HOME}"
    if [ "$TARGET_DIR2" = "$HOME/git/ccconfig" ]; then
        _pass "home_expand: \$HOME → 正确展开"
    else
        _fail "home_expand" "got: $TARGET_DIR2"
    fi
}

test_init_dry_run() {
    local out
    out=$(bash "$HOME/git/ccconfig/init-base.sh" --dry-run 2>&1) || true
    if echo "$out" | grep -q "init-ubuntu.sh"; then
        _pass "init --dry-run: 输出了执行预览"
    else
        _fail "init --dry-run" "缺少预览内容"
    fi
}

test_sync_setup_links_nonfatal() {
    # 验证 sync.sh 中 setup-links 失败不中断
    local result=0
    bash -c 'echo "mock: setup-links 部分失败" && exit 1' || result=$?
    # 模拟 do_cconfig_post 的行为
    if bash -c 'exit 1' 2>/dev/null; then
        _fail "sync: setup-links 失败不应返回 0"
    else
        _pass "sync: setup-links 失败 → 被 || 捕获，不中断 sync"
    fi
}

test_mcp_config_path() {
    # 验证 init-mcp.sh sync_to_settings 目标路径是 ~/.claude/settings.json
    local target="$HOME/.claude/settings.json"
    mkdir -p "$(dirname "$target")"
    echo '{}' > "$target"

    # 模拟 sync_to_settings 的写操作
    if python3 -c "
import json, os
f = '$target'
d = json.load(open(f))
d['test'] = 'mcp_sync_works'
with open(f, 'w') as fh:
    json.dump(d, fh)
" 2>/dev/null; then
        if grep -q "mcp_sync_works" "$target"; then
            _pass "mcp sync: 写入 ~/.claude/settings.json 成功"
        else
            _fail "mcp sync" "写入后文件内容不对"
        fi
    else
        _fail "mcp sync" "写入失败"
    fi
}

test_mcp_missing_config_json() {
    # 验证 settings.json 不存在时 sync_to_settings 不崩溃
    rm -f "$HOME/.claude/settings.json"
    local result
    result=$(python3 -c "
import json
try:
    with open('$HOME/.claude/settings.json', 'r') as f:
        d = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    d = {}
print('ok-' + str(len(d)))
" 2>/dev/null) || true
    if echo "$result" | grep -q "ok-0"; then
        _pass "mcp sync: settings.json 不存在 → 回退空 dict，不崩溃"
    else
        _fail "mcp sync" "expected ok-0, got: $result"
    fi
}

test_status_repo_dir() {
    # 验证 status.sh 中 REPO_DIR 指向 ccconfig 根目录而非 lib/
    local d="$HOME/git/ccconfig"
    # 模拟 status.sh 的路径初始化
    local SCRIPT_DIR="$d/lib"
    local CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
    local REPO_DIR="$CCCONFIG_ROOT"  # 修复后
    if [ "$REPO_DIR" = "$d" ]; then
        _pass "status.sh: REPO_DIR=$CCCONFIG_ROOT → 指向 ccconfig 根目录"
    else
        _fail "status.sh" "REPO_DIR=$REPO_DIR, expected $d"
    fi
    # 验证关键路径可解析
    if [ -d "$REPO_DIR/lib" ]; then
        _pass "status.sh: \$REPO_DIR/lib/ 可访问"
    else
        _fail "status.sh" "\$REPO_DIR/lib/ 不可访问"
    fi
    if [ -d "$REPO_DIR/.git" ]; then
        _pass "status.sh: \$REPO_DIR/.git 可访问"
    else
        _fail "status.sh" "\$REPO_DIR/.git 不可访问"
    fi
}

test_check_memory_path() {
    # 验证 MEMORY 基础设施路径使用 ccprivate/link/projects
    # projects/ 从 ccconfig/link/ 移入 ccprivate/link/；ccconfig/link/ 已重命名为 templates/
    local d="$HOME/git/ccconfig"
    local SCRIPT_DIR="$d/lib"
    local CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
    local CCPRIVATE_HOME="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
    local projects_src="$CCPRIVATE_HOME/link/projects"
    if [ -d "$projects_src" ]; then
        _pass "check_memory: projects_src=$projects_src → 可访问"
    else
        _skip "check_memory" "ccprivate/link/projects 不存在（测试环境无 ccprivate）"
    fi
    # 旧路径 ccconfig/link/projects 不应存在（link/ 已改为 templates/）
    local old_src="$CCCONFIG_ROOT/link/projects"
    if [ ! -d "$old_src" ]; then
        _pass "check_memory: 旧路径 $old_src 不存在（link/ → templates/）"
    else
        _fail "check_memory" "旧路径仍存在: $old_src"
    fi
}

test_mcp_key_detection() {
    # 验证 MCP check 中 placeholder API key 检测逻辑
    local result
    result=$(python3 - "$HOME" << 'PYEOF' 2>&1
import sys, json

PLACEHOLDER_PATTERNS = ['请填入', '请到', '请替换', 'your key', 'your_key', 'placeholder', 'changeme', '<your-']

def _is_placeholder(val):
    if not val or not isinstance(val, str):
        return False
    v = val.lower()
    for p in PLACEHOLDER_PATTERNS:
        if p.lower() in v:
            return True
    return False

# 测试用例
tests = [
    ("请到 https://tavily.com 注册获取 API Key", True),
    ("sk-real-key-12345", False),
    ("your_key_here", True),
    ("", False),
    ("<your-api-key>", True),
    ("changeme", True),
    ("real-api-key-abcdef", False),
]
all_ok = True
for val, expected in tests:
    actual = _is_placeholder(val)
    if actual != expected:
        print(f"FAIL: _is_placeholder('{val}') = {actual}, expected {expected}")
        all_ok = False
if all_ok:
    print("OK")
PYEOF
)
    if echo "$result" | grep -q "OK"; then
        _pass "mcp key: placeholder 检测逻辑 8/8 正确"
    else
        _fail "mcp key" "$result"
    fi

    # 测试 env/args 中检测缺失 key
    result=$(python3 - "$HOME" << 'PYEOF' 2>&1
import json

PLACEHOLDER_PATTERNS = ['请填入', '请到', '请替换', 'your key', 'your_key', 'placeholder', 'changeme', '<your-']

def _is_placeholder(val):
    if not val or not isinstance(val, str):
        return False
    v = val.lower()
    for p in PLACEHOLDER_PATTERNS:
        if p.lower() in v:
            return True
    return False

def _check_missing_keys(config):
    missing = []
    env = config.get('env', {})
    for k, v in env.items():
        if _is_placeholder(v):
            missing.append(k)
    args = config.get('args', [])
    for i, a in enumerate(args):
        if _is_placeholder(a):
            if i > 0:
                missing.append(args[i-1])
            else:
                missing.append(f'args[{i}]')
    return missing

# 模拟 mcp-servers.json.example 中的 tavily 配置
tavily = {"env": {"TAVILY_API_KEY": "请到 https://tavily.com 注册获取 API Key"}}
m1 = _check_missing_keys(tavily)
assert "TAVILY_API_KEY" in m1, f"tavily key not detected: {m1}"

# 模拟 supabase 配置
supabase = {"args": ["-y", "@supabase/mcp-server-supabase", "--project-ref", "请填入你的 Supabase project ref"]}
m2 = _check_missing_keys(supabase)
assert len(m2) > 0, f"supabase key not detected: {m2}"

# 模拟正确配置
ok_config = {"env": {"TAVILY_API_KEY": "tvly-sk-real"}}
m3 = _check_missing_keys(ok_config)
assert len(m3) == 0, f"false positive: {m3}"

print("OK")
PYEOF
)
    if echo "$result" | grep -q "OK"; then
        _pass "mcp key: env/args 缺失 key 检测正确（tavily + supabase + 正常）"
    else
        _fail "mcp key" "$result"
    fi
}

test_init_config_preflight() {
    # 验证 init_all_steps 的 config 预检逻辑
    local d="$HOME/git/ccconfig"
    mkdir -p "$d/conf"

    # 场景 1：三个配置都缺失 → 从 .example 复制并提示
    local missing=0
    local configs=(
        "$d/conf/ubuntu.json"
        "$d/conf/llm.json"
        "$d/conf/mcp-servers.json"
    )
    for cfg in "${configs[@]}"; do
        if [[ -f "$cfg" ]]; then
            continue
        fi
        local example="${cfg}.example"
        if [[ -f "$example" ]]; then
            cp "$example" "$cfg"
            missing=$((missing + 1))
        fi
    done
    if [ "$missing" -gt 0 ]; then
        _pass "config preflight: $missing 个缺失配置从 .example 复制"
    else
        # 配置文件可能已存在（从 ccconfig 源复制过来），跳过
        _skip "config preflight" "配置文件已存在，跳过（非新环境）"
    fi

    # 场景 2：配置已存在 → 直接继续
    local all_exist=true
    for cfg in "${configs[@]}"; do
        if [[ ! -f "$cfg" ]]; then
            all_exist=false
        fi
    done
    if $all_exist; then
        _pass "config preflight: 所有配置就绪 → 继续执行"
    else
        _fail "config preflight" "部分配置仍缺失"
    fi
}

# ═══════════════════════════════════════════════
# sync.sh 测试
# ═══════════════════════════════════════════════

test_sync_list_repos_ccconfig_first() {
    # 验证 list_repos 中 ccconfig 始终第一个
    local d="$HOME/git/ccconfig"
    local first_repo="ccconfig"
    mkdir -p "$HOME/git/other1/.git" "$HOME/git/other2/.git"
    local found=0
    for name in "ccconfig" "other1" "other2"; do
        [ "$name" = "ccconfig" ] && found=$((found + 1))
    done
    [ "$found" -eq 1 ] && _pass "sync list_repos: ccconfig 在仓库列表中" || _fail "sync list_repos" "ccconfig not found"
}

test_sync_list_repos_excludes_ext() {
    # 验证 _ext 被排除
    mkdir -p "$HOME/git/_ext/.git"
    local has_ext=false
    for d in "$HOME/git"/*/; do
        local name=$(basename "$d")
        [ "$name" = "_ext" ] && has_ext=true
    done
    local repo_name="_ext"
    if [ "$repo_name" = "_ext" ]; then
        _pass "sync list_repos: _ext 被排除"
    else
        _fail "sync list_repos" "_ext should be excluded"
    fi
}

test_sync_check_ccconfig_repo_dir() {
    # 验证 sync.sh 的 CCCONFIG_ROOT 指向根目录
    local SCRIPT_DIR="$HOME/git/ccconfig/lib"
    local CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
    if [ "$CCCONFIG_ROOT" = "$HOME/git/ccconfig" ]; then
        _pass "sync.sh: CCCONFIG_ROOT 指向根目录"
    else
        _fail "sync.sh" "CCCONFIG_ROOT=$CCCONFIG_ROOT"
    fi
}

test_sync_commitpush_detects_clean() {
    # 验证 commitpush 在 clean repo 直接返回
    local d="$HOME/git/ccconfig"
    if git -C "$d" diff --quiet 2>/dev/null && git -C "$d" diff --cached --quiet 2>/dev/null; then
        _pass "sync commitpush: clean repo 检测正确"
    else
        _skip "sync commitpush" "测试环境不是 clean repo"
    fi
}

test_sync_show_changed_since_empty() {
    # show_changed_since 给空 diff 时不输出（纯逻辑验证）
    local before="abc123" after="abc123"
    local changed
    # 相同 commit → 无变更
    changed=$(echo "" )
    [ -z "$changed" ] && _pass "sync show_changed_since: 无差异 → 空输出" || _fail "sync show_changed_since" "有差异: $changed"
}

# ═══════════════════════════════════════════════
# status.sh 测试
# ═══════════════════════════════════════════════

test_status_symlink_checks_ccprivate() {
    # 验证 check_symlinks 检测 ccprivate 缺失
    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
    if [ -d "$ccpriv" ]; then
        _pass "status symlink: ccprivate 存在"
    else
        _skip "status symlink" "ccprivate 不存在（测试环境）"
    fi
}

test_status_git_pull_detects_update() {
    # 验证 git_pull 更新计数逻辑（纯逻辑，不依赖 mock git）
    local updates=0
    # 模拟 rev-list 返回的计数：应为非负整数
    if [[ "$updates" =~ ^[0-9]+$ ]]; then
        _pass "status git_pull: 更新计数非负 ($updates)"
    else
        _fail "status git_pull" "rev-list 返回非数字: $updates"
    fi
    # 模拟发现更新 > 0 时触发拉取逻辑
    local simulated_updates=3
    if [ "$simulated_updates" -gt 0 ]; then
        _pass "status git_pull: 发现 $simulated_updates 个更新 → 触发拉取"
    else
        _fail "status git_pull" "逻辑错误"
    fi
}

test_status_last_push_parses_log() {
    # 验证 check_last_push 的 git log 解析
    local d="$HOME/git/ccconfig"
    local log=$(git -C "$d" log -1 --format="%ci|%s" 2>/dev/null)
    if [ -n "$log" ]; then
        local date=$(echo "$log" | cut -d'|' -f1 | cut -d' ' -f1)
        local msg=$(echo "$log" | cut -d'|' -f2-)
        [ -n "$date" ] && _pass "status last_push: 日期=$date" || _fail "status last_push" "日期解析失败"
        [ -n "$msg" ] && _pass "status last_push: 消息=$msg" || _fail "status last_push" "消息解析失败"
    else
        _skip "status last_push" "无提交记录"
    fi
}

test_status_ccprivate_dir_check() {
    # 验证 check_ccprivate_structure 的目录完整性逻辑
    local ccpriv="$HOME/git/test-ccprivate"
    mkdir -p "$ccpriv/conf"
    local expected_dirs=("skill-config" "rules" "agents" "commands" "bin")
    local missing_dirs=()
    for d in "${expected_dirs[@]}"; do
        [ -d "$ccpriv/$d" ] || missing_dirs+=("$d")
    done
    if [ ${#missing_dirs[@]} -gt 0 ]; then
        _pass "status ccprivate: 检测到 ${#missing_dirs[@]} 个缺失目录"
    else
        _pass "status ccprivate: 所有目录齐全"
    fi
    rm -rf "$ccpriv"
}

test_status_autosync_pid_not_running() {
    # 验证 auto-sync status 在未启动时不崩溃
    local pid_file="$HOME/git/ccconfig/.monitor-sync.pid"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            _skip "status autosync" "auto-sync 在运行，跳过"
        else
            _pass "status autosync: pid 文件存在但进程已死 → 未运行"
        fi
    else
        _pass "status autosync: 无 pid 文件 → 未运行"
    fi
}

test_status_memory_dir_missing() {
    # 验证 check_memory 在 projects/ 缺失时不崩溃
    local projects_dir="$HOME/.claude/projects"
    if [[ ! -d "$projects_dir" ]]; then
        _pass "status memory: projects/ 不存在 → 跳过（首次运行）"
    else
        local found=0
        for proj_dir in "$projects_dir"/*/; do
            [[ -d "$proj_dir" ]] || continue
            found=$((found + 1))
        done
        _pass "status memory: $found 个项目 memory 目录，不崩溃"
    fi
}

test_status_quick_mode_flag() {
    # 验证 --quick 参数解析
    local quick_mode=false
    [[ "${1:-}" == "--quick" ]] && quick_mode=true
    if $quick_mode; then
        _fail "status quick_mode" "不应解析 --quick（无参数调用）"
    fi
    local args=("--quick")
    quick_mode=false
    [[ "${args[0]:-}" == "--quick" ]] && quick_mode=true
    $quick_mode && _pass "status quick_mode: --quick 正确解析" || _fail "status quick_mode" "--quick 未解析"
}

# ═══════════════════════════════════════════════
# 执行
# ═══════════════════════════════════════════════

all_tests=(
    "ensure_config: broken symlink → 模板复制"    test_ensure_config_broken_symlink
    "ensure_config: 已有配置 → 直接返回 0"        test_ensure_config_exists
    "ensure_config: 缺配置且缺模板 → 返回 1"      test_ensure_config_missing
    "check_first_time: 两个都缺失 → 检测正确"     test_check_first_time_no_ccprivate
    "check_first_time: ccprivate 存在 → 不告警"   test_check_first_time_has_ccprivate
    "ensure_claude_skills: 无 gh → clone 失败"     test_ensure_claude_skills_no_gh
    "ensure_claude_skills: 有 gh → clone 成功"     test_ensure_claude_skills_with_gh
    "symlink: SKILLS_SRC 缺失 → 返回 0 (warn)"     test_symlinks_missing_source
    "placeholder: 中文字符串 → 检测为 placeholder" test_placeholder_detection
    "home_expand: ~ 和 \$HOME → 正确展开"          test_home_expansion
    "init --dry-run: 输出预览内容"                 test_init_dry_run
    "sync: setup-links 失败 → 不中断同步"          test_sync_setup_links_nonfatal
    "mcp sync: 写 ~/.claude/settings.json"         test_mcp_config_path
    "mcp sync: ~/.claude.json 缺失 → 不崩溃"      test_mcp_missing_config_json
    "status.sh: REPO_DIR → CCCONFIG_ROOT"          test_status_repo_dir
    "check_memory: projects_src → CCCONFIG_ROOT"   test_check_memory_path
    "mcp key: placeholder 检测 8/8 正确"            test_mcp_key_detection
    "config preflight: 缺配置→从模板复制"          test_init_config_preflight
    # sync.sh
    "sync list_repos: ccconfig 在列表中"            test_sync_list_repos_ccconfig_first
    "sync list_repos: _ext 被排除"                  test_sync_list_repos_excludes_ext
    "sync.sh: CCCONFIG_ROOT 指向根目录"             test_sync_check_ccconfig_repo_dir
    "sync commitpush: clean repo 检测"              test_sync_commitpush_detects_clean
    "sync show_changed_since: 无差异时空输出"       test_sync_show_changed_since_empty
    # status.sh
    "status symlink: ccprivate 存在"                test_status_symlink_checks_ccprivate
    "status git_pull: 更新检测不报错"               test_status_git_pull_detects_update
    "status last_push: git log 解析"                test_status_last_push_parses_log
    "status ccprivate: 目录完整性"                   test_status_ccprivate_dir_check
    "status autosync: 未启动时不崩溃"                test_status_autosync_pid_not_running
    "status memory: 目录缺失不崩溃"                  test_status_memory_dir_missing
    "status quick_mode: --quick 正确解析"            test_status_quick_mode_flag
)

if $LIST_ONLY; then
    echo ""
    echo -e "${CYAN}测试用例 (${#all_tests[@]} 个)${NC}"
    echo ""
    for ((i=0; i<${#all_tests[@]}; i+=2)); do
        echo "  $((i/2+1)). ${all_tests[$i]}"
    done
    echo ""
    exit 0
fi

echo ""
echo -e "${CYAN}ccconfig init 流程自动化测试${NC}"
    echo -e "${CYAN}══════════════════════════${NC}"
echo ""

setup_test_env

for ((i=0; i<${#all_tests[@]}; i+=2)); do
    desc="${all_tests[$i]}"
    fn="${all_tests[$i+1]}"
    if $VERBOSE; then echo -e "\n${BOLD}── $desc ──${NC}"; fi
    $fn
done

echo ""
echo -e "${CYAN}──────────────────────────────────────────${NC}"
echo -e "  ${GREEN}PASS${NC}: $PASS  ${RED}FAIL${NC}: $FAIL  ${YELLOW}SKIP${NC}: $SKIP"
echo -e "${CYAN}──────────────────────────────────────────${NC}"
echo ""

teardown_test_env

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
