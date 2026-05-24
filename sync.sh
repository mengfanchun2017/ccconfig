#!/bin/bash
# sync.sh — 另一终端一键同步 ccconfig
#
# 用法:
#   bash ccconfig/sync.sh           # 拉取 + 重建链接 + skills + 依赖检查 + 摘要
#   bash ccconfig/sync.sh --force   # 强制远程覆盖本地（丢弃本地改动）
#   bash ccconfig/sync.sh --check   # 仅检查（不拉取）
#
# 与 gitforce.sh 的区别：sync.sh 专注"另一终端追赶"，多了 dep 检查和变更摘要。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; GRAY='\033[0;90m'; NC='\033[0m'

MODE="${1:-pull}"

banner() {
    echo ""
    echo -e "${CYAN}🔄 ccconfig 同步${NC}"
    echo ""
}

# ========== 拉取 ==========
do_pull() {
    echo -e "${CYAN}── 拉取远程 ──${NC}"

    git -C "$SCRIPT_DIR" fetch origin main --prune 2>/dev/null || {
        echo -e "  ${RED}❌ 无法连接远程${NC}"
        return 1
    }

    local before after
    before=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
    after=$(git -C "$SCRIPT_DIR" rev-parse --short origin/main)

    if [ "$before" = "$after" ]; then
        echo -e "  ${GREEN}✅ 已是最新${NC} ($before)"
        return 0
    fi

    if [ "$MODE" = "--force" ]; then
        echo -e "  ${YELLOW}强制远程覆盖本地...${NC}"
        git -C "$SCRIPT_DIR" reset --hard origin/main
        git -C "$SCRIPT_DIR" clean -fd 2>/dev/null || true
        echo -e "  ${GREEN}✅ $before → $after${NC}"
    else
        echo -e "  ${CYAN}$before → $after${NC}"
        local pull_output pull_ok=true
        set +e
        pull_output=$(git -C "$SCRIPT_DIR" pull --ff-only origin main 2>&1)
        local pull_status=$?
        set -e

        if [ $pull_status -eq 0 ]; then
            echo -e "  ${GREEN}✅ 拉取成功${NC}"
        else
            echo -e "  ${RED}❌ 拉取失败${NC}"
            echo "$pull_output" | tail -3
            echo ""
            echo -e "  ${YELLOW}可能原因: 本地有未提交改动 或 分支已分叉${NC}"
            echo -e "  ${GRAY}强制同步: bash ccconfig/sync.sh --force${NC}"
            echo -e "  ${GRAY}手动处理: cd $SCRIPT_DIR && git status${NC}"
            return 1
        fi
    fi

    # 变更文件列表
    local changed
    changed=$(git -C "$SCRIPT_DIR" diff --name-only "$before" "$after" 2>/dev/null || echo "")
    if [ -n "$changed" ]; then
        echo ""
        echo -e "  ${GRAY}变更文件:${NC}"
        echo "$changed" | while read f; do
            echo -e "    ${GRAY}$f${NC}"
        done
    fi
}

# ========== 重建链接 ==========
do_links() {
    echo ""
    echo -e "${CYAN}── 重建符号链接 ──${NC}"
    if [ -x "$SCRIPT_DIR/setup-links.sh" ]; then
        bash "$SCRIPT_DIR/setup-links.sh"
    else
        echo -e "  ${RED}❌ setup-links.sh 不存在${NC}"
    fi
}

# ========== 同步 Skills ==========
do_skills() {
    echo ""
    echo -e "${CYAN}── 同步 Skills ──${NC}"
    if [ -x "$SCRIPT_DIR/init-skill.sh" ]; then
        bash "$SCRIPT_DIR/init-skill.sh" sync
    else
        echo -e "  ${RED}❌ init-skill.sh 不存在${NC}"
    fi
}

# ========== 依赖检查 ==========
do_deps() {
    echo ""
    echo -e "${CYAN}── 依赖检查 ──${NC}"
    if [ -x "$SCRIPT_DIR/deps-check.sh" ]; then
        bash "$SCRIPT_DIR/deps-check.sh" --required
    else
        echo -e "  ${RED}❌ deps-check.sh 不存在${NC}"
    fi
}

# ========== 新配置文件检测 ==========
do_new_configs() {
    local new_examples=()
    for example in "$SCRIPT_DIR"/conf/*.json.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .example)
        local target="$SCRIPT_DIR/conf/$base"
        if [ ! -f "$target" ]; then
            new_examples+=("$base")
            cp "$example" "$target"
            echo -e "  ${GREEN}✅${NC} 新建 $base (从 .example 复制)"
        fi
    done
    if [ ${#new_examples[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️ 请编辑新配置文件填入个人凭证${NC}"
    fi
}

# ========== 摘要 ==========
do_summary() {
    echo ""
    echo -e "${CYAN}── 同步摘要 ──${NC}"
    echo ""

    local last_commit last_date
    last_commit=$(git -C "$SCRIPT_DIR" log -1 --format="%h %s" 2>/dev/null)
    last_date=$(git -C "$SCRIPT_DIR" log -1 --format="%ci" 2>/dev/null | cut -d' ' -f1)

    echo -e "  最后提交: ${GREEN}$last_commit${NC}"
    echo -e "  提交日期: ${GRAY}$last_date${NC}"

    # 检查 auto-sync
    local pid_file="$SCRIPT_DIR/.monitor-sync.pid"
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo -e "  auto-sync: ${GREEN}✅ 运行中${NC}"
    else
        echo -e "  auto-sync: ${YELLOW}○ 未运行${NC}"
    fi

    # 配置链接状态
    if [ -L "$HOME/.claude/settings.json" ]; then
        echo -e "  配置链接: ${GREEN}✅${NC}"
    else
        echo -e "  配置链接: ${YELLOW}○ 未就绪${NC}"
    fi

    echo ""
    echo -e "  ${GRAY}完整检查: bash ccconfig/status.sh${NC}"
    echo -e "  ${GRAY}启动同步: bash ccconfig/monitor.sh start${NC}"
    echo ""
}

# ========== 主流程 ==========
case "$MODE" in
    --check)
        banner
        do_deps
        do_summary
        ;;
    --force)
        banner
        do_pull || true
        do_links
        do_skills
        do_new_configs
        do_deps
        do_summary
        echo -e "${GREEN}✅ 强制同步完成${NC}"
        ;;
    pull|"")
        banner
        do_pull || exit 1
        do_links
        do_skills
        do_new_configs
        do_deps
        do_summary
        echo -e "${GREEN}✅ 同步完成${NC}"
        ;;
    *)
        echo "用法: $0 [--force|--check]"
        ;;
esac
