#!/usr/bin/env bash
# f-sync 安装脚本 — 交互式配置 + 安装 systemd user timer
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_DIR="${HOME}/.config/f-sync"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

echo "=== f-sync 安装 ==="
echo ""

# ── 依赖检查 ──
command -v python3 &>/dev/null || { echo "需要 python3"; exit 1; }
command -v lark-cli &>/dev/null || { echo "需要 lark-cli，先安装: https://open.feishu.cn"; exit 1; }

# ── 飞书账号 ──
echo "可用的飞书账号:"
ls -d ~/.lark-cli-* 2>/dev/null | while read d; do echo "  $d"; done || true
read -rp "飞书配置目录 [~/.lark-cli-<account>]: " LARK_DIR
LARK_DIR="${LARK_DIR:-~/.lark-cli-<account>}"

# ── 创建配置目录 ──
mkdir -p "$CONFIG_DIR"

# ── 已有配置？ ──
if [[ -f "$CONFIG_FILE" ]]; then
    echo "已有配置: $CONFIG_FILE"
    read -rp "覆盖？[y/N]: " OVERWRITE
    [[ "$OVERWRITE" =~ ^[Yy]$ ]] || { echo "取消"; exit 0; }
fi

# ── 交互输入 ──
JOBS_JSON="["
FIRST=true
while true; do
    echo ""
    echo "--- 同步任务 $([ "$FIRST" = true ] && echo "1" || echo "追加") ---"
    read -rp "任务名称: " NAME
    [[ -z "$NAME" ]] && break

    read -rp "本地目录: " LOCAL_DIR
    [[ -z "$LOCAL_DIR" ]] && break

    read -rp "飞书云盘文件夹 token: " FOLDER_TOKEN
    [[ -z "$FOLDER_TOKEN" ]] && break

    read -rp "冲突策略 [local-wins/remote-wins/keep-both, 默认 local-wins]: " ON_CONFLICT
    ON_CONFLICT="${ON_CONFLICT:-local-wins}"

    read -rp "轮询间隔(秒) [默认 30]: " INTERVAL
    INTERVAL="${INTERVAL:-30}"

    $FIRST || JOBS_JSON+=","
    FIRST=false
    JOBS_JSON+="{\"name\":\"$NAME\",\"local_dir\":\"$LOCAL_DIR\",\"folder_token\":\"$FOLDER_TOKEN\",\"on_conflict\":\"$ON_CONFLICT\",\"interval_seconds\":$INTERVAL}"
done
JOBS_JSON+="]"

# ── 写入配置 ──
python3 -c "
import json
cfg = {
    'jobs': json.loads('''$JOBS_JSON'''),
    'lark_config_dir': '$LARK_DIR',
}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
print(json.dumps(cfg, indent=2, ensure_ascii=False))
"
echo ""
echo "配置已写入: $CONFIG_FILE"

# ── systemd service（loop 模式，支持秒级间隔）──
read -rp "安装 systemd user service 自动运行？[Y/n]: " INSTALL_SVC
INSTALL_SVC="${INSTALL_SVC:-y}"

if [[ "$INSTALL_SVC" =~ ^[Yy]$ ]]; then
    mkdir -p "$SYSTEMD_DIR"

    cat > "$SYSTEMD_DIR/f-sync.service" << EOF
[Unit]
Description=f-sync: 飞书云盘双向同步（轮询模式）

[Service]
Type=simple
ExecStart=/usr/bin/env bash $SCRIPT_DIR/sync-loop.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now f-sync.service

    echo ""
    echo "已安装并启动 systemd user service（loop 模式）"
    echo "  查看状态: systemctl --user status f-sync.service"
    echo "  查看日志: journalctl --user -u f-sync.service -f"
    echo "  停止:     systemctl --user stop f-sync.service"
    echo "  卸载:     $SCRIPT_DIR/uninstall.sh"
fi

echo ""
echo "=== 安装完成 ==="
echo "手动执行一次: bash $SCRIPT_DIR/sync.sh"
