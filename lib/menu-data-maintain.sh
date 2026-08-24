# lib/menu-data-maintain.sh — maintain.sh 菜单数据层
#
# 定义 CAT_NAME / MENU_ENTRIES 供 menu_loop 驱动。
# source 后直接调 menu_loop "ccconfig 运维中心"。

# ── 分类 ──
CAT_NAME[1]="状态"
CAT_NAME[2]="维护"
CAT_NAME[3]="工具"

# ── 菜单条目: cat|letter|title|desc|action|submenu
#   action: 直接执行的 shell 命令（eval 上下文）
#   submenu: "menu:xxx" → 调 _submenu_xxx 函数
MENU_ENTRIES=(
    # ── 1: 状态 ──
    "1|A|状态总览|检查符号链接/auto-sync/LLM/飞书等运行状态|bash \"$LIB_DIR/status.sh\"|"
    "1|B|Monitor 状态|查看监控进程运行状态|bash \"$LIB_DIR/monitor.sh\" status|"
    "1|C|快速探测|一行状态头（quick-probe）|source \"$LIB_DIR/quick-probe.sh\"; header_status|"
    "1|D|git 状态|git log/status/diff|git -C \"$SCRIPT_DIR\" status -s && git -C \"$SCRIPT_DIR\" log --oneline -5|"

    # ── 2: 维护 ──
    "2|A|一键修复|符号链接+缺失目录+auto-sync+模板|do_finalize|"
    "2|B|Monitor|启动/停止/重启/追踪/修复||menu:monitor"
    "2|C|追踪日志|tail monitor 日志|bash \"$LIB_DIR/monitor.sh\" tail|"
    "2|D|自我更新|ccconfig + skill 拉取最新|do_self all|"
    "2|E|Git 同步|pull/push 远程仓库|bash \"$LIB_DIR/sync.sh\"|"
    "2|F|组件升级|Node/Claude/skill 组件升级|bash \"$LIB_DIR/update.sh\" menu|"
    "2|G|依赖检查|deps 完整性验证|bash \"$LIB_DIR/deps-check.sh\"|"
    "2|H|模板同步|.example 与模板间同步|bash \"$LIB_DIR/example-sync.sh\" status|"

    # ── 3: 工具 ──
    "3|A|LLM 切换|init-llm 交互选择|bash \"$LIB_DIR/init-llm.sh\"|"
    "3|B|llmswitch|Gateway 代理管理||menu:llmswitch"
    "3|C|Bill \& Token|模型单价/用量统计||menu:bill_token"
    "3|D|MCP 管理|跨项目查看/配置 MCP|bash \"$LIB_DIR/mcp-manager.sh\" config|"
    "3|E|飞书管理|lark-cli 账号/OAuth/测试||menu:feishu"
    "3|F|getnote|得到大脑 MCP 账号管理||menu:getnote"
    "3|G|ccprivate 升级|私有配置仓库升级|bash \"$LIB_DIR/ccprivate-upgrade.sh\"|"
    "3|H|回归测试|bootstrap 测试|bash \"$CCCONFIG_DIR/bin/test-bootstrap.sh\"|"
    "3|I|GitHub PAT|刷新 fine-grained PAT|bash \"$CCCONFIG_DIR/bin/refresh-gh-auth.sh\"|"

    # ── 0: 退出 ──
    "0|0|退出||exit 0|"
)
