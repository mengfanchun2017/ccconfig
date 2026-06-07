#!/bin/bash
# 修复 WSL interop - 关闭 Windows PATH 注入
# 用途：让 Claude Code / Bun 在 WSL 中不再尝试执行 Windows 程序
#
# 使用：bash ccconfig/windows/wsl-interop.sh

set -e

CURRENT_USER=$(whoami)
TARGET="/etc/wsl.conf"

CONTENT="[boot]
systemd=true

[interop]
appendWindowsPath=false

[user]
default=${CURRENT_USER}
"

echo "写入 $TARGET ..."
echo "$CONTENT" | sudo tee "$TARGET" > /dev/null

echo "✅ wsl.conf 已更新"
echo ""
echo "内容："
cat "$TARGET"
echo ""
echo "下一步：在 PowerShell 中运行 'wsl --shutdown' 重启 WSL"
echo "之后 Windows PATH 就不会再注入到 WSL 了"
