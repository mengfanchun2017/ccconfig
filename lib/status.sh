#!/bin/bash
# Claude Config - 状态检查
#
# 检查项：
# 1. 配置文件符号链接
# 2. 核心依赖
# 3. auto-sync 状态
# 4. GitHub 最后推送
# 5. MEMORY（~/.claude/projects/ 直查）
# 6. Git 项目状态
# 7. 飞书 lark-cli 状态
# 8. Playwright 浏览器测试
# 9. MCP 服务器状态
# 10. option-* 可选组件（含远程连接 SSH/Tailscale）
# 11. Skills 安装状态
# 12. Example 模板同步
#
# 用途：通过 SessionStart hook 在 Claude 启动时运行

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/path-helper.sh"
REPO_DIR="$CCCONFIG_ROOT"

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

    # MEMORY.md — 检查项目级 memory 基础设施
    # memory 内容由 Claude Code 自动管理，这里只检查 symlink 链路是否就绪
    local mem_ok=false
    if [ -L "$HOME/.claude/projects" ]; then
        # ccprivate 创建的 symlink：~/.claude/projects → ccprivate/link/projects
        local mem_target=$(readlink "$HOME/.claude/projects" 2>/dev/null)
        if [ -d "$HOME/.claude/projects" ]; then
            mem_ok=true
        fi
    elif [ -d "$HOME/.claude/projects" ]; then
        # Claude Code 自动创建了 projects 目录
        mem_ok=true
    elif [ -L "$CCCONFIG_ROOT/link/projects" ]; then
        # ccconfig/link/projects → ccprivate/link/projects 链路存在
        # ~/.claude/projects 尚未创建（新装，Claude Code 未运行过）
        mem_ok=true
    fi
    if $mem_ok; then
        echo -e "  ${GREEN}✅${NC} MEMORY.md"
    else
        echo -e "  ${YELLOW}○${NC} MEMORY.md (ccprivate 未链接，run setup.sh)"
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
        local fixed=false
        if [ -x "$CCPRIVATE_HOME/setup.sh" ]; then
            if bash "$CCPRIVATE_HOME/setup.sh" 2>/dev/null; then
                echo -e "  ${GREEN}✅ 配置链接已自动修复 (ccprivate/setup.sh)${NC}"
                fixed=true
            fi
        fi
        if ! $fixed && bash "$REPO_DIR/lib/setup-links.sh" 2>/dev/null; then
            echo -e "  ${GREEN}✅ 公开链接已修复 (setup-links.sh)${NC}"
        elif ! $fixed; then
            echo -e "  ${RED}❌ 自动修复失败${NC}"
            echo -e "  ${GRAY}手动: bash ${CCPRIVATE_HOME}/setup.sh${NC}"
        fi
    fi
}

# ========== 3. 检查 auto-sync ==========
check_autosync() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[3] auto-sync${NC}"

    if [ -x "$REPO_DIR/lib/monitor.sh" ]; then
        bash "$REPO_DIR/lib/monitor.sh" status 2>/dev/null || true
    else
        echo -e "  ${RED}❌${NC} monitor.sh 不存在"
    fi
}

# ========== 4. GitHub 最后推送 ==========
check_last_push() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[4] 最后推送${NC}"

    if [ ! -d "$REPO_DIR/.git" ]; then
        echo -e "  ${YELLOW}⚠️${NC} 非 Git 仓库"
        return
    fi

    # 获取最后一次提交的日期和消息
    local log=$(git -C "$REPO_DIR" log -1 --format="%ci|%s" 2>/dev/null)
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

    local projects_dir="$HOME/.claude/projects"
    local found=0

    if [[ ! -d "$projects_dir" ]]; then
        echo -e "  ${YELLOW}⚠️${NC} ~/.claude/projects/ 不存在（Claude Code 首次运行后自动创建）"
        return
    fi

    for proj_dir in "$projects_dir"/*/; do
        [[ -d "$proj_dir" ]] || continue
        local proj_name=$(basename "$proj_dir")
        # 跳过 worktree 临时目录
        [[ "$proj_name" == *"--claude-worktrees-"* ]] && continue

        local mem_dir="${proj_dir}memory"
        if [[ -f "$mem_dir/MEMORY.md" ]]; then
            local mtime=$(stat -L -c %y "$mem_dir/MEMORY.md" 2>/dev/null | cut -d'.' -f1)
            local display_name=$(echo "$proj_name" | sed 's/^-home-[^-]*-//' | tr '-' '/')
            echo -e "  ${GREEN}✅${NC} $display_name — $mtime"
            found=$((found + 1))
        elif [[ -d "$mem_dir" ]]; then
            local display_name=$(echo "$proj_name" | sed 's/^-home-[^-]*-//' | tr '-' '/')
            echo -e "  ${GRAY}○${NC} $display_name — 无 MEMORY.md"
            found=$((found + 1))
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo -e "  ${GRAY}(尚无项目 memory，Claude Code 运行后自动创建)${NC}"
    fi
}

# ========== 6. Git 项目状态 ==========
check_git_projects() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[6] Git 项目状态${NC}"

    local found=0
    for git_dir in "$HOME/git"/*/; do
        [ -d "${git_dir}.git" ] || continue
        local name=$(basename "$git_dir")
        # ccprivate 是私有数据层，不作为开发项目展示
        if [ "$name" = "ccprivate" ]; then
            continue
        fi
        found=$((found + 1))

        # CLAUDE.md 状态
        local claude_status=""
        if [ -L "${git_dir}CLAUDE.md" ]; then
            local target=$(readlink "${git_dir}CLAUDE.md" 2>/dev/null)
            if [ -e "${git_dir}CLAUDE.md" ]; then
                if echo "$target" | grep -q "ccprivate"; then
                    claude_status="${GREEN}✅ ccprivate${NC}"
                else
                    claude_status="${YELLOW}⚠️  ${target}${NC}"
                fi
            else
                claude_status="${RED}❌ 断链${NC}"
            fi
        elif [ -f "${git_dir}CLAUDE.md" ]; then
            claude_status="${YELLOW}📄 本地文件${NC}"
        else
            claude_status="${GRAY}－${NC}"
        fi

        # Memory 状态
        # /home/user/git/<project-name> → -home-user-git-<project-name>
        local rel_path="${git_dir#/}"
        rel_path="${rel_path%/}"
        local proj_id="-${rel_path//\//-}"
        local mem_status=""
        local mem_path="$HOME/.claude/projects/$proj_id/memory"
        if [ -L "$mem_path" ] && [ -d "$mem_path" ]; then
            local mem_target=$(readlink "$mem_path" 2>/dev/null)
            if [ -d "$mem_target" ]; then
                mem_status="${GREEN}✅${NC}"
            else
                mem_status="${RED}❌ 断链${NC}"
            fi
        elif [ -d "$mem_path" ] && [ -f "$mem_path/MEMORY.md" ]; then
            mem_status="${GREEN}✅ 本地${NC}"
        else
            mem_status="${GRAY}－${NC}"
        fi

        # Git 状态
        local git_status=""
        local dirty=$(git -C "$git_dir" status --porcelain 2>/dev/null | wc -l)
        local branch=$(git -C "$git_dir" branch --show-current 2>/dev/null)
        local remote=$(git -C "$git_dir" remote get-url origin 2>/dev/null || echo "")
        if [ -z "$remote" ]; then
            git_status="${YELLOW}无 remote${NC}"
        elif [ "$dirty" -gt 0 ]; then
            git_status="${YELLOW}${branch} (${dirty} 改动)${NC}"
        else
            git_status="${GREEN}${branch} 干净${NC}"
        fi

        printf "  %-20s CLAUDE: %b  Mem: %b  Git: %b\n" "$name" "$claude_status" "$mem_status" "$git_status"
    done

    if [ $found -eq 0 ]; then
        echo -e "  ${GRAY}(~/git/ 下无项目)${NC}"
    fi
}

# ========== 8. Playwright 浏览器测试 ==========
check_playwright() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[8] Playwright 浏览器测试${NC}"

    echo -n "  npx playwright ... "
    if timeout 10 npx playwright --version &>/dev/null; then
        echo -e "${GREEN}✅${NC} $(timeout 10 npx playwright --version 2>/dev/null)"
    else
        echo -e "${GRAY}－${NC} 未安装"
    fi

    echo -n "  浏览器 ... "
    if [ -d "$HOME/.cache/ms-playwright/chromium"* ] 2>/dev/null; then
        echo -e "${GREEN}✅${NC} Chromium"
    elif [ -d "$HOME/.cache/ms-playwright" ]; then
        echo -e "${GREEN}✅${NC} 已安装"
    else
        echo -e "${YELLOW}○${NC} 未安装浏览器"
    fi

    echo -n "  MCP ... "
    if timeout 10 npx @playwright/mcp@latest --version 2>/dev/null | grep -q .; then
        echo -e "${GREEN}✅${NC} 可用"
    else
        echo -e "${YELLOW}○${NC} 未配置"
    fi
}

# ========== 9. MCP 服务器状态 ==========
check_mcp() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[9] MCP 服务器${NC}"

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

PLACEHOLDER_PATTERNS = ['请填入', '请到', '请替换', 'your key', 'your_key', 'placeholder', 'changeme', '<your-']

def _is_placeholder(val):
    if not val or not isinstance(val, str):
        return False
    v = val.lower()
    for p in PLACEHOLDER_PATTERNS:
        if p.lower() in v:
            return True
    return False

def _missing_keys(config):
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

def test_mcp(name, config):
    try:
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
        # 连接失败，检查是否因缺 Key
        missing = _missing_keys(config)
        if missing:
            return name, None, f"缺少 Key: {', '.join(missing[:3])}"
        return name, "✅ (无版本)", None
    except subprocess.TimeoutExpired:
        missing = _missing_keys(config)
        if missing:
            return name, None, f"缺少 Key: {', '.join(missing[:3])}"
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
    current_dir="${current_dir/#\~/$HOME}"

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
    local feishu_json="$(resolve_conf feishu.json)"
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

# ========== 2. 依赖检查 ==========
check_deps_quick() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[2] 核心依赖${NC}"

    local deps_script="$REPO_DIR/lib/deps-check.sh"
    if [ -x "$deps_script" ]; then
        bash "$deps_script" --required 2>/dev/null || true
    else
        echo -e "  ${YELLOW}○${NC} deps-check.sh 不存在"
    fi
}

# ========== 10. option-* 可选组件（含远程连接） ==========
check_option_components() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[10] option-* 可选组件（含远程连接）${NC}"

    local found=0
    for opt_dir in "$REPO_DIR"/option-*/; do
        [ -d "$opt_dir" ] || continue
        local name=$(basename "$opt_dir")
        local init_script="$opt_dir/init.sh"

        found=$((found + 1))
        echo -n "  $name ... "
        if [ ! -f "$init_script" ]; then
            echo -e "${GRAY}－${NC} (无 init.sh)"
            continue
        fi

        local out
        out=$(bash "$init_script" --status 2>&1) || true
        local esc=$'\033'
        local first_line=$(echo "$out" | sed "s/${esc}\[[0-9;]*m//g" | grep -vE '^[[:space:]]*$' | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

        if [ -z "$first_line" ]; then
            echo -e "${GRAY}－${NC}"
        elif echo "$first_line" | grep -qi "^OK"; then
            echo -e "${GREEN}✅${NC} ${first_line#OK }"
        elif echo "$first_line" | grep -qi "^ready"; then
            echo -e "${GREEN}✅${NC} ${first_line#ready }"
        elif echo "$first_line" | grep -qi "^FAIL\|^❌\|^error"; then
            # 可选组件未运行不算错误，黄色提示
            local msg="${first_line#FAIL }"
            msg="${msg#❌ }"
            echo -e "${YELLOW}○${NC} $msg"
        else
            # 检查是否有安装/配置标记（SSH ✅ 等）
            if echo "$first_line" | grep -q '✅'; then
                echo -e "${GREEN}✅${NC} ${first_line}"
            elif echo "$first_line" | grep -qE '(未安装|未登录|not running|not installed)'; then
                echo -e "${GRAY}－${NC} $first_line"
            elif echo "$first_line" | grep -qiE '(cloudflare|plugin|workers)'; then
                echo -e "${GRAY}－${NC} $first_line"
            else
                echo -e "${GRAY}－${NC} $first_line"
            fi
        fi

        # option-remote: 额外展开 SSH/Tailscale 详情
        if [[ "$name" == "option-remote" ]]; then
            echo "$out" | sed "s/${esc}\[[0-9;]*m//g" | grep -vE '^[[:space:]]*$' | tail -n +2 | while IFS= read -r line; do
                echo "    $line"
            done
        fi
    done

    if [ $found -eq 0 ]; then
        echo -e "  ${GRAY}(无可选组件)${NC}"
    fi
}

# ========== 12. Skills 安装状态 ==========
check_skills() {
    echo -e "${CYAN}── Skills${NC}"

    local skills_dir="$HOME/.claude/skills"
    local skills_src="${SKILL_SRC:-$HOME/git/skill/plugins}"
    local ok=true

    if [[ -d "$skills_src" ]]; then
        local self_count=$(ls "$skills_src" 2>/dev/null | wc -l)
        echo -e "  自建: ${GREEN}${self_count}${NC} 个 (skill/plugins/)"
    else
        echo -e "  自建: ${YELLOW}未找到${NC} skill/plugins/"
        ok=false
    fi

    if [[ -d "$skills_dir" ]]; then
        local broken=0 linked=0
        for d in "$skills_dir"/*; do
            if [[ -L "$d" ]] && [[ ! -e "$d" ]]; then
                broken=$((broken + 1))
            elif [[ -L "$d" ]]; then
                linked=$((linked + 1))
            fi
        done
        echo -e "  已链接: ${GREEN}${linked}${NC} 个"
        if [[ $broken -gt 0 ]]; then
            echo -e "  ${RED}断链: ${broken}${NC} 个 → bash init-skill.sh cleanup"
            ok=false
        fi
    else
        echo -e "  ${YELLOW}~/.claude/skills/ 不存在${NC} → bash init-skill.sh sync"
        ok=false
    fi

    local third_party="$CCCONFIG_ROOT/conf/third-party-skills.txt"
    if [[ -f "$third_party" ]]; then
        local tp_count=$(grep -cEv '^\s*(#|$)' "$third_party" 2>/dev/null || echo 0)
        echo -e "  第三方清单: ${tp_count} 个 (third-party-skills.txt)"
    fi

    $ok && echo -e "  ${GREEN}✓ Skills 正常${NC}"
}

# ========== Example 模板同步检查 ==========
check_example_sync() {
    local ccconfig_example="$CCCONFIG_ROOT/link"
    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[12b] Example 模板同步${NC}"

    # rules 检查
    local rules_outdated=0 rules_new=0 rules_added=0
    if [ -d "$ccpriv/rules" ]; then
        for f in "$ccpriv/rules/"*.md; do [ -f "$f" ] || continue; done 2>/dev/null
    fi
    for example in "$ccconfig_example/rules/"*.md.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .md.example)
        local target="$ccpriv/rules/${base}.md"
        if [ ! -f "$target" ]; then
            rules_new=$((rules_new + 1))
        elif ! diff -q "$example" "$target" &>/dev/null; then
            rules_outdated=$((rules_outdated + 1))
        fi
    done
    rules_added=0
    for f in "$ccpriv/rules/"*.md; do
        [ -f "$f" ] || continue
        base=$(basename "$f" .md)
        [ -f "$ccconfig_example/rules/${base}.md.example" ] || rules_added=$((rules_added + 1))
    done

    local out=""
    [ $rules_outdated -gt 0 ] && out="${out}${YELLOW}${rules_outdated} 过期${NC} "
    [ $rules_new -gt 0 ] && out="${out}${CYAN}${rules_new} 新增${NC} "
    [ $rules_added -gt 0 ] && out="${out}${GRAY}${rules_added} 独有${NC} "
    [ -z "$out" ] && out="${GREEN}✅ 同步${NC}"
    echo -e "  rules: $out"

    # agents 检查
    local agents_outdated=0 agents_new=0 agents_added=0
    for example in "$ccconfig_example/agents/"*.md.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .md.example)
        local target="$ccpriv/agents/${base}.md"
        if [ ! -f "$target" ]; then
            agents_new=$((agents_new + 1))
        elif ! diff -q "$example" "$target" &>/dev/null; then
            agents_outdated=$((agents_outdated + 1))
        fi
    done
    agents_added=0
    for f in "$ccpriv/agents/"*.md; do
        [ -f "$f" ] || continue
        base=$(basename "$f" .md)
        [ -f "$ccconfig_example/agents/${base}.md.example" ] || agents_added=$((agents_added + 1))
    done

    local out=""
    [ $agents_outdated -gt 0 ] && out="${out}${YELLOW}${agents_outdated} 过期${NC} "
    [ $agents_new -gt 0 ] && out="${out}${CYAN}${agents_new} 新增${NC} "
    [ $agents_added -gt 0 ] && out="${out}${GRAY}${agents_added} 独有${NC} "
    [ -z "$out" ] && out="${GREEN}✅ 同步${NC}"
    echo -e "  agents: $out"

    local needs_action=$((rules_outdated + rules_new + agents_outdated + agents_new))
    if [ $needs_action -gt 0 ]; then
        echo ""
        echo -e "  ${GRAY}运行: bash maintain.sh example promote${NC}"
    fi

    # conf 新增模板检测
    local conf_new=0
    for example in "$CCCONFIG_ROOT"/conf/*.json.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .example)
        [ -f "$ccpriv/conf/$base" ] || conf_new=$((conf_new + 1))
    done
    [ $conf_new -gt 0 ] && echo -e "  conf: ${CYAN}${conf_new} 新模板${NC}（自 sync.sh 处理）"
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
check_git_projects
check_feishu
check_playwright
check_mcp
check_option_components
check_skills
check_example_sync

echo ""
