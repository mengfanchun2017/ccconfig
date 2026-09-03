# setup.bash — bats 测试环境公共配置
# 使用：load "$TEST_DIR/setup"（bats load 找 .bash 后缀）

# 全局路径（setup_file 阶段可用）
TEST_DIR_BASE="$(cd "$(dirname "${BATS_TEST_FILENAME:-$0}")" && pwd)"
CCCONFIG_DIR="$(cd "$TEST_DIR_BASE/.." && pwd)"
LIB_DIR="$CCCONFIG_DIR/lib"

setup() {
    # 颜色输出（静默模式，bats 自动合并 stdout）
    source "$LIB_DIR/colors.sh" 2>/dev/null || true
}

# 隔离临时 home 目录
make_isolated_home() {
    local dir
    dir=$(mktemp -d)
    mkdir -p "$dir/git" "$dir/.claude" "$dir/.local/bin"
    echo "$dir"
}

# 在临时 home 中运行命令
with_isolated_home() {
    local tmp; tmp=$(make_isolated_home)
    HOME="$tmp" PATH="$tmp/.local/bin:$PATH" "$@"
    rm -rf "$tmp"
}
