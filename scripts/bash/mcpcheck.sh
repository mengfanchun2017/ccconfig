#!/bin/bash
# Claude Code MCP 检查脚本
# 功能：对比 mcplist.json 与当前环境，提供专业交互选项

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
        args_list = m.get('args', [])
        args_str = ' '.join(args_list) if args_list else ''
        print(f"{name}|{desc}|{mtype}|{install}|{args_str}")
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

# 添加 MCP 到列表
add_mcp_to_list() {
    python3 - "$MCP_LIST_FILE" "$1" << 'PYTHON_EOF'
import json
import sys

try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)

    name = sys.argv[2]
    # 检查是否已存在
    if any(m.get('name') == name for m in data.get('mcp', [])):
        print(f"  {name} 已存在于列表中")
        return

    data['mcp'].append({
        'name': name,
        'description': '（待补充）',
        'type': 'http'
    })

    with open(sys.argv[1], 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print('ok')
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
}

# 获取当前已安装的 MCP
declare -A InstalledMcp
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*([^:]+): ]]; then
        InstalledMcp["${BASH_REMATCH[1]}"]=1
    fi
done < <(claude mcp list 2>&1 || true)

# ========== 读取列表 ==========
McpNames=$(read_mcp_list)

# ========== 对比分析 ==========
Matched=""
MissingFromList=""
ExtraInEnv=""

# 检查列表中的每个 MCP
while IFS='|' read -r name desc type install args; do
    [[ -z "$name" ]] && continue
    full_cmd="$install $args"
    if [[ -n "${InstalledMcp[$name]}" ]]; then
        Matched="$Matched$name|$desc\n"
    else
        MissingFromList="$MissingFromList$name|$desc|$type|$full_cmd\n"
    fi
done <<< "$McpNames"

# 检查环境中的 MCP 是否在列表中
for env_name in "${!InstalledMcp[@]}"; do
    found=$(mcp_exists_in_list "$env_name")
    if [[ "$found" == "false" ]]; then
        ExtraInEnv="$ExtraInEnv$env_name\n"
    fi
done

# ========== 显示结果 ==========
title "Claude Code MCP 检查"

# 匹配的部分
if [[ -n "$Matched" ]]; then
    section "✅ 列表与环境一致"
    while IFS='|' read -r name desc; do
        good "✓ $name: $desc"
    done <<< "$Matched"
fi

# 缺失的部分
if [[ -n "$MissingFromList" ]]; then
    section "❌ 列表中有但环境缺失"
    while IFS='|' read -r name desc type install args; do
        [[ -z "$name" ]] && continue
        [[ "$type" == "http" ]] && type_tag="[HTTP]" || type_tag="[STDIO]"
        item "$name - $desc $type_tag"
    done <<< "$MissingFromList"
fi

# 多出的部分
if [[ -n "$ExtraInEnv" ]]; then
    section "⚠️ 环境中有但列表缺失"
    while read -r name; do
        [[ -n "$name" ]] && item "$name"
    done <<< "$ExtraInEnv"
fi

# ========== 交互菜单 ==========
has_diff=false
[[ -n "$MissingFromList" ]] || [[ -n "$ExtraInEnv" ]] && has_diff=true

if [[ "$has_diff" == "false" ]]; then
    title "检查完成"
    good "✅ 列表与环境完全一致，无需操作"
    exit 0
fi

title "请选择操作"

echo -e "  1) 安装所有缺失的 MCP 到现有环境${NC}"
echo -e "  2) 补充缺失项到 mcplist.json${NC}"

if [[ -n "$ExtraInEnv" ]]; then
    echo -e "  3) 双向同步（安装+补充）${NC}"
fi

echo -e "  4) 单独安装某个 MCP（按名称选择）${NC}"
echo -e "  5) 单独添加到列表（按名称选择）${NC}"
echo -e "  0) 跳过，不做任何修改${GRAY}"
echo ""

read -p "请输入选项 [0-5]: " choice
echo ""

case "$choice" in
    1)
        # 安装缺失的 MCP 到环境
        title "安装 MCP 到环境"
        installed=0
        skipped=0

        while IFS='|' read -r name desc type install args; do
            [[ -z "$name" ]] && continue

            if [[ "$type" == "http" ]]; then
                info "⏭ $name: HTTP 类型需手动配置，跳过"
                ((skipped++))
                continue
            fi

            echo -n "安装: $name ... "
            if claude mcp add $name -- $install $args 2>/dev/null; then
                good "✅"
                ((installed++))
            else
                bad "❌"
            fi
        done <<< "$MissingFromList"

        echo ""
        good "✅ 完成：已安装 $installed 个，跳过 $skipped 个（HTTP类型）"
        ;;

    2)
        # 补充缺失项到 mcplist.json
        title "补充到 mcplist.json"

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

        echo ""
        good "✅ 已更新 mcplist.json，请补充描述信息"
        ;;

    3)
        if [[ -z "$ExtraInEnv" ]]; then
            bad "❌ 没有多出的项目，无法双向同步"
            exit 1
        fi

        title "双向同步"

        # 先补充列表
        info "1/2: 补充列表..."
        while read -r name; do
            [[ -z "$name" ]] && continue
            add_mcp_to_list "$name" > /dev/null
        done <<< "$ExtraInEnv"
        good "✅ 列表已更新"

        # 再安装缺失
        info "2/2: 安装缺失..."
        installed=0
        while IFS='|' read -r name desc type install args; do
            [[ -z "$name" ]] && continue
            [[ "$type" == "http" ]] && continue
            if claude mcp add $name -- $install $args 2>/dev/null; then
                ((installed++))
            fi
        done <<< "$MissingFromList"
        good "✅ 完成：安装 $installed 个，列表 +$(echo -e "$ExtraInEnv" | grep -c .) 个"
        ;;

    4)
        # 单独安装某个 MCP
        title "单独安装 MCP"

        section "可安装的 MCP（不在环境中）:"
        i=1
        installable=()
        while IFS='|' read -r name desc type install args; do
            [[ -z "$name" ]] && continue
            [[ "$type" == "http" ]] && continue
            echo -e "  $i) $name - $desc${NC}"
            installable+=("$i|$name|$install $args")
            ((i++))
        done <<< "$MissingFromList"

        if [[ ${#installable[@]} -eq 0 ]]; then
            info "没有可安装的 MCP（HTTP 类型需手动配置）"
            exit 0
        fi

        echo ""
        read -p "请输入编号 [1-${#installable[@]}]，或 0 取消: " sel

        if [[ "$sel" == "0" || -z "$sel" ]]; then
            info "已取消"
            exit 0
        fi

        selected=$(echo "${installable[@]}" | tr ' ' '\n' | grep "^$sel|")
        if [[ -n "$selected" ]]; then
            name=$(echo "$selected" | cut -d'|' -f2)
            install_cmd=$(echo "$selected" | cut -d'|' -f3-)
            echo -n "安装: $name ... "
            if claude mcp add $name -- $install_cmd 2>/dev/null; then
                good "✅ 安装成功"
            else
                bad "❌"
            fi
        else
            bad "❌ 无效选择"
        fi
        ;;

    5)
        # 单独添加到列表
        title "单独添加到列表"

        section "可添加的 MCP（不在列表中）:"
        i=1
        addable=()
        while read -r name; do
            [[ -z "$name" ]] && continue
            echo -e "  $i) $name${NC}"
            addable+=("$i|$name")
            ((i++))
        done <<< "$ExtraInEnv"

        if [[ ${#addable[@]} -eq 0 ]]; then
            info "没有可添加的 MCP"
            exit 0
        fi

        echo ""
        read -p "请输入编号 [1-${#addable[@]}]，或 0 取消: " sel

        if [[ "$sel" == "0" || -z "$sel" ]]; then
            info "已取消"
            exit 0
        fi

        selected=$(echo "${addable[@]}" | tr ' ' '\n' | grep "^$sel|")
        if [[ -n "$selected" ]]; then
            name=$(echo "$selected" | cut -d'|' -f2)
            echo -n "添加: $name ... "
            result=$(add_mcp_to_list "$name")
            if [[ "$result" == "ok" ]]; then
                good "✅ 已添加，请补充描述信息"
            else
                echo "$result"
            fi
        else
            bad "❌ 无效选择"
        fi
        ;;

    *)
        info "已跳过，未做任何修改"
        ;;
esac
