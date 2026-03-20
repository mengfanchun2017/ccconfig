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
        args_list = m.get('args', [])
        args_str = ' '.join(args_list) if args_list else ''
        env_list = m.get('env', {})
        env_str = ' '.join([f"{k}={v}" for k, v in env_list.items()]) if env_list else ''
        print(f"{name}|{desc}|{mtype}|{install}|{install_local}|{args_str}|{env_str}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
}

# 检查某个 MCP 是否存在于列表中
mcp_exists_in_list() {
    python3 - "$MCP_LIST_FILE" "$1" << 'PYTHON_EOF'
import json
import sys

try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    name = sys.argv[2]
    exists = any(m.get('name') == name for m in data.get('mcp', []))
    print('true' if exists else 'false')
except:
    print('false')
PYTHON_EOF
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

# ========== 对比分析 ==========
Matched=""
MissingFromList=""
ExtraInEnv=""
FailedCmd=""

# 检查列表中的每个 MCP
while IFS='|' read -r name desc type install install_local args env; do
    [[ -z "$name" ]] && continue

    if [[ -n "${RegisteredMcp[$name]}" ]]; then
        # MCP 已注册，检测命令是否实际可用
        # 解析 install 命令获取 command 和 args
        cmd_parts=($install)
        cmd="${cmd_parts[0]}"
        install_args="${install#$cmd }"

        if ! check_mcp_command "$cmd" "$install_args"; then
            # 命令不可用
            if [[ -n "$install_local" ]]; then
                FailedCmd="$FailedCmd$name|$desc|$install|$install_local\n"
            else
                FailedCmd="$FailedCmd$name|$desc|$install|\n"
            fi
        else
            Matched="$Matched$name|$desc\n"
        fi
    else
        # MCP 未注册
        MissingFromList="$MissingFromList$name|$desc|$type|$install|$install_local|$env\n"
    fi
done <<< "$McpNames"

# 检查环境中的 MCP 是否在列表中
for env_name in "${!RegisteredMcp[@]}"; do
    found=$(mcp_exists_in_list "$env_name")
    if [[ "$found" == "false" ]]; then
        ExtraInEnv="$ExtraInEnv$env_name\n"
    fi
done

# ========== 显示结果 ==========

# 正常的部分
if [[ -n "$Matched" ]]; then
    section "✅ 正常工作"
    while IFS='|' read -r name desc; do
        good "✓ $name: $desc"
    done <<< "$Matched"
fi

# 缺失的部分
if [[ -n "$MissingFromList" ]]; then
    section "❌ 列表中有但未注册"
    while IFS='|' read -r name desc type install install_local env; do
        [[ -z "$name" ]] && continue
        [[ "$type" == "http" ]] && type_tag="[HTTP]" || type_tag="[STDIO]"
        item "$name - $desc $type_tag"
        info "  安装命令: $install"
        if [[ -n "$env" ]]; then
            info "  环境变量: $env"
        fi
    done <<< "$MissingFromList"
fi

# 命令无效的部分
if [[ -n "$FailedCmd" ]]; then
    section "⚠️ 注册了但命令不可用"
    while IFS='|' read -r name desc install install_local; do
        [[ -z "$name" ]] && continue
        item "$name: $install"
        if [[ -n "$install_local" ]]; then
            info "  本地安装: $install_local"
        fi
    done <<< "$FailedCmd"
fi

# 多出的部分
if [[ -n "$ExtraInEnv" ]]; then
    section "⚠️ 环境中注册但列表中无"
    while read -r name; do
        [[ -n "$name" ]] && item "$name"
    done <<< "$ExtraInEnv"
fi

# ========== 总结 ==========
total_list=$(echo "$McpNames" | grep -c "^[^|]")
total_matched=$(echo "$Matched" | grep -c "^[^|]")
total_missing=$(echo "$MissingFromList" | grep -c "^[^|]")
total_failed=$(echo "$FailedCmd" | grep -c "^[^|]")
total_extra=$(echo "$ExtraInEnv" | grep -c "^[^|]")

section "统计"
item "列表中: $total_list | 正常: $total_matched | 缺失: $total_missing | 失败: $total_failed | 多余: $total_extra"

# ========== 交互菜单 ==========
has_action_needed=false
[[ -n "$MissingFromList" ]] || [[ -n "$FailedCmd" ]] || [[ -n "$ExtraInEnv" ]] && has_action_needed=true

if [[ "$has_action_needed" == "false" ]]; then
    title "检查完成"
    good "✅ 所有 MCP 都正常工作"
    exit 0
fi

title "请选择操作"

echo -e "  1) 安装缺失的 MCP（需要命令可用）${NC}"
echo -e "  2) 修复命令不可用的 MCP${NC}"

if [[ -n "$FailedCmd" ]]; then
    echo -e "  3) 尝试自动修复（使用 install_local）${NC}"
fi

echo -e "  4) 补充缺失项到 mcplist.json${NC}"

if [[ -n "$ExtraInEnv" ]]; then
    echo -e "  5) 双向同步（安装+补充）${NC}"
fi

echo -e "  6) 单独处理某个 MCP${NC}"
echo -e "  0) 跳过，不做任何修改${GRAY}"
echo ""

read -p "请输入选项 [0-6]: " choice
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

    if claude mcp add $name -- $install_cmd 2>&1; then
        good "✅"
        return 0
    else
        bad "❌"
        return 1
    fi
}

case "$choice" in
    1)
        # 安装缺失的 MCP
        title "安装缺失的 MCP"

        if [[ -z "$available_managers" ]]; then
            bad "❌ 没有可用的包管理器，无法安装"
            bad "请先安装 Node.js (npm) 或 Python (pip)"
            exit 1
        fi

        while IFS='|' read -r name desc type install install_local env; do
            [[ -z "$name" ]] && continue

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

            do_install_mcp "$name" "$install" "$env"
        done <<< "$MissingFromList"
        ;;

    2)
        # 修复命令不可用的 MCP
        title "修复命令不可用的 MCP"

        while IFS='|' read -r name desc install install_local; do
            [[ -z "$name" ]] && continue

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
        done <<< "$FailedCmd"
        ;;

    3)
        # 自动修复
        title "自动修复"

        fixed=0
        while IFS='|' read -r name desc install install_local; do
            [[ -z "$name" ]] && continue
            [[ -z "$install_local" ]] && continue

            echo -n "修复 $name ... "

            # 尝试安装
            if eval "$install_local" &>/dev/null; then
                # 安装成功，重新注册
                if claude mcp add $name -- $install &>/dev/null; then
                    good "✅"
                    ((fixed++))
                else
                    bad "❌ 注册失败"
                fi
            else
                bad "❌ 安装失败"
            fi
        done <<< "$FailedCmd"

        good "✅ 完成：修复 $fixed 个"
        ;;

    4)
        # 补充缺失项到 mcplist.json
        title "补充到 mcplist.json"

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
        return

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

        while read -r name; do
            [[ -z "$name" ]] && continue
            echo -n "添加: $name ... "
            result=$(add_mcp_to_list "$name")
            if [[ "$result" == "ok" ]]; then
                good "✅"
            else
                echo "$result"
            fi
        done <<< "$ExtraInEnv"

        good "✅ 已更新 mcplist.json，请补充描述信息"
        ;;

    5)
        # 双向同步
        title "双向同步"

        # 补充列表
        info "1/2: 补充列表..."
        add_mcp_to_list() {
            python3 - "$MCP_LIST_FILE" "$1" << 'PYEOF'
import json
import sys
with open(sys.argv[1], 'r') as f: data = json.load(f)
name = sys.argv[2]
if not any(m.get('name') == name for m in data.get('mcp', [])):
    data['mcp'].append({'name': name, 'description': '（待补充）', 'type': 'stdio'})
    with open(sys.argv[1], 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
        }
        while read -r name; do
            [[ -z "$name" ]] && continue
            add_mcp_to_list "$name" 2>/dev/null
        done <<< "$ExtraInEnv"
        good "✅ 列表已更新"

        # 安装缺失
        info "2/2: 安装缺失..."
        installed=0
        while IFS='|' read -r name desc type install install_local env; do
            [[ -z "$name" ]] && continue
            [[ "$type" == "http" ]] && continue

            cmd_parts=($install)
            cmd="${cmd_parts[0]}"
            if [[ "$cmd" == "npx" && ! -v available_managers =~ npx ]]; then
                continue
            fi

            if do_install_mcp "$name" "$install" "$env"; then
                ((installed++))
            fi
        done <<< "$MissingFromList"
        good "✅ 完成：安装 $installed 个"
        ;;

    6)
        # 单独处理
        title "单独处理"

        all_items=()
        idx=1

        while IFS='|' read -r name desc type install install_local env; do
            [[ -z "$name" ]] && continue
            all_items+=("$idx|MISSING|$name|$desc|$install|$install_local|$env")
            ((idx++))
        done <<< "$MissingFromList"

        while IFS='|' read -r name desc install install_local; do
            [[ -z "$name" ]] && continue
            all_items+=("$idx|FAILED|$name|$desc|$install|$install_local|")
            ((idx++))
        done <<< "$FailedCmd"

        while read -r name; do
            [[ -z "$name" ]] && continue
            all_items+=("$idx|EXTRA|$name|||")
            ((idx++))
        done <<< "$ExtraInEnv"

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
