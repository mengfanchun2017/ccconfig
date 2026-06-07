#!/bin/bash
# wslconfig-sync.sh — WSL 端入口：触发 Win 端 PowerShell 同步 .wslconfig
#
# 用途：
#   把 ccconfig/windows/wslconfig.ps1 的目标内容写入 %USERPROFILE%\.wslconfig
#   适用场景：status.sh [13] 报红，或 sync.sh pullff 拉到 wslconfig.ps1 新版本
#
# 用法：
#   bash ccconfig/windows/wslconfig-sync.sh         # 写入 + 提示重启
#   bash ccconfig/windows/wslconfig-sync.sh --shutdown   # 写入 + 直接 wsl.exe --shutdown（会杀掉当前会话！）
#
# 注意：
#   - .wslconfig 仅在 WSL 子系统冷启时读取一次，必须 `wsl.exe --shutdown` 后重开终端才生效
#   - 默认不主动 shutdown，避免杀掉当前 claude code 会话；用户自行选择时机

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS1_FILE="$SCRIPT_DIR/wslconfig.ps1"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; GRAY='\033[0;90m'; NC='\033[0m'

if [ ! -f "$PS1_FILE" ]; then
    echo -e "${RED}❌${NC} 未找到: $PS1_FILE"
    exit 1
fi

if ! command -v powershell.exe >/dev/null 2>&1; then
    echo -e "${RED}❌${NC} powershell.exe 不在 PATH（需要 WSL interop 开启）"
    exit 1
fi

# 转 WSL 路径到 Win 路径
WIN_PS1=$(wslpath -w "$PS1_FILE" 2>/dev/null)
if [ -z "$WIN_PS1" ]; then
    echo -e "${RED}❌${NC} wslpath 转换失败"
    exit 1
fi

echo -e "${CYAN}▶${NC} 在 Windows 端执行: $WIN_PS1"
echo ""

# 调 Win 端 PowerShell（用户主动跑，不受 Claude AI 禁令影响）
powershell.exe -ExecutionPolicy Bypass -File "$WIN_PS1"
RC=$?
echo ""

if [ $RC -ne 0 ]; then
    echo -e "${RED}❌${NC} PowerShell 执行失败 (exit=$RC)"
    exit $RC
fi

echo -e "${GREEN}✅${NC} .wslconfig 已写入"
echo ""

if [ "$1" = "--shutdown" ]; then
    echo -e "${YELLOW}⚠${NC}  10 秒后执行 wsl.exe --shutdown（按 Ctrl+C 取消）..."
    sleep 10
    powershell.exe -Command "wsl.exe --shutdown"
    echo -e "${GREEN}✅${NC} wsl --shutdown 已触发"
else
    echo -e "${YELLOW}下一步（择机执行，会关掉当前 WSL 会话）:${NC}"
    echo -e "  ${CYAN}wsl.exe --shutdown${NC}"
    echo -e "  ${GRAY}然后重开 WSL 终端，新配置生效${NC}"
    echo ""
    echo -e "${GRAY}验证: bash ccconfig/status.sh 查看 [13] .wslconfig 同步${NC}"
fi
