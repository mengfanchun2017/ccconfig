#!/bin/bash
# ccconfig/option-larkcli/init.sh — 飞书 lark-cli 初始化（可选组件）
#
# lark-cli: 创建飞书文档/日历/任务（用户 OAuth）
# 配置源: ../conf/feishu.json（单一真相源）
#
# 用法：
#   bash ccconfig/option-larkcli/init.sh           # 配置所有启用的 lark-cli 账号
#   bash ccconfig/option-larkcli/init.sh --status  # 状态检查
#   bash ccconfig/option-larkcli/init.sh --list    # 列出可用账号
#
# 多账号切换：
#   bash ccconfig/option-larkcli/lark-switch.sh <name>
#   bash ccconfig/option-larkcli/lark-switch.sh ailab -p   # 持久化

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_DIR/lib/dry-run.sh"
source "$CCCONFIG_DIR/lib/colors.sh"
source "$CCCONFIG_DIR/lib/path-helper.sh"
FEISHU_CONF="$(resolve_conf feishu.json)" || exit 1
export PATH="$(find_node_bin):${HOME}/.local/bin:$PATH"
export LARK_CLI_NO_PROXY=1


# ========== JSON 读取 ==========
get_apps() {
    python3 - "$FEISHU_CONF" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
for app in data.get('apps', []):
    print(json.dumps(app))
PYEOF
}

# ========== lark-cli 安装 ==========
# 探测真实 npm 包路径（不依赖 PATH），从 package.json bin 字段读真实入口
_install_lark_cli_symlink() {
    local pkg_dir="$1"
    local pkg_json="$pkg_dir/package.json"
    [ -f "$pkg_json" ] || return 1
    local bin_target
    bin_target=$(python3 -c "import json; d=json.load(open('$pkg_json')); b=d.get('bin', {}); print(b.get('lark-cli', '') if isinstance(b, dict) else b)" 2>/dev/null)
    [ -n "$bin_target" ] || return 1
    mkdir -p "$HOME/.local/bin"
    ln -sf "$pkg_dir/$bin_target" "$HOME/.local/bin/lark-cli"
    return 0
}

install_lark_cli() {
    echo -e "${CYAN}── lark-cli ──${NC}"
    local npm_root pkg_dir
    npm_root=$(npm root -g 2>/dev/null || echo "$(dirname "$(find_node_bin)")/lib/node_modules")
    pkg_dir="$npm_root/@larksuite/cli"

    if [ -d "$pkg_dir" ]; then
        if _install_lark_cli_symlink "$pkg_dir"; then
            good "  ✓ 已安装（symlink 已建）"
        else
            good "  ✓ 已安装"
        fi
        return 0
    fi

    echo -n "  npm install @larksuite/cli ... "
    if npm install -g @larksuite/cli 2>&1 && good "✅"; then
        _install_lark_cli_symlink "$npm_root/@larksuite/cli" || warn "    ⚠ symlink 未建（手动: ln -s $npm_root/@larksuite/cli/scripts/run.js ~/.local/bin/lark-cli）"
    else
        bad "❌"
        return 1
    fi
}

setup_lark_cli_account() {
    local name="$1" brand="$2" app_id="$3" app_secret="$4" config_dir="$5"
    config_dir="${config_dir/#\~/$HOME}"
    mkdir -p "$config_dir"
    export LARKSUITE_CLI_CONFIG_DIR="$config_dir"

    local cf="${config_dir}/config.json"
    if [ -f "$cf" ]; then
        good "  ✓ ${name}"
        # 检测 auth，未授权则自动拉起
        if ! lark-cli auth status 2>/dev/null | grep -q "tokenStatus.*valid"; then
            warn "    ○ 待授权，自动发起 OAuth 授权..."
            _do_auth_login "$config_dir" "$name"
        fi
        return 0
    fi
    echo -n "  → ${name} ... "
    echo "$app_secret" | lark-cli config init --app-id "$app_id" --app-secret-stdin --brand "$brand" 2>&1 && good "✅" || bad "❌"
    # 配置完成后检测 auth
    if [ -f "$cf" ]; then
        if ! lark-cli auth status 2>/dev/null | grep -q "tokenStatus.*valid"; then
            echo ""
            warn "  ○ 配置完成，需 OAuth 授权"
            _do_auth_login "$config_dir" "$name"
        fi
    fi
}

# ── 自动 OAuth 授权 ──
_do_auth_login() {
    local config_dir="$1" name="$2"
    export LARKSUITE_CLI_CONFIG_DIR="$config_dir"

    # 请求 device code（--domain all 一次授权所有 scope）
    local auth_out
    auth_out=$(lark-cli auth login --domain all --no-wait --json 2>&1 | grep -v '^\[lark-cli\]')
    local device_code url
    device_code=$(echo "$auth_out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('device_code',''))" 2>/dev/null || echo "")
    url=$(echo "$auth_out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('verification_url',''))" 2>/dev/null || echo "")

    if [ -z "$device_code" ] || [ -z "$url" ]; then
        warn "    授权请求失败，稍后可手动执行:"
        warn "    LARKSUITE_CLI_CONFIG_DIR=$config_dir lark-cli auth login --domain all"
        return 1
    fi

    echo ""
    info "    授权链接:"
    echo "    $url"
    echo ""
    info "    扫码后自动继续..."

    lark-cli auth login --device-code "$device_code" 2>&1 | grep -v '^\[lark-cli\]' | grep -v 'AI agent' | grep -v '此命令最长' | grep -v '不要在同一轮' | grep -v '必须生成二维码' | grep -v '**MUST' | grep -v '**CRITICAL' | grep -v '**Display' | grep -v '**URL Output' | grep -v 'For agent' | grep -v '等待用户' | grep -v '必须调用' | grep -v '优先生成' | grep -v '生成后必须' | grep -v '仅生成文件'

    if lark-cli auth status 2>/dev/null | grep -q "tokenStatus.*valid"; then
        good "  ✅ ${name} OAuth 授权成功"
    else
        warn "  ○ 授权未完成，稍后可手动执行:"
        warn "    LARKSUITE_CLI_CONFIG_DIR=$config_dir lark-cli auth login --domain all"
    fi
}

run_lark_cli() {
    install_lark_cli || return 1
    echo ""

    # 预检：检查是否有占位符 App ID/Secret
    local placeholder_apps
    placeholder_apps=$(python3 - "$FEISHU_CONF" << 'PYEOF' 2>/dev/null
import json, sys
PLACEHOLDER = ['请填入', '请到', '请替换', 'your key', 'your_key', 'placeholder', 'changeme', '<your-', 'your-app-name']
def is_ph(val):
    if not val or not isinstance(val, str): return True
    for p in PLACEHOLDER:
        if p.lower() in val.lower(): return True
    return False
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
apps = data.get('apps', [])
bad = [a.get('name','?') for a in apps if a.get('larkCli',{}).get('enabled') and (is_ph(a.get('appId','')) or is_ph(a.get('appSecret','')))]
if bad:
    print('\n'.join(bad))
PYEOF
    )
    if [ -n "$placeholder_apps" ]; then
        warn "以下账号的 App ID/Secret 仍为占位符，需先填写:"
        echo "$placeholder_apps" | while read -r name; do
            echo -e "    ${YELLOW}→${NC} $name"
        done
        echo ""
        info "编辑 feishu.json 填入真实值: vim $FEISHU_CONF"
        info "获取地址: https://open.feishu.cn/app"
        return 1
    fi

    local apps=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        local lc_enabled=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('larkCli',{}).get('enabled',False))" 2>/dev/null)
        [ "$lc_enabled" = "True" ] && apps+=("$line")
    done < <(get_apps)

    if [ ${#apps[@]} -eq 0 ]; then
        info "  无启用的 lark-cli 账号"
        return 0
    fi

    echo -e "${CYAN}配置 lark-cli 账号 (${#apps[@]} 个):${NC}"
    local first_name=""
    for line in "${apps[@]}"; do
        local name=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        local brand=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('brand','feishu'))" 2>/dev/null)
        local app_id=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['appId'])" 2>/dev/null)
        local app_secret=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['appSecret'])" 2>/dev/null)
        local lc=$(echo "$line" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('larkCli',{})))" 2>/dev/null)
        local config_dir=$(echo "$lc" | python3 -c "import json,sys; print(json.load(sys.stdin).get('configDir','~/.lark-cli'))" 2>/dev/null || echo "~/.lark-cli")
        setup_lark_cli_account "$name" "$brand" "$app_id" "$app_secret" "$config_dir"
        [ -z "$first_name" ] && first_name="$name"
    done

    # 激活第一个账号（写入 marker 文件，status.sh 可检测）
    if [ -n "$first_name" ]; then
        echo ""
        echo -e "${CYAN}激活默认账号: ${GREEN}${first_name}${NC}"
        bash "$SCRIPT_DIR/lark-switch.sh" "$first_name"
        echo -e "${GRAY}后续切换: bash ccconfig/option-larkcli/lark-switch.sh <name>${NC}"
    fi
}

list_apps() {
    echo -e "${CYAN}可用飞书应用（larkCli.enabled）${NC}\n"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        echo "$line" | python3 -c "
import json,sys
a=json.load(sys.stdin)
lc=a.get('larkCli',{})
if lc.get('enabled'):
    print(f'  {a[\"name\"]:12s}  {a.get(\"description\",\"\")}')
    print(f'  {\"\":12s}  {a[\"appId\"][:22]}...')
" 2>/dev/null
    done < <(get_apps)
    echo ""
}

show_status() {
    # 第一行：无 ANSI 状态行（供 init-option.sh 解析）
    if ! command -v lark-cli &>/dev/null; then
        echo "MISSING lark-cli 未安装"
        return 0
    fi
    local ver=$(lark-cli --version 2>/dev/null | head -1 | sed 's/^[^0-9]*//')
    local cf="$HOME/.lark-cli-account"
    local acct="-"
    [ -f "$cf" ] && acct=$(grep '^name=' "$cf" | cut -d'=' -f2)

    # 检查 feishu.json 是否有占位符 key
    local has_ph="false"
    if [ -f "$FEISHU_CONF" ]; then
        has_ph=$(python3 -c "
import json, sys
PLACEHOLDER = ['请填入','请到','请替换','your key','your_key','placeholder','changeme','<your-','your-app-name']
def is_ph(v):
    if not v or not isinstance(v, str): return True
    return any(p in v.lower() for p in PLACEHOLDER)
with open('$FEISHU_CONF') as f: d = json.load(f)
print('true' if any(is_ph(a.get('appId','')) or is_ph(a.get('appSecret','')) for a in d.get('apps',[]) if a.get('larkCli',{}).get('enabled')) else 'false')
" 2>/dev/null || echo "false")
    fi

    if [ "$has_ph" = "true" ]; then
        echo "WARN lark-cli v${ver:-?} (账号: ${acct}) — feishu.json 含占位符"
    else
        echo "OK lark-cli v${ver:-?} (账号: ${acct})"
    fi

    # 后续行：彩色详情（--status 直接展示用）
    echo ""
    echo -e "${CYAN}── lark-cli 详情 ──${NC}"
    echo -n "  二进制 ... "
    if command -v lark-cli &>/dev/null; then
        echo -e "${GREEN}✅${NC} $(lark-cli --version 2>/dev/null | head -1)"
    else
        echo -e "${RED}❌${NC} 未安装"
    fi
    if [ -f "$cf" ]; then
        local name=$(grep '^name=' "$cf" | cut -d'=' -f2)
        echo -e "  当前账号 ... ${GREEN}${name}${NC}"
    fi
    if [ "$has_ph" = "true" ]; then
        echo -e "  ${YELLOW}!${NC} feishu.json 仍含占位符 → 编辑 ${GRAY}$FEISHU_CONF${NC}"
    fi
}

# ========== 主程序 ==========
case "${1:-}" in
    --list|-ls)
        list_apps
        ;;
    --status|-s)
        show_status
        ;;
    --help|-h)
        echo "用法: $0 [--list|--status|--auth-login <name>]"
        echo ""
        echo "  (无参数)    配置所有启用的 lark-cli 账号"
        echo "  --list      列出可用账号"
        echo "  --status    状态检查"
        echo "  --auth-login <name>  手动触发 OAuth 授权"
        ;;
    --auth-login)
        _cl_auth_name="${2:-}"
        if [ -z "$_cl_auth_name" ]; then
            bad "用法: $0 --auth-login <name>"
            exit 1
        fi
        _cl_conf_line=$(get_apps | while IFS= read -r line; do
            n=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
            [ "$n" = "$_cl_auth_name" ] && echo "$line"
        done | head -1)
        if [ -z "$_cl_conf_line" ]; then
            bad "未找到 app: $_cl_auth_name"
            exit 1
        fi
        _cl_config_dir=$(echo "$_cl_conf_line" | python3 -c "import json,sys; d=json.load(sys.stdin).get('larkCli',{}); print(d.get('configDir','~/.lark-cli'))" 2>/dev/null || echo "~/.lark-cli")
        _cl_config_dir="${_cl_config_dir/#\~/$HOME}"
        _do_auth_login "$_cl_config_dir" "$_cl_auth_name"
        ;;
    "")
        run_lark_cli
        echo ""
        good "✅ lark-cli 配置完成"
        echo ""
        ;;
    *)
        bad "❌ 未知参数: $1"
        exit 1
        ;;
esac