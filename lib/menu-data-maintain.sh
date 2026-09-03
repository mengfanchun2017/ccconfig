# shellcheck shell=bash
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
    "1|A|状态检查|深度检查：链接/依赖/monitor/PAT/飞书/MCP|bash \"$LIB_DIR/status.sh\"|"
    "1|B|一键修复|符号链接+缺失目录+auto-sync+依赖检查|do_finalize|"
    "1|C|追踪日志|tail monitor 日志|bash \"$LIB_DIR/monitor.sh\" tail|"

    # ── 2: 维护 ──
    "2|A|监控配置|启动/停止/重启/追踪/修复||menu:monitor"
    "2|B|更新配置|ccconfig更新 / Git同步 / ccprivate升级 / 全部||menu:update_sync"
    "2|C|组件升级|Node/Claude/skill 组件升级|bash \"$LIB_DIR/update.sh\" menu|"

    # ── 3: 工具 ──
    "3|A|LLM 配置|切换预设/Gateway/单价/自定义|bash \"$LIB_DIR/init-llm.sh\"|"
    "3|B|用量统计|token-usage 统计/报告/归档||menu:usage"
    "3|C|MCP 管理|跨项目查看/配置 MCP|bash \"$LIB_DIR/mcp-manager.sh\" config|"
    "3|D|Lark 配置|lark-cli 账号/OAuth/测试||menu:feishu"
    "3|E|Getnote 配置|得到大脑 MCP 账号管理||menu:getnote"
    "3|F|Bootstrap 回归测试|bootstrap 集成测试|bash \"$CCCONFIG_DIR/bin/test-bootstrap.sh\"|"
    "3|G|gitPAT 配置|刷新 fine-grained PAT|bash \"$CCCONFIG_DIR/bin/refresh-gh-auth.sh\"|"
    "3|H|LLM 测试|测试所有模型|bash \"$LIB_DIR/init-llm.sh\" test all|"

    # ── 0: 退出 ──
    "0| |退出||exit 0|"
)
