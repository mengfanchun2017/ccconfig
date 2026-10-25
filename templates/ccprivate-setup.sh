#!/bin/bash
# ccprivate — 私有配置注入脚本
#
# ⚠️ 本文件是 ccprivate/setup.sh 的【唯一真相源】。
#    init-bootstrap.sh（新机引导）和 lib/ccprivate-upgrade.sh（老机升级）
#    都从这里 cp，不再各自内嵌副本 —— 三份副本漂移曾导致
#    "setup.sh 建本机文件、upgrade 建 symlink" 互相打架。
#
# 职责（v3）：
#   1. 用户级文件：共享的 symlink → ccprivate；本机的从 .example cp 一次
#   2. 触发 ccconfig 公开部分链接（agents/rules/commands/skills）
#   (ccconfig 脚本通过 resolve_conf() 直接读 ccprivate/conf/，无需中间目录)
#
# 分层（详见 ADR-0032）：
#   共享同步   link/CLAUDE.md、rules/、memory/
#   本机独立   ~/.claude/settings.json（LLM 选择）、.config.json（会话配置）、
#              .claudeignore（context 策略）—— symlink 会跨机覆盖，必须本机维护
#
# 用法：
#   bash ~/git/ccprivate/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="${CCCONFIG_DIR:-$HOME/git/ccconfig}"
CLAUDE_DIR="$HOME/.claude"

# 从 ccconfig 借 colors.sh；缺失时用本地 ANSI 兜底
source "$CCCONFIG_DIR/lib/colors.sh" 2>/dev/null || {
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    YELLOW='\033[0;33m'
    NC='\033[0m'

    section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
    info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
    ok()      { echo -e "${GREEN}✅ $1${NC}"; }
    warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
}

# 初始化代次水位：记录"这台机的本机配置文件是用哪一代模板生成的"。
# settings.json/.config.json/.claudeignore 是每机独立文件，模板更新后没有任何机制
# 知道某台机落后了 —— status 只查基线键存在性，不查内容过期。有这个标记才能告警。
mark_init_version() {
    local tdir="$CCCONFIG_DIR/templates"
    # version= 只是人读日志标签：取当前 HEAD 短 sha，一眼看出"这台机上次对齐的是哪次提交"。
    # 此前取 versions.json 的 self.version —— 那个字段已删（仓库无 CalVer tag，也没人读它）。
    # 真正承重的判定是 template_hash（下面的 sha256），version 不参与任何比较。
    local ver="unknown" h=""
    if [ -d "$CCCONFIG_DIR/.git" ]; then
        ver=$(git -C "$CCCONFIG_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
    fi
    if command -v sha256sum >/dev/null 2>&1 && [ -d "$tdir" ]; then
        h=$(cat "$tdir"/settings.json.example "$tdir"/.config.json.example 2>/dev/null | sha256sum | cut -c1-16)
    fi
    printf 'version=%s\napplied_at=%s\ntemplate_hash=%s\n' \
        "$ver" "$(date --iso-8601=seconds 2>/dev/null || date)" "$h" \
        > "$CLAUDE_DIR/.ccconfig-init" 2>/dev/null || true
}

setup_link() {
    local link="$1"
    local target="$2"
    local label="$3"
    mkdir -p "$(dirname "$link")"
    # 必须 [ -e "$link" ] 才算健康：readlink -f 对死链也返回规范路径字符串（非空，
    # 退出码 0），只看字符串相等会把死链判成"已链接" → 永远不修，症状是
    # maintain 反复报 memory 断链却怎么修都不好
    if [ -L "$link" ] && [ -e "$link" ]; then
        local existing expected
        existing=$(readlink -f "$link" 2>/dev/null || true)
        expected=$(readlink -f "$target" 2>/dev/null || true)
        if [ "$existing" = "$expected" ] && [ -n "$existing" ]; then
            info "$label: 已链接"
            return 0
        fi
        rm -f "$link"
    elif [ -L "$link" ]; then
        warn "$label: 死链（目标不存在），重建"
        rm -f "$link"
    elif [ -e "$link" ]; then
        rm -rf "$link"
    fi
    # 目标不存在时不建链：建出的死链会让问题更隐蔽（下次运行还会被判"已链接"）
    if [ ! -e "$target" ]; then
        warn "$label: 目标不存在，跳过（$target）"
        return 0
    fi
    ln -s "$target" "$link"
    ok "$label"
}

# ============================================================
# 1. 用户级 ~/ 链接（直连 ccprivate/link/）
# ============================================================
section "用户级链接"
setup_link "$HOME/CLAUDE.md"           "$SCRIPT_DIR/link/CLAUDE.md"     "~/CLAUDE.md"
setup_link "$HOME/.lark-default-account" "$SCRIPT_DIR/link/.lark-default-account" ".lark-default-account → ccprivate"
# should-compact.md 已废弃（ccconfig/commands/ 整个目录已删），不要再建它的链接

# 以下三文件是本机状态（LLM 选择 / 会话配置 / context 策略），symlink 会跨机覆盖
# 首次 setup 时从 .example 模板 cp；已存在则跳过，各机独立维护，永不回写 ccprivate
install_user_file() {
    local dst="$1" src_template="$2" desc="$3"
    mkdir -p "$(dirname "$dst")"
    if [ ! -f "$src_template" ]; then
        warn "$desc: 模板缺失 $src_template，跳过"
    elif [ -L "$dst" ]; then
        rm -f "$dst"
        cp "$src_template" "$dst"
        ok "$desc: symlink 转本机文件"
    elif [ ! -f "$dst" ]; then
        cp "$src_template" "$dst"
        ok "$desc: 已从模板创建"
    else
        # 已存在 ≠ 完整：init-ubuntu.sh 的 setup_hook 会先建出只有 hooks 的
        # settings.json、init-llm.sh 会先建出只有 env/model 的，都比本脚本早。
        # 旧逻辑一律 "已存在，跳过" → permissions/statusLine 永远不写入，
        # 新机装完白名单全缺而 status 仍报绿（实测复现）。
        # 只补模板里缺的【顶层键】，已有键一律不覆盖（尊重用户自主裁剪）。
        local added=""
        added=$(TPL="$src_template" DST="$dst" python3 - << 'PYEOF'
import json, os
tpl, dst = os.environ["TPL"], os.environ["DST"]
try:
    with open(tpl) as f: t = json.load(f)
    with open(dst) as f: d = json.load(f)
except Exception:
    raise SystemExit(0)          # 非 JSON（如 .claudeignore）→ 不适用，视为已就绪
if not isinstance(t, dict) or not isinstance(d, dict):
    raise SystemExit(0)

# 只比顶层键不够：settings.json 里 permissions 顶层键常在（哪怕是 {} 空壳），
# 而 permissions.allow 26 条规则缺失也判"已就绪" → 换机后白名单静默没生效。
# 因此对 dict 值下钻一层，对 allow/deny/ask 这类列表值取并集。
added = []
def fill(dst_d, tpl_d, prefix=""):
    for k, v in tpl_d.items():
        if k not in dst_d:
            dst_d[k] = v
            added.append(prefix + k)
            continue
        if isinstance(v, dict) and isinstance(dst_d.get(k), dict):
            fill(dst_d[k], v, prefix + k + ".")
        elif isinstance(v, list) and isinstance(dst_d.get(k), list) and k in ("allow", "deny", "ask"):
            # 权限列表取并集：补上模板里有、本机没有的条目（不删本机已有）
            extra = [x for x in v if x not in dst_d[k]]
            if extra:
                dst_d[k].extend(extra)
                added.append(prefix + k + f"(+{len(extra)})")

fill(d, t)
if not added:
    raise SystemExit(0)
with open(dst, "w") as f:
    json.dump(d, f, indent=4, ensure_ascii=False)
    f.write("\n")
print(" ".join(added))
PYEOF
        ) || added=""
        if [ -n "$added" ]; then
            warn "$desc: 已存在，补齐缺失键（$added）"
        else
            info "$desc: 已存在，跳过"
        fi
    fi
}

install_user_file "$CLAUDE_DIR/.config.json"  "$SCRIPT_DIR/link/.config.json.example"  ".config.json"
install_user_file "$CLAUDE_DIR/.claudeignore" "$SCRIPT_DIR/link/.claudeignore.example" ".claudeignore"
install_user_file "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/link/settings.json.example" "settings.json"

# ============================================================
# 2. ccprivate 私有配置 — 由 resolve_conf() 直接读 ccprivate/conf/
#    无需中间目录。ccconfig/ 零 symlink。
# ============================================================
info "ccconfig 私有配置: ccconfig 脚本通过 resolve_conf() 直接读 ccprivate/conf/"

# 私有 skill 实体目录（不开源，跨机器同步）
mkdir -p "$SCRIPT_DIR/skill-local"
[ -f "$SCRIPT_DIR/skill-local/.gitkeep" ] || touch "$SCRIPT_DIR/skill-local/.gitkeep"
info "私有 skill 目录: $SCRIPT_DIR/skill-local/（用户自建 skill 存放处）"

# ============================================================
# 3. 用户级 memory symlink（动态计算 project ID，不硬编码用户名）
# ============================================================
section "用户级记忆"
_cconfig_id="$(echo "$HOME/git/ccconfig" | tr '/' '-')"
# git 不跟踪空目录：新账号的 ccprivate 里可能没有 link/memory/，
# 不先建目录就会链接到一个不存在的目标（死链）
mkdir -p "$SCRIPT_DIR/link/memory"
setup_link "$CLAUDE_DIR/projects/$_cconfig_id/memory" "$SCRIPT_DIR/link/memory" "memory → ccprivate/link/memory"
unset _cconfig_id

# ============================================================
# 3b. 项目级记忆（公开项目走 ccprivate 集中存储，不能进项目仓库）
# 私有项目直接在项目内 .claude/memory/ 即可，无需在这里登记
# ============================================================
if [ -d "$SCRIPT_DIR/link/memory-projects" ]; then
    for _mp_dir in "$SCRIPT_DIR/link/memory-projects/"*/; do
        [ -d "$_mp_dir" ] || continue
        _mp_name=$(basename "$_mp_dir")
        _mp_id="$(echo "$HOME/git/$_mp_name" | tr '/' '-')"
        setup_link "$CLAUDE_DIR/projects/$_mp_id/memory" "$_mp_dir" "memory-projects/$_mp_name → ccprivate"
    done
    unset _mp_dir _mp_name _mp_id
fi

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
# ~/.claude/workflows 是真实目录，每个 workflow .js 单独 symlink → ccprivate
# Claude 拒绝通过 symlink 目录保存新 workflow，且不递归扫描子目录
if [ -d "$SCRIPT_DIR/workflows" ]; then
    if [ -L "$CLAUDE_DIR/workflows" ]; then
        rm -f "$CLAUDE_DIR/workflows"
    fi
    mkdir -p "$CLAUDE_DIR/workflows"
    for _wf_dir in "$SCRIPT_DIR/workflows/"*/; do
        [ -d "$_wf_dir" ] || continue
        _wf_name=$(basename "$_wf_dir")
        _wf_dir="${_wf_dir%/}"
        _wf_js="$_wf_dir/workflow.js"
        if [ -f "$_wf_js" ]; then
            # workflow.js 用 HERE=$HOME/.claude/workflows/<name> 读同目录下的
            # paths.sh / translate-config*.sh，故目录 symlink 也必须建，缺了运行时报错
            setup_link "$CLAUDE_DIR/workflows/${_wf_name}" "$_wf_dir" "workflows/${_wf_name} → ccprivate"
            setup_link "$CLAUDE_DIR/workflows/${_wf_name}.js" "$_wf_js" "workflows/${_wf_name}.js → ccprivate"
        fi
    done
    unset _wf_dir _wf_name _wf_js
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

# 注册私有 skill 到 ~/.claude/skills/
if [ -x "$CCCONFIG_DIR/lib/init-skill.sh" ] && [ -d "$SCRIPT_DIR/skill-local" ] && ls "$SCRIPT_DIR/skill-local"/*/ &>/dev/null; then
    info "私有 skill → ~/.claude/skills/"
    bash "$CCCONFIG_DIR/lib/init-skill.sh" link-only
fi

# 记录本次初始化代次（供 status 判断"这台机落后了几代模板"）
mark_init_version

echo ""
ok "ccprivate setup 完成"
