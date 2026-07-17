#!/usr/bin/env bash
# publish.sh — 把 ccconfig/link/skills/ 的指定 skill 推到 skill/plugins/
# 用法:
#   bash publish.sh <skill-name> [<skill-name> ...]
#   bash publish.sh --push <skill-name> [<skill-name> ...]   # 同步 + push
#
# 行为:
#   1. 复制 ccconfig/link/skills/<skill> → skill/plugins/<skill>
#   2. 在 skill 仓 git add + commit
#   3. 默认不 push；加 --push 才推到 origin
#
# 适用: ccconfig 改完 f-* skill 后一键同步到发布仓

set -euo pipefail

CCCONFIG_DIR="${CCCONFIG_DIR:-${CCCONFIG_HOME:-$HOME/git/ccconfig}}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/git/skill}"
PLUGINS_DIR="$CLAUDE_SKILLS_DIR/plugins"

DO_PUSH=false
SKILLS=()

for arg in "$@"; do
  case "$arg" in
    --push) DO_PUSH=true ;;
    -h|--help)
      echo "用法: bash publish.sh [--push] <skill-name> [<skill-name> ...]"
      echo ""
      echo "选项:"
      echo "  --push    推到 origin（默认只本地 commit）"
      echo ""
      echo "示例:"
      echo "  bash publish.sh f-search f-research-domain f-report-gen"
      echo "  bash publish.sh --push f-search"
      exit 0
      ;;
    -*) echo "未知选项: $arg"; exit 1 ;;
    *) SKILLS+=("$arg") ;;
  esac
done

if [[ ${#SKILLS[@]} -eq 0 ]]; then
  echo "❌ 至少指定一个 skill 名"
  echo "   用法: bash publish.sh [--push] <skill-name> [...]"
  exit 1
fi

# 校验源
for skill in "${SKILLS[@]}"; do
  src="$CCCONFIG_DIR/link/skills/$skill"
  if [[ ! -d "$src" ]]; then
    echo "❌ 源不存在: $src"
    exit 1
  fi
  if [[ ! -f "$src/SKILL.md" ]]; then
    echo "❌ 源不是 skill (无 SKILL.md): $src"
    exit 1
  fi
done

# 校验目标仓
if [[ ! -d "$CLAUDE_SKILLS_DIR" ]]; then
  echo "❌ skill 仓不存在: $CLAUDE_SKILLS_DIR"
  echo "   用 CLAUDE_SKILLS_DIR 环境变量指定其他位置"
  exit 1
fi

# 复制
echo "=== 复制 ==="
for skill in "${SKILLS[@]}"; do
  src="$CCCONFIG_DIR/link/skills/$skill"
  dst="$PLUGINS_DIR/$skill"

  if [[ -d "$dst" ]]; then
    rm -rf "$dst"
    echo "  ⚠ 已删除旧版: $dst"
  fi
  cp -r "$src" "$dst"
  echo "  ✓ $skill → $dst"
done

# 在 skill 仓 commit
echo ""
echo "=== commit ==="
cd "$CLAUDE_SKILLS_DIR"

# 检查 working tree 是否干净（除了我们要发布的 skill）
CHANGED_OUTSIDE=$(git status --porcelain | grep -v "^.. plugins/$SKILLS" | grep -v "^?? plugins/$SKILLS" || true)
if [[ -n "$CHANGED_OUTSIDE" ]]; then
  echo "❌ skill 仓有未提交改动（不在 plugins/ 下）："
  echo "$CHANGED_OUTSIDE"
  echo "   先处理这些改动再发布"
  exit 1
fi

git add plugins/

# 检查是否有 staged 改动
if git diff --cached --quiet; then
  echo "  ⚠ 无改动可 commit（已是最新的？）"
  exit 0
fi

# 生成 commit message
SKILL_LIST=$(IFS=', '; echo "${SKILLS[*]}")
COMMIT_MSG="sync: 发布 ${SKILL_LIST}

由 ccconfig/lib/publish.sh 自动生成。
源: ccconfig/link/skills/ (本地)
目标: skill/plugins/ (公开)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"

git commit -m "$COMMIT_MSG"
echo "  ✓ commit 完成"

# push
if $DO_PUSH; then
  echo ""
  echo "=== push ==="
  git push origin main
  echo "  ✓ push 完成"
else
  echo ""
  echo "  ⚠ 未 push。本地 commit 已完成。"
  echo "    推送: cd $CLAUDE_SKILLS_DIR && git push origin main"
  echo "    或重跑: bash publish.sh --push ${SKILLS[*]}"
fi

echo ""
echo "=== 发布完成 ==="
