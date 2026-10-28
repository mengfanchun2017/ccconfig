# shellcheck shell=bash
# lib/menu-data-maintain.sh — maintain.sh 菜单数据层
#
# 定义 CAT_NAME / MENU_ENTRIES 供 menu_loop 驱动。
# source 后直接调 menu_loop "ccconfig 运维中心"。
#
# ── 结构约定（扁平，无二级菜单）──
#   一级 = 功能域（状态/同步、更新、LLM、MCP、rag、远程）
#   二级 = 该域下的字母项，选中即执行，**没有"返回上层"这一步**
#
# ── 条目 schema: cat|letter|title|cmd|action ──
#   cmd    : 右侧灰色列，显示绕过菜单的直接调用命令（须真实可跑，cwd = 仓库根）
#   action : 实际执行的命令/函数名（eval 上下文，可用 $LIB_DIR / $CCCONFIG_DIR）
#
#   action 里带交互输入（删预设、切账号）的用 ask_run / ask_run_p helper，
#   不要为此再开一层菜单。见 maintain.sh「菜单动作 helper」。

# ── 分类（编号连续，不跳号）──
# 2026-10-18 板块重构：原「状态」+「监控/同步」合并为「状态/同步」，
# 「更新」前移一位，原「飞书/Lark」+「getnote」合并为「rag」，远程顺移。
CAT_NAME[1]="状态/同步"
CAT_NAME[2]="更新"
CAT_NAME[3]="LLM"
CAT_NAME[4]="MCP"
CAT_NAME[5]="rag"
CAT_NAME[6]="远程"

MENU_ENTRIES=(
    # ── 1: 状态/同步（原 1 状态 + 原 2 监控/同步 合并）──
    # 看（1A 只读）与同步监控（1B-1E，原 2A-2D）同属"观察本机当前状态"，合并后
    # 不必在两个分区之间来回找。原 1B 一键修复已移出（见 2 分区），
    # 原 1C 高权限说明也移出（它不是状态观察）。
    "1|A|检查（只读）|./maintain.sh status|bash \"\$LIB_DIR/status.sh\""
    "1|B|日志跟踪|./maintain.sh monitor tail|bash \"\$LIB_DIR/monitor.sh\" tail"
    "1|C|监控状态|./maintain.sh monitor status|bash \"\$LIB_DIR/monitor.sh\" status"
    "1|D|启动监控|./maintain.sh monitor start|bash \"\$LIB_DIR/monitor.sh\" start"
    "1|E|停止监控|./maintain.sh monitor stop|bash \"\$LIB_DIR/monitor.sh\" stop"
    "1|F|高权限开启（claudeby）|./maintain.sh highpriv|do_highpriv"

    # ── 2: 更新 ──
    # 2A 动的是【3 个配置仓库】：ccprivate 结构升级 → 拉取 ccprivate/skill/ccconfig 3 个库
    #    → 重建链接 → skill sync（原 3C 已并入，同步的全部仓库就是这 3 个）。
    # 2B 动的是【已安装的工具版本】（Node/Claude/gh/lark-cli/pip/MCP 缓存…），不碰 git；
    #    ccconfig 自更新已移出（归 2A 负责），update.sh 保留关键文件自 reload 防旧代码跑新步骤。
    # 2C/2D 顺序提前：PAT 与可选组件属"环境更新维护"，紧跟代码/tool 更新后。
    # 2E 一键修复：原 1B，做的是恢复链（拉仓库+重建链接+settings 归位+MCP 注册+memory 链），
    #    本质是"把本机修到与最新版一致"，与更新同域，故从状态分区挪来。去掉"（全量）"后缀。
    "2|A|配置仓库更新（3库）|./maintain.sh self config|do_self config"
    "2|B|tool 更新（Node/Claude）|./maintain.sh upgrade all|bash \"\$LIB_DIR/update.sh\" all"
    "2|C|GitHub PAT 刷新|./maintain.sh pat|bash \"\$CCCONFIG_DIR/bin/refresh-gh-auth.sh\""
    "2|D|可选组件安装/补装|bash init-option.sh|bash \"\$CCCONFIG_DIR/init-option.sh\""
    "2|E|一键修复|./maintain.sh fix|do_setup"

    # ── 3: LLM ──
    # 原「修复 /model 污染」「修复 bridge 转 Anthropic」两个菜单项已删
    # （删前编号 4E/4F，重构后 3 分区）：
    #   4E 是静默 no-op —— 只在 env.ANTHROPIC_MODEL 与顶层 model 不一致时才写，
    #     正常状态下零输出零退出（"选了没反馈"）；而且每次切预设 switch_llm 末尾
    #     已自动调 sync_top_model，手动入口冗余。函数保留，仅去掉菜单项。
    #   4F 的自愈逻辑（selfheal_bridge）仍由 status.sh 会话冷启动调用，函数保留；
    #     它此前作为独立菜单项暴露的价值不大（bridge 挂了由 supervisor/2E 兜底）。
    "3|A|切换预设（交互）|./maintain.sh llm|bash \"\$LIB_DIR/init-llm.sh\""
    "3|B|列出预设|./maintain.sh llm list|bash \"\$LIB_DIR/init-llm.sh\" list"
    "3|C|链路诊断（当前生效）|./maintain.sh llm status|bash \"\$LIB_DIR/init-llm.sh\" status"
    "3|D|真实探测（问预设名）|./maintain.sh llm test <名>|ask_run \"预设名（3B 可查）\" \"\$LIB_DIR/init-llm.sh\" test"
    "3|E|删除预设（问预设名）|./maintain.sh llm delete <名>|ask_run \"要删除的预设名\" \"\$LIB_DIR/init-llm.sh\" delete"
    "3|F|设置上下文窗口|./maintain.sh llm ctx|bash \"\$LIB_DIR/init-llm.sh\" ctx"
    "3|G|新增自定义预设|./maintain.sh llm add|bash \"\$LIB_DIR/init-llm.sh\" add"
    "3|H|编辑自定义预设|./maintain.sh llm edit|bash \"\$LIB_DIR/init-llm.sh\" edit"

    # ── 4: MCP ──
    # 4D 注册同步：从 conf/mcp-servers.json 把服务器写进 .config.json。
    # 此前这个动作只以「mcp」之名挂在 2D 可选组件菜单里（2D 是装组件的地方，
    # 而它做的是注册同步），MCP 域自己反而没有入口 —— 归位到这里。
    "4|A|MCP 配置（用户级）|./maintain.sh mcp config|bash \"\$LIB_DIR/mcp-manager.sh\" config"
    "4|B|MCP 状态|./maintain.sh mcp status|bash \"\$LIB_DIR/mcp-manager.sh\" status"
    "4|C|MCP Key 配置|./maintain.sh mcp keys|bash \"\$LIB_DIR/mcp-manager.sh\" keys"
    "4|D|MCP 注册同步|./maintain.sh mcp sync|bash \"\$LIB_DIR/mcp-manager.sh\" sync"

    # ── 5: rag（lark + getnote 合并）──
    # 两个都是"从外部知识源取资料"的工具，合到一处。小标题带来源前缀（lark /
    # getnote），避免同名项（两边都有"OAuth 授权""状态"）分不清。
    # 原 6A「账号列表/当前账号」删去"当前账号"后缀：进入即列出全部并标出当前，
    #   标题里的"当前账号"是冗余描述。
    # getnote 侧只留两项（安装已归 2D，诊断/升级见下方注释）。
    "5|A|lark 账号列表|bash option-larkcli/lark-switch.sh --list|bash \"\$CCCONFIG_DIR/option-larkcli/lark-switch.sh\" --list"
    "5|B|lark 切换账号|bash option-larkcli/lark-switch.sh <名> -p|ask_run_p \"账号名\" \"\$CCCONFIG_DIR/option-larkcli/lark-switch.sh\""
    "5|C|lark OAuth 授权|bash option-larkcli/lark-switch.sh|bash \"\$CCCONFIG_DIR/option-larkcli/lark-switch.sh\""
    "5|D|lark 配置/更新账号|bash option-larkcli/init.sh|bash \"\$CCCONFIG_DIR/option-larkcli/init.sh\""
    "5|E|getnote 状态|bash option-getnote/init.sh --status|bash \"\$CCCONFIG_DIR/option-getnote/init.sh\" --status"
    "5|F|getnote OAuth 授权|bash option-getnote/init.sh auth|bash \"\$CCCONFIG_DIR/option-getnote/init.sh\" auth"
    # botmux = 飞书 ↔ AI 编程 CLI 桥（取代已停更的 ccbridge）。通信/会话归 botmux daemon，
    # 这里是运维入口：状态、启动、会话、Dashboard。
    # 状态项：WARN（未配置/daemon 没跑）是正常输出而非失败。action 走 do_botmux_status
    # 包装函数（吞三态退出码）—— 不能写「|| true」，'|' 会撕裂 MENU_ENTRIES 的字段 schema。
    "5|G|botmux 桥状态|bash option-botmux/init.sh --status|do_botmux_status"
    "5|H|botmux 桥配置（引导）|bash option-botmux/init.sh guide|bash \"\$CCCONFIG_DIR/option-botmux/init.sh\" guide"
    "5|I|botmux 管理菜单|bash option-botmux/init.sh menu|bash \"\$CCCONFIG_DIR/option-botmux/init.sh\" menu"

    # ── 6: 远程（SSH + tailscale）──
    "6|A|查看 SSH 状态/端口|bash option-remote/init.sh --status|bash \"\$CCCONFIG_DIR/option-remote/init.sh\" --status"
    "6|B|设置 SSH 端口（问端口）|bash option-remote/init.sh set-port <端口>|ask_run \"要设置的 SSH 端口\" \"\$CCCONFIG_DIR/option-remote/init.sh\" set-port"

    # ── 0: 退出 ──
    "0| |退出||exit 0"
)