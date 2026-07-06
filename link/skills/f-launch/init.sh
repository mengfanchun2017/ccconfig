#!/usr/bin/env bash
# f-launch — 项目启动 skill 初始化 / 脚手架生成脚本
# 用法:
#   bash init.sh                       # 首次安装(符号链接 rules + skill)
#   bash init.sh scaffold <name> <type> # 生成项目脚手架
#   bash init.sh list                  # 列出 8 类项目类型
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SKILL_NAME="$(basename "$SKILL_DIR")"
RULES_TARGET="${HOME}/.claude/rules"
SKILLS_TARGET="${HOME}/.claude/skills"

# ── 解析参数 ──
CMD="${1:-install}"
shift || true

# ── 颜色 ──
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
error()   { echo -e "${RED}❌ $1${NC}"; }

# ── 列出 8 类项目 ──
list_types() {
  cat << 'EOF'
f-launch 项目类型 (8 类):

  1. static-web-personal   个人静态 web (礼物/纪念/展示) ★
  2. web-api-backend       Web 后端 API (CRUD/REST)      ★★★
  3. cli-tool              CLI 工具                       ★★
  4. ai-agent-tool         AI Agent / 工具调用            ★★★
  5. data-pipeline         数据 / ML Pipeline             ★★★★
  6. mobile-app            移动 App                       ★★★★
  7. desktop-app           桌面 App                       ★★★★
  8. game                  游戏                           ★★★★

参考案例:
  static-web-personal  → ~/git/<project-name>
  web-api-backend      → ~/git/<project-name>
EOF
}

# ── 安装(符号链接) ──
install() {
  echo "=== ${SKILL_NAME} 安装 ==="

  # 1. rules.d → ~/.claude/rules/
  if [[ -d "${SKILL_DIR}/rules.d" ]]; then
    mkdir -p "$RULES_TARGET"
    for rule_file in "${SKILL_DIR}"/rules.d/*.md; do
      [[ -f "$rule_file" ]] || continue
      name="$(basename "$rule_file")"
      target="${RULES_TARGET}/${name}"
      if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$(readlink -f "$rule_file")" ]]; then
        info "rules/${name} 已链接"
      else
        rm -f "$target"
        ln -sf "$(readlink -f "$rule_file")" "$target"
        success "rules/${name} 已链接"
      fi
    done
  fi

  # 2. skill 自身 → ~/.claude/skills/
  if [[ ! -e "${SKILLS_TARGET}/${SKILL_NAME}" ]]; then
    ln -s "$SKILL_DIR" "${SKILLS_TARGET}/${SKILL_NAME}"
    success "skills/${SKILL_NAME} 已链接"
  else
    info "skills/${SKILL_NAME} 已存在"
  fi

  echo "=== ${SKILL_NAME} 安装完成 ==="
}

# ── 脚手架生成 ──
scaffold() {
  local name="${1:?项目代号必填}"
  local type="${2:-static-web-personal}"
  local parent_dir="${PARENT_DIR:-$HOME/git}"

  local project_dir="${parent_dir}/${name}"
  local template_file="${SKILL_DIR}/references/${type}.md"

  if [[ -d "$project_dir" ]]; then
    error "目录已存在: $project_dir"
    exit 1
  fi

  if [[ ! -f "$template_file" ]]; then
    error "未找到类型模板: $template_file"
    list_types
    exit 1
  fi

  info "生成脚手架: $project_dir ($type)"

  mkdir -p "$project_dir"
  cd "$project_dir"

  # 通用文件
  cat > README.md << EOF
# ${name}

> 类型:${type} · 创建日期:$(date +%Y-%m-%d) · 由 f-launch skill 生成

## 一句话目标

<!-- 在这里写项目目标 -->

## 技术栈

<!-- 列出主要技术 -->

## 开发

\`\`\`bash
# 启动 / 构建 / 测试
\`\`\`

## 部署

<!-- 部署路径 -->

## 许可

$(if [[ "${LICENSE:-MIT}" == "MIT" ]]; then echo "MIT"; elif [[ "${LICENSE:-MIT}" == "Apache-2.0" ]]; then echo "Apache-2.0"; else echo "见 LICENSE 文件"; fi)
EOF

  cat > .gitignore << 'EOF'
# OS
.DS_Store
Thumbs.db

# Editor
.vscode/
.idea/
*.swp
*~

# Node
node_modules/
dist/
build/
.env
.env.local
*.log

# Python
__pycache__/
*.py[cod]
.venv/
venv/
.pytest_cache/
.mypy_cache/

# Go
*.exe
*.out
vendor/

# Rust
target/
Cargo.lock

# 数据 / 缓存
data/cache/
*.sqlite
*.sqlite-journal
*.db
EOF

  cat > .editorconfig << 'EOF'
root = true

[*]
indent_style = space
indent_size = 2
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.py]
indent_size = 4

[*.{go,rs}]
indent_size = 4
EOF

  # CLAUDE.md(由类型模板填充)
  if [[ -f "${SKILL_DIR}/templates/CLAUDE.${type}.tmpl" ]]; then
    sed "s|{{NAME}}|${name}|g; s|{{TYPE}}|${type}|g; s|{{DATE}}|$(date +%Y-%m-%d)|g" \
      "${SKILL_DIR}/templates/CLAUDE.${type}.tmpl" > CLAUDE.md
  else
    cat > CLAUDE.md << EOF
# ${name}

> 类型:${type} · 由 f-launch skill 创建于 $(date +%Y-%m-%d)

## 目标

<!-- 写项目目标 -->

## 技术栈

<!-- 列出技术选型 -->

## 目录

<!-- 描述目录结构 -->

## 风险点

<!-- 5 项主要风险 + 缓解 -->
EOF
  fi

  # LICENSE
  case "${LICENSE:-MIT}" in
    MIT)
      cat > LICENSE << 'EOF'
MIT License

Copyright (c) YEAR AUTHOR

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
      ;;
    Apache-2.0)
      warn "Apache-2.0 LICENSE 模板待补,使用占位"
      echo "Apache License 2.0" > LICENSE
      ;;
    None)
      : > LICENSE
      ;;
  esac

  # docs/plan.md 占位
  mkdir -p docs
  cat > docs/plan.md << 'EOF'
# 开发计划

> 占位文件,按项目规模填充:WBS / 里程碑 / 风险 / 验收标准

## 阶段

- [ ] 阶段 1
- [ ] 阶段 2
- [ ] 阶段 3

## 风险跟踪

| 风险 | 状态 | 缓解 |
|------|------|------|
| - | - | - |
EOF

  success "脚手架生成: $project_dir"
  info "下一步:"
  echo "  cd $project_dir"
  echo "  # 编辑 CLAUDE.md 写项目目标"
  if [[ "${GIT_INIT:-true}" == "true" ]]; then
    git init -q
    git add -A
    git -c user.email=f-launch@noreply.local -c user.name="f-launch" commit -q -m "chore: initial scaffold via f-launch skill"
    success "git init + 首次 commit"
  fi

  # 显示类型模板的关键信息
  echo ""
  warn "类型模板提示:"
  head -20 "$template_file" | sed 's/^/  /'
}

# ── 分发 ──
case "$CMD" in
  install)    install ;;
  scaffold)   scaffold "$@" ;;
  list)       list_types ;;
  -h|--help)
    cat << 'EOF'
f-launch 项目启动 skill

用法:
  bash init.sh                     首次安装(符号链接)
  bash init.sh scaffold NAME TYPE  生成项目脚手架
  bash init.sh list                列出 8 类项目类型

环境变量:
  PARENT_DIR    脚手架父目录(默认 ~/git)
  LICENSE       默认 LICENSE(MIT / Apache-2.0 / None)
  GIT_INIT      是否自动 git init(默认 true)
EOF
    ;;
  *)
    error "未知命令: $CMD"
    echo "运行:bash init.sh --help"
    exit 1
    ;;
esac
