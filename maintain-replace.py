import re

with open('maintain.sh', 'r') as f:
    content = f.read()

replacements = [
    # show_menu: main menu read-p (line ~190-192)
    ('read -p "选择 [0-17]: " c\n    c=$(menu_num "$c")',
     'c=$(menu_select "ccconfig 运维中心" \\
        "1) 状态检查" "2) Monitor 管理" "3) 自我更新" \\
        "4) Git 同步" "5) 组件升级" "6) 依赖检查" \\
        "7) 一键修复" "8) 模板同步" "9) ccprivate 升级" \\
        "10) Bill & Token" "11) MCP 管理" "12) llmswitch" \\
        "13) 飞书管理" "14) 回归测试" "15) GitHub PAT" \\
        "16) LLM 切换" "17) getnote 账号" "0) 退出")\n    c="${c:0:1}"'),

    # submenu_monitor (line ~297-310)
    ('read -p "选择 [0-6]: " c\n    c=$(menu_num "$c")\n    case "$c" in\n        1) bash "$LIB_DIR/monitor.sh" start ;,\n        2) bash "$LIB_DIR/monitor.sh" stop ;,\n        3) bash "$LIB_DIR/monitor.sh" status ;,\n        4) bash "$LIB_DIR/monitor.sh" tail ;,\n        5) bash "$LIB_DIR/monitor.sh" monitor ;,\n        6) fix_monitor ;,\n        0) return ;,
        *) submenu_monitor ;,
    esac',
     'sub_menu=$(menu_select "Monitor 管理" \\
        "1) 启动" "2) 停止" "3) 看状态" "4) 实时追踪" \\
        "5) 文件变更" "6) 修复" "0) 返回")\n    [[ -z "$sub_menu" ]] && return\n    case "${sub_menu:0:1}" in\n        1) bash "$LIB_DIR/monitor.sh" start ;,\n        2) bash "$LIB_DIR/monitor.sh" stop ;,\n        3) bash "$LIB_DIR/monitor.sh" status ;,\n        4) bash "$LIB_DIR/monitor.sh" tail ;,\n        5) bash "$LIB_DIR/monitor.sh" monitor ;,\n        6) fix_monitor ;,
    esac'),

    # submenu_llmswitch (line ~323-345)
    ('read -p "选择 [0-5]: " c\n    c=$(menu_num "$c")\n    case "$c" in\n        1) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --start ;,\n        2) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --stop ;,\n        3) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --restart ;,\n        4) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --status ;,\n        5) bash "$LIB_DIR/init-llm.sh" ;,\n        0) return ;,\n        *) submenu_llmswitch ;,
    esac',
     'sub_menu=$(menu_select "llmswitch" \\
        "1) 启动" "2) 停止" "3) 重启" "4) 状态" "5) 切换 LLM" "0) 返回")\n    [[ -z "$sub_menu" ]] && return\n    case "${sub_menu:0:1}" in\n        1) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --start ;,
        2) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --stop ;,
        3) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --restart ;,
        4) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --status ;,
        5) bash "$LIB_DIR/init-llm.sh" ;,
    esac'),

    # template sync submenu (line ~202-212)
    ('read -p "选择 [d/f/r/0]: " choice\n           case "$choice" in\n             d) bash "$LIB_DIR/example-sync.sh" diff ;,\n             f) bash "$LIB_DIR/example-sync.sh" promote ;,
             r) bash "$LIB_DIR/example-sync.sh" reverse ;,
             0) ;,
             *) ;,
           esac',
     'ex_sel=$(menu_select "模板同步" \\
            "d) 查看差异" "f) 正向同步" "r) 反向同步" "0) 返回")\n           [[ -z "$ex_sel" ]] && continue\n           case "${ex_sel:0:1}" in\n             d) bash "$LIB_DIR/example-sync.sh" diff ;,
             f) bash "$LIB_DIR/example-sync.sh" promote ;,
             r) bash "$LIB_DIR/example-sync.sh" reverse ;,
           esac'),

    # Bill & Token submenus (line ~238-286) - multiple read-p
    ('read -p "  选择 [0-7]: " choice\n           choice=$(menu_num "$choice")\n           case "$choice" in\n             1) bash "$LIB_DIR/init-llm.sh" bill ;,\n             2) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --stats ;,
             3) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --report ;,
             4) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ;,
             5)\n                read -p "  飞书 URL (回车 = 用 config 默认): " url\n                if [[ -n "$url" ]]; then\n                   bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --feishu "$url"\n                else\n                   bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental\n                fi\n                ;,
             6) bash "$CCCONFIG_DIR/option-usage/init.sh" status\n                echo ""\n                echo "  ─ 操作 ─"\n                echo "    i) 装 systemd timer"\n                echo "    u) 卸 systemd timer"\n                echo "    c) 配置 feishu_url / schedule / include_today"\n                echo "    b) 返回"\n                read -p "  选择 [i/u/c/b]: " sub\n                case "$sub" in\n                  i) bash "$CCCONFIG_DIR/option-usage/init.sh" install ;,
                  u) bash "$CCCONFIG_DIR/option-usage/init.sh" uninstall ;,
                  c) bash "$CCCONFIG_DIR/option-usage/init.sh" config ;,
                esac\n                ;,
             7) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;,
             0) break ;,
             *) ;,
           esac\n           echo ""\n           echo "  按回车继续..."\n           read -r dummy\n           done ;,',
     'bill_sel=$(menu_select "Bill & Token" \\
            "1) Bill(模型单价)" "2) 用量统计" "3) 按日报告" \\
            "4) 按天归档" "5) 推飞书" "6) timer 管理" "7) 手动触发+推飞书" "0) 返回")\n           [[ -z "$bill_sel" ]] && continue\n           case "${bill_sel:0:1}" in\n             1) bash "$LIB_DIR/init-llm.sh" bill ;,
             2) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --stats ;,
             3) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --report ;,
             4) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ;,
             5) local url; url=$(prompt "飞书 URL" 2>/dev/null);\n                if [[ -n "$url" ]]; then\n                   bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --feishu "$url"\n                else\n                   bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental\n                fi ;,
             6) bash "$CCCONFIG_DIR/option-usage/init.sh" status\n                local timer_sel; timer_sel=$(menu_select "timer" \\
                    "i) 安装" "u) 卸载" "c) 配置" "b) 返回")\n                [[ -z "$timer_sel" ]] && break\n                case "${timer_sel:0:1}" in\n                  i) bash "$CCCONFIG_DIR/option-usage/init.sh" install ;,
                  u) bash "$CCCONFIG_DIR/option-usage/init.sh" uninstall ;,
                  c) bash "$CCCONFIG_DIR/option-usage/init.sh" config ;,
                esac ;,
             7) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;,
           esac\n           done ;,'),

    # feishu submenu (line ~416-468)
    ('read -p "选择 [0-7]: " c\n        c=$(menu_num "$c")',
     'c=$(menu_select "飞书管理" \\
        "1) 飞书账号" "2) lark-cli" "3) larkbridge" \\
        "4) 发测试消息" "5) 装 lark-cli" "6) 装 larkbridge" "7) 申请权限" "0) 返回")\n        c="${c:0:1}"'),

    # feishu - perms menu (line ~400-408)
    ('read -p "  选择 app [0-${#labels[@]}]: " c\n    c=$(menu_num "$c")\n    [ "$c" = "0" ] && return 0\n    if [ -n "$c" ] && [ "$c" -ge 1 ] && [ "$c" -le "${#labels[@]}" ] 2>/dev/null; then\n        _feishu_open_perms_for_app "${labels[$((c-1))]}"\n    fi\n    read -p "  按回车返回飞书菜单..." dummy',
     'perms_sel=$(menu_select "选择 app" "${labels[@]}")\n    [[ -z "$perms_sel" ]] && return 0\n    for ((pi=0; pi<${#labels[@]}; pi++)); do\n        [[ "${labels[$pi]}" == "$perms_sel" ]] && { _feishu_open_perms_for_app "$perms_sel"; break; }\n    done'),

    # feishu larkcli submenu (line ~477-494)
    ('read -p "  选择 [a/k/l/0]: " sub\n        case "$sub" in\n            a|A) bash "$feishu_lc" ;,
            k|K) bash "$feishu_switch" ;,
            l|L) bash "$feishu_switch" --list ;,
            0) return 0 ;,
            *) continue ;,
        esac',
     'sub=$(menu_select "lark-cli" \\
            "a) 重置配置" "k) OAuth 状态" "l) 列出账号" "0) 返回")\n        [[ -z "$sub" ]] && return 0\n        case "${sub:0:1}" in\n            a) bash "$feishu_lc" ;,
            k) bash "$feishu_switch" ;,
            l) bash "$feishu_switch" --list ;,
        esac'),

    # larkbridge submenu (line ~498-539)
    ('read -p "  选择 [1-6/n/r/d/0]: " sub\n        case "$sub" in\n            1) bash "$feishu_lb" --run ;,
            2) bash "$feishu_lb" --bg ;,
            3) bash "$feishu_lb" --stop ;,
            4) bash "$feishu_lb" --restart ;,
            5) bash "$feishu_lb" --logs ;,
            6)\n                echo ""\n                info "日志目录: $HOME/.lark-channel/profiles/"\n                ls -lt "$HOME/.lark-channel/profiles/"*/logs/*.jsonl 2>/dev/null || warn "暂无日志文件"\n                read -p "  按回车返回..." dummy\n                ;,
            n|N) bash "$feishu_lb" --profile add ;,
            r|R) bash "$feishu_lb" --profile remove ;,
            d|D) bash "$feishu_lb" --profile default ;,
            0) return 0 ;,
            *) continue ;,
        esac',
     'lb_sel=$(menu_select "larkbridge" \\
        "1) 前台启动" "2) 后台启动" "3) 停止" "4) 重启" \\
        "5) 看日志" "6) 日志目录" \\
        "n) 新增 profile" "r) 删除" "d) 设为默认" "0) 返回")\n        [[ -z "$lb_sel" ]] && return 0\n        case "${lb_sel:0:1}" in\n            1) bash "$feishu_lb" --run ;,
            2) bash "$feishu_lb" --bg ;,
            3) bash "$feishu_lb" --stop ;,
            4) bash "$feishu_lb" --restart ;,
            5) bash "$feishu_lb" --logs ;,
            6) info "日志目录: $HOME/.lark-channel/profiles/"; ls -lt "$HOME/.lark-channel/profiles/"*/logs/*.jsonl 2>/dev/null || warn "暂无" ;,
            n|N) bash "$feishu_lb" --profile add ;,
            r|R) bash "$feishu_lb" --profile remove ;,
            d|D) bash "$feishu_lb" --profile default ;,
        esac'),

    # send test message - app select (line ~614-637)
    ('read -p "  选择 app [0-${#names[@]}]: " sel\n    [[ "$sel" =~ ^[0-9]+$ ]] || return 0\n    [ "$sel" -ge 1 ] && [ "$sel" -le ${#names[@]} ] || return 0\n    local target="${names[$((sel - 1))]}"',
     'sel=$(menu_select "选择 app" "${names[@]}")\n    [[ -z "$sel" ]] && return 0\n    local target="$sel"'),

    # send test message - confirm (line ~672-673)
    ('read -p "  发送? [Y/n]: " cf\n    [[ "$cf" =~ ^[Nn]$ ]] && { info "  取消" >&2; return 0; }',
     'confirm "发送？" y >&2 || { info "取消" >&2; return 0; }'),

    # feishu accounts submenu (line ~768-809)
    ('read -p "  选择 [0-${#lines[@]}/a/d]: " sel',
     'sel=$(menu_select "飞书账号" "${names[@]}" "a) 添加" "d) 删除" "0) 返回")'),

    # feishu accounts - confirm delete (line ~779-790)
    ('read -p "  确认从 feishu.json 删 '\''${dn}'\''? [y/N] " cf\n                    if [[ "$cf" =~ ^[Yy]$ ]]; then',
     'if confirm "确认删除 ${dn}？" n; then'),

    # feishu app detail submenu (line ~808-809)
    ('read -p "  选择 [0-5]: " sub\n        case "$sub" in\n            1) bash "$feishu_switch" "$target" ;,
            2)\n                local cd="$HOME/.lark-cli-${target}"\n                if [ -f "${cd}/config.json" ]; then\n                    LARKSUITE_CLI_CONFIG_DIR="$cd" bash "$feishu_lc" --auth-login "$target"\n                else\n                    warn "先选 4 编辑 App ID/Secret"\n                fi\n                ;,
            3)\n                local cd="$HOME/.lark-cli-${target}"\n                if [ -f "${cd}/config.json" ]; then\n                    LARKSUITE_CLI_CONFIG_DIR="$cd" lark-cli auth status 2>&1 \\\
                        | grep -v '^\\[lark-cli\\]' | sed 's/^/  /'\n                else\n                    warn "config.json 不存在"\n                fi\n                ;,
            4) warn "手动编辑: vim $conf" ;,
            5) _feishu_send_test_message_for "$target" ;,
            0) ;,
            *) ;,
        esac',
     'sub=$(menu_select "应用: $target" \\
        "1) 切换账号" "2) OAuth 授权" "3) 看授权" "4) 编辑 App ID/Secret" "5) 发测试消息" "0) 返回")\n        [[ -z "$sub" ]] && continue\n        case "${sub:0:1}" in\n            1) bash "$feishu_switch" "$target" ;,
            2) local cd="$HOME/.lark-cli-${target}"; [ -f "${cd}/config.json" ] && LARKSUITE_CLI_CONFIG_DIR="$cd" bash "$feishu_lc" --auth-login "$target" || warn "先编辑 App ID/Secret" ;,
            3) local cd="$HOME/.lark-cli-${target}"; [ -f "${cd}/config.json" ] && LARKSUITE_CLI_CONFIG_DIR="$cd" lark-cli auth status 2>&1 | grep -v "^\\[lark-cli\\]" | sed "s/^/  /" || warn "config.json 不存在" ;,
            4) warn "手动编辑: vim $conf" ;,
            5) _feishu_send_test_message_for "$target" ;,
        esac'),

    # getnote submenu (line ~854-872)
    ('read -p "  选择 [0-4]: " c\n\n        case "$c" in\n            1) bash "$init" add ;,
            2) bash "$init" remove ;,
            3)\n                read -p "  输入账号名（回车取消）: " target < /dev/tty\n                [ -n "$target" ] && bash "$sw" "$target"\n                ;,
            4)\n                read -p "  输入账号名（回车取消）: " target < /dev/tty\n                [ -n "$target" ] && bash "$sw" "$target" -p\n                ;,
            0|q|"") return 0 ;,
            *) warn "无效选项" ;,
        esac\n        echo ""\n        read -p "  按回车返回 getnote 菜单..." dummy\n    done',
     'note_sel=$(menu_select "getnote" \\
        "1) 添加" "2) 删除" "3) 切换" "4) 切换(持久化)" "0) 返回")\n        [[ -z "$note_sel" ]] && continue\n        case "${note_sel:0:1}" in\n            1) bash "$init" add ;,
            2) bash "$init" remove ;,
            3) local target; target=$(prompt "账号名") 2>/dev/null; [ -n "$target" ] && bash "$sw" "$target" ;,
            4) local target; target=$(prompt "账号名") 2>/dev/null; [ -n "$target" ] && bash "$sw" "$target" -p ;,
            0) return 0 ;,
        esac\n        echo ""; read -p "按回车返回..." dummy\n    done'),

    # feishu default openid prompt (line ~571-573)
    ('read -p "  输入你的 open_id (回车跳过): " input_oid\n    [ -z "$input_oid" ] && { warn "  跳过" >&2; return 1; }',
     'input_oid=$(prompt "输入 open_id") 2>/dev/null\n    [ -z "$input_oid" ] && { warn "跳过" >&2; return 1; }'),

    # send test message for app - confirm (line ~908-909)
    ('read -p "  发送? [Y/n]: " cf\n        [[ "$cf" =~ ^[Nn]$ ]] && { info "  取消"; return 0; }',
     'confirm "发送？" y || { info "取消"; return 0; }'),
]

for pattern, replacement in replacements:
    content = re.sub(re.escape(pattern), replacement, content)

with open('maintain.sh', 'w') as f:
    f.write(content)

print('Replacements applied')
import subprocess
result = subprocess.run(['grep', '-c', 'read -p', 'maintain.sh'], capture_output=True, text=True)
print(f'Remaining read -p: {result.stdout.strip()}')
