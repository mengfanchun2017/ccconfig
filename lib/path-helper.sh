#!/bin/bash
# ==============================================
# path-helper.sh — 动态路径解析库
#
# 功能：
#   - find_node_bin()    多策略发现 Node.js 安装路径
#   - get_version()      读取 versions.json 中的版本
#   - save_version()     写入版本到 versions.json
#   - recreate_node_symlinks()  重建 ~/.local/bin/{node,npm,npx} 符号链接
#
# 用法：source "$SCRIPT_DIR/path-helper.sh"
# ==============================================

# 自动检测自身所在目录（被 source 时 BASH_SOURCE[0] 指向本文件）
_PATH_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_VERSION_FILE="$_PATH_HELPER_DIR/../conftemp/versions.json"
_LOCAL_BIN="$HOME/.local/bin"
_LOCAL_DIR="$HOME/.local"

export CCCONFIG_HOME="${CCCONFIG_HOME:-$HOME/git/ccconfig}"
export CCPRIVATE_HOME="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

# ========== 版本文件读取 ==========

get_version() {
    local component="$1"
    python3 - "$_VERSION_FILE" "$component" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('components', {}).get(sys.argv[2], {}).get('version', ''))
except:
    print('')
PYEOF
}

save_version() {
    local component="$1"
    local new_version="$2"
    python3 - "$_VERSION_FILE" "$component" "$new_version" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    data.setdefault('components', {})
    # 保留已有字段，只更新 version
    existing = data['components'].get(sys.argv[2], {})
    if isinstance(existing, dict):
        existing['version'] = sys.argv[3]
    else:
        existing = {'version': sys.argv[3]}
    data['components'][sys.argv[2]] = existing
    data['last_checked'] = __import__('datetime').datetime.now().astimezone().isoformat()
    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print('ok')
except Exception as e:
    print(f'error: {e}')
PYEOF
}

get_node_version() {
    get_version "node"
}

get_node_pin() {
    python3 - "$_VERSION_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    pin = data.get('components', {}).get('node', {}).get('pin', '')
    print(pin)
except:
    print('')
PYEOF
}

get_gh_version() {
    get_version "gh"
}

get_cconnect_version() {
    get_version "cc_connect"
}

# ========== Node.js 路径发现（核心函数）==========

# 多策略发现当前 Node.js 安装的 bin 目录
# 返回路径如 $HOME/.local/node-v20.11.0-linux-x64/bin
find_node_bin() {
    local found

    # 策略 1: 跟随 ~/.local/bin/node 符号链接
    if [ -L "$_LOCAL_BIN/node" ]; then
        found=$(readlink -f "$_LOCAL_BIN/node" 2>/dev/null)
        if [ -n "$found" ] && [ -x "$found" ]; then
            dirname "$found"
            return 0
        fi
    fi

    # 策略 2: 扫描 ~/.local/node-v*-linux-x64/，取最高版本
    found=$(ls -d "$_LOCAL_DIR"/node-v*-linux-x64/bin/node 2>/dev/null | sort -V | tail -1)
    if [ -n "$found" ] && [ -x "$found" ]; then
        dirname "$found"
        return 0
    fi

    # 策略 3: 回退到 versions.json 中记录的版本
    local ver
    ver=$(get_node_version)
    if [ -n "$ver" ] && [ -x "$_LOCAL_DIR/node-v${ver}-linux-x64/bin/node" ]; then
        echo "$_LOCAL_DIR/node-v${ver}-linux-x64/bin"
        return 0
    fi

    # 策略 4: 最终回退 ~/.local/bin
    echo "$_LOCAL_BIN"
    return 1
}

# 重建 ~/.local/bin/{node,npm,npx} 符号链接
recreate_node_symlinks() {
    local node_bin_dir="$1"

    if [ -z "$node_bin_dir" ]; then
        node_bin_dir=$(find_node_bin)
    fi

    mkdir -p "$_LOCAL_BIN"

    ln -sf "$node_bin_dir/node" "$_LOCAL_BIN/node"
    ln -sf "$node_bin_dir/npm"  "$_LOCAL_BIN/npm"
    ln -sf "$node_bin_dir/npx"  "$_LOCAL_BIN/npx"

    echo "Node symlinks → $node_bin_dir"
}

# ========== 配置文件检查与模板复制 ==========

# 检查配置文件是否存在，不存在则从 .example 模板复制并提示用户
# 用法: ensure_config <config_file> [friendly_name]
# 返回: 0=配置已就绪, 1=模板已复制(需用户编辑后重试)
ensure_config() {
    local config_file="$1"
    local friendly_name="${2:-$(basename "$config_file")}"

    if [ -f "$config_file" ]; then
        return 0
    fi

    # 处理 broken symlink（ccprivate 不在时 conftemp/*.json → ccprivate 的 symlink 断链）
    if [ -L "$config_file" ] && [ ! -e "$config_file" ]; then
        rm -f "$config_file"
    fi

    local example_file="${config_file}.example"
    if [ -f "$example_file" ]; then
        echo ""
        echo -e "\033[1;33m⚠️  配置文件不存在: ${friendly_name}\033[0m"
        echo -e "   从模板复制: ${example_file}"
        cp "$example_file" "$config_file"
        echo ""
        echo -e "\033[0;36m📝 请编辑配置文件填入你的信息:\033[0m"
        echo "   vim ${config_file}"
        echo ""
        echo "   编辑完成后重新运行此脚本"
        return 1
    else
        echo ""
        echo -e "\033[0;31m❌ 配置文件 ${config_file} 和模板 ${example_file} 都不存在\033[0m"
        return 1
    fi
}

# 确保 PATH 包含正确的 Node 和 local bin
