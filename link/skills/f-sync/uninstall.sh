#!/usr/bin/env bash
# f-sync 卸载脚本
set -euo pipefail

SYSTEMD_DIR="${HOME}/.config/systemd/user"

echo "=== f-sync 卸载 ==="

if systemctl --user is-active f-sync.service &>/dev/null; then
    systemctl --user stop f-sync.service
    systemctl --user disable f-sync.service
    echo "已停止 service"
fi

rm -f "$SYSTEMD_DIR/f-sync.service"
systemctl --user daemon-reload
echo "已移除 systemd 文件"

read -rp "删除配置文件 ~/.config/f-sync/config.json？[y/N]: " DEL
[[ "$DEL" =~ ^[Yy]$ ]] && rm -rf "${HOME}/.config/f-sync" && echo "已删除配置目录"

echo "=== 卸载完成 ==="
echo "skill 目录未删除（手动删: rm -rf skills/f-sync）"
