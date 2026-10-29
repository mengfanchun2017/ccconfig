#!/bin/bash
# tests/test-botmux-option.sh — option-botmux 回归
#
# 覆盖：
#   1. 语法 + 可执行 + shebang
#   2. --status 契约（首行 OK/WARN/MISSING，退出码与状态一致）
#   3. 接线：init-option 分组、maintain 菜单项、maintain.sh 子命令、deps-check
#   4. 已废弃 ccbridge 不再被引用（无 resolve_ccbridge 调用方）
#   5. dry-run 安全（--install 不真装）
#   6. 非 TTY 不阻塞（无 tty 时 sessions 走 --plain）

set -uo pipefail
CCCONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$CCCONFIG_DIR"
INIT="$CCCONFIG_DIR/option-botmux/init.sh"

PASS=0; FAIL=0
pass() { echo -e "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ❌ $1"; FAIL=$((FAIL + 1)); }
section() { echo -e "\n=== $1 ==="; }

# ── 1. 语法 / 可执行 / shebang ──
section "1. 语法 / 可执行 / shebang"
if bash -n "$INIT" 2>/dev/null; then pass "bash -n 语法 OK"; else fail "bash -n 语法错误"; fi
if [ -x "$INIT" ]; then pass "可执行"; else fail "不可执行"; fi
if head -1 "$INIT" | grep -q '^#!/bin/bash'; then pass "bash shebang"; else fail "shebang 非 bash"; fi

# ── 2. --status 契约 ──
section "2. --status 契约"
out="$(bash "$INIT" --status 2>&1)"; rc=$?
first="$(printf '%s\n' "$out" | head -1)"
if printf '%s' "$first" | grep -qE '^(OK|WARN|MISSING) botmux '; then
    pass "首行符合 OK/WARN/MISSING 契约: $first"
else
    fail "首行不符契约: $first"
fi
case "$first" in
    OK*)      [ $rc -eq 0 ] && pass "OK → rc=0" || fail "OK 但 rc=$rc（应 0）" ;;
    WARN*)    [ $rc -eq 1 ] && pass "WARN → rc=1" || fail "WARN 但 rc=$rc（应 1）" ;;
    MISSING*) [ $rc -eq 2 ] && pass "MISSING → rc=2" || fail "MISSING 但 rc=$rc（应 2）" ;;
esac
# 无 ANSI 在首行（init-option 按行解析，带色会解析失败）
if printf '%s' "$first" | grep -q $'\x1b'; then fail "首行含 ANSI（破坏 init-option 解析）"; else pass "首行无 ANSI"; fi

# ── 3. 接线 ──
section "3. 接线（init-option / maintain / deps-check）"
if grep -q '"\-\-飞书--|larkcli botmux"' "$CCCONFIG_DIR/init-option.sh"; then
    pass "init-option 分组含 botmux"
else
    fail "init-option 分组缺 botmux"
fi
if grep -q 'botmux)' "$CCCONFIG_DIR/init-option.sh"; then
    pass "init-option --yes 分支含 botmux"
else
    fail "init-option --yes 分支缺 botmux"
fi
if grep -q 'botmux)' "$CCCONFIG_DIR/maintain.sh"; then
    pass "maintain.sh 有 botmux 子命令"
else
    fail "maintain.sh 缺 botmux 子命令"
fi
if grep -q '5|G|botmux' "$CCCONFIG_DIR/lib/menu-data-maintain.sh"; then
    pass "主菜单含 botmux 项（5G）"
else
    fail "主菜单缺 botmux 项"
fi
if grep -q '"botmux|botmux --version' "$CCCONFIG_DIR/lib/deps-check.sh"; then
    pass "deps-check 含 botmux 依赖项"
else
    fail "deps-check 缺 botmux 依赖项"
fi
if grep -q 'botmux)' "$CCCONFIG_DIR/lib/status.sh"; then
    pass "status.sh 有 botmux 检测分支"
else
    fail "status.sh 缺 botmux 检测分支"
fi

# 旧名转发（larkbridge → botmux）
if grep -q 'larkbridge' "$CCCONFIG_DIR/init-option.sh" && \
   grep -q 'install_option "botmux"' "$CCCONFIG_DIR/init-option.sh"; then
    pass "旧名 larkbridge 转发到 botmux"
else
    fail "旧名 larkbridge 未转发"
fi

# ── 4. ccbridge 已摘除 ──
section "4. ccbridge 已摘除"
# resolve_ccbridge 无调用方（定义已删，注释里提到不算）
if grep -rn 'resolve_ccbridge' --include=*.sh "$CCCONFIG_DIR/lib" "$CCCONFIG_DIR/init-option.sh" "$CCCONFIG_DIR/maintain.sh" 2>/dev/null \
    | grep -v '^.*#' | grep -q .; then
    fail "仍有 resolve_ccbridge 调用方"
else
    pass "无 resolve_ccbridge 调用方（已摘除）"
fi
if grep -q 'lark-channel-bridge' "$CCCONFIG_DIR/lib/deps-check.sh"; then
    fail "deps-check 仍引用 lark-channel-bridge"
else
    pass "deps-check 不再引用 lark-channel-bridge"
fi

# ── 5. dry-run 安全 ──
section "5. dry-run 安全"
out="$(bash "$INIT" --install --dry-run 2>&1)"
if printf '%s' "$out" | grep -q 'would:'; then
    pass "--install --dry-run 走 would:（未真装）"
else
    # 已安装时 --dry-run 也会打印 would；缺 would 说明 dry-run 未生效
    fail "--install --dry-run 未走 dry-run 路径: $(printf '%s' "$out" | head -1)"
fi

# ── 6. 引导向导 ──
section "6. 引导向导（guide）"
# 6a. 非 TTY 必须明确拒绝，不能静默挂起
out="$(timeout 15 bash "$INIT" guide </dev/null 2>&1)"; rc=$?
if [ $rc -eq 124 ]; then
    fail "guide 非 TTY 挂起（应明确拒绝）"
elif printf '%s' "$out" | grep -q '非交互终端'; then
    pass "guide 非 TTY 明确拒绝并给出指引"
else
    fail "guide 非 TTY 行为不明: $(printf '%s' "$out" | head -1)"
fi
# 6b. dispatch 里有 guide 分支
if grep -qE '^\s*guide\|wizard\|--guide\)' "$INIT"; then
    pass "dispatch 含 guide 分支"
else
    fail "dispatch 缺 guide 分支"
fi
# 6c. 装完即引导：_offer_setup_and_start 被 do_install 调用
# （do_install 体较长，取到下一个顶层函数定义为止）
if awk '/^do_install\(\)/{f=1} f&&/^[a-z_]+\(\)/{if(NR>1&&!/^do_install/)exit} f' "$INIT" \
     | grep -q '_offer_setup_and_start'; then
    pass "do_install 末尾调用引导询问"
else
    fail "do_install 未接引导询问"
fi
# 6d. NONINTERACTIVE 下不弹询问（--yes 批处理安全）
out="$(NONINTERACTIVE=true timeout 15 bash "$INIT" --install </dev/null 2>&1)"; rc=$?
if [ $rc -eq 124 ]; then
    fail "--install NONINTERACTIVE 挂起"
elif printf '%s' "$out" | grep -q '现在就配置'; then
    fail "--install NONINTERACTIVE 仍弹交互询问"
else
    pass "--install NONINTERACTIVE 不弹询问（批处理安全）"
fi
# 6e. 只能有一个 dispatch case 块（重复 case 会让所有子命令静默落进 menu）
ncase="$(grep -c '^case "\${1' "$INIT")"
if [ "$ncase" -eq 1 ]; then
    pass "dispatch case 块唯一（无重复）"
else
    fail "dispatch 有 $ncase 个 case 块（重复会导致子命令静默进 menu）"
fi
# 6f. 菜单含引导项
if grep -q '一条龙引导' "$INIT"; then
    pass "交互菜单含「一条龙引导」项"
else
    fail "交互菜单缺引导项"
fi

# ── 7. 非 TTY 不阻塞 ──
section "7. 非 TTY 不阻塞"
# sessions 在无 tty 下应走 --plain，且不挂起（用 < /dev/null 模拟）
if timeout 15 bash "$INIT" sessions </dev/null >/dev/null 2>&1; then
    pass "sessions 非 TTY 快速返回（未阻塞）"
else
    rc=$?
    if [ $rc -eq 124 ]; then fail "sessions 非 TTY 超时（阻塞）"; else pass "sessions 非 TTY 返回 rc=$rc（非阻塞）"; fi
fi
if grep -q 'has_tty' "$INIT"; then pass "sessions 有 TTY 判定分支"; else fail "sessions 无 TTY 判定"; fi

# ── 8. 二维码实时流式（防"等一分钟才出二维码"回归）──
section "8. 二维码实时流式"
# 根因：二维码走 stderr，而 out="$(bmx ... 2>&1)" 会把两股流一起缓冲进变量，
# 命令结束才打印 —— 命令正在等扫码，于是死等到链接过期。
# 断言：setup add 的调用必须走 tee（实时透传），不得用命令替换整段捕获。
if grep -qE 'bmx setup add --create-app.*\|\s*tee' "$INIT"; then
    pass "setup add 走 tee 实时透传（二维码立即可见）"
else
    fail "setup add 未走 tee —— 二维码会被缓冲到命令结束才显示"
fi
if grep -qE 'out="\$\(bmx setup add --create-app' "$INIT"; then
    fail "setup add 仍用命令替换整段捕获（二维码会被扣住）"
else
    pass "setup add 不再整段捕获"
fi
# tee 之后仍要能解析 JSON（否则建应用成功却判失败）
if grep -q '_setup_json_ok' "$INIT" && grep -qE 'out="\$\(cat ' "$INIT"; then
    pass "tee 落盘后仍解析 JSON 结果"
else
    fail "tee 后未保留 JSON 解析"
fi

# ── 9. SSH / 远端场景 ──
section "9. SSH 远端场景"
if grep -q 'SSH_CONNECTION' "$INIT"; then
    pass "引导检测 SSH 会话并给出替代路径"
else
    fail "引导未检测 SSH（远端用户会对着扫不到的二维码干等）"
fi
# botmux 二进制不提供输出链接的开关，故必须有"手动建应用"这条可用路径
if grep -qE '^\s*manual\|--manual\)' "$INIT"; then
    pass "dispatch 含 manual 分支（浏览器建应用、不走扫码）"
else
    fail "dispatch 缺 manual 分支 —— SSH 场景无可用的浏览器路径"
fi
if awk '/^do_manual\(\)/{f=1} f&&/^[a-z_]+\(\)/{if(NR>1&&!/^do_manual/)exit} f' "$INIT" \
     | grep -q '\-\-app-id'; then
    pass "do_manual 走 --app-id/--app-secret（无需扫码）"
else
    fail "do_manual 未用 app-id/app-secret 路径"
fi
# 非 TTY 下 botmux 只给二维码、不给链接 —— 这条实测结论要有注释沉淀，防后人再试
if grep -q '不提供' "$INIT" || grep -q '不输出' "$INIT"; then
    pass "代码内注明 botmux 不提供链接输出（防重复试错）"
else
    fail "未沉淀 botmux 无链接开关这一实测结论"
fi

# ── 10. CJK + Emoji 字体预检 ──
section "10. CJK + Emoji 字体预检"
# botmux 启动时要 CJK 字体渲染中文；WSL 默认没有（fc-list :lang=zh 为空），
# 它会去 GitHub 下 16MB → 受限网络 60 秒超时。预检应提前提示装 apt 包。
if grep -q 'ensure_cjk_font' "$INIT"; then
    pass "有 CJK 字体预检函数"
else
    fail "无字体预检 —— 用户会撞上 GitHub 下载超时"
fi
# 必须查 botmux 真正认的那几条路径（否则装了字体也命不中）
for p in 'opentype/noto/NotoSansCJK-Regular.ttc' 'noto-cjk/NotoSansCJK-Regular.ttc' \
         'google-noto-cjk/NotoSansCJK-Regular.ttc'; do
    if grep -q "$p" "$INIT"; then
        pass "预检查 botmux 认的路径: $p"
    else
        fail "预检漏了路径: $p"
    fi
done
# 提示必须给出 apt 方案（正统修法），而不是让人去配代理或拷 Windows 字体
if grep -q 'fonts-noto-cjk' "$INIT"; then
    pass "提示装 fonts-noto-cjk（resp. botmux 查找路径）"
else
    fail "未提示 fonts-noto-cjk"
fi
# Emoji 字体同样要查 —— 实测 botmux 对 CJK 与 Emoji 各下一次、各自 60s 超时
for p in 'truetype/noto/NotoColorEmoji.ttf' 'noto/NotoColorEmoji.ttf' \
         'google-noto-emoji/NotoColorEmoji.ttf'; do
    if grep -q "$p" "$INIT"; then
        pass "预检查 Emoji 路径: $p"
    else
        fail "预检漏了 Emoji 路径: $p"
    fi
done
if grep -q 'fonts-noto-color-emoji' "$INIT"; then
    pass "提示装 fonts-noto-color-emoji"
else
    fail "未提示 fonts-noto-color-emoji（Emoji 缺了截图里表情成方块）"
fi
# 判定必须"任一命中即可"：写成 `ls A B C || missing+=` 会在只装一个候选时误报缺
if grep -q '_any_font' "$INIT"; then
    pass "字体判定用 _any_font（任一命中即可）"
else
    fail "字体判定用 ls 多路径 —— 只装一个候选会误报缺"
fi
if grep -qE 'ls /usr/share/fonts/.*NotoSansCJK.*>\?/dev/null.*\|\|' "$INIT"; then
    fail "仍有 ls 多路径判定（任一不存在即误判）"
else
    pass "无 ls 多路径误判写法"
fi
# 实测断言：已装字体时预检必须静默通过
if bash -c "source '$REPO/lib/colors.sh'; source '$REPO/lib/interact.sh'; \
   $(sed -n '/^ensure_cjk_font()/,/^}/p' "$INIT"); ensure_cjk_font" >/dev/null 2>&1; then
    pass "已装字体时预检静默通过（实测）"
else
    fail "已装字体却仍报缺（实测失败）"
fi
# 字体缺失不应阻断启动（只慢/告警）
if grep -qE 'ensure_cjk_font \|\| true' "$INIT"; then
    pass "字体缺失不阻断启动（仅提示）"
else
    fail "字体预检可能阻断启动"
fi

# ── 12. doctor 体检（2026-10-29 故障：状态全绿但飞书零反馈）──
# 结构性教训：botmux 自带的 status/list 只反映 daemon 存活，不反映会话能否干活。
# doctor 必须覆盖「会话健康 / 队列积压 / 长连接 / cliId 可执行性」四类盲区。
section "12. doctor 体检"
DOC="$CCCONFIG_DIR/option-botmux/lib/doctor.sh"
if [ -f "$DOC" ]; then pass "doctor 模块存在"; else fail "doctor 模块缺失"; fi
if bash -n "$DOC" 2>/dev/null; then pass "doctor bash -n 语法 OK"; else fail "doctor 语法错误"; fi

# 分发器接线
# 注意：-E 下交替用 |，写成 \| 会被当字面竖线（实测踩到）
grep -qE '^ *doctor\b' "$INIT" && pass "init.sh 有 doctor 分发" || fail "init.sh 缺 doctor 分发"
grep -qE '^ *fix\b' "$INIT" && pass "init.sh 有 fix 分发" || fail "init.sh 缺 fix 分发"

# 四类盲区检查项齐备
for fn in _bmx_check_bots _bmx_check_sessions _bmx_check_queue _bmx_check_upstream _bmx_check_version_drift; do
    grep -q "^$fn()" "$DOC" && pass "体检项存在: $fn" || fail "体检项缺失: $fn"
done

# 会话健康必须查「pane 已死」与「worker D 状态」——本次故障的两个硬信号
grep -q 'pane_dead' "$DOC" && pass "检查 tmux pane 是否已死" || fail "未检查 pane 死活"
grep -qE "st.*=.*\"D\"|/proc/\\\$pid/stat" "$DOC" && pass "检查 worker 是否卡 D 状态" || fail "未检查 worker D 状态"
grep -q 'Daemon WSClient started' "$DOC" && pass "检查飞书长连接是否建立" || fail "未检查长连接"

# cliId 可执行性：本次故障的触发条件（cliId=aiden 但未装）
grep -q 'cliPathOverride' "$DOC" && pass "认 cliPathOverride 覆盖字段" || fail "未处理 cliPathOverride"
grep -q 'cliRuntime' "$DOC" && pass "cliRuntime 跳过而非误报" || fail "未处理 cliRuntime"
grep -q '需要命令' "$DOC" && pass "报告 cliId 指向未安装 CLI" || fail "未报告 cliId 未装"

# 版本漂移：本脚本 cliId 表 vs 已装 botmux（官方加适配器时能发现）
grep -q '_bmx_check_version_drift' "$DOC" && pass "有 cliId 表漂移检测" || fail "缺漂移检测"
grep -q 'dsh' "$DOC" && pass "cliId 表含 dsh（DeepSeek Harness）" || fail "cliId 表缺 dsh"

# 计数器跨子 shell 陷阱：while 必须走 < <(...) 而非管道，否则 ERR/WARN 计数丢失
if grep -qE '\| while .*read' "$DOC"; then
    fail "用管道 while 读（计数会丢在子 shell 里）"
else
    pass "无管道 while（计数能回到父 shell）"
fi

# set -e 安全：检查函数末尾必须 return 0，否则 [ -n ] && ... 会静默中止整个脚本
for fn in _bmx_check_bots _bmx_check_sessions _bmx_check_queue _bmx_check_upstream; do
    if awk "/^$fn\(\)/{f=1} f&&/^}/{print;exit} f" "$DOC" | grep -q 'return 0'; then
        pass "$fn 末尾 return 0（set -e 安全）"
    else
        fail "$fn 缺末尾 return 0（set -e 下会静默中止）"
    fi
done

# 实测：doctor 可跑且输出体检标题（不依赖 botmux 是否装好）
if command -v botmux >/dev/null 2>&1 || [ -x "$HOME/.local/bin/botmux" ]; then
    dout="$(PATH="$HOME/.local/bin:$PATH" bash "$INIT" doctor 2>&1 || true)"
    printf '%s' "$dout" | grep -q 'botmux 体检' && pass "doctor 实跑输出体检标题" || fail "doctor 无输出"
    printf '%s' "$dout" | grep -q '会话健康' && pass "doctor 实跑含会话健康段" || fail "doctor 缺会话健康段"
fi

# fix 非交互不得阻塞、不得擅改用户配置
if grep -q 'NONINTERACTIVE' "$DOC"; then pass "fix 尊重 NONINTERACTIVE（非交互不阻塞）"; else fail "fix 缺 NONINTERACTIVE 保护"; fi

# 接线进 maintain 生态
grep -q 'do_botmux_doctor' "$CCCONFIG_DIR/maintain.sh" && pass "maintain.sh 有 do_botmux_doctor" || fail "maintain.sh 缺 do_botmux_doctor"
grep -q 'botmux 体检' "$CCCONFIG_DIR/lib/menu-data-maintain.sh" && pass "菜单含 botmux 体检项" || fail "菜单缺体检项"

# ── 13. 底层 CLI 依赖（botmux 只桥接、不装 CLI）──
# 装了 botmux 但没装底层 CLI = 静默失败：daemon 全绿、飞书零反馈。
# 修法必须区分「公开可装」与「仅内部渠道」—— 给内部渠道发 npm install 是错的。
section "13. 底层 CLI 依赖"
grep -q '_bmx_cli_install_pkg' "$DOC" && pass "有 CLI 安装包映射表" || fail "缺 CLI 安装包映射"
grep -q 'npm install -g @anthropic-ai/claude-code' "$INIT" && pass "提示装默认 claude" || fail "未提示装 claude"
grep -q '_bmx_hint_base_cli' "$INIT" && pass "安装后提示底层 CLI" || fail "安装后无 CLI 提示"
# aiden/traex/coco 是内部渠道，绝不能给出装不上的 npm 包名
grep -q '__INTERNAL__' "$DOC" && pass "内部渠道适配器单列（不给假包名）" || fail "未区分内部渠道"
grep -q '仅内部渠道发行' "$DOC" && pass "内部渠道给明确说明" || fail "内部渠道无说明"
# 已装 claude 时提示必须静默（否则每次安装都刷一堆无用警告）
if grep -A3 'command -v claude' "$INIT" | grep -q 'return 0'; then
    pass "claude 已装则提示静默"
else
    fail "claude 已装仍会刷提示"
fi
# fix 里装 CLI 必须先确认、且尊重 NONINTERACTIVE
if grep -q 'NONINTERACTIVE.*true.*has_tty' "$DOC" || grep -qE 'NONINTERACTIVE:-false.*!=.*true' "$DOC"; then
    pass "fix 装 CLI 尊重 NONINTERACTIVE"
else
    fail "fix 装 CLI 未防非交互"
fi
# 实测：内部渠道适配器不产出可执行 npm 命令
_tmppkg="$(bash -c '
source "'"$CCCONFIG_DIR"'/lib/colors.sh" 2>/dev/null
source "'"$CCCONFIG_DIR"'/option-botmux/lib/doctor.sh" 2>/dev/null
for c in aiden traex coco; do _bmx_cli_install_pkg "$c"; echo; done
' 2>/dev/null | tr "\n" " ")"
case "$_tmppkg" in
    *__INTERNAL__*) pass "aiden/traex/coco → __INTERNAL__（不发假包名）" ;;
    *) fail "内部渠道适配器映射错误: $_tmppkg" ;;
esac
_tmppkg2="$(bash -c '
source "'"$CCCONFIG_DIR"'/lib/colors.sh" 2>/dev/null
source "'"$CCCONFIG_DIR"'/option-botmux/lib/doctor.sh" 2>/dev/null
_bmx_cli_install_pkg claude-code
' 2>/dev/null)"
[ "$_tmppkg2" = "@anthropic-ai/claude-code" ] && pass "claude-code → @anthropic-ai/claude-code" || fail "claude-code 映射错: $_tmppkg2"

echo ""
echo "────────────────────────────"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "────────────────────────────"
[ "$FAIL" -eq 0 ]