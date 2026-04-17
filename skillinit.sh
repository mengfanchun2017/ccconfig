#!/bin/bash
# Claude Skills 管理脚本
# 功能：安装、同步、管理 Claude Code Skills
# 配合 claudeinit.sh 使用
#
# 使用：
#   bash ccconfig/skillinit.sh          # 同步安装所有 skills（install + config）
#   bash ccconfig/skillinit.sh install # 安装缺失的 skills
#   bash ccconfig/skillinit.sh sync    # 双向同步 skills

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/.agents/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
SKILLS_LOCK="$SCRIPT_DIR/skills-lock.json"

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

# ========== Skills 列表 ==========
get_skill_list() {
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

# ========== 检查 skills 是否安装 ==========
is_skill_installed() {
    local name="$1"
    # 检查 ccconfig 目录或 ~/.claude/skills
    [[ -d "$SKILLS_DIR/$name" || -d "$CLAUDE_SKILLS_DIR/$name" ]]
}

# ========== 同步 skills 到 ~/.claude/skills ==========
sync_skills_to_local() {
    section "同步 Skills 到本地"

    # 1. 同步 ccconfig/.agents/skills/* → ~/.claude/skills/
    if [[ -d "$SKILLS_DIR" ]]; then
        for skill_dir in "$SKILLS_DIR"/*; do
            [[ -d "$skill_dir" ]] || continue
            skill_name=$(basename "$skill_dir")
            target="$CLAUDE_SKILLS_DIR/$skill_name"

            if [[ -L "$target" ]]; then
                # 已经是符号链接，跳过
                info "跳过 $skill_name: 已是符号链接"
            elif [[ -d "$target" ]]; then
                # 本地存在但不是链接，检查是否相同
                info "保留 $skill_name: 本地存在"
            else
                # 创建符号链接
                ln -s "$skill_dir" "$target" 2>/dev/null && good "链接 $skill_name" || warn "失败 $skill_name"
            fi
        done
    fi

    # 2. 同步 ccconfig/.claude/skills/* → ~/.claude/skills/
    if [[ -d "$SCRIPT_DIR/.claude/skills" ]]; then
        for skill_dir in "$SCRIPT_DIR/.claude/skills"/*; do
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
regenerate_lock() {
    python3 - "$SKILLS_DIR" << 'PYEOF'
import json, os, hashlib

skills_dir = os.path.expanduser(os.path.expandvars(os.path.abspath(__file__).replace('/skillinit.sh', '/.agents/skills')))
lock_file = os.path.expanduser(os.path.expandvars(os.path.abspath(__file__).replace('/skillinit.sh', '/skills-lock.json')))

skills = {}
if os.path.isdir(skills_dir):
    for name in os.listdir(skills_dir):
        skill_path = os.path.join(skills_dir, name)
        if not os.path.isdir(skill_path):
            continue
        # 计算 hash
        hash_md5 = hashlib.md5()
        for root, dirs, files in os.walk(skill_path):
            for f in sorted(files):
                fpath = os.path.join(root, f)
                try:
                    with open(fpath, 'rb') as fh:
                        hash_md5.update(fpath.encode())
                        hash_md5.update(fh.read())
                except:
                    pass
        skills[name] = {
            "source": "npx-skills-add",
            "sourceType": "github",
            "computedHash": hash_md5.hexdigest()
        }

result = {"version": 1, "skills": skills}
with open(lock_file, 'w') as f:
    json.dump(result, f, indent=2)
print("ok")
PYEOF
}

# ========== 添加新 skill ==========
add_skill() {
    local source="$1"
    local skill_name="$2"

    info "添加 $skill_name ($source)..."

    # 使用 npx skills add 安装
    if npx skills add "$source" --yes 2>&1 | grep -q "error\|Error\|failed\|Failed"; then
        bad "❌ 添加失败"
        return 1
    fi

    good "✅ 添加成功"
    return 0
}

# ========== 主程序 ==========
if [[ ! -d "$SKILLS_DIR" ]]; then
    mkdir -p "$SKILLS_DIR"
fi

action="${1:-sync}"

case "$action" in
    install)
        title "安装 Skills"
        # 显示可用的 skills 并安装
        if [[ -f "$SKILLS_LOCK" ]]; then
            while IFS='|' read -r name source sourceType; do
                [[ -z "$name" ]] && continue
                if is_skill_installed "$name"; then
                    info "跳过 $name: 已安装"
                else
                    echo "安装 $name..."
                    # TODO: 从 source 重新安装
                    warn "需要手动安装: $name (source: $source)"
                fi
            done <<< "$(get_skill_list)"
        fi
        ;;
    sync)
        title "Skills 同步"
        sync_skills_to_local
        ;;
    lock)
        title "生成 skills-lock.json"
        regenerate_lock
        ;;
    add)
        [[ -z "$2" ]] && bad "用法: $0 add <source>" && exit 1
        add_skill "$2" "$3"
        ;;
    list)
        npx skills list 2>&1
        ;;
    *)
        info "用法: $0 {install|sync|lock|add|list}"
        exit 1
        ;;
esac

echo ""
title "✅ 完成"
echo "提示: npx skills list 查看 Skills 状态"
exit 0
