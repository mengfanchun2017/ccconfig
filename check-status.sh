#!/bin/bash
# Claude Config - 状态检查
#
# 检查项：
# 1. 配置文件符号链接
# 2. auto-sync 状态
# 3. GitHub 最后推送
# 4. MEMORY 最后更新
# 5. MCP 服务器状态
#
# 用途：通过 SessionStart hook 在 Claude 启动时运行

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/path-helper.sh"
REPO_DIR="$SCRIPT_DIR"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# ========== Git 拉取 ==========
git_pull() {
    cd "$REPO_DIR"
    if [ ! -d ".git" ]; then
        return 0
    fi
    if git fetch origin main 2>/dev/null; then
        local updates=$(git rev HEAD..origin/main 2>/dev/null | wc -l)
        if [ "$updates" -gt 0 ]; then
            echo -e "${CYAN}[Git]${NC} 发现 $updates 个更新，正在拉取..."
            git pull --rebase origin main 2>/dev/null
        fi
    fi
}

# ========== 1. 检查符号链接 ==========
check_symlinks() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[1] 配置文件链接${NC}"

    local issues=0

    # settings.json
    if [ -L "$HOME/.claude/settings.json" ] && [ -e "$HOME/.claude/settings.json" ]; then
        echo -e "  ${GREEN}✅${NC} settings.json"
    else
        echo -e "  ${RED}❌${NC} settings.json"
        issues=$((issues + 1))
    fi

    # .config.json
    if [ -L "$HOME/.claude/.config.json" ] && [ -e "$HOME/.claude/.config.json" ]; then
        echo -e "  ${GREEN}✅${NC} .config.json"
    else
        echo -e "  ${RED}❌${NC} .config.json"
        issues=$((issues + 1))
    fi

    # CLAUDE.md
    if [ -L "$HOME/CLAUDE.md" ] && [ -e "$HOME/CLAUDE.md" ]; then
        echo -e "  ${GREEN}✅${NC} CLAUDE.md"
    else
        echo -e "  ${RED}❌${NC} CLAUDE.md"
        issues=$((issues + 1))
    fi

    # MEMORY.md (memory/ dir is symlink, MEMORY.md is inside it)
    local memory_dir="$HOME/.claude/projects/-home-francis-git/memory"
    local memory_file="$memory_dir/MEMORY.md"
    if [ -L "$memory_dir" ] && [ -f "$memory_file" ]; then
        echo -e "  ${GREEN}✅${NC} MEMORY.md"
    elif [ -L "$memory_file" ] && [ -e "$memory_file" ]; then
        echo -e "  ${GREEN}✅${NC} MEMORY.md"
    else
        echo -e "  ${RED}❌${NC} MEMORY.md"
        issues=$((issues + 1))
    fi

    # rules (条件规则)
    if [ -L "$HOME/.claude/rules" ] && [ -d "$HOME/.claude/rules" ]; then
        local rule_count=$(ls "$HOME/.claude/rules/"*.md 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✅${NC} rules ($rule_count 个)"
    else
        echo -e "  ${YELLOW}○${NC} rules (未链接)"
    fi

    # commands (自定义命令)
    if [ -L "$HOME/.claude/commands" ] && [ -d "$HOME/.claude/commands" ]; then
        local cmd_count=$(ls "$HOME/.claude/commands/"*.md 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✅${NC} commands ($cmd_count 个)"
    else
        echo -e "  ${YELLOW}○${NC} commands (未链接)"
    fi

    if [ $issues -eq 0 ]; then
        echo -e "  ${GREEN}配置链接就绪${NC}"
    fi
}

# ========== 2. 检查 auto-sync ==========
check_autosync() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[2] auto-sync${NC}"

    local pid_file="$REPO_DIR/.monitor-sync.pid"
    local service_file="$HOME/.config/systemd/user/claude-auto-sync.service"

    # 检查进程
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} 进程运行中 (PID: $(cat "$pid_file"))"
    else
        echo -e "  ${RED}❌${NC} 进程未运行"
    fi

    # 检查自启动
    if [ -f "$service_file" ]; then
        echo -e "  ${GREEN}✅${NC} systemd 自启动已配置"
    else
        echo -e "  ${RED}❌${NC} systemd 自启动未配置"
    fi
}

# ========== 3. GitHub 最后推送 ==========
check_last_push() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[3] 最后推送${NC}"

    cd "$REPO_DIR"
    if [ ! -d ".git" ]; then
        echo -e "  ${YELLOW}⚠️${NC} 非 Git 仓库"
        return
    fi

    # 获取最后一次提交的日期和消息
    local log=$(git log -1 --format="%ci|%s" 2>/dev/null)
    if [ -n "$log" ]; then
        local date=$(echo "$log" | cut -d'|' -f1 | cut -d' ' -f1)
        local msg=$(echo "$log" | cut -d'|' -f2-)
        echo -e "  📅 $date"
        echo -e "  📝 $msg"
    else
        echo -e "  ${YELLOW}⚠️${NC} 无提交记录"
    fi
}

# ========== 4. MEMORY 最后更新 ==========
check_memory() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[4] MEMORY 更新${NC}"

    # 使用 -L 跟随符号链接，读取目标文件的真实修改时间
    local memory_file="$HOME/.claude/projects/-home-francis-git/memory/MEMORY.md"
    if [ -f "$memory_file" ]; then
        local mtime=$(stat -L -c %y "$memory_file" 2>/dev/null | cut -d'.' -f1)
        local size=$(stat -L -c %s "$memory_file" 2>/dev/null)
        echo -e "  📅 $mtime ($size bytes)"
    else
        echo -e "  ${RED}❌${NC} MEMORY.md 不存在"
    fi
}

# ========== 5. MCP 服务器状态 (编号 7) ==========
check_mcp() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[7] MCP 服务器${NC}"

    local claude_json="$HOME/.claude/.config.json"

    if [ ! -f "$claude_json" ]; then
        echo -e "  ${RED}❌${NC} .config.json 不存在"
        return
    fi

    # 读取 MCP 配置并测试（并行，总超时约 5 秒）
    python3 - "$claude_json" << 'PYEOF' 2>/dev/null
import json, sys, subprocess, os
from concurrent.futures import ThreadPoolExecutor, as_completed

def test_mcp(name, config):
    try:
        cmd = config.get('command')
        args = config.get('args', [])
        if not cmd:
            return name, None, "无命令"
        full_cmd = [cmd] + args if args else [cmd]
        env = os.environ.copy()
        env.update(config.get('env', {}))
        init_req = json.dumps({
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "test", "version": "1.0"}}
        })
        list_req = json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        proc = subprocess.Popen(full_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True)
        stdout, _ = proc.communicate(input=f"{init_req}\n{list_req}\n", timeout=5)
        for line in stdout.strip().split("\n"):
            if line:
                try:
                    resp = json.loads(line)
                    if resp.get("id") == 1 and "result" in resp:
                        ver = resp["result"].get("serverInfo", {}).get("version", "?")
                        return name, f"✅ {ver}", None
                except: pass
        return name, "✅ (无版本)", None
    except subprocess.TimeoutExpired:
        return name, None, "超时"
    except FileNotFoundError:
        return name, None, "命令未找到"
    except Exception as e:
        return name, None, str(e)[:50]

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

mcps = data.get('mcpServers', {})
if not mcps:
    print("  (无 MCP 配置)")
    sys.exit(0)

# 并行测试所有 MCP 服务器
results = {}
with ThreadPoolExecutor(max_workers=len(mcps)) as ex:
    futures = {ex.submit(test_mcp, name, config): name for name, config in mcps.items()}
    for future in as_completed(futures):
        name, result, error = future.result()
        results[name] = (result, error)

for name in sorted(results):
    result, error = results[name]
    if result:
        print(f"  {name}: {result}")
    else:
        print(f"  {name}: ❌ {error}")
PYEOF
}

# ========== 6. 飞书 lark-cli 状态 ==========
check_feishu() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[6] 飞书 (lark-cli)${NC}"

    export PATH="$HOME/.local/bin:$(find_node_bin):$PATH"

    # 检查安装
    echo -n "  安装 ... "
    if command -v lark-cli &> /dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌${NC}"
    fi

    # 检查配置
    echo -n "  配置 ... "
    if lark-cli config show 2>/dev/null | grep -q "appId"; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌${NC}"
    fi

    # 检查授权
    echo -n "  授权 ... "
    if lark-cli config show 2>/dev/null | grep -q "users"; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${YELLOW}○${NC} 未授权"
    fi

    # cc-connect Bridge 状态
    echo -n "  Bridge ... "
    if command -v cc-connect &> /dev/null; then
        if systemctl --user is-active cc-connect.service &>/dev/null 2>&1; then
            echo -e "${GREEN}✅${NC} (systemd 运行中)"
        elif pgrep -f "cc-connect" > /dev/null 2>&1; then
            echo -e "${GREEN}✅${NC} (进程运行中)"
        else
            echo -e "${YELLOW}○${NC} (未运行)"
        fi
    else
        echo -e "${GRAY}－${NC} (未安装)"
    fi
    # cconnect 机器人数量（无论二进制是否安装都检查配置）
    local feishu_json="$REPO_DIR/conf/feishu.json"
    if [ -f "$feishu_json" ]; then
        local total enabled_count
        total=$(python3 -c "import json; d=json.load(open('$feishu_json')); print(len(d.get('apps',[])))" 2>/dev/null || echo "?")
        enabled_count=$(python3 -c "import json; d=json.load(open('$feishu_json')); print(sum(1 for a in d.get('apps',[]) if a.get('ccConnect',{}).get('enabled')))" 2>/dev/null || echo "?")
        echo -e "  机器人: ${enabled_count}/${total} 启用 (cconnect)"
    fi
}

# ========== 执行所有检查 ==========
echo ""
echo -e "${GREEN}=== Claude Config 状态检查 ===${NC}"
echo ""

git_pull
check_symlinks
check_autosync
check_last_push
check_memory
check_feishu
check_mcp

echo ""
