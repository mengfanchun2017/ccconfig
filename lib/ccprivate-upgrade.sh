#!/bin/bash
# ccprivate-upgrade.sh — ccprivate 结构检测与升级
#
# 检测旧版 ccprivate 结构问题，一键修复到当前 ccconfig 期望的 v3 格式。
#
# 用法:
#   bash ccconfig/lib/ccprivate-upgrade.sh              # 检测 + 交互修复
#   bash ccconfig/lib/ccprivate-upgrade.sh --check-only  # 仅检测，不改动
#   bash ccconfig/lib/ccprivate-upgrade.sh --yes         # 检测 + 自动修复（跳过确认）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/path-helper.sh" 2>/dev/null || true

CCPRIVATE="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
CHECK_ONLY=false
AUTO_YES=false

for arg in "${@}"; do
    case "$arg" in
        --check-only) CHECK_ONLY=true ;;
        --yes|-y) AUTO_YES=true ;;
    esac
done

# ── v3 setup.sh 模板 ──
# 与 ccprivate/setup.sh 当前版本保持一致
SETUP_SH_V3='#!/bin/bash
# ccprivate — 私有配置注入脚本
#
# 职责（v3）：
#   1. 用户级文件 symlink → ~/ 和 ~/.claude/
#   2. 触发 ccconfig 公开部分链接（agents/rules/commands/skills）
#   (ccconfig 脚本通过 resolve_conf() 直接读 ccprivate/conf/，无需中间目录)
#
# 私有数据分类：
#   link/       — 用户级（CLAUDE.md、settings.json、.config.json）
#   conf/       — API key/token（ccconfig 通过 resolve_conf() 直接读）
#
# 用法：
#   bash ~/git/ccprivate/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="${CCCONFIG_DIR:-$HOME/git/ccconfig}"
CLAUDE_DIR="$HOME/.claude"

GREEN='\''\033[0;32m'\''
BLUE='\''\033[0;34m'\''
CYAN='\''\033[0;36m'\''
YELLOW='\''\033[0;33m'\''
NC='\''\033[0m'\''

section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
ok()      { echo -e "${GREEN}✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }

setup_link() {
    local link="$1"
    local target="$2"
    local label="$3"
    mkdir -p "$(dirname "$link")"
    if [ -L "$link" ]; then
        local existing expected
        existing=$(readlink -f "$link" 2>/dev/null || true)
        expected=$(readlink -f "$target" 2>/dev/null || true)
        if [ "$existing" = "$expected" ] && [ -n "$existing" ]; then
            info "$label: 已链接"
            return 0
        fi
        rm -f "$link"
    elif [ -e "$link" ]; then
        rm -rf "$link"
    fi
    ln -s "$target" "$link"
    ok "$label"
}

# ============================================================
# 1. 用户级 ~/ 链接（直连 ccprivate/link/）
# ============================================================
section "用户级链接"
setup_link "$HOME/CLAUDE.md"           "$SCRIPT_DIR/link/CLAUDE.md"     "~/CLAUDE.md"
setup_link "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/link/settings.json" "~/.claude/settings.json"
setup_link "$CLAUDE_DIR/.config.json"  "$SCRIPT_DIR/link/.config.json"  "~/.claude/.config.json"

# ============================================================
# 2. ccconfig 私有配置 — 由 resolve_conf() 直接读 ccprivate/conf/
#    无需中间目录。ccconfig/ 零 symlink。
# ============================================================
info "ccconfig 私有配置: ccconfig 脚本通过 resolve_conf() 直接读 ccprivate/conf/"

# ============================================================
# 3. 用户级 memory symlink（动态计算 project ID，不硬编码用户名）
# ============================================================
section "用户级记忆"
_cconfig_id="$(echo "$HOME/git/ccconfig" | tr '\''/'\'' '\''-'\'')"
setup_link "$CLAUDE_DIR/projects/$_cconfig_id/memory" "$SCRIPT_DIR/link/memory" "memory → ccprivate/link/memory"
unset _cconfig_id

# ============================================================
# 4. 运行时链接（rules/agents/commands → ccprivate，用户可自定义）
# ============================================================
section "运行时链接"
if [ -d "$SCRIPT_DIR/rules" ]; then
    setup_link "$CLAUDE_DIR/rules" "$SCRIPT_DIR/rules" "rules → ccprivate/rules"
fi
if [ -d "$SCRIPT_DIR/agents" ]; then
    setup_link "$CLAUDE_DIR/agents" "$SCRIPT_DIR/agents" "agents → ccprivate/agents"
fi
if [ -d "$SCRIPT_DIR/commands" ]; then
    setup_link "$CLAUDE_DIR/commands" "$SCRIPT_DIR/commands" "commands → ccprivate/commands"
fi

# ============================================================
# 5. ccconfig 公开部分（shell_init.sh + pre-commit hook）
# ============================================================
section "ccconfig 公开链接"
if [ -x "$CCCONFIG_DIR/lib/setup-links.sh" ]; then
    bash "$CCCONFIG_DIR/lib/setup-links.sh"
else
    warn "ccconfig/lib/setup-links.sh 不存在，跳过（请确认 ccconfig 已 clone）"
fi

echo ""
ok "ccprivate setup 完成"'

# ── link/ 文件模板 ──
LINK_CLAUDE_MD='# Claude Code 用户配置

> 全局 AI 行为指南。所有项目通用。项目级配置见各项目 `CLAUDE.md`。

## 核心约定
- 中文回复
- **输出风格**: caveman 模式为默认。极简输出：删冠词/填充词/客套语，短词短句，fragments 可用。技术术语精确，代码块不变。不说"sure"/"of course"/"happy to"。
- 未列出的命令会询问是否允许，可选择单次允许或永久添加
- 禁止: rm -rf, git reset --hard, git clean -f, mkfs, dd, chmod -R 777, sudo（除 apt-get）, powershell -ExecutionPolicy Bypass
- **自动错误分析**: 任何 Bash/CLI 命令返回非零退出码或报错时，自动：①定位根因 ②修复相关脚本/workflow/memory ③记录错误教训。不等待用户触发。修复前若涉及重大变更需确认，否则直接修。

## 权限双层机制
CLAUDE.md = AI 行为指南 | settings.json `permissions.allow` = 权限系统
规则拆分到 `.claude/rules/`（按路径条件加载），不在 CLAUDE.md 中重复 rules 已有内容。

## 自然语言触发（无需前缀）
- "记录工作" / "写日志" / "总结任务" / "OKR" / "目标管理" / "反思" / "生成总结" / "季度报告" / "年度报告" → 自动调用 flogme skill
- 调研/研究/分析 → 自动调用 f-research-domain skill
- "写报告" / "出报告" / "分析报告" / "对比报告" / "方案报告" → 自动调用 f-research-domain skill（出报告走 f-report-gen 工作流）
- 创建飞书文档/PPT/表格 → 自动调用 ffeishu skill（统一文档入口）
- 生成PPT/做slides → fpptx skill
- 画架构图/流程图/时序图 → fdiagram skill
- 更新文档/整合/拆分/转换 → ffeishu skill

## CLAUDE.md 分层规则

| 层级 | 文件 | 加载时机 | 写什么 |
|------|------|---------|--------|
| 用户级 | `~/CLAUDE.md` | 所有会话 | 编码规范、行为偏好、权限说明、自然语言触发、允许命令、工作目录约定 |
| 项目级 | `<project>/CLAUDE.md` | 仅该目录 | 项目架构、暗号、常用命令、版本管理、项目特有约束 |

**不要放项目级**：全局行为偏好、自然语言触发、与用户级重复的内容（浪费 context token）。

## 工作目录约定
- 配置/环境维护 → `cd ~/git/ccconfig && claude`（改 rules、conf、CLAUDE.md、skills）
- 项目开发 → `cd ~/git/<project> && claude`
- 不要从 `~/git/` 启动 Claude（非 git repo，无项目 CLAUDE.md，缺上下文）
- ccconfig 不记录项目级 memory（架构决策属于用户级，在用户级 memory 维护）

## Auto Memory
- 用户级记忆: `ccprivate/link/memory/MEMORY.md` → setup.sh 自动链接到 `~/.claude/projects/<id>/memory/`（id 由 `$HOME/git/ccconfig` 动态派生）
- 项目标识符格式: 路径 `/` 替换为 `-`，如 `/home/user/git` → `-home-user-git`

## 允许的 Bash 命令（权限已设 Bash(*)）
文件/系统: ls, dir, tree, pwd, cd, mkdir, cp, mv, rm, rmdir, touch, ln, chmod, chown, cat, head, tail, less, more, file, stat, wc, sort, uniq, diff, cmp, find, grep, rg, ack, ag, which, where, locate, xargs, zip, unzip, tar, gzip
网络: curl, wget, ping, ssh, scp, sftp, nslookup, dig, netstat, ss
系统: uname, env, echo, date, whoami, id, uptime, top, ps, df, du, free, lsof, dmesg
Git: git status, log, branch, checkout, switch, restore, diff, show, add, commit, reset, stash, rebase, merge, cherry-pick, tag, remote, fetch, pull, push, clone, config, init, mv, rm, clean, bisect, blame, reflog
JS/TS: node, npm, npx, yarn, pnpm, bun, bunx, tsc, vitest, jest
Python: python3, pip3, pytest
Go/Rust: go, gofmt, cargo, rustc
数据库: mysql, psql, sqlite3, redis-cli
编辑器: code, vim, nvim, nano
其他: awk, sed, cut, tr, make, cmake, docker, kubectl, tmux, screen'

LINK_SETTINGS_JSON='{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Glob(*)",
      "Grep(*)",
      "WebSearch",
      "WebFetch",
      "Skill(*)"
    ]
  }
}
'

LINK_DOT_CONFIG_JSON='{}
'

# ═══════════════════════════════════════════════════════════════
# 检测函数
# ═══════════════════════════════════════════════════════════════

check_generated_dir() {
    local gendir="$CCPRIVATE/conf/.generated"
    if [ ! -d "$gendir" ]; then
        return 0
    fi
    local files=()
    for f in "$gendir"/*.json; do
        [ -f "$f" ] || continue
        files+=("$(basename "$f")")
    done
    if [ ${#files[@]} -eq 0 ]; then
        return 0
    fi

    # 检查哪些已迁移、哪些未迁移
    local pending=() already=()
    for f in "${files[@]}"; do
        if [ -f "$CCPRIVATE/conf/$f" ]; then
            already+=("$f")
        else
            pending+=("$f")
        fi
    done

    echo -e "  ${YELLOW}⚠${NC}  conf/.generated/ 残留"
    [ ${#pending[@]} -gt 0 ] && echo -e "    待迁移: ${pending[*]}"
    [ ${#already[@]} -gt 0 ] && echo -e "    已存在 conf/ 中 (可安全删除 .generated/): ${already[*]}"
    return 1
}

check_directories() {
    local expected=("skill-config" "rules" "agents" "commands" "bin")
    local missing=()
    for d in "${expected[@]}"; do
        [ -d "$CCPRIVATE/$d" ] || missing+=("$d")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC}  缺少目录: ${missing[*]}"
        return 1
    fi
    return 0
}

check_setup_sh_version() {
    if [ ! -f "$CCPRIVATE/setup.sh" ]; then
        echo -e "  ${RED}❌${NC} setup.sh 缺失"
        return 1
    fi

    # v2 签名检测
    if grep -q 'shell_aliases' "$CCPRIVATE/setup.sh" 2>/dev/null; then
        echo -e "  ${RED}❌${NC} setup.sh 为旧版 (v2) — 含 shell_aliases 引用"
        return 1
    fi

    if grep -q 'link/projects' "$CCPRIVATE/setup.sh" 2>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC}  setup.sh 使用 link/projects/ 循环模式 (v2，与当前 v3 模板不同)"
        return 1
    fi

    # 检查是否含 v3 关键特征
    if grep -q 'resolve_conf' "$CCPRIVATE/setup.sh" 2>/dev/null && \
       grep -q 'link/memory' "$CCPRIVATE/setup.sh" 2>/dev/null; then
        return 0
    fi

    # 结构不同但无明确 v2 特征 → 可能是用户修改版
    if ! diff -q <(echo "$SETUP_SH_V3") "$CCPRIVATE/setup.sh" &>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC}  setup.sh 与当前模板不同（可能已自定义）"
        return 1
    fi
    return 0
}

check_link_content() {
    local required=("CLAUDE.md" "settings.json" ".config.json")
    local missing=()
    for f in "${required[@]}"; do
        [ -f "$CCPRIVATE/link/$f" ] || missing+=("$f")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠${NC}  link/ 缺少: ${missing[*]}"
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════
# 修复函数
# ═══════════════════════════════════════════════════════════════

fix_generated_dir() {
    local gendir="$CCPRIVATE/conf/.generated"
    [ -d "$gendir" ] || return 0

    local migrated=0 skipped=0
    for f in "$gendir"/*.json; do
        [ -f "$f" ] || continue
        local name=$(basename "$f")
        if [ -f "$CCPRIVATE/conf/$name" ]; then
            info "跳过 (已存在): $name"
            skipped=$((skipped + 1))
        else
            cp -n "$f" "$CCPRIVATE/conf/$name" 2>/dev/null || true
            ok "迁移: conf/.generated/$name → conf/$name"
            migrated=$((migrated + 1))
        fi
    done

    if [ $skipped -gt 0 ] || [ $migrated -gt 0 ]; then
        rm -rf "$gendir"
        ok "已删除 conf/.generated/"
    fi
}

fix_directories() {
    local dirs=("skill-config" "rules" "agents" "commands" "bin")
    for d in "${dirs[@]}"; do
        if [ ! -d "$CCPRIVATE/$d" ]; then
            mkdir -p "$CCPRIVATE/$d"
            ok "创建目录: $d/"
        fi
    done
}

fix_setup_sh() {
    local bak="$CCPRIVATE/setup.sh.bak.$(date +%Y%m%d)"
    if [ -f "$CCPRIVATE/setup.sh" ]; then
        cp "$CCPRIVATE/setup.sh" "$bak"
        info "已备份: setup.sh → setup.sh.bak.$(date +%Y%m%d)"
    fi
    echo "$SETUP_SH_V3" > "$CCPRIVATE/setup.sh"
    chmod +x "$CCPRIVATE/setup.sh"
    ok "setup.sh 已更新到 v3"
}

fix_link_content() {
    if [ ! -f "$CCPRIVATE/link/CLAUDE.md" ]; then
        echo "$LINK_CLAUDE_MD" > "$CCPRIVATE/link/CLAUDE.md"
        ok "创建: link/CLAUDE.md"
    fi
    if [ ! -f "$CCPRIVATE/link/settings.json" ]; then
        echo "$LINK_SETTINGS_JSON" > "$CCPRIVATE/link/settings.json"
        ok "创建: link/settings.json"
    fi
    if [ ! -f "$CCPRIVATE/link/.config.json" ]; then
        echo "$LINK_DOT_CONFIG_JSON" > "$CCPRIVATE/link/.config.json"
        ok "创建: link/.config.json"
    fi
}

fix_symlinks() {
    if [ -x "$CCPRIVATE/setup.sh" ]; then
        bash "$CCPRIVATE/setup.sh"
    else
        err "ccprivate/setup.sh 不可执行，无法重建 symlink"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  ccprivate 结构检测${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Guard: ccprivate 不存在
if [ ! -d "$CCPRIVATE" ]; then
    echo -e "  ${RED}❌${NC} ccprivate 目录不存在: $CCPRIVATE"
    echo -e "  ${GRAY}创建: bash ccconfig/init-ccprivate-repo.sh${NC}"
    exit 1
fi

echo -e "  ccprivate: ${GREEN}$CCPRIVATE${NC}"
echo ""

# ── 执行所有检测 ──
declare -A check_results
total_issues=0

echo -e "${BOLD}1. .generated/ 迁移${NC}"
if check_generated_dir; then
    echo -e "  ${GREEN}✅${NC} 无需迁移"
    check_results[generated]="ok"
else
    check_results[generated]="fix"
    total_issues=$((total_issues + 1))
fi

echo ""
echo -e "${BOLD}2. 目录结构${NC}"
if check_directories; then
    echo -e "  ${GREEN}✅${NC} 目录完整"
    check_results[dirs]="ok"
else
    check_results[dirs]="fix"
    total_issues=$((total_issues + 1))
fi

echo ""
echo -e "${BOLD}3. setup.sh 版本${NC}"
if check_setup_sh_version; then
    echo -e "  ${GREEN}✅${NC} setup.sh 为当前版本"
    check_results[setup]="ok"
else
    check_results[setup]="fix"
    total_issues=$((total_issues + 1))
fi

echo ""
echo -e "${BOLD}4. link/ 内容${NC}"
if check_link_content; then
    echo -e "  ${GREEN}✅${NC} link/ 文件完整"
    check_results[link]="ok"
else
    check_results[link]="fix"
    total_issues=$((total_issues + 1))
fi

echo ""
echo -e "${BOLD}5. 符号链接${NC}"
echo -e "  ${GRAY}(修复阶段自动重建)${NC}"

echo ""

if [ $total_issues -eq 0 ]; then
    ok "ccprivate 结构已是最新"
    exit 0
fi

if $CHECK_ONLY; then
    echo -e "  ${YELLOW}发现 ${total_issues} 个问题${NC}"
    echo -e "  ${GRAY}修复: bash maintain.sh upgrade-ccprivate${NC}"
    exit 1
fi

# ── 确认 ──
if ! $AUTO_YES; then
    echo -e "${YELLOW}发现 ${total_issues} 个问题，将进行以下修复:${NC}"
    echo ""
    [ "${check_results[generated]}" = "fix" ] && echo "  • 迁移 conf/.generated/ → conf/"
    [ "${check_results[dirs]}" = "fix" ] && echo "  • 创建缺失目录"
    [ "${check_results[setup]}" = "fix" ] && echo "  • 更新 setup.sh (备份为 .bak)"
    [ "${check_results[link]}" = "fix" ] && echo "  • 创建缺失的 link/ 文件"
    echo "  • 重建所有符号链接"
    echo ""
    read -p "是否修复？[Y/n]: " yn
    if [ "$yn" = "n" ] || [ "$yn" = "N" ]; then
        info "已取消"
        exit 0
    fi
fi

echo ""
echo -e "${CYAN}── 开始修复 ──${NC}"
echo ""

# 按顺序执行修复
[ "${check_results[generated]}" = "fix" ] && fix_generated_dir
[ "${check_results[dirs]}" = "fix" ] && fix_directories
[ "${check_results[link]}" = "fix" ] && fix_link_content
[ "${check_results[setup]}" = "fix" ] && fix_setup_sh

# 始终重建 symlink（确保链路正确）
echo ""
fix_symlinks

# 同步模板
if [ -x "$SCRIPT_DIR/example-sync.sh" ]; then
    echo ""
    bash "$SCRIPT_DIR/example-sync.sh" sync 2>/dev/null || true
fi

echo ""
ok "ccprivate 升级完成"
echo -e "  ${GRAY}验证: bash maintain.sh status${NC}"
