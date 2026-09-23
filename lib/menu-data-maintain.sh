# shellcheck shell=bash
# lib/menu-data-maintain.sh — maintain.sh 菜单数据层
#
# 定义 CAT_NAME / MENU_ENTRIES 供 menu_loop 驱动。
# source 后直接调 menu_loop "ccconfig 运维中心"。
#
# ── 结构约定（扁平，无二级菜单）──
#   一级 = 功能域（状态/监控/更新/LLM/MCP/飞书/getnote）
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
CAT_NAME[5]="MCP"
CAT_NAME[6]="飞书/Lark"
CAT_NAME[7]="getnote"

MENU_ENTRIES=(
    # ── 1: 状态 ──
    # 只有两件事：看（1A，只读）和修（1B，把新版本设定全部启用）。
    # 1B 名字与 2F「修复 inotify」/4E「修复 /model 污染」统一为「修复 <对象>」。
    # --quick 快速模式仍在 status.sh 里，但不再单占一个菜单项（菜单只暴露全量 1A）。
    # 用量并入状态：只读看统计（1C）+ 管理定时器（1D-1F），不单设分类。
    "1|A|检查（只读）|./maintain.sh status|bash \"\$LIB_DIR/status.sh\""
    "1|B|一键修复（全量）|./maintain.sh fix|do_setup"
    "1|C|用量统计（跨 LLM）|./maintain.sh token --stats|bash \"\$CCCONFIG_DIR/option-usage/token-usage.sh\" --stats"
    "1|D|用量定时器状态|bash option-usage/init.sh status|bash \"\$CCCONFIG_DIR/option-usage/init.sh\" status"
    "1|E|用量定时器启用|bash option-usage/init.sh install|bash \"\$CCCONFIG_DIR/option-usage/init.sh\" install"
    "1|F|用量定时器停用|bash option-usage/init.sh uninstall|bash \"\$CCCONFIG_DIR/option-usage/init.sh\" uninstall"

    # ── 2: 监控/同步 ──
    # 重启即停止+启动（2C+2B），不单占项；inotify 修复已含在 1B 一键修复
    "2|A|日志跟踪|./maintain.sh monitor tail|bash \"\$LIB_DIR/monitor.sh\" tail"
    "2|B|监控状态|./maintain.sh monitor status|bash \"\$LIB_DIR/monitor.sh\" status"
    "2|C|启动监控|./maintain.sh monitor start|bash \"\$LIB_DIR/monitor.sh\" start"
    "2|D|停止监控|./maintain.sh monitor stop|bash \"\$LIB_DIR/monitor.sh\" stop"

    # ── 3: 更新 ──
    # 3A 动的是【配置仓库】：ccprivate 结构升级 → ccconfig 拉代码+重建链接 → skill 同步。
    #    原 3A/3B/3C 三个单项合并，一次跑完（git pull / skill sync 幂等，重跑无害）。
    # 3B 动的是【已安装的工具版本】（Node/Claude/gh/lark-cli/pip/MCP 缓存…），不碰 git；
    #    含 ccconfig 自更新 + skill 同步（update.sh all 内部步骤，行为不变）。
    # 3C 动的是【所有 git 仓库】（拉 + 脏库提交推送）；它把 ccconfig 也当第一个仓库
    #    处理，所以 3A 的"拉代码+重建链接"已被它涵盖，重跑无害。
    "3|A|配置仓库更新|./maintain.sh self config|do_self config"
    "3|B|tool 更新（Node/Claude）|./maintain.sh upgrade all|bash \"\$LIB_DIR/update.sh\" all"
    "3|C|git 全部更新（所有仓库）|./maintain.sh sync --all|bash \"\$LIB_DIR/sync.sh\" --all"
    # 原 8 区并入：PAT 续期与可选组件都属"环境更新维护"，与更新放一处。
    "3|D|GitHub PAT 刷新|./maintain.sh pat|bash \"\$CCCONFIG_DIR/bin/refresh-gh-auth.sh\""
    "3|E|可选组件安装/补装|bash init-option.sh|bash \"\$CCCONFIG_DIR/init-option.sh\""

    # ── 4: LLM ──
    "4|A|切换预设（交互）|./maintain.sh llm|bash \"\$LIB_DIR/init-llm.sh\""
    "4|B|列出预设|./maintain.sh llm list|bash \"\$LIB_DIR/init-llm.sh\" list"
    "4|C|链路诊断（当前生效）|./maintain.sh llm status|bash \"\$LIB_DIR/init-llm.sh\" status"
    "4|D|真实探测（问预设名）|./maintain.sh llm test <名>|ask_run \"预设名（4B 可查）\" \"\$LIB_DIR/init-llm.sh\" test"
    "4|E|修复 /model 污染|./maintain.sh llm sync|bash \"\$LIB_DIR/init-llm.sh\" sync"
    "4|F|修复 bridge 转 Anthropic|./maintain.sh llm heal|bash \"\$LIB_DIR/init-llm.sh\" heal"
    "4|G|删除预设（问预设名）|./maintain.sh llm delete <名>|ask_run \"要删除的预设名\" \"\$LIB_DIR/init-llm.sh\" delete"

    # ── 5: MCP ──
    "5|A|MCP 配置（用户级）|./maintain.sh mcp config|bash \"\$LIB_DIR/mcp-manager.sh\" config"
    "5|B|MCP 状态|./maintain.sh mcp status|bash \"\$LIB_DIR/mcp-manager.sh\" status"
    "5|C|配置 MCP Key|./maintain.sh mcp keys|bash \"\$LIB_DIR/mcp-manager.sh\" keys"

    # ── 6: 飞书/Lark ──
    # 账号新增即持久化（feishu.json），切换默认持久化（带 -p），不再拆「并持久化」独立项
    "6|A|账号列表/当前账号|bash option-larkcli/lark-switch.sh --list|bash \"\$CCCONFIG_DIR/option-larkcli/lark-switch.sh\" --list"
    "6|B|切换账号（问账号名）|bash option-larkcli/lark-switch.sh <名> -p|ask_run_p \"账号名\" \"\$CCCONFIG_DIR/option-larkcli/lark-switch.sh\""
    "6|C|OAuth 授权状态|bash option-larkcli/lark-switch.sh|bash \"\$CCCONFIG_DIR/option-larkcli/lark-switch.sh\""
    "6|D|配置/更新 lark-cli 账号|bash option-larkcli/init.sh|bash \"\$CCCONFIG_DIR/option-larkcli/init.sh\""

    # ── 7: getnote ──
    "7|A|账号列表|bash option-getnote/getnote-switch.sh --list|bash \"\$CCCONFIG_DIR/option-getnote/getnote-switch.sh\" --list"
    "7|B|状态|bash option-getnote/init.sh --status|bash \"\$CCCONFIG_DIR/option-getnote/init.sh\" --status"
    "7|C|添加账号|bash option-getnote/init.sh add|bash \"\$CCCONFIG_DIR/option-getnote/init.sh\" add"
    "7|D|删除账号|bash option-getnote/init.sh remove|bash \"\$CCCONFIG_DIR/option-getnote/init.sh\" remove"
    "7|E|切换账号（问账号名）|bash option-getnote/getnote-switch.sh <名> -p|ask_run_p \"账号名\" \"\$CCCONFIG_DIR/option-getnote/getnote-switch.sh\""

    # ── 0: 退出 ──
    "0| |退出||exit 0"
)
