#!/bin/bash
# Claude Config - 状态检查
#
# 检查项：
# 1. 配置文件符号链接
# 2. 核心依赖
# 3. auto-sync 状态
# 4. GitHub 最后推送
# 5. MEMORY 最后更新
# 6. ppt-master PPT 生成环境
# 7. 飞书 lark-cli 状态
# 8. Vessel AI 浏览器
# 9. OfficeCLI 状态
# 10. MCP 服务器状态
# 11. 远程连接状态 (Tailscale + SSH)
# 12. option-* 可选组件
# 13. .wslconfig 同步状态
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
    if [ ! -d "$REPO_DIR/.git" ]; then
        return 0
    fi
    if timeout 30 git -C "$REPO_DIR" fetch origin main 2>/dev/null; then
        local updates=$(git -C "$REPO_DIR" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
        if [ "$updates" -gt 0 ]; then
            echo -e "${CYAN}[Git]${NC} 发现 $updates 个更新，正在拉取..."
            timeout 30 git -C "$REPO_DIR" pull --rebase origin main 2>/dev/null
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
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        echo -e "  ${GREEN}配置链接就绪${NC}"
    else
        echo -e "  ${GRAY}自动修复中...${NC}"
        if bash "$REPO_DIR/setup-links.sh" 2>/dev/null; then
            echo -e "  ${GREEN}✅ 配置链接已自动修复${NC}"
        else
            echo -e "  ${RED}❌ 自动修复失败，手动执行: bash ccconfig/setup-links.sh${NC}"
        fi
    fi
}

# ========== 3. 检查 auto-sync ==========
check_autosync() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[3] auto-sync${NC}"

    if [ -x "$REPO_DIR/monitor.sh" ]; then
        bash "$REPO_DIR/monitor.sh" status 2>/dev/null
    else
        echo -e "  ${RED}❌${NC} monitor.sh 不存在"
    fi
}

# ========== 4. GitHub 最后推送 ==========
check_last_push() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[4] 最后推送${NC}"

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

# ========== 5. MEMORY 最后更新 ==========
check_memory() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[5] MEMORY 更新${NC}"

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

# ========== 6. ppt-master 状态 ==========
check_ppt_master() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[6] ppt-master (PPT 生成)${NC}"

    local repo_dir="$HOME/git/_ext/ppt-master"
    local ok=true

    # 仓库
    if [[ -d "$repo_dir/.git" ]]; then
        echo -e "  ${GREEN}✅${NC} 仓库已克隆"
    else
        echo -e "  ${RED}❌${NC} 仓库未克隆: $repo_dir"
        ok=false
    fi

    # python-pptx
    if python3 -c "import pptx" 2>/dev/null; then
        local ver=$(python3 -c "import pptx; print(pptx.__version__)" 2>/dev/null)
        echo -e "  ${GREEN}✅${NC} python-pptx $ver"
    else
        echo -e "  ${RED}❌${NC} python-pptx 未安装"
        ok=false
    fi

    # cairosvg
    if python3 -c "import cairosvg" 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} cairosvg 已安装"
    else
        echo -e "  ${RED}❌${NC} cairosvg 未安装"
        ok=false
    fi

    if $ok; then
        echo -e "  ${GREEN}PPT 生成环境就绪${NC}"
    else
        echo -e "  ${YELLOW}修复: bash ccconfig/option-ppt-master/init.sh --install${NC}"
    fi
}

# ========== 8. Vessel AI 浏览器（可选） ==========
check_vessel() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[8] Vessel AI 浏览器 [option]${NC}"

    local vessel_bin="$HOME/.local/bin/vessel"
    local vessel_dir="$HOME/.local/lib/vessel/squashfs-root/vessel"

    echo -n "  安装 ... "
    if [ -x "$vessel_bin" ] || [ -f "$vessel_dir" ]; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${GRAY}－${NC} (未安装)"
    fi

    echo -n "  进程 ... "
    if pgrep -f "squashfs-root/vessel|vessel.*AppImage" > /dev/null 2>&1; then
        local pid=$(pgrep -f "squashfs-root/vessel" | head -1)
        echo -e "${GREEN}✅${NC} 运行中 (PID: $pid)"
    else
        echo -e "${YELLOW}○${NC} 未运行"
    fi

    echo -n "  Token ... "
    local auth_file="$HOME/.config/vessel/mcp-auth.json"
    if [ -f "$auth_file" ]; then
        local token=$(python3 -c "import json; print(json.load(open('$auth_file'))['token'])" 2>/dev/null)
        if [ -n "$token" ]; then
            echo -e "${GREEN}✅${NC} ${token:0:16}..."
        else
            echo -e "${YELLOW}○${NC} 解析失败"
        fi
    else
        echo -e "${YELLOW}○${NC} 未生成"
    fi

    echo -n "  MCP (端口 3100) ... "
    if curl -s --max-time 2 "http://localhost:3100/mcp" 2>/dev/null | grep -q "Unauthorized\|bearer"; then
        echo -e "${GREEN}✅${NC} 已监听"
    else
        echo -e "${GRAY}－${NC} 未监听"
    fi

    echo -n "  MCP 注册 ... "
    if grep -q '"vessel"' "$HOME/.claude/.config.json" 2>/dev/null; then
        echo -e "${GREEN}✅${NC} 已注册"
    else
        echo -e "${YELLOW}○${NC} 未注册"
    fi

    echo -e "  ${GRAY}安装: bash ccconfig/option-vessel/init.sh${NC}"
}

# ========== 10. MCP 服务器状态 ==========
check_mcp() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[10] MCP 服务器${NC}"

    local claude_json="$HOME/.claude/.config.json"

    if [ ! -f "$claude_json" ]; then
        echo -e "  ${RED}❌${NC} .config.json 不存在"
        return
    fi

    # 24h 内已检查过则跳过（避免每次 SessionStart 都测试 MCP 增加启动延迟）
    local mcp_stamp="$HOME/.cache/ccconfig-mcp-check.stamp"
    if [ -f "$mcp_stamp" ] && [ "$(find "$mcp_stamp" -mmin -1440 2>/dev/null)" ]; then
        echo -e "  ${GRAY}... 24h 内已检查，跳过（删除 $mcp_stamp 强制刷新）${NC}"
        return
    fi

    # 读取 MCP 配置并测试（并行，总超时约 5 秒）
    local mcp_output
    mcp_output=$(python3 - "$claude_json" << 'PYEOF' 2>/dev/null
import json, sys, subprocess, os
from concurrent.futures import ThreadPoolExecutor, as_completed

def test_mcp(name, config):
    try:
        # HTTP 类型 MCP（vessel 等）无 command 字段，单独标记不视为错误
        if config.get('type') == 'http':
            url = config.get('url', '?')
            return name, f"✅ http ({url})", None
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
    print("STATUS=ok")
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

# bash 端根据 STATUS= 决定是否写 24h 缓存 stamp
if any(error for _, error in results.values()):
    print("STATUS=fail")
else:
    print("STATUS=ok")
PYEOF
)
    echo "$mcp_output" | grep -v "^STATUS="

    mkdir -p "$HOME/.cache"
    if echo "$mcp_output" | grep -q "^STATUS=fail"; then
        rm -f "$mcp_stamp"
        echo "⚠ MCP 检查有失败，24h 缓存禁用，下次 SessionStart 重试" >&2
    else
        touch "$mcp_stamp"
    fi
}

# ========== 7. 飞书 lark-cli 状态（可选） ==========
check_feishu() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[7] 飞书 (lark-cli) [option]${NC}"

    export PATH="$HOME/.local/bin:$(find_node_bin):$PATH"

    # 当前账号
    local current_name=""
    local current_dir
    local marker_file="$HOME/.lark-cli-account"
    if [ -f "$marker_file" ]; then
        current_name=$(grep '^name=' "$marker_file" 2>/dev/null | cut -d'=' -f2)
        current_dir=$(grep '^configDir=' "$marker_file" 2>/dev/null | cut -d'=' -f2)
    fi
    current_dir="${current_dir:-${LARKSUITE_CLI_CONFIG_DIR:-$HOME/.lark-cli}}"
    current_dir="$(eval echo "$current_dir")"

    # 检查安装
    echo -n "  安装 ... "
    if command -v lark-cli &> /dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${GRAY}－${NC} (未安装)"
    fi

    # 当前账号别名
    if [ -n "$current_name" ]; then
        echo -e "  当前账号: ${GREEN}${current_name}${NC} ${GRAY}(${current_dir})${NC}"
    else
        echo -e "  当前账号: ${YELLOW}未匹配${NC} ${GRAY}(${current_dir})${NC}"
    fi

    # 检查配置
    if command -v lark-cli &> /dev/null; then
        echo -n "  配置 ... "
        if lark-cli config show 2>/dev/null | grep -q "appId"; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${YELLOW}○${NC} 未配置"
        fi

        # 检查授权
        echo -n "  授权 ... "
        if lark-cli config show 2>/dev/null | grep -q "users"; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${YELLOW}○${NC} 未授权"
        fi
    fi

    # 列出所有已配置账号
    local feishu_json="$REPO_DIR/conf/feishu.json"
    if [ -f "$feishu_json" ]; then
        local accounts_info
        accounts_info=$(python3 - "$feishu_json" "$current_name" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
current = sys.argv[2]
apps = data.get('apps', [])
if not apps:
    sys.exit(0)
for app in apps:
    lark = app.get('larkCli', {})
    if lark.get('enabled'):
        name = app.get('name', '?')
        marker = '▶' if name == current else ' '
        cfg = lark.get('configDir', '~/.lark-cli')
        print(f"    {marker} {name}  {cfg}")
PYEOF
        )
        if [ -n "$accounts_info" ]; then
            echo -e "  账号列表:"
            echo "$accounts_info"
        fi
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
    if [ -f "$feishu_json" ]; then
        local total enabled_count
        total=$(python3 -c "import json; d=json.load(open('$feishu_json')); print(len(d.get('apps',[])))" 2>/dev/null || echo "?")
        enabled_count=$(python3 -c "import json; d=json.load(open('$feishu_json')); print(sum(1 for a in d.get('apps',[]) if a.get('ccConnect',{}).get('enabled')))" 2>/dev/null || echo "?")
        echo -e "  机器人: ${enabled_count}/${total} 启用 (cconnect)"
    fi
    echo -e "  ${GRAY}切换账号: bash ccconfig/option-bridge/lark-switch.sh <name>${NC}"
    echo -e "  ${GRAY}安装/启动: bash ccconfig/option-bridge/init.sh --cc-connect${NC}"
}

# ========== 11. 远程连接状态 ==========
check_remote() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[11] 远程连接 (SSH + Tailscale)${NC}"

    local ssh_ok=false
    local ssh_fix=""

    # SSH 配置
    local ssh_port
    ssh_port=$(grep -oP '^Port \K[0-9]+' /etc/ssh/sshd_config 2>/dev/null || echo "22")

    # SSH socket 状态
    local socket_active=$(systemctl is-active ssh.socket 2>/dev/null)
    local socket_failed=false
    local portproxy_conflict=false
    if [ "$socket_active" = "active" ]; then
        echo -e "  SSH (端口 $ssh_port) ... ${GREEN}✅${NC} 运行中"
        ssh_ok=true
    elif systemctl is-enabled ssh.socket &>/dev/null 2>&1; then
        if [ "$socket_active" = "failed" ]; then
            socket_failed=true
            # 诊断：检查是否被 Windows 进程占用
            local netstat_out
            netstat_out=$(/mnt/c/Windows/System32/netstat.exe -ano 2>/dev/null | grep ":$ssh_port ")
            if [ -n "$netstat_out" ]; then
                local win_pid
                win_pid=$(echo "$netstat_out" | awk '{print $NF}' | tr -d '\r')
                local proc_name
                proc_name=$(/mnt/c/Windows/System32/tasklist.exe 2>/dev/null | grep -E "^[^ ]+[ ]+$win_pid " | head -1 | awk '{print $1}')
                portproxy_conflict=true
                if [ "$proc_name" = "svchost.exe" ]; then
                    echo -e "  SSH (端口 $ssh_port) ... ${RED}❌${NC} 端口被 Windows iphlpsvc 占用"
                elif [ -n "$proc_name" ]; then
                    echo -e "  SSH (端口 $ssh_port) ... ${RED}❌${NC} 端口被 Windows $proc_name 占用"
                else
                    echo -e "  SSH (端口 $ssh_port) ... ${RED}❌${NC} 端口被 Windows PID $win_pid 占用"
                fi
            else
                echo -e "  SSH (端口 $ssh_port) ... ${YELLOW}○${NC} 启动失败（瞬态端口冲突）"
            fi
        else
            echo -e "  SSH (端口 $ssh_port) ... ${YELLOW}○${NC} 已配置但未启动"
        fi
    else
        echo -e "  SSH ... ${GRAY}－${NC} 未安装"
    fi

    # 端口冲突诊断
    if [ "$portproxy_conflict" = true ]; then
        local proxy_rule
        proxy_rule=$(/mnt/c/Windows/System32/netsh.exe interface portproxy show all 2>/dev/null | grep ":$ssh_port" || echo "")
        echo -e "    ${GRAY}原因: mirrored 模式下残留 portproxy 规则${NC}"
        if [ -n "$proxy_rule" ]; then
            echo -e "    ${GRAY}$proxy_rule${NC}"
        fi
        echo -e "    ${GRAY}修复 (Win 管理员 PS): netsh interface portproxy delete v4tov4 listenport=$ssh_port listenaddress=0.0.0.0${NC}"
        echo -e "    ${GRAY}修复 (WSL):           sudo systemctl reset-failed ssh.socket && sudo systemctl start ssh.socket${NC}"
        ssh_fix="先删除 Windows portproxy 规则，再 sudo systemctl reset-failed ssh.socket && sudo systemctl start ssh.socket"
    elif [ "$socket_failed" = true ]; then
        ssh_fix="sudo systemctl reset-failed ssh.socket && sudo systemctl start ssh.socket"
    elif [ -z "$ssh_fix" ]; then
        ssh_fix="sudo systemctl start ssh.socket"
    fi

    # 端口检查
    echo -n "  端口 $ssh_port ... "
    if ss -tlnp 2>/dev/null | grep -q ":$ssh_port "; then
        echo -e "${GREEN}✅${NC} 已监听"
    elif [ "$portproxy_conflict" = true ]; then
        echo -e "${RED}❌${NC} 被 Windows 占用"
    elif [ "$socket_failed" = true ]; then
        echo -e "${YELLOW}○${NC} 需重置 socket"
    elif [ -n "$ssh_fix" ] && [ "$ssh_fix" != "bash ccconfig/remote/server/tmux-sshd.sh" ]; then
        echo -e "${YELLOW}○${NC} $ssh_fix"
    else
        echo -e "${YELLOW}○${NC} 未监听"
    fi

    # WSL 网络模式
    local win_user
    win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "$USER")
    local wslconfig="/mnt/c/Users/${win_user}/.wslconfig"
    echo -n "  网络模式 ... "
    if [ -f "$wslconfig" ] && grep -q "networkingMode=mirrored" "$wslconfig" 2>/dev/null; then
        echo -e "${GREEN}✅${NC} mirrored"
    else
        echo -e "${YELLOW}○${NC} 非 mirrored（mirrored 模式下无需端口转发）"
    fi

    # Tailscale (Windows 侧)
    local ts_exe="/mnt/c/Program Files/Tailscale/tailscale.exe"
    echo -n "  Tailscale ... "
    if [ -f "$ts_exe" ]; then
        local ts_ip
        ts_ip=$("$ts_exe" ip -4 2>/dev/null || echo "")
        if [ -n "$ts_ip" ]; then
            echo -e "${GREEN}✅${NC} $ts_ip"
        else
            echo -e "${YELLOW}○${NC} 未登录或无网络"
        fi
    else
        echo -e "${GRAY}－${NC} 未安装"
    fi

    echo -n "  远程可用 ... "
    if [ "$ssh_ok" = true ] && ss -tlnp 2>/dev/null | grep -q ":$ssh_port "; then
        echo -e "${GREEN}✅${NC} ssh $USER@<Tailscale IP> -p $ssh_port"
    elif [ -n "$ssh_fix" ]; then
        echo -e "${YELLOW}○${NC} $ssh_fix"
    else
        echo -e "${GRAY}－${NC}"
    fi
}

# ========== 2. 依赖检查 ==========
check_deps_quick() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[2] 核心依赖${NC}"

    local deps_script="$REPO_DIR/deps-check.sh"
    if [ -x "$deps_script" ]; then
        bash "$deps_script" --required 2>/dev/null
    else
        echo -e "  ${YELLOW}○${NC} deps-check.sh 不存在"
    fi
}

# ========== 12. option-* 组件自动发现 ==========
check_option_components() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[12] option-* 可选组件${NC}"

    local found=0
    for opt_dir in "$REPO_DIR"/option-*/; do
        [ -d "$opt_dir" ] || continue
        local name=$(basename "$opt_dir")
        local init_script="$opt_dir/init.sh"

        found=$((found + 1))
        echo -n "  $name ... "
        if [ ! -f "$init_script" ]; then
            echo -e "${YELLOW}○${NC} (无 init.sh)"
            continue
        fi
        local out
        out=$(bash "$init_script" --status 2>&1)
        local status_exit=$?
        local first_line=$(echo "$out" | head -1 | sed 's/[[:space:]]*$//')
        if [ $status_exit -ne 0 ] || [ -z "$first_line" ]; then
            echo -e "${GRAY}－${NC} (无 --status 支持)"
        elif echo "$first_line" | grep -qi "^OK\|^✅\|^ready"; then
            echo -e "${GREEN}✅${NC} $first_line"
        elif echo "$first_line" | grep -qi "^FAIL\|^❌\|^error"; then
            echo -e "${RED}❌${NC} $first_line"
        else
            # 单行 OK/FAIL 规约未遵循，原样显示
            echo -e "${GRAY}－${NC} $first_line"
        fi
    done

    if [ $found -eq 0 ]; then
        echo -e "  ${GRAY}(无可选组件)${NC}"
    fi
}

# ========== 9. OfficeCLI 状态 ==========
check_officecli() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[9] OfficeCLI [option]${NC}"

    local officecli_bin="$HOME/.local/bin/officecli"

    echo -n "  安装 ... "
    if [ -x "$officecli_bin" ]; then
        local ver=$("$officecli_bin" --version 2>/dev/null)
        echo -e "${GREEN}✅${NC} $ver"
    else
        echo -e "${GRAY}－${NC} (未安装)"
    fi

    echo -n "  MCP 注册 ... "
    if [ -x "$officecli_bin" ] && "$officecli_bin" mcp list 2>/dev/null | grep -q "Claude"; then
        echo -e "${GREEN}✅${NC}"
    elif [ -x "$officecli_bin" ]; then
        echo -e "${YELLOW}○${NC} 未注册"
    else
        echo -e "${GRAY}－${NC}"
    fi

    echo -e "  ${GRAY}安装: bash ccconfig/option-officecli/init.sh${NC}"
}

# ========== 13. .wslconfig 同步检查 ==========
check_wslconfig() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[13] .wslconfig 同步${NC}"

    local ps1="$REPO_DIR/windows-tools/wslconfig.ps1"
    if [ ! -f "$ps1" ]; then
        echo -e "  ${GRAY}－${NC} ccconfig 无 wslconfig.ps1 源"
        return
    fi

    # 从 ps1 提取 here-string 期望内容（@" ... "@ 之间）
    local expected
    expected=$(awk '/^\$content = @"/{flag=1;next} /^"@/{flag=0} flag' "$ps1")
    if [ -z "$expected" ]; then
        echo -e "  ${YELLOW}○${NC} 解析 wslconfig.ps1 失败"
        return
    fi

    local win_user
    win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "$USER")
    local wslconfig="/mnt/c/Users/${win_user}/.wslconfig"

    if [ ! -f "$wslconfig" ]; then
        echo -e "  ${RED}❌${NC} $wslconfig 不存在"
        echo -e "  ${GRAY}修复: powershell.exe -ExecutionPolicy Bypass -File \"\$(wslpath -w ccconfig/windows-tools/wslconfig.ps1)\" && wsl.exe --shutdown${NC}"
        return
    fi

    # 标准化对比（去除 CRLF + 尾空白）
    local actual_norm expected_norm
    actual_norm=$(tr -d '\r' < "$wslconfig" | sed 's/[[:space:]]*$//')
    expected_norm=$(printf '%s\n' "$expected" | sed 's/[[:space:]]*$//')

    if [ "$actual_norm" = "$expected_norm" ]; then
        echo -e "  ${GREEN}✅${NC} 与 ccconfig 源一致"
        # 显示关键字段提示
        local auto_proxy
        auto_proxy=$(grep -oP '^autoProxy=\K\w+' "$wslconfig" 2>/dev/null)
        echo -e "  ${GRAY}autoProxy=${auto_proxy:-?}, 切代理不弹窗${NC}"
    else
        echo -e "  ${RED}❌${NC} 落后于 ccconfig 源"
        echo -e "  ${GRAY}差异 (期望 < / 实际 >):${NC}"
        diff <(echo "$expected_norm") <(echo "$actual_norm") | sed 's/^/    /' | head -10
        echo -e "  ${YELLOW}修复: powershell.exe -ExecutionPolicy Bypass -File \"\$(wslpath -w ccconfig/windows-tools/wslconfig.ps1)\" && wsl.exe --shutdown${NC}"
        echo -e "  ${GRAY}(wsl --shutdown 后重开 WSL 终端生效；已运行 session 不会热更新)${NC}"
    fi
}

# ========== 执行所有检查 ==========

echo ""
echo -e "${GREEN}=== Claude Config 状态检查 ===${NC}"
echo ""

git_pull
check_symlinks
check_deps_quick
check_autosync
check_last_push
check_memory
check_ppt_master
check_feishu
check_vessel
check_officecli
check_mcp
check_remote
check_option_components
check_wslconfig

echo ""
