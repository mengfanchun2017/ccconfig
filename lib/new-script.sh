#!/bin/bash
# new-script.sh — 生成新的 option 脚手架
#
# 用法:
#   bash lib/new-script.sh mytool                    # 在 option-mytool/ 生成
#   bash lib/new-script.sh mytool --no-register      # 不注册到 init-option
#
# 生成:
#   option-mytool/init.sh        模板填充（脚本入口 + 基础动作）
#   option-mytool/menu-data.sh   菜单数据（MENU_ENTRIES + CAT_NAME）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/colors.sh"

NAME="${1:-}"
REGISTER=true
shift 2>/dev/null || true
for arg in "$@"; do
    case "$arg" in
        --no-register) REGISTER=false ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

[[ -z "$NAME" ]] && { echo "用法: $0 <name> [--no-register]"; exit 1; }
[[ ! "$NAME" =~ ^[a-z][a-z0-9_-]*$ ]] && { echo "名字须小写字母开头: $NAME"; exit 1; }

TARGET="$CCCONFIG_ROOT/option-$NAME"
[[ -d "$TARGET" ]] && { err "已存在: $TARGET"; exit 1; }

mkdir -p "$TARGET"

# ── 生成 init.sh（模板填充）──
# 用 # 作 sed 分隔符（避开 <MYTOOL> 里的 |）
sed "s#<MYTOOL>#$NAME#g" "$SCRIPT_DIR/menu-template.sh" > "$TARGET/init.sh"
chmod +x "$TARGET/init.sh"

# ── 生成 menu-data.sh ──
cat > "$TARGET/menu-data.sh" <<EOF
# option-$NAME 菜单数据
# cat(全局) | letter(分类内) | title | desc | action | submenu

declare -a MENU_ENTRIES=(
    "1|A|安装|首次部署|do_install|"
    "1|B|更新|到最新版|do_update|"
    "1|C|状态||do_status|"
    "1|D|卸载|confirm 后执行|do_uninstall|"
    "0|Q|退出||exit 0|"
)

declare -A CAT_NAME=([1]="$NAME" [0]="退出")
EOF

# ── 注册到 init-option.sh ──
if $REGISTER; then
    INITOPT="$CCCONFIG_ROOT/init-option.sh"
    if grep -q "option-$NAME" "$INITOPT" 2>/dev/null; then
        warn "init-option.sh 已含 $NAME，跳过注册"
    else
        # 用 Python 改 init-option.sh（避开 sed 分隔符转义麻烦）
        python3 - "$INITOPT" "$NAME" <<'PYEOF'
import sys, re
path, name = sys.argv[1], sys.argv[2]
with open(path) as f: src = f.read()
# 在 MENU_GROUPS 的 --other-- 行尾（引号前）追加 $name
pattern = re.compile(r'(--other--\|[^\n"]+)"')
new, n = pattern.subn(lambda m: m.group(1) + ' ' + name + '"', src, count=1)
if n > 0:
    with open(path, 'w') as f: f.write(new)
    print(f'已注册 {name} 到 init-option.sh')
else:
    print(f'未找到 --other-- 行，跳过注册')
PYEOF
    fi
fi

echo ""
ok "已生成 option-$NAME/"
echo "  → 编辑 $TARGET/menu-data.sh 加菜单项"
echo "  → 编辑 $TARGET/init.sh 加 do_install/do_update 逻辑"
echo "  → 测试: bash $TARGET/init.sh"
