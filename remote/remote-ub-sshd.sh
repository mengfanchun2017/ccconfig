#!/bin/bash
# ============================================================
# WSL2 SSH Server 初始化脚本
# 在台式机 WSL2 内执行一次即可
# ============================================================
set -e

SSH_PORT=2222

echo "=== WSL2 SSH Server 安装 ==="

# 1. 安装 openssh-server
if ! dpkg -l openssh-server 2>/dev/null | grep -q '^ii'; then
    echo "[1/6] 安装 openssh-server..."
    sudo apt-get update -qq
    sudo apt-get install -y openssh-server
else
    echo "[1/6] openssh-server 已安装，跳过"
fi

# 2. 配置 SSH （端口 2222 避免和 Windows SSH 冲突）
echo "[2/6] 配置 SSH 端口 $SSH_PORT..."
sudo sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# 确认配置生效
if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
    echo "Port $SSH_PORT" | sudo tee -a /etc/ssh/sshd_config
fi

# 3. 生成 host keys（如果没有）
echo "[3/6] 检查 host keys..."
sudo ssh-keygen -A 2>/dev/null || true

# 4. 启动并开机自启
echo "[4/6] 启动 SSH 服务..."
sudo systemctl enable ssh
sudo systemctl restart ssh
sudo systemctl status ssh --no-pager

# 5. tmux 配置文件（鼠标滚动支持）
echo "[5/6] 配置 tmux..."
if [ ! -f ~/.tmux.conf ] || ! grep -q "mouse on" ~/.tmux.conf 2>/dev/null; then
    cat > ~/.tmux.conf <<'TMCONF'
# 鼠标支持：滚轮翻页，点击切换窗格
set -g mouse on
# 加快 escape-time
set -g escape-time 0
# 滚动历史行数
set -g history-limit 50000
TMCONF
    echo "  ✓ 已创建 ~/.tmux.conf"
else
    echo "  ✓ ~/.tmux.conf 已配置，跳过"
fi

# 6. tmux 自动 attach（SSH 登录后自动恢复 Claude 会话）
echo "[6/6] 配置 tmux 自动 attach..."
TMUX_SNIPPET=$(
    cat <<'TMUXEOF'

# --- 远程 SSH 自动 tmux attach（wsl-sshd-init 添加）---
if [ -n "$SSH_TTY" ] && [ -z "$TMUX" ] && command -v tmux >/dev/null 2>&1; then
    tmux attach -t claude 2>/dev/null || tmux new -s claude
fi
TMUXEOF
)

if ! grep -q "wsl-sshd-init" ~/.bashrc 2>/dev/null; then
    echo "$TMUX_SNIPPET" >> ~/.bashrc
    echo "  ✓ 已添加到 ~/.bashrc"
else
    echo "  ✓ ~/.bashrc 已有 tmux 配置，跳过"
fi

echo ""
echo "=== 完成 ==="
echo "SSH Server 运行在 WSL2 端口 $SSH_PORT"
echo "WSL2 IP: $(hostname -I | awk '{print $1}')"
echo ""
echo "下一步：在 Windows 管理员 PowerShell 中执行 ccconfig/wsl-portforward.ps1"
