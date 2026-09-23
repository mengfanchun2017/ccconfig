#!/bin/bash
# test-maintain.sh — maintain.sh 数据层/菜单/入口回归测试
#
# 覆盖：
#   - 语法 + MAINTAIN_TEST_MODE guard
#   - MENU_ENTRIES schema：5 字段、分类连续、退出项、字母唯一
#   - cmd 列真实可跑（脚本路径存在、maintain.sh 子命令存在）
#   - action 引用的脚本/函数全部存在
#   - set -e 下菜单动作不得杀死进程（历史 bug：选完就退出）
#   - cmd 列显示宽度对齐（CJK 按 2 列算）
#   - menu_select 取消契约（cancel="0"）
#   - 顶层 case 无 local（set -e 不中断）
#   - SCRIPT_DIR 单赋值
#   - pty：菜单渲染一次、动作后回到菜单不退出、q 干净退出
#
# 用法: bash tests/test-maintain.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── 1. 语法 ──
echo "=== 1. 语法检查 ==="
for f in maintain.sh lib/menu-data-maintain.sh lib/interact.sh; do
    bash -n "$CCCONFIG_DIR/$f" 2>/dev/null && pass "$f syntax" || fail "$f syntax"
done

# ── 2. guard ──
echo "=== 2. MAINTAIN_TEST_MODE guard ==="
grep -q 'MAINTAIN_TEST_MODE' "$CCCONFIG_DIR/maintain.sh" && pass "guard 存在" || fail "guard 缺失"

# ── 3. source 加载函数/数据 ──
echo "=== 3. 加载函数 + MENU_ENTRIES ==="
eval "$(MAINTAIN_TEST_MODE=1 bash -c '
source "'"$CCCONFIG_DIR"'/lib/colors.sh" 2>/dev/null || true
source "'"$CCCONFIG_DIR"'/lib/path-helper.sh" 2>/dev/null || true
source "'"$CCCONFIG_DIR"'/lib/interact.sh"
source "'"$CCCONFIG_DIR"'/lib/menu-data-maintain.sh"
' 2>/dev/null)"
# 菜单动作函数（do_setup/ask_run/...）定义在 maintain.sh 主体
# 注意：maintain.sh 内部 set -euo pipefail 会打开 set -e，source 后重置避免测试误中断
MAINTAIN_TEST_MODE=1 source "$CCCONFIG_DIR/maintain.sh" 2>/dev/null
set +e

[[ "${#MENU_ENTRIES[@]}" -gt 0 ]] && pass "MENU_ENTRIES 已加载 (${#MENU_ENTRIES[@]} 条)" || fail "MENU_ENTRIES 空"

# ── 4. schema：字段数 / 退出项 / 分类连续 / 字母唯一 ──
echo "=== 4. MENU_ENTRIES schema ==="
has_exit=false
bad_fields=0
declare -A seen
dupe=0
declare -A cat_seen
for entry in "${MENU_ENTRIES[@]}"; do
    [[ "$(echo "$entry" | awk -F'|' '{print NF}')" -eq 5 ]] || bad_fields=$((bad_fields+1))
    IFS='|' read -r cat letter title cmd action <<< "$entry"
    cat=$(trim "$cat"); letter=$(trim "$letter")
    cat_seen[$cat]=1
    [[ "$cat" == "0" ]] && { has_exit=true; continue; }
    [[ -z "$letter" ]] && { fail "cat=$cat 条目缺 letter: $title"; continue; }
    [[ -n "${seen[$cat$letter]:-}" ]] && { fail "键重复: $cat$letter"; dupe=$((dupe+1)); }
    seen[$cat$letter]=1
done
$has_exit && pass "含退出项 (cat=0)" || fail "缺退出项"
[[ $bad_fields -eq 0 ]] && pass "所有条目 5 字段 (cat|letter|title|cmd|action)" || fail "字段数不对" "$bad_fields 条"
[[ $dupe -eq 0 ]] && pass "无重复键" || fail "重复键 $dupe 处"

cats=$(for k in "${!cat_seen[@]}"; do echo "$k"; done | sort -n | tr '\n' ' ')
[[ "$cats" == "0 1 2 3 4 5 6 7 " ]] && pass "分类连续 1-7 + 退出" || fail "分类编号不连续" "$cats"

# ── 5. cmd 列：非空 + 路径存在 + maintain.sh 子命令存在 ──
echo "=== 5. cmd 列可跑性 ==="
bad_cmd=0
for entry in "${MENU_ENTRIES[@]}"; do
    IFS='|' read -r cat letter title cmd action <<< "$entry"
    cat=$(trim "$cat"); letter=$(trim "$letter"); cmd=$(trim "$cmd")
    [[ "$cat" == "0" ]] && continue
    [[ -n "$cmd" ]] || { fail "$cat$letter cmd 为空"; bad_cmd=$((bad_cmd+1)); continue; }

    if [[ "$cmd" == ./* ]]; then
        first="${cmd%% *}"
        [[ -e "$CCCONFIG_DIR/${first#./}" ]] || { fail "$cat$letter cmd 脚本不存在: $first"; bad_cmd=$((bad_cmd+1)); continue; }
        # ./maintain.sh <sub> → <sub> 必须真的在顶层 case 里，否则"直接调用"是假的
        sub=$(echo "$cmd" | awk '{print $2}')
        if [[ -n "$sub" && "$sub" != -* ]]; then
            grep -qE "^[[:space:]]*[a-z|-]*\b${sub}\b" "$CCCONFIG_DIR/maintain.sh" \
                || { fail "$cat$letter cmd 子命令未注册: $sub"; bad_cmd=$((bad_cmd+1)); continue; }
        fi
    elif [[ "$cmd" == bash\ * ]]; then
        path=$(echo "$cmd" | awk '{print $2}')
        [[ "$path" == -* ]] && { fail "$cat$letter cmd 缺脚本路径"; bad_cmd=$((bad_cmd+1)); continue; }
        [[ -e "$CCCONFIG_DIR/$path" ]] || { fail "$cat$letter cmd 路径不存在: $path"; bad_cmd=$((bad_cmd+1)); continue; }
    else
        fail "$cat$letter cmd 不是可复制到终端的命令: $cmd"; bad_cmd=$((bad_cmd+1)); continue
    fi
done
[[ $bad_cmd -eq 0 ]] && pass "全部 cmd 指向真实脚本/子命令" || fail "$bad_cmd 条 cmd 断裂"

# ── 6. action 引用解析 ──
echo "=== 6. action 引用 ==="
missing=0
for entry in "${MENU_ENTRIES[@]}"; do
    IFS='|' read -r cat letter title cmd action <<< "$entry"
    cat=$(trim "$cat"); letter=$(trim "$letter")
    [[ "$cat" == "0" ]] && continue
    [[ -n "$action" ]] || { fail "$cat$letter 无 action"; missing=$((missing+1)); continue; }

    # bash "$VAR/xxx" [args] → 解析路径
    script_path=$(echo "$action" | grep -oE 'bash "\$[A-Z_]+/[^"]+"' | head -1 | sed -E 's/bash "\$[A-Z_]+\///; s/"$//')
    if [[ -n "$script_path" ]]; then
        case "$action" in
            *'"$LIB_DIR/'*)      full="$CCCONFIG_DIR/lib/$script_path" ;;
            *'"$CCCONFIG_DIR/'*) full="$CCCONFIG_DIR/$script_path" ;;
            *)                   full="$CCCONFIG_DIR/$script_path" ;;
        esac
        [[ -e "$full" ]] || { fail "$cat$letter action 路径不存在: $full"; missing=$((missing+1)); continue; }
    else
        # 函数名（可带参数，取第一个 token）
        fn=$(echo "$action" | awk '{print $1}')
        declare -F "$fn" >/dev/null 2>&1 || { fail "$cat$letter action 未定义函数: $fn"; missing=$((missing+1)); continue; }
    fi
    pass "$cat$letter action OK"
done
[[ $missing -eq 0 ]] && pass "action 引用全部解析" || fail "$missing 处引用断裂"

# ── 7. menu_loop 死代码清除 ──
echo "=== 7. menu_loop 无死代码 ==="
if grep -A2 'read -r dummy' "$CCCONFIG_DIR/lib/interact.sh" | grep -qE 'selected\[@\]|items\[@\]'; then
    fail "menu_loop 仍有 selected/items 死代码"
else
    pass "menu_loop 死代码已清除"
fi

# ── 8. menu_select 取消契约 ──
echo "=== 8. menu_select 取消契约 ==="
out=$(printf "99\n" | menu_select "t" "a" "b" 2>/dev/null)
[[ "$out" == "0" ]] && pass "OOR → 0" || fail "OOR" "got $out"
out=$(menu_select "t" "a" "b" </dev/null 2>/dev/null)
[[ "$out" == "0" ]] && pass "EOF → 0" || fail "EOF" "got $out"
out=$(printf "2\n" | menu_select "t" "a" "b" 2>/dev/null)
[[ "$out" == "2" ]] && pass "valid → 序号" || fail "valid" "got $out"

# ── 9. set -e 下菜单动作不得杀死进程 ──
echo "=== 9. set -e 回归（动作失败/返回 3 不得退出）==="
# 历史 bug：_exec_entry 返回 3（子菜单返回 / 未知项 / 动作失败）被 set -e 当成致命错误，
# 表现为"选完一项、或从子菜单返回时 maintain.sh 自己退出了"。
out=$(bash -c '
set -euo pipefail
source "'"$CCCONFIG_DIR"'/lib/colors.sh"
source "'"$CCCONFIG_DIR"'/lib/interact.sh"
MENU_ENTRIES=("1|A|失败项||false" "1|B|正常项||true" "0| |退出||exit 0")
menu_parse "1A" || true
echo "ALIVE-AFTER-FAIL"
menu_parse "2Z" || true
echo "ALIVE-AFTER-MISS"
menu_parse "1B" || true
echo "ALIVE-AFTER-OK"
' 2>/dev/null)
for marker in ALIVE-AFTER-FAIL ALIVE-AFTER-MISS ALIVE-AFTER-OK; do
    echo "$out" | grep -q "$marker" && pass "$marker" || fail "set -e 杀死了进程（缺 $marker）"
done

# menu_loop 也必须捕获 menu_parse 的 1/2/3
grep -qE 'menu_parse "\$choice" \|\| rc=\$\?' "$CCCONFIG_DIR/lib/interact.sh" \
    && pass "menu_loop 捕获 menu_parse 返回码" || fail "menu_loop 裸调 menu_parse（set -e 会退出）"

# ── 10. cmd 列显示宽度对齐 ──
echo "=== 10. cmd 列对齐 ==="
align=$(python3 - "$CCCONFIG_DIR" <<'PYEOF'
import re, subprocess, sys
cc = sys.argv[1]
out = subprocess.run(["bash", "-c",
    'source lib/colors.sh; source lib/interact.sh; source lib/menu-data-maintain.sh; menu_render'],
    capture_output=True, text=True, cwd=cc).stdout
w = lambda s: sum(2 if ord(c) > 127 else 1 for c in s)
cols = set()
for line in out.splitlines():
    clean = re.sub(r"\x1b\[[0-9;]*m", "", line)
    if re.match(r"^  \d+[A-Z]  ", clean):
        m = re.search(r"\s(\./maintain\.sh|bash )", clean)
        if m:
            cols.add(w(clean[:m.start() + 1]))
print("OK" if len(cols) == 1 else f"BAD:{sorted(cols)}")
PYEOF
)
[[ "$align" == "OK" ]] && pass "所有 cmd 起始列一致（CJK 按 2 列）" || fail "cmd 列不齐" "$align"

# ── 11. 扁平化：无二级菜单 ──
echo "=== 11. 无子菜单 ==="
grep -qE '_submenu_|menu:[a-z]' "$CCCONFIG_DIR/maintain.sh" "$CCCONFIG_DIR/lib/menu-data-maintain.sh" \
    && fail "残留子菜单机制（menu:xxx / _submenu_）" || pass "无子菜单机制"
# 只查代码/文案，注释里解释"为什么不要返回上层"不算
if grep -n '返回上层' "$CCCONFIG_DIR/maintain.sh" "$CCCONFIG_DIR/lib/interact.sh" "$CCCONFIG_DIR/lib/menu-data-maintain.sh" \
     | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -q .; then
    fail "残留「返回上层」文案" "$(grep -n '返回上层' "$CCCONFIG_DIR/maintain.sh" "$CCCONFIG_DIR/lib/interact.sh" "$CCCONFIG_DIR/lib/menu-data-maintain.sh" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | head -3)"
else
    pass "无「返回上层」文案"
fi

# ── 12. 顶层 case 无 local ──
echo "=== 12. 顶层 case 无 local ==="
awk '/^case "\$\{1:-menu\}/,/^esac$/' "$CCCONFIG_DIR/maintain.sh" | grep -q 'local ' \
    && fail "顶层 case 仍用 local" || pass "顶层 case 无 local"

# ── 13. SCRIPT_DIR 单赋值 ──
echo "=== 13. SCRIPT_DIR 单赋值 ==="
assign_count=$(grep -cE '^SCRIPT_DIR=' "$CCCONFIG_DIR/maintain.sh")
[[ $assign_count -eq 1 ]] && pass "SCRIPT_DIR 单赋值 ($assign_count)" || fail "SCRIPT_DIR 重复赋值" "$assign_count 处"

# ── 14. menu_parse 快捷键返回码（不执行动作）──
echo "=== 14. menu_parse 快捷键 ==="
menu_parse "q" ; [[ $? -eq 2 ]] && pass "q → 2(退出)" || fail "q"
menu_parse "r" ; [[ $? -eq 1 ]] && pass "r → 1(刷新)" || fail "r"
menu_parse "zzz" ; [[ $? -eq 3 ]] && pass "无效 → 3" || fail "无效输入"

echo "=== 15. 快捷键映射与文案一致 ==="
# 历史 bug：t 指向的项与 help 文案写的不是同一个，按 t 会进高风险操作。
grep -qE 't\|T\)[[:space:]]+_exec_entry 2 A' "$CCCONFIG_DIR/lib/interact.sh" \
    && pass "t → 2A(日志跟踪)" || fail "t 快捷键未指向日志跟踪"
grep -qE 's\|S\)[[:space:]]+_exec_entry 1 A' "$CCCONFIG_DIR/lib/interact.sh" \
    && pass "s → 1A(状态检查)" || fail "s 快捷键未指向状态检查"

# ── 16. pty：动作执行后回到菜单（不退出）+ q 干净退出 ──
echo "=== 16. pty 菜单交互 ==="
pty_out=$(python3 - "$CCCONFIG_DIR" <<'PYEOF'
import os, pty, sys, time, select, signal
ccconfig = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(ccconfig)
    os.execvp("bash", ["bash", "maintain.sh"])
buf = b""
def drain(sec):
    global buf
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if fd in r:
            try:
                d = os.read(fd, 8192)
            except OSError:
                return
            if not d:
                return
            buf += d
drain(0.8)
os.write(fd, b"9B\n")      # 9B 无效项：验证无效输入不崩溃、回到菜单
drain(2.0)
os.write(fd, b"\n")        # 按回车继续 → 应重绘主菜单
drain(1.5)
os.write(fd, b"q\n")       # 退出
drain(1.5)
# 子进程若不退（动作吃了输入导致 read 阻塞），别让 waitpid 把测试挂死
for _ in range(20):
    try:
        if os.waitpid(pid, os.WNOHANG)[0]:
            break
    except ChildProcessError:
        break
    time.sleep(0.1)
else:
    os.kill(pid, signal.SIGKILL)
    try:
        os.waitpid(pid, 0)
    except Exception:
        pass
sys.stdout.write(buf.decode("utf-8", "replace"))
PYEOF
)
banner_count=$(echo "$pty_out" | grep -c 'ccconfig 运维中心')
if [[ $banner_count -ge 2 ]]; then
    pass "动作执行后重绘主菜单（banner ×$banner_count，没有退出）"
else
    fail "动作后未回到菜单（banner ×$banner_count）—— set -e 退出回归？"
fi
echo "$pty_out" | grep -q -- '--4 LLM--' && pass "菜单含 LLM 分类" || fail "菜单缺 LLM 分类"
echo "$pty_out" | grep -q '退出' && pass "菜单含退出项" || fail "无退出项"

echo "=== 17. 非交互不死循环 ==="
# 历史 bug：EOF → choice="" → 重绘，无限自旋（实测 4s 渲染 116 次）。
for s in maintain.sh lib/sync.sh; do
    start=$(date +%s)
    timeout 10 bash "$CCCONFIG_DIR/$s" </dev/null >/dev/null 2>&1
    rc=$?
    elapsed=$(( $(date +%s) - start ))
    if [[ $rc -eq 124 ]]; then
        fail "$s 非交互下死循环"
    elif [[ $elapsed -gt 8 ]]; then
        fail "$s 非交互下耗时 ${elapsed}s"
    else
        pass "$s 非交互快速退出 (exit=$rc, ${elapsed}s)"
    fi
done

echo ""
echo "────────────────────────────────────"
printf "  ${GREEN}PASS${NC}: %d  ${RED}FAIL${NC}: %d\n" "$PASS" "$FAIL"
echo "────────────────────────────────────"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
