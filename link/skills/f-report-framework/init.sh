#!/usr/bin/env bash
# {{SKILL_NAME}} 安装/更新脚本 — 符号链接 rules.d → ~/.claude/rules/
# 用法: bash init.sh [--config] [--force]
set -euo pipefail

SKILL_DIR="$(dirname "$(readlink -f "$0")")"
SKILL_NAME="$(basename "$SKILL_DIR")"
RULES_TARGET="${HOME}/.claude/rules"
FORCE=false
DO_CONFIG=false

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --config) DO_CONFIG=true ;;
    *) echo "未知参数: $arg"; exit 1 ;;
  esac
done

echo "=== ${SKILL_NAME} 安装 ==="

# ── rules.d → ~/.claude/rules/ ──
if [[ -d "${SKILL_DIR}/rules.d" ]]; then
  mkdir -p "$RULES_TARGET"
  for rule_file in "${SKILL_DIR}"/rules.d/*.md; do
    [[ -f "$rule_file" ]] || continue
    name="$(basename "$rule_file")"
    target="${RULES_TARGET}/${name}"

    if [[ -L "$target" ]]; then
      current="$(readlink -f "$target")"
      if [[ "$current" == "$(readlink -f "$rule_file")" ]]; then
        echo "  ✓ rules/${name} 已链接"
        continue
      elif $FORCE; then
        rm "$target"
      else
        echo "  ⚠ rules/${name} 指向不同目标，用 --force 覆盖"
        continue
      fi
    elif [[ -f "$target" ]]; then
      if $FORCE; then
        rm "$target"
      else
        echo "  ⚠ rules/${name} 已存在（非链接），用 --force 覆盖"
        continue
      fi
    fi

    ln -s "$(readlink -f "$rule_file")" "$target"
    echo "  → rules/${name} 已链接"
  done
fi

# ── skill 自身符号链接 ──
SKILLS_TARGET="${HOME}/.claude/skills/${SKILL_NAME}"
if [[ ! -e "$SKILLS_TARGET" ]]; then
  ln -s "$(readlink -f "$SKILL_DIR")" "$SKILLS_TARGET"
  echo "  → skills/${SKILL_NAME} 已链接"
elif [[ -L "$SKILLS_TARGET" ]]; then
  echo "  ✓ skills/${SKILL_NAME} 已链接"
fi

# ── 交互式配置 ──
if $DO_CONFIG && [[ -f "${SKILL_DIR}/config.yaml" ]]; then
  echo ""
  echo "当前配置 (${SKILL_DIR}/config.yaml):"
  cat "${SKILL_DIR}/config.yaml"
  echo ""
  read -rp "用编辑器打开修改？[y/N]: " EDIT
  [[ "$EDIT" =~ ^[Yy]$ ]] && ${EDITOR:-nano} "${SKILL_DIR}/config.yaml"
fi

echo "=== ${SKILL_NAME} 安装完成 ==="
