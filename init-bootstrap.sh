#!/bin/bash
# init-bootstrap.sh — ccconfig 新机器一体化初始化
#
# 合并 bootstrap-gh-auth.sh + init-ccprivate-repo.sh + init-base.sh all
# 为一条命令。新机器只需:
#   git clone <ccconfig.git> ~/git/ccconfig
#   bash init-bootstrap.sh
#
# 子命令:
#   bash init-bootstrap.sh          交互（默认）
#   bash init-bootstrap.sh all      全自动非交互
#   bash init-bootstrap.sh --dry-run 预览
#
# 环境变量:
#   GH_TOKEN            GitHub PAT（CI 友好，跳过 gh auth）
#   CCP_NONINTERACTIVE=1 非交互模式
#   CCP_GH_USER          GitHub 用户名
#   CCP_GIT_EMAIL        Git 邮箱
#   CCP_DEFAULT_LLM      默认 LLM（deepseek/minimax/claude）
#   CCP_LLM_DEEPSEEK_KEY / CCP_LLM_MINIMAX_KEY / CCP_LLM_ANTHROPIC_KEY
#   CCP_SKIP_FEISHU=1    跳过飞书引导

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/interact.sh"
source "$SCRIPT_DIR/lib/dry-run.sh"

if _dry_run_enabled "$@"; then
    echo ""
    echo -e "${CYAN}init-bootstrap — DRY-RUN${NC}"
    echo -e "${CYAN}══════════════════════${NC}"
    echo ""
    echo "  would: Step 1/3 bootstrap-gh-auth.sh（装 gh + GitHub 认证）"
    echo "  would: Step 2/3 init-ccprivate-repo.sh（创建 ccprivate）"
    echo "  would: Step 3/3 init-base.sh all（全量初始化）"
    echo ""
    echo "  === dry-run: no changes applied ==="
    exit 0
fi

banner() {
    echo ""
    echo -e "${CYAN}ccconfig 新机器初始化${NC}"
    echo -e "${CYAN}══════════════════════${NC}"
    echo -e "  ${GRAY}三步合一：GitHub 认证 → ccprivate → 全量系统初始化${NC}"
    echo ""
}

init_all() {
    banner

    # Step 1: gh auth + git 身份
    section "Step 1/3: GitHub 认证"
    echo -e "  ${GRAY}装 gh + GitHub 登录 + 配 git user.name/email${NC}"
    echo ""
    if ! bash "$SCRIPT_DIR/bootstrap-gh-auth.sh"; then
        err "GitHub 认证失败"
        err "  修复后重跑: bash init-bootstrap.sh"
        exit 1
    fi

    # Step 2: ccprivate（创建或克隆）
    section "Step 2/3: ccprivate 私有配置仓库"
    echo -e "  ${GRAY}创建 ~/git/ccprivate/ + 配置（LLM Key 等）+ 符号链接${NC}"
    echo ""
    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
    if [[ -d "$ccpriv/.git" ]]; then
        info "ccprivate 已存在，刷新符号链接"
        bash "$ccpriv/setup.sh"
    else
        if ! bash "$SCRIPT_DIR/init-ccprivate-repo.sh"; then
            err "ccprivate 初始化失败"
            err "  修复后重跑: bash init-bootstrap.sh"
            exit 1
        fi
    fi

    # Step 3: 全量初始化
    section "Step 3/3: 全量初始化"
    echo -e "  ${GRAY}Ubuntu 环境 → LLM 写入 → MCP 同步 → 链接修复 → auto-sync${NC}"
    echo ""
    local all_flag=""
    if [[ "${CCP_NONINTERACTIVE:-}" == "1" ]]; then
        all_flag="--yes"
    fi
    if ! bash "$SCRIPT_DIR/init-base.sh" all $all_flag; then
        err "全量初始化部分步骤失败"
        info "  检查上方日志，修复后可重跑: bash init-base.sh all"
        exit 1
    fi

    echo ""
    ok "新机器初始化完成 🎉"
    echo -e "  ${GREEN}claude 已可用${NC}"
    echo -e "  ${GRAY}当前终端需 source ~/.bashrc 或开新终端${NC}"
    echo ""
}

case "${1:-}" in
    all|--all|-a)
        export CCP_NONINTERACTIVE=1
        init_all
        ;;
    --dry-run|--preview|--what)
        # 顶部已处理
        ;;
    help|--help|-h)
        sed -n '2,20p' "$0"
        ;;
    *)
        banner
        if confirm "开始三步初始化？" y; then
            init_all
        else
            info "已取消"
        fi
        ;;
esac