#!/bin/bash
# 模拟 3 轮全新环境 init.sh all，快速暴露流程中的错误
# 在隔离临时目录运行，mock 外部命令
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0

_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✅${NC} $1"; }
_fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}❌${NC} $1"; }

run_sim() {
    local round="$1"; shift
    local desc="$1"; shift
    echo ""
    echo -e "${CYAN}── Round $round: $desc ──${NC}"

    local TEST_HOME=$(mktemp -d)
    trap "rm -rf $TEST_HOME" RETURN

    export HOME="$TEST_HOME"
    mkdir -p "$HOME/git" "$HOME/.claude" "$HOME/.local/bin" "$HOME/.cache"

    local CCCONFIG_DIR
    CCCONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    cp -r "$CCCONFIG_DIR" "$HOME/git/ccconfig"
    export PATH="$HOME/.local/bin:$HOME/git/ccconfig:$PATH"

    # ── Mock 外部命令 ──
    mkdir -p "$HOME/.local/bin"
    for cmd in git gh npm npx claude curl systemctl inotifywait sudo uv uvx pip3 python3; do
        cat > "$HOME/.local/bin/$cmd" << "MOCK"
#!/bin/bash
case "$(basename $0)" in
    git)
        case "${1:-}" in
            clone) mkdir -p "${@: -1}/.git" 2>/dev/null; echo "mock: cloned" ;;
            pull) echo "Already up to date." ;;
            fetch) echo "mock: fetched" ;;
            -C) shift; echo "mock git output"; ;;
            *) echo "mock git output" ;;
        esac ;;
    pip3) echo "mock pip3: installed packages" ;;
    python3) /usr/bin/python3 "$@" 2>/dev/null || echo "mock python3" ;;
    uv) echo "uv 0.11.28" ;;
    uvx) echo "uvx 0.11.28" ;;
    node) echo "v22.23.1" ;;
    npm)
        case "${1:-}" in
            prefix) echo "$HOME/.local" ;;
            install) echo "mock: npm installed" ;;
            list) echo "mock: npm list" ;;
            *) echo "mock npm" ;;
        esac ;;
    npx) echo "mock: npx" ;;
    claude)
        case "${1:-}" in
            mcp) echo "mock: claude mcp" ;;
            plugin) echo "mockuser-skills" ;;
            --version) echo "2.0.0" ;;
            install) echo "mock: native binary installed" ;;
            *) echo "mock claude" ;;
        esac ;;
    gh)
        case "${1:-}" in
            auth) echo "mock: gh auth ok" ;;
            api) echo '{"login":"testuser","email":"test@example.com"}' ;;
            repo) echo "mock: gh repo" ;;
            *) echo "mock gh" ;;
        esac ;;
    curl) echo "mock curl output" ;;
    systemctl) echo "mock systemctl" ;;
    inotifywait) echo "mock inotifywait" ;;
    sudo) echo "mock sudo $*" ;;
    *) echo "mock $(basename $0)" ;;
esac
exit 0
MOCK
        chmod +x "$HOME/.local/bin/$cmd"
    done

    # ccprivate mock（init 流程需要）
    mkdir -p "$HOME/git/ccprivate"
    cat > "$HOME/git/ccprivate/setup.sh" << 'MOCK'
#!/bin/bash
# 真实创建 symlinks，不只是打印
mkdir -p ~/.claude
ln -sf ~/git/ccprivate/link/CLAUDE.md ~/CLAUDE.md 2>/dev/null || true
ln -sf ~/git/ccprivate/link/settings.json ~/.claude/settings.json 2>/dev/null || true
ln -sf ~/git/ccprivate/link/.config.json ~/.claude/.config.json 2>/dev/null || true
echo "--- 用户级链接 ---"
echo "  ~/CLAUDE.md: 已链接，跳过"
echo "  ~/.claude/settings.json: 已链接，跳过"
echo "  ~/.claude/.config.json: 已链接，跳过"
echo "--- Memory 链接 ---"
echo "  memory/-home-francis-git-ccconfig: 已链接，跳过"
echo "--- Conf 覆盖 ---"
exit 0
MOCK
    chmod +x "$HOME/git/ccprivate/setup.sh"

    # ccprivate link 目录（setup.sh 的源）
    mkdir -p "$HOME/git/ccprivate/link"
    echo '{"env":{}}' > "$HOME/git/ccprivate/link/settings.json"
    echo '{}' > "$HOME/git/ccprivate/link/.config.json"
    echo "# CLAUDE.md" > "$HOME/git/ccprivate/link/CLAUDE.md"

    # Memory
    mkdir -p "$HOME/.claude/projects/-home-francis-git/memory"
    echo "# MEMORY" > "$HOME/.claude/projects/-home-francis-git/memory/MEMORY.md"
    mkdir -p "$HOME/git/ccconfig/link/projects/-home-francis-git/memory"
    echo "# MEMORY" > "$HOME/git/ccconfig/link/projects/-home-francis-git/memory/MEMORY.md"

    # skill 仓库 mock
    mkdir -p "$HOME/git/skill/plugins"
    for s in f-diagram f-docx f-feishu f-logme f-pptx f-search f-xlsx f-syncpage f-skillcreat; do
        mkdir -p "$HOME/git/skill/plugins/$s"
    done
    mkdir -p "$HOME/git/skill/.git"

    # ── 创建 .example 模板及配置文件（模拟已编辑过）──
    local ccd="$HOME/git/ccconfig"
    if [[ "$1" == "with_configs" ]]; then
        echo '{"git":{"username":"testuser","email":"test@test.com"}}' > "$ccd/conftemp/ubuntu.json"
        echo '{"current":"deepseek","llms":{"deepseek":{"name":"DeepSeek","base_url":"https://api.deepseek.com","model":"deepseek-chat","key":"sk-test123","small_model":"deepseek-chat"}}}' > "$ccd/conftemp/llm.json"
        echo '{"mcp_servers":[]}' > "$ccd/conftemp/claude.json"
    fi

    cd "$ccd"

    # 执行
    echo "  → bash init.sh all"
    local out rc
    out=$(bash init.sh all 2>&1) || rc=$?
    rc=${rc:-0}

    # 判断结果
    if echo "$out" | grep -q "配置文件已从模板创建"; then
        echo "  → 命中 preflight（配置模板已创建）"
        if [[ "$1" == "with_configs" ]]; then
            _fail "$desc: 已有配置不应触发 preflight"
        else
            _pass "$desc: 缺配置→preflight 正确拦截"
        fi
    elif echo "$out" | grep -q "全部初始化完成"; then
        echo "  → 流程完成"
        if echo "$out" | grep -q "❌.*失败"; then
            _fail "$desc: 流程完成但有步骤失败"
            echo "$out" | grep -E "❌|失败" | head -5
        else
            _pass "$desc: 全部步骤成功"
        fi
    else
        echo "  → 异常退出 (rc=$rc)"
        echo "$out" | tail -20
        _fail "$desc: 异常退出"
    fi
}

# ═══ 3 轮模拟 ═══

# Round 1: 全新环境，无配置文件
run_sim 1 "全新环境无配置" "no_configs"

# Round 2: 配置文件已就绪（用户编辑过），第一次真正初始化
run_sim 2 "配置就绪首次初始化" "with_configs"

# Round 3: 再次初始化（幂等，所有组件已装）
run_sim 3 "二次初始化幂等" "with_configs"

echo ""
echo -e "${CYAN}──────────────────────────────────────────${NC}"
echo -e "  ${GREEN}PASS${NC}: $PASS  ${RED}FAIL${NC}: $FAIL"
echo -e "${CYAN}──────────────────────────────────────────${NC}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
