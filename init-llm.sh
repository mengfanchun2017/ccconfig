#!/bin/bash
# ==============================================
# LLM 配置管理脚本
# 功能：
#   - 列出所有可用 LLM
#   - 切换 LLM
#   - 查看当前 LLM
#
# 使用：
#   bash ccconfig/llminit.sh               # 交互式选择
#   bash ccconfig/llminit.sh list          # 仅列出
#   bash ccconfig/llminit.sh <name>        # 直接切换
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/conf/llm.json"
CLAUDE_JSON="$HOME/.claude.json"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# ========== 读取配置 ==========
list_llms() {
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    config = json.load(f)

llms = config.get('llms', {})
current = config.get('current', '')

names = list(llms.keys())
print(f"TOTAL:{len(names)}")
print(f"CURRENT:{current}")

for name in names:
    llm = llms[name]
    marker = "◀" if name == current else " "
    print(f"{marker} {name} | {llm.get('name', name)} | {llm.get('model', '')} | {llm.get('base_url', '')}")
PYEOF
}

get_llm_config() {
    local target="$1"
    python3 - "$CONFIG_FILE" "$target" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    config = json.load(f)

target = sys.argv[2]
llms = config.get('llms', {})

if target not in llms:
    print("ERROR:Unknown LLM")
    sys.exit(1)

llm = llms[target]
print(f"{llm.get('base_url', '')}|{llm.get('model', '')}|{llm.get('key', '')}")
PYEOF
}

# ========== 切换 LLM ==========
switch_llm() {
    local name="$1"

    # 获取配置
    CONFIG=$(get_llm_config "$name") || { error "无法获取 LLM 配置: $name"; return 1; }
    IFS='|' read -r BASE_URL MODEL_NAME API_KEY <<< "$CONFIG"

    info "切换到: $name"
    info "  API: $BASE_URL"
    info "  模型: $MODEL_NAME"

    # 先 export，让 heredoc 里的 Python 能读到
    export BASE_URL MODEL_NAME API_KEY

    # 更新 ~/.claude.json
    python3 << 'PYEOF'
import json, os

config_file = os.path.expanduser(os.environ.get('CLAUDE_JSON', '~/.claude.json'))
try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except:
    config = {}

if 'env' not in config:
    config['env'] = {}

config['env'].update({
    "ANTHROPIC_BASE_URL": os.environ.get('BASE_URL', ''),
    "ANTHROPIC_AUTH_TOKEN": os.environ.get('API_KEY', ''),
    "ANTHROPIC_MODEL": os.environ.get('MODEL_NAME', ''),
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
})

with open(config_file, 'w') as f:
    json.dump(config, f, indent=4)
print("~/.claude.json 已更新")
PYEOF

    # 更新 ~/.claude/settings.json（Claude Code 实际读取）
    python3 << 'PYEOF'
import json, os

settings_file = os.path.expanduser("~/.claude/settings.json")
try:
    with open(settings_file, 'r') as f:
        config = json.load(f)
except:
    config = {}

if 'env' not in config:
    config['env'] = {}

config['env'].update({
    "ANTHROPIC_BASE_URL": os.environ.get('BASE_URL', ''),
    "ANTHROPIC_AUTH_TOKEN": os.environ.get('API_KEY', ''),
    "ANTHROPIC_MODEL": os.environ.get('MODEL_NAME', ''),
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
})

# 如果 settings_file 是损坏的符号链接，先删除
if os.path.islink(settings_file) and not os.path.exists(settings_file):
    os.unlink(settings_file)

with open(settings_file, 'w') as f:
    json.dump(config, f, indent=4)
print("~/.claude/settings.json 已更新")
PYEOF

    # 更新 conf/llm.json 的 current
    export CONFIG_FILE NAME="$name"
    python3 << 'PYEOF'
import json, os

config_file = os.environ['CONFIG_FILE']
name = os.environ['NAME']

with open(config_file, 'r') as f:
    config = json.load(f)

config['current'] = name

with open(config_file, 'w') as f:
    json.dump(config, f, indent=4)
print("conf/llm.json 已更新")
PYEOF

    success "LLM 已切换为: $name"
}

# ========== 显示列表 ==========
show_list() {
    echo ""
    echo "可用 LLM："
    echo ""
    list_llms | tail -n +2 | while IFS='|' read -r marker name model url; do
        if [[ "$marker" == "TOTAL:"* ]] || [[ "$marker" == "CURRENT:"* ]]; then
            continue
        fi
        if [[ "$url" == "CURRENT:"* ]] || [[ "$marker" == "" && "$name" == "" ]]; then
            continue
        fi
        printf "  %s %-10s %-10s %s\n" "$marker" "$name" "$model" ""
    done
    echo ""

    current=$(grep "^CURRENT:" <(list_llms) | cut -d: -f2)
    if [[ -n "$current" ]]; then
        info "当前: $current"
    fi
}

# ========== 交互式选择 ==========
interactive_select() {
    echo ""
    echo "请选择 LLM："
    echo ""

    local lines=$(list_llms)
    local total=$(echo "$lines" | grep "^TOTAL:" | cut -d: -f2)
    local current=$(echo "$lines" | grep "^CURRENT:" | cut -d: -f2)

    # 显示选项
    local idx=1
    local names=()
    while IFS='|' read -r marker name model url; do
        if [[ "$marker" == "TOTAL:"* ]] || [[ "$marker" == "CURRENT:"* ]]; then
            continue
        fi
        if [[ -z "$name" ]]; then
            continue
        fi
        names+=("$name")
        if [[ "$marker" == "◀" ]]; then
            printf "  %d) %s (%s) ◀ 当前\n" "$idx" "$name" "$model"
        else
            printf "  %d) %s (%s)\n" "$idx" "$name" "$model"
        fi
        ((idx++))
    done < <(echo "$lines")

    echo ""
    printf "请输入数字 [1-%d] 或直接回车保持当前: " "$total"
    read -r choice

    if [[ -z "$choice" ]]; then
        info "保持当前: $current"
        return 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$total" ]]; then
        target="${names[$((choice-1))]}"
        switch_llm "$target"
    else
        error "无效选择: $choice"
        return 1
    fi
}

# ========== 主流程 ==========
main() {
    local cmd="${1:-}"

    if [[ "$cmd" == "list" ]]; then
        show_list
    elif [[ -z "$cmd" ]]; then
        # 无参数：交互式选择
        interactive_select
    else
        # 直接指定 LLM 名称
        switch_llm "$cmd"
    fi
}

main "$@"