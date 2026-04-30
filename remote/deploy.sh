#!/bin/bash
# ============================================================
# deploy.sh — 将 remote 配置部署到 Windows 和 WSL
# 用法:
#   台式机: bash ccconfig/remote/deploy.sh server
#   笔记本: bash ccconfig/remote/deploy.sh client
# ============================================================
set -e

TYPE="${1:-}"
if [ "$TYPE" != "server" ] && [ "$TYPE" != "client" ]; then
    echo "用法: bash deploy.sh <server|client>"
    echo ""
    echo "  server — 台式机（SSH Server + tmux + 端口转发）"
    echo "  client — 笔记本（Win Terminal 快捷连接）"
    exit 1
fi

REMOTE_DIR="$(cd "$(dirname "$0")" && pwd)"
WIN_DIR="/mnt/c/git/winremote"

if [ ! -d "/mnt/c" ]; then
    echo "[错误] /mnt/c 不存在，请在 WSL 中执行此脚本"
    exit 1
fi

echo "=== 远程配置部署 ==="
echo "  目标: $TYPE"
echo "  部署到: C:\\git\\winremote\\"
echo ""

mkdir -p "$WIN_DIR"

# --- 复制 Windows 脚本（自动加 UTF-8 BOM，PowerShell 才能正确显示中文）---
echo "[$TYPE] 复制脚本到 Windows..."
for f in "$REMOTE_DIR/$TYPE"/*.ps1; do
    if [ -f "$f" ]; then
        printf '\xEF\xBB\xBF' | cat - "$f" > "$WIN_DIR/$(basename "$f")"
        echo "  -> C:\\git\\winremote\\$(basename "$f")"
    fi
done

# --- tmux.conf（仅 server） ---
if [ "$TYPE" = "server" ]; then
    echo ""
    echo "[server] 部署 tmux 配置..."
    cp "$REMOTE_DIR/server/tmux.conf" "$HOME/.tmux.conf"
    echo "  -> ~/.tmux.conf"

    echo ""
    echo "=== 部署完成 ==="
    echo ""
    echo "台式机还需执行（WSL 中）:"
    echo "  bash ccconfig/remote/server/tmux-sshd.sh"
    echo ""
    echo "台式机还需执行（Windows 管理员 PowerShell）:"
    echo '  powershell -ExecutionPolicy Bypass -File "C:\git\winremote\tmux-portforward.ps1"'
    echo ""
    echo "然后启动 Tailscale 组网（管理员 PowerShell）:"
    echo '  powershell -ExecutionPolicy Bypass -File "C:\git\winremote\ts-setup.ps1"'
else
    echo ""
    echo "=== 部署完成 ==="
    echo ""
    echo "启动 Tailscale 组网（管理员 PowerShell）:"
    echo '  powershell -ExecutionPolicy Bypass -File "C:\git\winremote\ts-setup.ps1"'
fi

echo ""
echo "详细说明: ~/git/ccconfig/remote/readme.md"
