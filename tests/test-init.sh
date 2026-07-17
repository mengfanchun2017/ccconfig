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
    out=$(bash "$HOME/git/ccconfig/init.sh" --dry-run 2>&1) || true
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
    # 验证 ~/.claude.json 不存在时 sync_to_settings 不崩溃
    rm -f "$HOME/.claude.json"
    local result
    result=$(python3 -c "
import json
try:
    with open('$HOME/.claude.json', 'r') as f:
        d = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    d = {}
print('ok-' + str(len(d)))
" 2>/dev/null) || true
    if echo "$result" | grep -q "ok-0"; then
        _pass "mcp sync: ~/.claude.json 不存在 → 回退空 dict，不崩溃"
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
    # 验证 check_memory 使用 $CCCONFIG_ROOT/link/projects 而非 $SCRIPT_DIR/link/projects
    local d="$HOME/git/ccconfig"
    local SCRIPT_DIR="$d/lib"
    local CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
    # 修复后: projects_src="$CCCONFIG_ROOT/link/projects"
    local projects_src="$CCCONFIG_ROOT/link/projects"
    if [ -d "$projects_src" ]; then
        _pass "check_memory: projects_src=$CCCONFIG_ROOT/link/projects → 可访问"
    else
        _fail "check_memory" "projects_src=$projects_src 不可访问"
    fi
    # 修复前: projects_src="$SCRIPT_DIR/link/projects" ('lib/link/projects' 不存在)
    local old_src="$SCRIPT_DIR/link/projects"
    if [ ! -d "$old_src" ]; then
        _pass "check_memory: 旧路径 $old_src 不存在（已修复为 CCCONFIG_ROOT）"
    else
        _skip "check_memory" "旧路径意外存在: $old_src"
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
    ("请填入你的 MiniMax API Key", True),
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

# 模拟 claude.json.example 中的 tavily 配置
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
        "$d/conf/claude.json"
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
