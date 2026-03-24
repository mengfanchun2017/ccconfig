#!/bin/bash
# Claude Code MCP 检查脚本 v2
# 功能：对比 mcplist.json 与当前环境，提供专业交互选项
#
# ============================================================
# 使用流程：
#
#   第一步：安装 Node.js（如果还没有）
#     bash scripts/bash/initnodejs.sh
#
#   第二步：安装 MCP
#     bash scripts/bash/mcpcheck.sh
#     - 选择要安装的 MCP
#     - 脚本会调用 claude mcp add 配置到 ~/.claude.json
#
#   第三步：配置 API Key
#     - 运行 claude
#     - 执行 /mcp 查看已注册的 MCP
#     - 点击需要 API Key 的 MCP，手动提供
#
# 重要说明：
#   - API Key 不会在脚本中输入，避免同步到 git
#   - mcplist.json 只记录 MCP 元信息，不含敏感数据
#   - install_local 字段记录本地安装命令，供修复时使用
#
# 核心逻辑：
#   1. 读取 mcplist.json 获取期望的 MCP 配置
#   2. 通过 claude mcp list 获取当前已注册的 MCP
#   3. 检测每个 MCP 的实际可执行命令是否存在于系统中
#   4. 对比分析：列表 vs 环境 vs 实际可用
#   5. 提供交互选项让用户选择处理方式
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_LIST_FILE="$REPO_DIR/config/mcplist.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

title() { echo -e "\n========================================\n  $1\n========================================\n${CYAN}"; }
section() { echo -e "\n【$1】${YELLOW}"; }
item() { echo -e "  $1${NC}"; }
good() { echo -e "  $1${GREEN}"; }
bad() { echo -e "  $1${RED}"; }
info() { echo -e "  $1${GRAY}"; }
warn() { echo -e "  $1${YELLOW}"; }

# ========== 环境检测函数 ==========
check_command() {
    command -v "$1" &> /dev/null
}

check_python_module() {
    python3 -c "import $1" 2>/dev/null
}

# ========== 安装方法检测 ==========
# 检测可用的包管理器
detect_package_managers() {
    local managers=()

    if check_command npm; then
        managers+=("npm")
    fi
    if check_command npx; then
        managers+=("npx")
    fi
    if check_command pip || check_command pip3; then
        managers+=("pip")
    fi
    if check_command python3; then
        managers+=("python3")
    fi
    if check_command node; then
        managers+=("node")
    fi
    if check_command bun; then
        managers+=("bun")
    fi

    echo "${managers[*]}"
}

# 检测 MCP 命令是否可用（支持多种形式）
check_mcp_command() {
    local cmd="$1"
    local args="$2"

    # 直接命令
    if check_command "$cmd"; then
        return 0
    fi

    # python3 -m module 形式
    if [[ "$cmd" == "python3" && "$args" == "-m "* ]]; then
        local module="${args#-m }"
        module="${module%% *}"  # 取第一个单词作为模块名
        if check_python_module "$module"; then
            return 0
        fi
    fi

    # npx 命令
    if [[ "$cmd" == "npx" ]]; then
        if check_command npx; then
            return 0
        fi
    fi

    return 1
}

# 检测 MCP 运行时状态（检测命令是否存在，以及运行时错误如缺少环境变量）
# 返回: 0=正常, 1=命令不存在, 2=运行时错误
check_mcp_runtime() {
    local cmd="$1"
    local install_args="$2"
    local key_env="$3"  # 可选：需要的环境变量名

    # 首先检查命令是否存在
    if ! check_mcp_command "$cmd" "$install_args"; then
        return 1
    fi

    # 构建完整命令
    local full_cmd="$cmd $install_args"

    # 尝试运行 MCP，捕获错误输出（超时 3 秒）
    # MCP 服务器通常启动时会立即输出错误（如缺少 API key）
    # 注意：使用 < /dev/null 避免 stdin 被 inherited 导致 MCP 读取到 here-string 内容
    local error_output
    error_output=$(timeout 3s $full_cmd < /dev/null 2>&1) || true
    local exit_code=$?

    # 检查是否包含常见运行时错误（支持多行错误输出）
    # -z 将 NUL 作为行分隔符，使 . 可以匹配换行符
    if echo "$error_output" | grep -qzi "API_KEY\|ACCESS_TOKEN\|environment variable\|missing.*required\|key.*is required\|required.*environment"; then
        return 2
    fi

    return 0
}

# ========== Python 辅助函数 ==========
# 读取 MCP 列表并输出格式化的文本
read_mcp_list() {
    python3 - "$MCP_LIST_FILE" << 'PYTHON_EOF'
import json
import sys

try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    for m in data.get('mcp', []):
        name = m.get('name', '')
        desc = m.get('description', '')
        mtype = m.get('type', 'stdio')
        install = m.get('install', '')
        install_local = m.get('install_local', '')
        needs_key = str(m.get('needsKey', False)).lower()
        key_env = m.get('keyEnv', '')
        key_url = m.get('keyUrl', '')
        command = m.get('command', '')
        args = ' '.join(m.get('args', [])) if isinstance(m.get('args', []), list) else ''
        print(f"{name}|{desc}|{mtype}|{install}|{install_local}|{needs_key}|{key_env}|{key_url}|{command}|{args}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
}

# 检查某个 MCP 是否存在于列表中（忽略大小写）
mcp_exists_in_list() {
    python3 - "$MCP_LIST_FILE" "$1" << 'PYTHON_EOF'
import json
import sys

try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    name = sys.argv[2].lower()
    exists = any(m.get('name', '').lower() == name for m in data.get('mcp', []))
    print('true' if exists else 'false')
except:
    print('false')
PYTHON_EOF
}

# 添加 MCP 到列表
add_mcp_to_list() {
    python3 - "$MCP_LIST_FILE" "$1" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)

    name = sys.argv[2]
    if any(m.get('name') == name for m in data.get('mcp', [])):
        print(f"  {name} 已存在")
        sys.exit(0)

    data['mcp'].append({
        'name': name,
        'description': '（待补充）',
        'type': 'stdio'
    })

    with open(sys.argv[1], 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print('ok')
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ========== Supabase 特殊处理函数 ==========

# 检查并提示 Supabase token 和 project-ref
check_supabase_config() {
    # 检查 Supabase 是否实际已注册（支持大小写不敏感）
    local has_supabase=false
    for key in "${!RegisteredMcp[@]}"; do
        if [[ "${key,,}" == "supabase" ]]; then
            has_supabase=true
            break
        fi
    done

    [[ "$has_supabase" == "false" ]] && return 0

    local supabase_entry=""
    # 获取 mcplist 中的 supabase 配置
    while IFS='|' read -r name desc type install install_local needs_key key_env key_url command args; do
        [[ "$name" == "supabase" ]] && supabase_entry="$install" && break
    done <<< "$McpNames"

    # 检查 ~/.claude.json 中 supabase 是否已配置正确的 token（检查 root 和 project 级别）
    local current_config=$(python3 - "$CLAUDE_JSON" << 'PYEOF'
import json
import sys
try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)

    # 1. 检查 root-level mcpServers
    supabase = data.get('mcpServers', {}).get('supabase', {})
    if supabase:
        args = supabase.get('args', [])
        for i, arg in enumerate(args):
            if arg == '--access-token' and i+1 < len(args):
                print(args[i+1])
                sys.exit(0)

    # 2. 检查 project-level mcpServers
    projects = data.get('projects', {})
    for proj_path, proj_data in projects.items():
        proj_supabase = proj_data.get('mcpServers', {}).get('supabase', {})
        if proj_supabase:
            args = proj_supabase.get('args', [])
            for i, arg in enumerate(args):
                if arg == '--access-token' and i+1 < len(args):
                    print(args[i+1])
                    sys.exit(0)

    print('')
except:
    print('')
PYEOF
)

    if [[ -z "$current_config" ]] || [[ "$current_config" == "<YOUR_TOKEN>" ]]; then
        echo ""
        section "🔑 Supabase MCP 配置"
        echo -e "  ${CYAN}Supabase MCP 需要访问令牌来操作数据库${NC}"
        echo ""

        # 提示输入 token
        echo -n "  请输入 SUPABASE_ACCESS_TOKEN (sbp_...): "
        read -s supabase_token
        echo ""

        if [[ -n "$supabase_token" ]]; then
            # 获取 project-ref (从 mcplist 的 install 字段)
            local project_ref=$(echo "$supabase_entry" | grep -oP '(?<=--project-ref\s)\S+' || echo "<your-supabase-project-id>")

            # 更新 ~/.claude.json
            python3 - "$CLAUDE_JSON" "$supabase_token" "$project_ref" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)

    token = sys.argv[2]
    project_ref = sys.argv[3]

    # 查找 supabase MCP 配置
    if 'mcpServers' not in data:
        data['mcpServers'] = {}

    if 'supabase' not in data['mcpServers']:
        data['mcpServers']['supabase'] = {
            'command': 'npx',
            'args': ['-y', '@supabase/mcp-server-supabase', '--project-ref', project_ref, '--access-token', token]
        }
    else:
        # 更新现有的 token
        args = data['mcpServers']['supabase'].get('args', [])
        new_args = []
        skip_next = False
        for arg in args:
            if skip_next:
                skip_next = False
                continue
            if arg == '--access-token':
                new_args.append(arg)
                new_args.append(token)
                skip_next = True
            elif arg == '<YOUR_TOKEN>':
                new_args.append(token)
            else:
                new_args.append(arg)
        data['mcpServers']['supabase']['args'] = new_args

    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=2)

    print('ok')
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYEOF

            if [[ "$?" == "0" ]]; then
                good "✅ Supabase token 已配置"
                # 重启 MCP
                claude mcp stop supabase 2>/dev/null || true
                claude mcp start supabase 2>/dev/null || true
            else
                bad "❌ Supabase token 配置失败"
            fi
        else
            warn "  Token 为空，已跳过"
        fi
    fi

    # ========== RLS 提醒 ==========
    echo ""
    section "🔒 Supabase Row Level Security (RLS) 提醒"
    echo -e "  ${CYAN}您的 Supabase 数据库已启用 RLS (Row Level Security)${NC}"
    echo ""
    echo -e "  ${YELLOW}为什么要启用 RLS:${NC}"
    echo "    - RLS 为数据库表添加行级安全策略"
    echo "    - 即使 API Key 被泄露，攻击者也无法访问未授权的数据"
    echo "    - 这是 Supabase 安全的核心特性"
    echo ""
    echo -e "  ${YELLOW}如何管理 RLS:${NC}"
    echo "    1. 访问 https://supabase.com/dashboard"
    echo "    2. 选择您的项目 → Table Editor → 选择表"
    echo "    3. 点击 'RLS' 开关启用/禁用"
    echo "    4. 在 'Policies' 标签中配置访问策略"
    echo ""
    echo -e "  ${YELLOW}使用 MCP 时的注意事项:${NC}"
    echo "    - MCP 使用 Personal Access Token (PAT)，具有 service_role 权限"
    echo "    - 这意味着 MCP 可以绕过 RLS（如果表有 INSERT 权限）"
    echo "    - 写入操作建议使用 RETURNING 子句确认结果"
    echo ""
    echo -e "  ${CYAN}开启 RLS 后，MCP 仍然可以正常读写数据${NC}"
    echo ""
}

# ========== Key 管理函数 ==========
CLAUDE_JSON="$HOME/.claude.json"

# 从 ~/.claude.json 读取某个 MCP 的当前 key
# 同时检查 root-level 和 project-level 的 mcpServers
get_current_key() {
    local mcp_name="$1"
    local key_env="$2"

    python3 - "$CLAUDE_JSON" "$mcp_name" "$key_env" << 'PYEOF'
import json
import sys
import os

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    mcp_name = sys.argv[2]
    key_env = sys.argv[3]

    # 1. 先检查 root-level mcpServers (全局注册)
    mcp_servers = data.get('mcpServers', {})
    if mcp_name in mcp_servers:
        env = mcp_servers[mcp_name].get('env', {})
        if key_env in env:
            print(env[key_env])
            sys.exit(0)

    # 2. 检查当前项目目录的 project-level mcpServers
    current_dir = os.path.basename(os.getcwd())
    projects = data.get('projects', {})

    # 尝试匹配当前目录相关的项目配置
    for proj_path, proj_data in projects.items():
        proj_mcp = proj_data.get('mcpServers', {})
        if mcp_name in proj_mcp:
            env = proj_mcp[mcp_name].get('env', {})
            if key_env in env:
                print(env[key_env])
                sys.exit(0)

    print('')
except:
    print('')
PYEOF
}

# 更新 ~/.claude.json 中某个 MCP 的 key
update_mcp_key() {
    local mcp_name="$1"
    local key_env="$2"
    local key_value="$3"

    python3 - "$CLAUDE_JSON" "$mcp_name" "$key_env" "$key_value" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    mcp_name = sys.argv[2]
    key_env = sys.argv[3]
    key_value = sys.argv[4]

    mcp_servers = data.get('mcpServers', {})
    if mcp_name not in mcp_servers:
        print(f"Error: {mcp_name} not found in mcpServers")
        sys.exit(1)

    if 'env' not in mcp_servers[mcp_name]:
        mcp_servers[mcp_name]['env'] = {}

    mcp_servers[mcp_name]['env'][key_env] = key_value

    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=2)

    print('ok')
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYEOF
}

# ========== Key 检查和处理 ==========
check_and_prompt_keys() {
    local mode="$1"  # "missing" or "registered"

    title "🔑 API Key 检查"

    local has_key_issues=false
    declare -a KeyIssuesArr=()

    # 检查列表中所有需要 key 的 MCP
    while IFS='|' read -r name desc type install install_local needs_key key_env key_url; do
        [[ -z "$name" ]] && continue
        [[ "$needs_key" != "true" ]] && continue
        [[ -z "$key_env" ]] && continue

        # 跳过未注册的 MCP（需要先安装才能配置 Key）
        if ! is_mcp_registered "$name"; then
            continue
        fi

        # 跳过运行时错误的 MCP（会在主菜单选项 1 中单独处理）
        if [[ " ${RuntimeErrorArr[*]} " =~ " $name|" ]]; then
            continue
        fi

        current_key=$(get_current_key "$name" "$key_env")

        if [[ -z "$current_key" ]]; then
            has_key_issues=true
            if [[ "$mode" == "missing" ]]; then
                KeyIssuesArr+=("$name|$desc|$key_env|$key_url|")
            else
                KeyIssuesArr+=("$name|$desc|$key_env|$key_url|existing")
            fi
        fi
    done <<< "$McpNames"

    if [[ "$has_key_issues" == "false" ]]; then
        good "✅ 所有需要 Key 的 MCP 都已配置"
        return 0
    fi

    section "⚠️ 需要配置 Key 的 MCP（已注册的）"

    for item in "${KeyIssuesArr[@]}"; do
        IFS='|' read -r name desc key_env key_url extra <<< "$item"
        [[ -z "$name" ]] && continue

        current_key=$(get_current_key "$name" "$key_env")
        is_existing=false
        [[ "$extra" == "existing" ]] && is_existing=true

        if [[ -n "$current_key" ]]; then
            echo -e "\n  $name ($desc)"
            info "  当前 Key: ${current_key:0:10}..."
            echo -e "  ${YELLOW}[已配置]${NC}"
        else
            echo -e "\n  $name ($desc)"
            [[ -n "$key_url" ]] && info "  Key 地址: $key_url"

            echo -e "  ${RED}[缺失]${NC} - 环境变量 $key_env 为空"
            echo -e "  ${CYAN}  1) 输入 Key"
            echo -e "  2) 跳过，稍后手动配置"
            [[ "$is_existing" == "true" ]] && echo -e "  3) 保持当前状态（不配置）"
            echo ""

            read -p "请选择 [1/2/3]: " key_choice

            case "$key_choice" in
                1)
                    read -p "请输入 $key_env: " new_key
                    if [[ -n "$new_key" ]]; then
                        result=$(update_mcp_key "$name" "$key_env" "$new_key")
                        if [[ "$result" == "ok" ]]; then
                            good "✅ Key 已更新"
                        else
                            bad "❌ 更新失败: $result"
                        fi
                    else
                        warn "Key 为空，已跳过"
                    fi
                    ;;
                2|3)
                    info "已跳过"
                    ;;
                *)
                    warn "无效选择，已跳过"
                    ;;
            esac
        fi
    done
}

# ========== 主程序 ==========

# 检查 mcplist.json
if [ ! -f "$MCP_LIST_FILE" ]; then
    bad "❌ 未找到 mcplist.json"
    exit 1
fi

# 检查 claude 命令
if ! command -v claude &> /dev/null; then
    bad "❌ Claude Code 未安装，请先运行 initgit.sh"
    exit 1
fi

# 检测可用的包管理器
available_managers=$(detect_package_managers)

title "Claude Code MCP 检查 v2"
info "可用的包管理器: ${available_managers:-无}"

# 获取当前已注册的 MCP
declare -A RegisteredMcp
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*([^:]+): ]]; then
        RegisteredMcp["${BASH_REMATCH[1]}"]=1
    fi
done < <(claude mcp list 2>&1 | grep -v "^Checking" | grep -v "^$" || true)

# 获取 MCP 列表
McpNames=$(read_mcp_list)

# ========== 辅助函数：大小写不敏感查找 ==========
# 检查 MCP 是否已注册（支持大小写不敏感匹配）
is_mcp_registered() {
    local mcp_name="$1"
    local mcp_name_lower=$(echo "$mcp_name" | tr '[:upper:]' '[:lower:]')

    # 检查原始大小写
    [[ -n "${RegisteredMcp[$mcp_name]}" ]] && return 0

    # 检查小写版本
    for key in "${!RegisteredMcp[@]}"; do
        if [[ "${key,,}" == "$mcp_name_lower" ]]; then
            return 0
        fi
    done
    return 1
}

# 获取 MCP 的实际注册名（用于后续操作）
get_registered_name() {
    local mcp_name="$1"
    local mcp_name_lower=$(echo "$mcp_name" | tr '[:upper:]' '[:lower:]')

    # 优先返回原始大小写匹配
    [[ -n "${RegisteredMcp[$mcp_name]}" ]] && echo "$mcp_name" && return

    # 否则返回任意大小写匹配
    for key in "${!RegisteredMcp[@]}"; do
        if [[ "${key,,}" == "$mcp_name_lower" ]]; then
            echo "$key"
            return
        fi
    done
    echo ""
}

# ========== 对比分析 ==========
# 使用数组代替字符串拼接，避免 \n 字面字符问题
declare -a MatchedArr=()
declare -a MissingFromListArr=()
declare -a ExtraInEnvArr=()
declare -a FailedCmdArr=()
declare -a RuntimeErrorArr=()  # 命令存在但运行时缺少 key 的 MCP

# 检查列表中的每个 MCP
# 格式: name|desc|type|install|install_local|needs_key|key_env|key_url|mcp_cmd|mcp_args
while IFS='|' read -r name desc type install install_local needs_key key_env key_url mcp_cmd mcp_args; do
    [[ -z "$name" ]] && continue

    # 优先使用 mcp_cmd+mcp_args，其次使用 install
    if [[ -n "$mcp_cmd" ]]; then
        actual_install="$mcp_cmd $mcp_args"
    elif [[ -n "$install" ]]; then
        actual_install="$install"
    else
        actual_install=""
    fi

    if is_mcp_registered "$name"; then
        # MCP 已注册，检测命令是否实际可用
        if [[ -z "$actual_install" ]]; then
            # install 为空时，跳过命令检测（配置不完整但已注册）
            info "⚬ $name: 已注册（配置待完善）"
        else
            cmd_parts=($actual_install)
            cmd="${cmd_parts[0]}"
            install_args="${actual_install#$cmd }"

            # 先检查命令是否存在
            if ! check_mcp_command "$cmd" "$install_args"; then
                # 命令不可用
                if [[ -n "$install_local" ]]; then
                    FailedCmdArr+=("$name|$desc|$actual_install|$install_local")
                else
                    FailedCmdArr+=("$name|$desc|$actual_install|")
                fi
            else
                # 命令存在，检测运行时状态（是否缺少 key）
                runtime_result=0
                check_mcp_runtime "$cmd" "$install_args" "$key_env" || runtime_result=$?

                if [[ $runtime_result -eq 2 ]]; then
                    # 运行时错误（通常是缺少 API key）
                    RuntimeErrorArr+=("$name|$desc|$key_env|$key_url")
                else
                    MatchedArr+=("$name|$desc")
                fi
            fi
        fi
    else
        # MCP 未注册
        MissingFromListArr+=("$name|$desc|$type|$actual_install|$install_local|$needs_key|$key_env|$key_url")
    fi
done <<< "$McpNames"

# 检查环境中的 MCP 是否在列表中
for env_name in "${!RegisteredMcp[@]}"; do
    found=$(mcp_exists_in_list "$env_name")
    if [[ "$found" == "false" ]]; then
        ExtraInEnvArr+=("$env_name")
    fi
done

# ========== 显示结果 ==========

# 正常的部分
if [[ ${#MatchedArr[@]} -gt 0 ]]; then
    section "✅ 正常工作"
    for item in "${MatchedArr[@]}"; do
        IFS='|' read -r name desc <<< "$item"
        good "✓ $name: $desc"
    done
fi

# 缺失的部分
if [[ ${#MissingFromListArr[@]} -gt 0 ]]; then
    section "❌ 列表中有但未注册"
    for item in "${MissingFromListArr[@]}"; do
        IFS='|' read -r name desc type install install_local needs_key key_env key_url <<< "$item"
        [[ "$type" == "http" ]] && type_tag="[HTTP]" || type_tag="[STDIO]"
        item "$name - $desc $type_tag"
        info "  安装命令: $install"
        if [[ -n "$key_env" ]]; then
            info "  需要 Key: $key_env"
        fi
    done
fi

# 命令无效的部分
if [[ ${#FailedCmdArr[@]} -gt 0 ]]; then
    section "⚠️ 注册了但命令不可用"
    for item in "${FailedCmdArr[@]}"; do
        IFS='|' read -r name desc install install_local <<< "$item"
        item "$name: $install"
        if [[ -n "$install_local" ]]; then
            info "  本地安装: $install_local"
        fi
    done
fi

# 运行时错误（命令存在但缺少 key）
if [[ ${#RuntimeErrorArr[@]} -gt 0 ]]; then
    section "🔑 注册了但缺少 API Key"
    for item in "${RuntimeErrorArr[@]}"; do
        IFS='|' read -r name desc key_env key_url <<< "$item"
        item "$name: 缺少 $key_env"
        [[ -n "$key_url" ]] && info "  Key 地址: $key_url"
    done
fi

# 多出的部分
if [[ ${#ExtraInEnvArr[@]} -gt 0 ]]; then
    section "⚠️ 环境中注册但列表中无"
    for name in "${ExtraInEnvArr[@]}"; do
        item "$name"
    done
fi

# ========== 总结 ==========
total_list=${#McpNames_arr[@]}
[[ $total_list -eq 0 ]] && total_list=$(echo "$McpNames" | grep -c "^[^|]") 2>/dev/null || true
total_matched=${#MatchedArr[@]}
total_missing=${#MissingFromListArr[@]}
total_failed=${#FailedCmdArr[@]}
total_extra=${#ExtraInEnvArr[@]}

section "统计"
item "列表中: $total_list | 正常: $total_matched | 缺失: $total_missing | 失败: $total_failed | 多余: $total_extra"

# ========== Key 检查（无论是否有 action 都检查）==========
check_and_prompt_keys "registered"

# ========== Supabase 特殊检查 ==========
check_supabase_config

# ========== 交互菜单 ==========
has_action_needed=false
[[ ${#MissingFromListArr[@]} -gt 0 ]] || [[ ${#FailedCmdArr[@]} -gt 0 ]] || [[ ${#ExtraInEnvArr[@]} -gt 0 ]] && has_action_needed=true

if [[ "$has_action_needed" == "false" ]] && [[ ${#RuntimeErrorArr[@]} -eq 0 ]]; then
    title "检查完成"
    good "✅ 所有 MCP 都正常工作"
    good "✅ Key 检查已完成"
    exit 0
fi

title "请选择操作"

if [[ ${#RuntimeErrorArr[@]} -gt 0 ]]; then
    echo -e "  1) 配置缺少的 API Key${NC}"
fi

echo -e "  2) 安装缺失的 MCP（需要命令可用）${NC}"
echo -e "  3) 修复命令不可用的 MCP${NC}"

if [[ ${#FailedCmdArr[@]} -gt 0 ]]; then
    echo -e "  4) 尝试自动修复（使用 install_local）${NC}"
fi

echo -e "  5) 补充缺失项到 mcplist.json${NC}"

if [[ ${#ExtraInEnvArr[@]} -gt 0 ]]; then
    echo -e "  6) 双向同步（安装+补充）${NC}"
fi

echo -e "  7) 单独处理某个 MCP${NC}"
echo -e "  0) 跳过，不做任何修改${GRAY}"
echo ""

read -p "请输入选项 [0-7]: " choice
echo ""

# ========== 安装函数 ==========
do_install_mcp() {
    local name="$1"
    local install_cmd="$2"
    local env_vars="$3"

    echo -n "安装: $name ... "

    # 设置环境变量
    if [[ -n "$env_vars" ]]; then
        export $env_vars
    fi

    # 使用 --scope user 添加到用户全局配置
    if claude mcp add -s user $name -- $install_cmd 2>&1; then
        good "✅"
        return 0
    else
        bad "❌"
        return 1
    fi
}

case "$choice" in
    1)
        # 配置缺少 API Key 的 MCP
        title "配置 API Key"

        for item in "${RuntimeErrorArr[@]}"; do
            IFS='|' read -r name desc key_env key_url <<< "$item"
            [[ -z "$name" ]] && continue

            echo -e "\n  $name"
            [[ -n "$key_url" ]] && info "  Key 地址: $key_url"
            echo -n "  请输入 $key_env: "
            read -s new_key
            echo ""

            if [[ -n "$new_key" ]]; then
                result=$(update_mcp_key "$name" "$key_env" "$new_key")
                if [[ "$result" == "ok" ]]; then
                    good "  ✅ Key 已配置"
                else
                    bad "  ❌ 配置失败: $result"
                fi
            else
                info "  已跳过"
            fi
        done
        good "✅ Key 配置完成"
        ;;

    2)
        # 安装缺失的 MCP
        title "安装缺失的 MCP"

        if [[ -z "$available_managers" ]]; then
            bad "❌ 没有可用的包管理器，无法安装"
            bad "请先安装 Node.js (npm) 或 Python (pip)"
            exit 1
        fi

        for item in "${MissingFromListArr[@]}"; do
            IFS='|' read -r name desc type install install_local needs_key key_env key_url <<< "$item"

            # 检查 install 命令的依赖
            cmd_parts=($install)
            cmd="${cmd_parts[0]}"

            if [[ "$cmd" == "npx" || "$cmd" == "npm" ]] && ! check_command npx; then
                warn "⏭ $name: 需要 npm/npx 但未安装"
                continue
            fi
            if [[ "$cmd" == "pip" || "$cmd" == "pip3" ]] && ! check_command pip && ! check_command pip3; then
                warn "⏭ $name: 需要 pip 但未安装"
                continue
            fi

            do_install_mcp "$name" "$install" ""
        done
        ;;

    3)
        # 修复命令不可用的 MCP
        title "修复命令不可用的 MCP"

        for item in "${FailedCmdArr[@]}"; do
            IFS='|' read -r name desc install install_local <<< "$item"

            if [[ -z "$install_local" ]]; then
                warn "⏭ $name: 没有本地安装命令"
                continue
            fi

            echo -e "\n修复 $name:"
            info "将执行: $install_local"
            read -p "继续? [y/N] " confirm

            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                eval "$install_local" 2>&1 | tail -5
                if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                    good "✅ 安装成功"
                    # 重新注册
                    do_install_mcp "$name" "$install" ""
                else
                    bad "❌ 安装失败"
                fi
            fi
        done
        ;;

    4)
        # 自动修复
        title "自动修复"

        fixed=0
        for item in "${FailedCmdArr[@]}"; do
            IFS='|' read -r name desc install install_local <<< "$item"
            [[ -z "$install_local" ]] && continue

            echo -n "修复 $name ... "

            # 尝试安装
            if eval "$install_local" &>/dev/null; then
                # 安装成功，重新注册
                if claude mcp add -s user $name -- $install &>/dev/null; then
                    good "✅"
                    ((fixed++))
                else
                    bad "❌ 注册失败"
                fi
            else
                bad "❌ 安装失败"
            fi
        done

        good "✅ 完成：修复 $fixed 个"
        ;;

    5)
        # 补充缺失项到 mcplist.json
        title "补充到 mcplist.json"

        for name in "${ExtraInEnvArr[@]}"; do
            [[ -z "$name" ]] && continue
            echo -n "添加: $name ... "
            result=$(add_mcp_to_list "$name")
            if [[ "$result" == "ok" ]]; then
                good "✅"
            else
                echo "$result"
            fi
        done

        good "✅ 已更新 mcplist.json，请补充描述信息"
        ;;

    6)
        # 双向同步
        title "双向同步"

        # 补充列表
        info "1/2: 补充列表..."
        for name in "${ExtraInEnvArr[@]}"; do
            [[ -z "$name" ]] && continue
            add_mcp_to_list "$name" 2>/dev/null
        done
        good "✅ 列表已更新"

        # 安装缺失
        info "2/2: 安装缺失..."
        installed=0
        for item in "${MissingFromListArr[@]}"; do
            IFS='|' read -r name desc type install install_local needs_key key_env key_url <<< "$item"
            [[ -z "$name" ]] && continue
            [[ "$type" == "http" ]] && continue

            cmd_parts=($install)
            cmd="${cmd_parts[0]}"
            if [[ "$cmd" == "npx" && ! " ${available_managers} " =~ " npx " ]]; then
                continue
            fi

            if do_install_mcp "$name" "$install" ""; then
                ((installed++))
            fi
        done
        good "✅ 完成：安装 $installed 个"
        ;;

    7)
        # 单独处理
        title "单独处理"

        all_items=()
        idx=1

        for item in "${MissingFromListArr[@]}"; do
            IFS='|' read -r name desc type install install_local needs_key key_env key_url <<< "$item"
            [[ -z "$name" ]] && continue
            all_items+=("$idx|MISSING|$name|$desc|$install|$install_local|$needs_key|$key_env|$key_url")
            ((idx++))
        done

        for item in "${FailedCmdArr[@]}"; do
            IFS='|' read -r name desc install install_local <<< "$item"
            [[ -z "$name" ]] && continue
            all_items+=("$idx|FAILED|$name|$desc|$install|$install_local|||")
            ((idx++))
        done

        for item in "${RuntimeErrorArr[@]}"; do
            IFS='|' read -r name desc key_env key_url <<< "$item"
            [[ -z "$name" ]] && continue
            all_items+=("$idx|RUNTIME|$name|$desc||$key_env|$key_url")
            ((idx++))
        done

        for name in "${ExtraInEnvArr[@]}"; do
            [[ -z "$name" ]] && continue
            all_items+=("$idx|EXTRA|$name|||||")
            ((idx++))
        done

        if [[ ${#all_items[@]} -eq 0 ]]; then
            info "没有可处理的 MCP"
            exit 0
        fi

        echo "可处理的 MCP:"
        for item in "${all_items[@]}"; do
            IFS='|' read -r i type name desc install install_local env <<< "$item"
            type_str=""
            case "$type" in
                MISSING) type_str="[缺失]" ;;
                FAILED)  type_str="[失败]" ;;
                RUNTIME) type_str="[缺Key]" ;;
                EXTRA)   type_str="[多余]" ;;
            esac
            echo -e "  $i) $type_str $name - $desc"
        done

        echo ""
        read -p "选择编号 [1-${#all_items[@]}]，或 0 取消: " sel

        if [[ "$sel" == "0" || -z "$sel" ]]; then
            info "已取消"
            exit 0
        fi

        selected=""
        for item in "${all_items[@]}"; do
            IFS='|' read -r i type name desc install install_local env <<< "$item"
            if [[ "$i" == "$sel" ]]; then
                selected="$item"
                break
            fi
        done

        if [[ -z "$selected" ]]; then
            bad "无效选择"
            exit 1
        fi

        IFS='|' read -r i type name desc install install_local env <<< "$selected"

        case "$type" in
            MISSING)
                echo -e "\n安装 $name"
                read -p "确认安装? [y/N] " confirm
                if [[ "$confirm" == "y" ]]; then
                    do_install_mcp "$name" "$install" "$env"
                fi
                ;;
            FAILED)
                echo -e "\n修复 $name"
                if [[ -n "$install_local" ]]; then
                    info "将执行: $install_local"
                    read -p "继续? [y/N] " confirm
                    if [[ "$confirm" == "y" ]]; then
                        eval "$install_local" 2>&1 | tail -3
                        if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                            do_install_mcp "$name" "$install" ""
                        fi
                    fi
                else
                    warn "没有本地安装命令可用"
                fi
                ;;
            RUNTIME)
                echo -e "\n配置 $name 的 API Key"
                IFS='|' read -r _ _ key_env key_url <<< "$selected"
                [[ -n "$key_url" ]] && info "  Key 地址: $key_url"
                echo -n "  请输入 $key_env: "
                read -s new_key
                echo ""
                if [[ -n "$new_key" ]]; then
                    result=$(update_mcp_key "$name" "$key_env" "$new_key")
                    if [[ "$result" == "ok" ]]; then
                        good "  ✅ Key 已配置"
                    else
                        bad "  ❌ 配置失败: $result"
                    fi
                else
                    info "  已跳过"
                fi
                ;;
            EXTRA)
                echo -e "\n从环境移除 $name"
                read -p "确认移除? [y/N] " confirm
                if [[ "$confirm" == "y" ]]; then
                    claude mcp remove $name 2>/dev/null && good "✅ 已移除" || bad "❌"
                fi
                ;;
        esac
        ;;

    *)
        info "已跳过"
        ;;
esac

# 安装完成后，重新检查 MCP 注册状态并配置 Key
echo ""
title "📋 安装后检查"

# 重新获取已注册的 MCP
declare -A NewRegisteredMcp
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*([^:]+): ]]; then
        NewRegisteredMcp["${BASH_REMATCH[1]}"]=1
    fi
done < <(claude mcp list 2>&1 | grep -v "^Checking" | grep -v "^$" || true)

# 检查是否有新的 MCP 已注册但 Key 还未配置
echo "检查已注册的 MCP Key 配置状态..."

has_new_keys=false
while IFS='|' read -r name desc type install install_local needs_key key_env key_url; do
    [[ -z "$name" ]] && continue
    [[ "$needs_key" != "true" ]] && continue
    [[ -z "$key_env" ]] && continue

    # 检查是否已注册
    mcp_name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    registered=false
    for key in "${!NewRegisteredMcp[@]}"; do
        if [[ "${key,,}" == "$mcp_name_lower" ]]; then
            registered=true
            break
        fi
    done

    if [[ "$registered" == "true" ]]; then
        current_key=$(get_current_key "$name" "$key_env")
        if [[ -z "$current_key" ]]; then
            has_new_keys=true
            echo -e "\n  $name ($desc)"
            info "  Key 地址: $key_url"
            echo -n "  请输入 $key_env: "
            read -s new_key
            echo ""
            if [[ -n "$new_key" ]]; then
                result=$(update_mcp_key "$name" "$key_env" "$new_key")
                if [[ "$result" == "ok" ]]; then
                    good "  ✅ Key 已配置"
                else
                    bad "  ❌ 配置失败: $result"
                fi
            else
                info "  已跳过"
            fi
        fi
    fi
done <<< "$McpNames"

if [[ "$has_new_keys" == "false" ]]; then
    good "✅ 所有已注册的 MCP Key 都已配置"
fi

echo ""
title "✅ MCP 检查完成"
echo "提示: 可以在 Claude Code 中执行 /mcp 查看已注册的 MCP"
