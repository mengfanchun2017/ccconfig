#!/bin/bash
# 更新 npx skills 装的第三方 skill（按 upstream 拉最新）
#
# 与 `npx skills update -g` 等价（只更 -g 全局装的）
# 如果更新后 SKILL.md 有大改（frontmatter/trigger 改了），重启 Claude Code 生效
#
# 用法：bash scripts/update-third-party-skills.sh

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -e

echo "========================================"
echo "npx skills update -g -y（按 upstream 拉最新）"
echo "========================================"

# 防御：github URL 走 HTTPS
git config --global url."https://github.com/".insteadOf "git@github.com:" 2>/dev/null || true

npx --yes skills@latest update -g -y 2>&1 | tail -30

echo ""
echo "========================================"
echo "完成。重启 Claude Code 加载新 skill 内容。"
echo "========================================"
