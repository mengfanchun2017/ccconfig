#!/bin/bash
# setup-pwsh-profile.sh — WSL 端入口：触发 Win 端 PowerShell 写入 $PROFILE
#
# 用途：
#   幂等禁用 PowerShell 7.4+ 启动时的版本更新通知
#   适用场景：每次启动 PowerShell 都弹 "new stable release" 提示
#
# 用法：
#   bash ccconfig/windows/setup-pwsh-profile.sh
#
# 幂等：检测到 ccconfig marker 跳过
# 生效：下次启动 PowerShell 即可
# 还原：手动删除 profile 中的 ccconfig marker 段

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS1_FILE="$SCRIPT_DIR/setup-pwsh-profile.ps1"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

if [ ! -f "$PS1_FILE" ]; then
    echo -e "${RED}❌${NC} 未找到: $PS1_FILE"
    exit 1
fi

if ! command -v powershell.exe >/dev/null 2>&1; then
    echo -e "${RED}❌${NC} powershell.exe 不在 PATH（需要 WSL interop 开启）"
    exit 1
fi

WIN_PS1=$(wslpath -w "$PS1_FILE" 2>/dev/null)
if [ -z "$WIN_PS1" ]; then
    echo -e "${RED}❌${NC} wslpath 转换失败"
    exit 1
fi

echo -e "${CYAN}▶${NC} 在 Windows 端执行: $WIN_PS1"
echo ""

powershell.exe -ExecutionPolicy Bypass -File "$WIN_PS1"
RC=$?

echo ""
if [ $RC -ne 0 ]; then
    echo -e "${RED}❌${NC} PowerShell 执行失败 (exit=$RC)"
    exit $RC
fi

echo -e "${GREEN}✅${NC} profile 已配置（下次启动 PowerShell 生效）"
