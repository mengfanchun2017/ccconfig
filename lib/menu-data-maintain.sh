# shellcheck shell=bash
# lib/menu-data-maintain.sh — maintain.sh 菜单数据层
#
# 定义 CAT_NAME / MENU_ENTRIES 供 menu_loop 驱动。
# source 后直接调 menu_loop "ccconfig 运维中心"。
#
# ── 结构约定（扁平，无二级菜单）──
#   一级 = 功能域（状态/监控/更新/LLM/用量/MCP/飞书/getnote/其他）
#   二级 = 该域下的字母项，选中即执行，**没有"返回上层"这一步**
#
# ── 条目 schema: cat|letter|title|cmd|action ──
#   cmd    : 右侧灰色列，显示绕过菜单的直接调用命令（须真实可跑，cwd = 仓库根）
#   action : 实际执行的命令/函数名（eval 上下文，可用 $LIB_DIR / $CCCONFIG_DIR）
#
#   action 里带交互输入（删预设、切账号）的用 ask_run / ask_run_p helper，
#   不要为此再开一层菜单。见 maintain.sh「菜单动作 helper」。

# ── 分类（编号连续，不跳号）──
CAT_NAME[1]="状态"
CAT_NAME[2]="监控/同步"
CAT_NAME[3]="更新"
CAT_NAME[4]="LLM"
CAT_NAME[5]="用量"
CAT_NAME[6]="MCP"
CAT_NAME[7]="飞书/Lark"
CAT_NAME[8]="getnote"
CAT_NAME[9]="其他"

MENU_ENTRIES=(
    # ── 1: 状态 ──
    "1|A|状态检查（全量）|./maintain.sh status|bash \"\$LIB_DIR/status.sh\""
    "1|B|快速状态（跳过慢检查）|./maintain.sh status --quick|bash \"\$LIB_DIR/status.sh\" --quick"
    "1|C|依赖检查|./maintain.sh deps|bash \"\$LIB_DIR/deps-check.sh\""
    "1|D|一键修复（链接/目录）|./maintain.sh fix|do_setup"

    # ── 2: 监控/同步 ──
    "2|A|监控状态|./maintain.sh monitor status|bash \"\$LIB_DIR/monitor.sh\" status"
    "2|B|启动监控|./maintain.sh monitor start|bash \"\$LIB_DIR/monitor.sh\" start"
    "2|C|停止监控|./maintain.sh monitor stop|bash \"\$LIB_DIR/monitor.sh\" stop"
    "2|D|重启监控|./maintain.sh monitor restart|bash \"\$LIB_DIR/monitor.sh\" restart"
    "2|E|追踪推送日志|./maintain.sh monitor tail|bash \"\$LIB_DIR/monitor.sh\" tail"
    "2|F|修复 inotify|./maintain.sh fix monitor|fix_monitor"
    "2|G|git 拉取（全部仓库）|./maintain.sh sync --all|bash \"\$LIB_DIR/sync.sh\" --all"

    # ── 3: 更新 ──
    # 3A-3C 动的是【配置仓库】（拉代码 / 重建链接 / 私有仓结构迁移）
    # 3D 动的是【已装的工具版本】（Node/Claude/gh/lark-cli…），不碰 git
    # 3E 动的是【所有 git 仓库】（拉 + 脏库提交推送）；它把 ccconfig 也当第一个
    #    仓库处理，所以 3A 的"拉代码+重建链接"已被它涵盖
    "3|A|ccconfig 自更新+重建链接|./maintain.sh self cc|do_self cc"
    "3|B|Skill 同步|./maintain.sh self skill|do_self skill"
    "3|C|ccprivate 升级（结构）|./maintain.sh upgrade-ccprivate|bash \"\$LIB_DIR/ccprivate-upgrade.sh\""
    "3|D|升级工具链（全部）|./maintain.sh upgrade all|bash \"\$LIB_DIR/update.sh\" all"
    "3|E|全部仓库 git 同步|./maintain.sh sync --all|bash \"\$LIB_DIR/sync.sh\" --all"

    # ── 4: LLM ──
    "4|A|切换预设（交互）|./maintain.sh llm|bash \"\$LIB_DIR/init-llm.sh\""
    "4|B|列出预设|./maintain.sh llm list|bash \"\$LIB_DIR/init-llm.sh\" list"
    "4|C|链路诊断（当前生效）|./maintain.sh llm status|bash \"\$LIB_DIR/init-llm.sh\" status"
    "4|D|真实探测（问预设名）|./maintain.sh llm test <名>|ask_run \"预设名（4B 可查）\" \"\$LIB_DIR/init-llm.sh\" test"
    "4|E|修复 /model 污染|./maintain.sh llm sync|bash \"\$LIB_DIR/init-llm.sh\" sync"
    "4|F|bridge 自愈|./maintain.sh llm heal|bash \"\$LIB_DIR/init-llm.sh\" heal"
    "4|G|删除预设（问预设名）|./maintain.sh llm delete <名>|ask_run \"要删除的预设名\" \"\$LIB_DIR/init-llm.sh\" delete"
    "4|H|归档用量（按模型+天）|./maintain.sh llm bill|bash \"\$LIB_DIR/init-llm.sh\" bill"

    # ── 5: 用量 ──
    # 只统计 token 与时间：不算钱（费用以上游账单为准）、不外发（飞书上报已移除）
    "5|A|用量统计（跨 LLM）|./maintain.sh token --stats|bash \"\$CCCONFIG_DIR/option-usage/token-usage.sh\" --stats"
    "5|B|按日报告|./maintain.sh token --report|bash \"\$CCCONFIG_DIR/option-usage/token-usage.sh\" --report"
    "5|C|立即归档（增量）|./maintain.sh token --by-day|bash \"\$CCCONFIG_DIR/option-usage/token-usage.sh\" --by-day"
    "5|D|今日快照（含今天）|./maintain.sh token --by-day --include-today|bash \"\$CCCONFIG_DIR/option-usage/token-usage.sh\" --by-day --include-today"
    "5|E|强制重算全量|./maintain.sh token --by-day --force|bash \"\$CCCONFIG_DIR/option-usage/token-usage.sh\" --by-day --force"
    "5|F|定时器状态|bash option-usage/init.sh status|bash \"\$CCCONFIG_DIR/option-usage/init.sh\" status"
    "5|G|启用定时器|bash option-usage/init.sh install|bash \"\$CCCONFIG_DIR/option-usage/init.sh\" install"
    "5|H|停用定时器|bash option-usage/init.sh uninstall|bash \"\$CCCONFIG_DIR/option-usage/init.sh\" uninstall"

    # ── 6: MCP ──
    "6|A|MCP 配置（跨项目）|./maintain.sh mcp config|bash \"\$LIB_DIR/mcp-manager.sh\" config"
    "6|B|MCP 状态|./maintain.sh mcp status|bash \"\$LIB_DIR/mcp-manager.sh\" status"
    "6|C|填 MCP Key|./maintain.sh mcp keys|bash \"\$LIB_DIR/mcp-manager.sh\" keys"
    "6|D|同步到 settings.json|./maintain.sh mcp sync|bash \"\$LIB_DIR/mcp-manager.sh\" sync"

    # ── 7: 飞书/Lark ──
    "7|A|账号列表/当前账号|bash option-larkcli/lark-switch.sh --list|bash \"\$CCCONFIG_DIR/option-larkcli/lark-switch.sh\" --list"
    "7|B|切换账号（问账号名）|bash option-larkcli/lark-switch.sh <名>|ask_run \"账号名\" \"\$CCCONFIG_DIR/option-larkcli/lark-switch.sh\""
    "7|C|切换账号并持久化|bash option-larkcli/lark-switch.sh <名> -p|ask_run_p \"账号名\" \"\$CCCONFIG_DIR/option-larkcli/lark-switch.sh\""
    "7|D|OAuth 授权状态|bash option-larkcli/lark-switch.sh|bash \"\$CCCONFIG_DIR/option-larkcli/lark-switch.sh\""
    "7|E|重置 lark-cli 配置|bash option-larkcli/init.sh|bash \"\$CCCONFIG_DIR/option-larkcli/init.sh\""
    "7|F|账号详情/发测试消息|bash lib/menu-feishu.sh|feishu_apps_menu"
    "7|G|飞书通道测试（ccbridge）|./maintain.sh feishu|bash \"\$CCCONFIG_DIR/maintain.sh\" feishu"

    # ── 8: getnote ──
    "8|A|账号列表|bash option-getnote/getnote-switch.sh --list|bash \"\$CCCONFIG_DIR/option-getnote/getnote-switch.sh\" --list"
    "8|B|状态|bash option-getnote/init.sh --status|bash \"\$CCCONFIG_DIR/option-getnote/init.sh\" --status"
    "8|C|添加账号|bash option-getnote/init.sh add|bash \"\$CCCONFIG_DIR/option-getnote/init.sh\" add"
    "8|D|删除账号|bash option-getnote/init.sh remove|bash \"\$CCCONFIG_DIR/option-getnote/init.sh\" remove"
    "8|E|切换账号（问账号名）|bash option-getnote/getnote-switch.sh <名>|ask_run \"账号名\" \"\$CCCONFIG_DIR/option-getnote/getnote-switch.sh\""
    "8|F|切换账号并持久化|bash option-getnote/getnote-switch.sh <名> -p|ask_run_p \"账号名\" \"\$CCCONFIG_DIR/option-getnote/getnote-switch.sh\""

    # ── 9: 其他 ──
    "9|A|GitHub PAT 刷新|./maintain.sh pat|bash \"\$CCCONFIG_DIR/bin/refresh-gh-auth.sh\""
    "9|B|模板差异|./maintain.sh example status|bash \"\$LIB_DIR/example-sync.sh\" status"
    "9|C|模板推广（本机→模板）|./maintain.sh example promote|bash \"\$LIB_DIR/example-sync.sh\" promote"

    # ── 0: 退出 ──
    "0| |退出||exit 0"
)
