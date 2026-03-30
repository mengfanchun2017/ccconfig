#!/bin/bash
# Claude Config - 状态检查与 Git 拉取
#
# 功能：
# 1. 自动从 GitHub 拉取最新配置
# 2. 检查符号链接状态（含 MEMORY.md）
# 3. 检查 auto-sync 状态
# 4. 显示最近 5 次推送记录
# 5. MCP 服务器真实调用测试
#
# 用途：每次启动终端时自动运行（通过 /etc/profile.d/ 或 ~/.bashrc）
#       以及通过 SessionStart hook 在 Claude 启动时运行

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========== Git 拉取 ==========
git_pull() {
    cd "$REPO_DIR"

    # 检查是否是 git 仓库
    if [ ! -d ".git" ]; then
        return 0
    fi

    # 尝试拉取
    if git fetch origin main 2>/dev/null; then
        local updates=$(git rev HEAD..origin/main 2>/dev/null | wc -l)
        if [ "$updates" -gt 0 ]; then
            echo -e "${CYAN}[config]${NC} 发现 $updates 个更新，正在拉取..."
            if git pull --rebase origin main 2>/dev/null; then
                echo -e "${GREEN}[config]${NC} ✅ 配置已更新"
            fi
        fi
    fi
}

# ========== 显示状态摘要 ==========
show_summary() {
    cd "$REPO_DIR"

    local issues=0

    # 检查符号链接
    if [ ! -L "$HOME/.claude/settings.json" ] || [ ! -e "$HOME/.claude/settings.json" ]; then
        issues=$((issues + 1))
    fi
    if [ ! -L "$HOME/CLAUDE.md" ] || [ ! -e "$HOME/CLAUDE.md" ]; then
        issues=$((issues + 1))
    fi

    # 检查 MEMORY.md 符号链接
    local memory_link="$HOME/.claude/projects/-home-francis-git/memory/MEMORY.md"
    if [ ! -L "$memory_link" ] || [ ! -e "$memory_link" ]; then
        issues=$((issues + 1))
    fi

    # 检查 auto-sync
    if ! pgrep -f "auto-sync.sh start" >/dev/null 2>&1; then
        issues=$((issues + 1))
    fi

    # 显示简短摘要
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}[config]${NC} ✅ 配置就绪"
    else
        echo -e "${YELLOW}[config]${NC} ⚠️  有 $issues 个配置问题，运行 ${CYAN}bash $REPO_DIR/init.sh status${NC} 查看"
    fi
}

# ========== 显示最近推送记录 ==========
show_recent_pushes() {
    cd "$REPO_DIR"

    # 检查是否是 git 仓库
    if [ ! -d ".git" ]; then
        return 0
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[config]${NC} 📋 最近推送记录："

    # 获取最近5次推送的 note（第一条行是 commit hash，第二行是 message）
    local count=0
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            echo -e "  ${YELLOW}•${NC} $line"
            count=$((count + 1))
        fi
        if [ $count -ge 5 ]; then
            break
        fi
    done < <(git log --oneline -10 --format="%s" 2>/dev/null | head -5)
}

# ========== MCP 服务器真实测试 ==========
test_mcp_servers() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[config]${NC} 🔧 MCP 服务器测试："

    local claude_json="$HOME/.claude.json"

    if [ ! -f "$claude_json" ]; then
        echo -e "  ${YELLOW}⚠️  ~/.claude.json 不存在${NC}"
        return
    fi

    # 读取 MCP 配置
    python3 - "$claude_json" << 'PYEOF' 2>/dev/null
import json
import sys
import subprocess
import os
import time

def test_mcp_server(name, config, env_vars):
    """测试单个 MCP 服务器"""
    try:
        cmd = config.get('command')
        args = config.get('args', [])
        full_cmd = [cmd] + args

        # 构建环境变量
        env = os.environ.copy()
        for k, v in env_vars.items():
            env[k] = v

        # 发送初始化请求
        init_request = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "test", "version": "1.0"}
            }
        }

        # 发送 tools/list 请求
        list_request = {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": {}
        }

        input_data = json.dumps(init_request) + "\n" + json.dumps(list_request) + "\n"

        proc = subprocess.Popen(
            full_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True
        )

        stdout, stderr = proc.communicate(input=input_data, timeout=15)

        # 解析响应
        lines = stdout.strip().split("\n")
        for line in lines:
            if line:
                try:
                    resp = json.loads(line)
                    if resp.get("id") == 1 and "result" in resp:
                        server_info = resp["result"].get("serverInfo", {})
                        version = server_info.get("version", "?")
                        return f"✅ {version}", None
                except:
                    pass

        # 如果没有找到有效的初始化响应
        if stderr and "Error" in stderr:
            return None, stderr[:100]
        return "✅ (无版本信息)", None

    except subprocess.TimeoutExpired:
        proc.kill()
        return None, "超时"
    except FileNotFoundError:
        return None, f"命令未找到: {cmd}"
    except Exception as e:
        return None, str(e)[:100]

# 读取配置
with open(sys.argv[1], 'r') as f:
    data = json.load(f)

mcp_servers = data.get('mcpServers', {})

for name, config in sorted(mcp_servers.items()):
    if not config.get('command'):
        continue

    # 从配置的 env 字段获取环境变量
    env_vars = config.get('env', {})

    result, error = test_mcp_server(name, config, env_vars)

    if result:
        print(f"  {name}: {result}")
    else:
        print(f"  {name}: ❌ {error}")
PYEOF
}

# 执行
git_pull
show_summary
show_recent_pushes
test_mcp_servers
