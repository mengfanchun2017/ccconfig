#!/bin/bash
# sync-plugin-env.sh — 把配置解析的 boot stub 分发到所有 plugin。
#
# 背景：`/plugin install` 只复制 plugin **自己**的目录，故跨 plugin 共享的实现
# （ffeishu/references/plugin_env.sh + config_env.py）别的 plugin 装完后拿不到
# —— 实测 27 个 plugin 全装一遍，只有 ffeishu 有解析器，其余 26 个无。
#
# 解法：每个 plugin 带一份 ~40 行的 boot stub 去找唯一实现（实现仍只有一处）。
# 本脚本负责把 stub 从源（ffeishu）复制到其余 26 个 plugin，并做一致性校验。
#
# 用法：
#   bash ccconfig/bin/sync-plugin-env.sh           # 分发（幂等，只写有差异的）
#   bash ccconfig/bin/sync-plugin-env.sh --check   # 只校验，有漂移则非零退出（CI 用）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL_REPO="${SKILL_SRC:-$HOME/git/skill}"
PLUGINS="$SKILL_REPO/plugins"
SRC_PLUGIN="ffeishu"

source "$CCCONFIG_ROOT/lib/colors.sh" 2>/dev/null || {
    ok() { echo "✅ $*"; }; warn() { echo "⚠️  $*"; }
    info() { echo "ℹ️  $*"; }; err() { echo "❌ $*"; }
    section() { echo "== $* =="; }
    GREEN=''; RED=''; YELLOW=''; CYAN=''; NC='';
}

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

STUBS=("_skillconf_boot.sh" "_skillconf_boot.py")
# 单一实现本体：只在 ffeishu 维护，**不**分发（分发它会退化成 N 份实现）
IMPL=("plugin_env.sh" "config_env.py")

SRC_DIR="$PLUGINS/$SRC_PLUGIN/references"
[[ -d "$SRC_DIR" ]] || { err "源目录不存在: $SRC_DIR"; exit 1; }
[[ -d "$PLUGINS" ]] || { err "plugins 目录不存在: $PLUGINS"; exit 1; }

for f in "${STUBS[@]}" "${IMPL[@]}"; do
    [[ -f "$SRC_DIR/$f" ]] || { err "源文件缺失: $SRC_DIR/$f"; exit 1; }
done

section "分发 boot stub（源: $SRC_PLUGIN/references）"

drift=0; copied=0; uptodate=0
for pdir in "$PLUGINS"/*/; do
    pname="$(basename "${pdir%/}")"
    [[ "$pname" == "$SRC_PLUGIN" ]] && continue
    dst="$pdir/references"
    # 没有 references/ 的要建出来 —— boot stub 必须随 plugin 分发，否则该 plugin
    # 装到 cache 后无处解析配置（实测 26/27 都缺实现，正是这个原因）
    if [[ ! -d "$dst" ]]; then
        if [[ $CHECK_ONLY -eq 1 ]]; then
            err "  $pname: 无 references/（跑 sync-plugin-env.sh 修）"
            drift=$((drift + 1)); continue
        fi
        mkdir -p "$dst"
    fi

    for f in "${STUBS[@]}"; do
        if [[ -f "$dst/$f" ]] && cmp -s "$SRC_DIR/$f" "$dst/$f"; then
            uptodate=$((uptodate + 1)); continue
        fi
        drift=$((drift + 1))
        if [[ $CHECK_ONLY -eq 1 ]]; then
            if [[ -f "$dst/$f" ]]; then
                err "  $pname/$f 与源不一致"
            else
                err "  $pname/$f 缺失"
            fi
        else
            cp "$SRC_DIR/$f" "$dst/$f"
            copied=$((copied + 1))
        fi
    done

    # 反向断言：实现本体不得散落到别的 plugin（否则又变成 N 份实现）
    for f in "${IMPL[@]}"; do
        if [[ -f "$dst/$f" ]] && ! cmp -s "$SRC_DIR/$f" "$dst/$f"; then
            warn "  $pname 有实现副本且与源不一致: $f（应删掉，只留 boot stub）"
            drift=$((drift + 1))
        fi
    done
done

section "结果"
if [[ $CHECK_ONLY -eq 1 ]]; then
    if [[ $drift -eq 0 ]]; then ok "全部一致（$uptodate 项）"; else
        err "发现 $drift 处漂移"; exit 1; fi
else
    ok "复制 $copied 项，已一致 $uptodate 项"
fi

# ── 校验每个 plugin 都能通过 stub 找到实现 ──
section "连通性校验"
fail=0
for pdir in "$PLUGINS"/*/; do
    pname="$(basename "${pdir%/}")"
    ref="$pdir/references"
    [[ -f "$ref/_skillconf_boot.sh" ]] || continue
    out=$(env -u CCPRIVATE_HOME -u CCPRIVATE_DIR bash -c "
        source '$ref/_skillconf_boot.sh' 2>/dev/null
        if declare -F skillconf_plugin_name >/dev/null; then
            SKILLCONF_PLUGIN_NAME=$pname skillconf_plugin_name
        fi" 2>/dev/null || true)
    if [[ "$out" != "$pname" ]]; then
        err "  $pname: stub 未找到实现"; fail=$((fail + 1))
    fi
done
[[ $fail -eq 0 ]] && ok "全部 plugin 的 stub 都能找到实现" || { err "$fail 个失败"; exit 1; }