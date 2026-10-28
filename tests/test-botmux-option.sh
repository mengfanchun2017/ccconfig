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

# ── 10. CJK 字体预检 ──
section "10. CJK 字体预检"
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
# 字体缺失不应阻断启动（只慢/告警）
if grep -qE 'ensure_cjk_font \|\| true' "$INIT"; then
    pass "字体缺失不阻断启动（仅提示）"
else
    fail "字体预检可能阻断启动"
fi

echo ""
echo "────────────────────────────"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "────────────────────────────"
[ "$FAIL" -eq 0 ]