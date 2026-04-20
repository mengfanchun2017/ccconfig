#!/bin/bash
# Claude Skills 管理脚本
# 功能：安装、同步、管理 Claude Code Skills
# 配合 claudeinit.sh 使用，skills 存放在 ccconfig 目录（Git 追踪）
#
# 同步流程：
#   A机器: skillinit.sh add <source> → 安装到 ccconfig/.agents/skills/ → git push
#   B机器: git pull → skillinit.sh install → 从 source 重新安装缺失 skills
#
# 使用：
#   bash ccconfig/skillinit.sh install  # 从 GitHub 拉取后，安装所有缺失的 skills
#   bash ccconfig/skillinit.sh add <npx-source>  # 添加新 skill 并同步到 GitHub
#   bash ccconfig/skillinit.sh sync     # 同步 skills 到 ~/.claude/skills/
#   bash ccconfig/skillinit.sh list    # 查看已安装 skills
#   bash ccconfig/skillinit.sh lock    # 更新 skills-lock.json

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_LOCK="$SCRIPT_DIR/skills-lock.json"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"

# 两个 skills 目录（都被 Git 追踪）
AGENTS_SKILLS_DIR="$SCRIPT_DIR/.agents/skills"
CLAUDE_SKILLS_DIR_IN_CC="$SCRIPT_DIR/.claude/skills"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

title() { echo -e "\n========================================\n$1\n========================================\n${CYAN}"; }
section() { echo -e "\n【$1】${YELLOW}"; }
good() { echo -e "$1${GREEN}"; }
bad() { echo -e "$1${RED}"; }
info() { echo -e "$1${GRAY}"; }
warn() { echo -e "$1${YELLOW}"; }

# ========== 读取 skills-lock.json ==========
read_skills_lock() {
    python3 - "$SKILLS_LOCK" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    skills = data.get('skills', {})
    for name, info in skills.items():
        print(f"{name}|{info.get('source','')}|{info.get('sourceType','')}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ========== 检查 skills 是否在本地 ccconfig ==========
is_skill_in_ccconfig() {
    local name="$1"
    [[ -d "$AGENTS_SKILLS_DIR/$name" || -d "$CLAUDE_SKILLS_DIR_IN_CC/$name" ]]
}

# ========== 检查 ~/.claude/skills 中是否有 ==========
is_skill_in_local() {
    local name="$1"
    [[ -d "$CLAUDE_SKILLS_DIR/$name" || -L "$CLAUDE_SKILLS_DIR/$name" ]]
}

# ========== 安装单个 skill（从 source） ==========
install_skill_from_source() {
    local name="$1"
    local source="$2"

    info "安装 $name (source: $source) ..."

    # npx skills add <source>
    if npx skills add "$source" --yes 2>&1 | grep -q "error\|Error\|failed\|Failed"; then
        bad "❌ $name 安装失败"
        return 1
    fi

    good "✅ $name 安装成功"
    return 0
}

# ========== 从 source 安装并同步到 ccconfig ==========
add_skill() {
    local npx_source="$1"

    info "添加 skill: $npx_source ..."

    # 1. 用 npx 安装到 ~/.claude/skills/
    if npx skills add "$npx_source" --yes 2>&1 | grep -q "error\|Error\|failed\|Failed"; then
        bad "❌ 添加失败"
        return 1
    fi

    # 2. 从 npx output 提取 skill name
    # npx skills add 会 clone 到 ~/.claude/skills/ 或 .agents/skills/
    # 找 newly added skill name
    local new_skill_name=""
    new_skill_name=$(npx skills list 2>&1 | grep -v "Project Skills" | awk '{print $1}' | while read n; do
        if [[ -d "$AGENTS_SKILLS_DIR/$n" || -d "$CLAUDE_SKILLS_DIR_IN_CC/$n" ]]; then
            echo "$n"
        fi
    done | tail -1)

    if [[ -z "$new_skill_name" ]]; then
        warn "无法自动检测新 skill 名称，请手动指定"
        new_skill_name=$(basename "$npx_source" | cut -d'@' -f1)
    fi

    # 3. 如果 skill 在 ~/.claude/skills/ 但不在 ccconfig，复制过去
    if [[ -d "$CLAUDE_SKILLS_DIR/$new_skill_name" ]] && [[ ! -d "$AGENTS_SKILLS_DIR/$new_skill_name" ]]; then
        cp -r "$CLAUDE_SKILLS_DIR/$new_skill_name" "$AGENTS_SKILLS_DIR/$new_skill_name" 2>/dev/null || \
        ln -s "$CLAUDE_SKILLS_DIR/$new_skill_name" "$AGENTS_SKILLS_DIR/$new_skill_name" 2>/dev/null
        good "✅ 已同步到 ccconfig/.agents/skills/"
    fi

    # 4. 更新 skills-lock.json
    regenerate_lock

    good "✅ $new_skill_name 添加成功"
    return 0
}

# ========== 安装所有缺失的 skills（从 source） ==========
do_install() {
    title "安装 Skills"

    if [[ ! -f "$SKILLS_LOCK" ]]; then
        warn "skills-lock.json 不存在，先运行 sync 或 lock"
        return 1
    fi

    local installed=0
    local failed=0

    while IFS='|' read -r name source sourceType; do
        [[ -z "$name" ]] && continue

        if is_skill_in_ccconfig "$name"; then
            info "跳过 $name: ccconfig 中已存在"
            continue
        fi

        echo "安装 $name (source: $source)..."
        if install_skill_from_source "$name" "$source"; then
            ((installed++))
        else
            ((failed++))
        fi
    done <<< "$(read_skills_lock)"

    echo ""
    if [[ $installed -gt 0 ]]; then
        good "✅ 成功安装 $installed 个 skills"
    fi
    if [[ $failed -gt 0 ]]; then
        bad "❌ $failed 个 skills 安装失败"
    fi
}

# ========== 同步 ccconfig skills 到 ~/.claude/skills ==========
do_sync() {
    title "同步 Skills 到本地"

    mkdir -p "$CLAUDE_SKILLS_DIR"

    # 1. 同步 .agents/skills/* → ~/.claude/skills/
    if [[ -d "$AGENTS_SKILLS_DIR" ]]; then
        for skill_dir in "$AGENTS_SKILLS_DIR"/*; do
            [[ -d "$skill_dir" ]] || continue
            skill_name=$(basename "$skill_dir")
            target="$CLAUDE_SKILLS_DIR/$skill_name"

            if [[ -L "$target" ]]; then
                info "跳过 $skill_name: 已是符号链接"
            elif [[ -d "$target" ]]; then
                # 本地存在但不是链接，用 ccconfig 版本覆盖或合并
                info "保留 $skill_name: 本地存在"
            else
                # 创建符号链接
                ln -s "$skill_dir" "$target" 2>/dev/null && good "链接 $skill_name" || warn "失败 $skill_name"
            fi
        done
    fi

    # 2. 同步 .claude/skills/* → ~/.claude/skills/
    if [[ -d "$CLAUDE_SKILLS_DIR_IN_CC" ]]; then
        for skill_dir in "$CLAUDE_SKILLS_DIR_IN_CC"/*; do
            [[ -d "$skill_dir" ]] || continue
            skill_name=$(basename "$skill_dir")
            target="$CLAUDE_SKILLS_DIR/$skill_name"

            if [[ -L "$target" ]]; then
                info "跳过 $skill_name: 已是符号链接"
            elif [[ -d "$target" ]]; then
                info "保留 $skill_name: 本地存在"
            else
                ln -s "$skill_dir" "$target" 2>/dev/null && good "链接 $skill_name" || warn "失败 $skill_name"
            fi
        done
    fi

    good "✅ Skills 同步完成"
}

# ========== 生成 skills-lock.json ==========
do_lock() {
    title "生成 skills-lock.json"

    python3 - "$AGENTS_SKILLS_DIR" "$CLAUDE_SKILLS_DIR_IN_CC" "$SKILLS_LOCK" << 'PYEOF'
import json, os, hashlib, sys

agents_dir = sys.argv[1]
claude_dir = sys.argv[2]
lock_file = sys.argv[3]

skills = {}

# 扫描 .agents/skills/
for name in os.listdir(agents_dir):
    skill_path = os.path.join(agents_dir, name)
    if not os.path.isdir(skill_path):
        continue
    hash_md5 = hashlib.md5()
    for root, dirs, files in os.walk(skill_path):
        dirs.sort()
        for f in sorted(files):
            fpath = os.path.join(root, f)
            try:
                with open(fpath, 'rb') as fh:
                    hash_md5.update(fpath.encode('utf-8'))
                    hash_md5.update(fh.read())
            except:
                pass
    skills[name] = {
        "source": "npx-skills-add",
        "sourceType": "github",
        "computedHash": hash_md5.hexdigest()
    }

# 扫描 .claude/skills/（Deep-Research 等）
if os.path.isdir(claude_dir):
    for name in os.listdir(claude_dir):
        skill_path = os.path.join(claude_dir, name)
        if not os.path.isdir(skill_path):
            continue
        if name in skills:
            continue  # 已存在则跳过
        hash_md5 = hashlib.md5()
        for root, dirs, files in os.walk(skill_path):
            dirs.sort()
            for f in sorted(files):
                fpath = os.path.join(root, f)
                try:
                    with open(fpath, 'rb') as fh:
                        hash_md5.update(fpath.encode('utf-8'))
                        hash_md5.update(fh.read())
                except:
                    pass
        skills[name] = {
            "source": "deep-research-manual",
            "sourceType": "local",
            "computedHash": hash_md5.hexdigest()
        }

result = {"version": 1, "skills": skills}
with open(lock_file, 'w') as f:
    json.dump(result, f, indent=2)
print(f"ok ({len(skills)} skills)")
PYEOF
}

# ========== 主程序 ==========
action="${1:-sync}"

case "$action" in
    install)
        do_install
        ;;
    sync)
        do_sync
        ;;
    lock)
        do_lock
        ;;
    add)
        [[ -z "$2" ]] && bad "用法: $0 add <npx-source>" && exit 1
        add_skill "$2"
        ;;
    list)
        npx skills list 2>&1
        ;;
    status)
        echo "=== Skills 状态 ==="
        echo ""
        echo "ccconfig/.agents/skills/:"
        ls "$AGENTS_SKILLS_DIR" 2>/dev/null | while read n; do echo "  ✅ $n"; done
        echo ""
        echo "ccconfig/.claude/skills/:"
        ls "$CLAUDE_SKILLS_DIR_IN_CC" 2>/dev/null | while read n; do echo "  ✅ $n"; done
        echo ""
        echo "~/.claude/skills/:"
        ls "$CLAUDE_SKILLS_DIR" 2>/dev/null | while read n; do echo "  ✅ $n"; done
        ;;
    *)
        echo "用法: $0 {install|sync|lock|add|list|status}"
        echo ""
        echo "  install - 从 GitHub 拉取后，安装所有缺失的 skills（多机同步用）"
        echo "  add     - 添加新 skill 并同步到 ccconfig（单机器用）"
        echo "  sync    - 同步 ccconfig/skills 到 ~/.claude/skills/（每次 Git pull 后运行）"
        echo "  lock    - 更新 skills-lock.json"
        echo "  list    - 查看已安装 skills"
        echo "  status  - 查看 skills 状态"
        exit 1
        ;;
esac

echo ""
good "提示: bash ccconfig/skillinit.sh install 在新环境同步时使用"
exit 0
