#!/bin/bash
# test-bootstrap.sh — 在已 import 的 WSL 内跑 bootstrap 全流程
#
# 调法（在 WSL 内）:
#   bash ~/git/ccconfig/bin/test-bootstrap.sh
# 或从 WSL 外（PowerShell 已建好 distro）:
#   bash maintain.sh test
#
# 依赖 env（在 PowerShell 端注入或 WSL 内 export）:
#   GH_TOKEN              — GitHub PAT（必需，init-bootstrap.sh 用）
#   CCP_GH_USER           — GitHub 用户名（init-bootstrap.sh 用）
#   CCP_GIT_EMAIL         — git 邮箱
#   CCP_DEFAULT_LLM       — deepseek | minimax | claude
#   CCP_LLM_DEEPSEEK_KEY  — DeepSeek API key（可选）
#   CCP_LLM_MINIMAX_KEY   — MiniMax API key（可选）
#   CCP_LLM_ANTHROPIC_KEY — Anthropic API key（可选）
#   CCP_SKIP_FEISHU=1     — 跳过飞书占位符引导（默认 0）
#   CCP_SKIP_PREREQ_PROMPT=1 — 跳过 init-base.sh prereq 提示（默认 0）

set -euo pipefail

CCCONFIG_DIR="${CCCONFIG_DIR:-$HOME/git/ccconfig}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/colors.sh"

[[ -d "$CCCONFIG_DIR" ]] || { err "ccconfig 目录不存在: $CCCONFIG_DIR"; exit 1; }

section "1/4 gh auth + ccprivate（--non-interactive）"
bash "$CCCONFIG_DIR/init-bootstrap.sh" --non-interactive

section "2/4 全量初始化 (Ubuntu → LLM → 收尾)"
bash "$CCCONFIG_DIR/init-base.sh" all --yes

section "3/4 可选组件（--yes，auth 类自动跳过）"
bash "$CCCONFIG_DIR/init-option.sh" all --yes

section "4/4 状态验证"
bash "$CCCONFIG_DIR/maintain.sh" status

ok "Bootstrap 全流程完成"