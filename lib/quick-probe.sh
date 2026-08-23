#!/bin/bash
# quick-probe.sh — 5 个轻量状态探针（每个 < 50ms）
#
# 用于主菜单顶部状态条，避开 status.sh 全量检查（840 行，慢）
#
# 用法：
#   source "$LIB_DIR/quick-probe.sh"
#   echo "$(quick_monitor) $(quick_pat) ..."

# ── Monitor 是否在跑 ──
quick_monitor() {
    if pgrep -f "monitor-sync|monitor\.sh.*run" > /dev/null 2>&1; then
        local pid; pid=$(pgrep -f "monitor-sync" | head -1)
        echo -e "${GREEN}●${NC} ${pid}"
    else
        echo -e "${GRAY}○${NC} -"
    fi
}

# ── PAT 剩余天数（从 conf/feishu.json 或 gh 读 expiry）──
quick_pat() {
    local exp_file="$HOME/.config/gh/pat-expiry"
    if [[ -f "$exp_file" ]]; then
        local exp; exp=$(cat "$exp_file" 2>/dev/null)
        local exp_ts; exp_ts=$(date -d "$exp" +%s 2>/dev/null || echo 0)
        local now; now=$(date +%s)
        if (( exp_ts == 0 )); then
            echo -e "${GRAY}?${NC}天"
        else
            local days=$(( (exp_ts - now) / 86400 ))
            if (( days > 30 )); then
                echo -e "${GREEN}${days}天${NC}"
            elif (( days > 7 )); then
                echo -e "${YELLOW}${days}天${NC}"
            else
                echo -e "${RED}${days}天${NC}"
            fi
        fi
    else
        echo -e "${GRAY}?${NC}"
    fi
}

# ── LLM 网关代理是否在跑 ──
quick_llm() {
    if pgrep -f "openai-bridge|llm-gateway|cc-gateway" > /dev/null 2>&1; then
        echo -e "${GREEN}●${NC}"
    else
        echo -e "${GRAY}○${NC}"
    fi
}

# ── 当前飞书账号 ──
quick_feishu() {
    local marker="$HOME/.lark-cli-account"
    if [[ -f "$marker" ]]; then
        local name; name=$(grep '^name=' "$marker" | cut -d'=' -f2 2>/dev/null)
        echo "${name:-?}"
    else
        echo "-"
    fi
}

# ── ccprivate 待提交数 ──
quick_priv() {
    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
    if [[ -d "$ccpriv/.git" ]]; then
        local pending; pending=$(git -C "$ccpriv" status --porcelain 2>/dev/null | wc -l)
        if (( pending == 0 )); then
            echo -e "${GREEN}clean${NC}"
        else
            echo -e "${YELLOW}${pending} pending${NC}"
        fi
    else
        echo -e "${GRAY}-${NC}"
    fi
}

# ── 顶部状态条（一行） ──
header_status() {
    printf "${CYAN}━━━ ccconfig 运维 ━━━${NC}  %s\n" "$(date '+%H:%M:%S')"
    printf "  ${BOLD}Mon${NC}:%-10s  ${BOLD}PAT${NC}:%-6s  ${BOLD}LLM${NC}:%-3s  ${BOLD}飞书${NC}:%-8s  ${BOLD}ccpriv${NC}:%s\n" \
           "$(quick_monitor)" "$(quick_pat)" "$(quick_llm)" "$(quick_feishu)" "$(quick_priv)"
    echo ""
}
