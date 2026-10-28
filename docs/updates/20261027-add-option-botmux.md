# 2026-10-27 新增 option-botmux（飞书 ↔ AI 编程 CLI 桥），弃用 ccbridge

> 范围：新增 `option-botmux/`；ccconfig 各接线点从 ccbridge 切到 botmux
> 起因：用户要求「把 botmux 作为 ccconfig 的 option-* 功能增加，ccbridge 项目不动作为参考」

## 为什么换

ccbridge 是 npm 包 `lark-channel-bridge` 的管理壳，其上游 **已停更约 2 个月**：

| 事实 | 证据 |
|------|------|
| 仓库改名 | `zarazhangrui/feishu-claude-code-bridge` → `lark-coding-agent-bridge`（API 301） |
| 最后 push | 2026-08-31（`gh api` `pushed_at`） |
| 最后发版 | npm `0.7.1` = 2026-09-01，此后 56 天无新版 |
| issue 堆积 | **272 open**（140 issue + 131 PR）vs 历史仅 merged 21 PR；2026-07-23 后再无 PR 合并 |
| owner 活跃度 | 自 2026-05 起零代码 commit（维护权易手社区后也停） |
| fork 生态 | 449 forks 最高仅 5★，无活跃替代分支 |

上游未修的关键 bug（全 open）：WS 半开静默失聪（#244）、`pingTimeout` 写死 3s 误杀健康连接（#252）、飞书卡片 10 分钟后强制 finalize 导致更新静默丢弃（#289，26 天日志 `ws-stuck` 628 次）、agent 决策卡回调 100% 失效（#334）、keystore KDF 绑 hostname 改主机名即永久不可解（#154/#291）、`claude -p` 无 `AskUserQuestion` 导致流截断（#62）。

**botmux**（`deepcoldy/botmux`，MIT，1775★，近乎日更）：自包含单文件二进制（运行不依赖本机 Node），每会话独立 CLI 进程 + 实时流式飞书卡片，一次扫码建应用+配权限+发版，支持 `/adopt` 接管跑了一半的会话、`/relay` 搬运上下文、Web 终端。

## 改了什么

**新增 `option-botmux/`**：
- `init.sh` — 状态/安装/更新/setup/start/stop/restart/logs/sessions/dashboard/menu
  - `--status` 首行 `OK|WARN|MISSING botmux …`（供 init-option 解析），退出码 0/1/2 对应三态
  - `--install` 走 `npm i -g botmux`（含 ~130MB 平台二进制）+ 补 `~/.local/bin` 链接
  - dry-run 判定置于函数最前（已安装时也要能 dry-run，不被 early-return 吃掉）
  - sessions 非 TTY 自动 `--plain`
- `README.md` — 用法、状态语义、前提（含「一个应用只能挂一套长连接」）、配置落点

**接线点改动**：

| 文件 | 改动 |
|------|------|
| `init-option.sh` | 分组 `--飞书--|larkcli botmux`；`_interactive_install_args` 加 botmux→`--install`；`--yes` 分支加 botmux（装二进制，扫码留给用户）；旧名 `larkbridge` 转发到 botmux |
| `lib/menu-data-maintain.sh` | 5 分区新增 5G 桥状态 / 5H 启动 / 5I 会话列表 |
| `maintain.sh` | 新增 `botmux` 子命令；用法串补 `botmux` |
| `lib/status.sh` | `--lark--` 组 `ccbridge` → `botmux`；删旧的 lark-channel-bridge 单行状态段，改 botmux；`other_list` 排除名单加 `botmux`（否则在 `--lark--` 与 `--other--` 重复显示） |
| `lib/deps-check.sh` | 可选依赖 `lark-channel-bridge` → `botmux` |
| `lib/path-helper.sh` | 删无调用方的 `resolve_ccbridge()`（botmux 走 PATH 查找，无需路径解析） |
| `README.md` | mermaid 图加 `optBotmux` 节点与边；目录树加一行 |

**新增 `tests/test-botmux-option.sh`**（18 项）：语法/可执行、`--status` 契约（首行格式 + 退出码 0/1/2 + 无 ANSI）、接线完整性、旧名转发、ccbridge 已摘除、dry-run 安全、非 TTY 不阻塞。

## 接线途中修掉的两处坑

1. **`other_list` 重复显示**：`lib/status.sh` 的 `--other--` 组由 `ls option-*/` 自动发现，排除名单是手写的 `grep -vE '^(larkcli|getnote|…)$'`。新增 botmux 后没加进排除名单 → 它同时出现在 `--lark--` 和 `--other--`。已补 `botmux`。

2. **菜单 action 里不能出现 `|`**：botmux 状态项要把三态退出码（WARN=1/MISSING=2）吞掉，否则菜单报「执行失败」。第一版写成 `… --status || true` —— **`|` 是 `MENU_ENTRIES` 的 5 字段分隔符**，直接撕裂 schema（`tests/test-maintain.sh` §4 抓出"字段数不对"）。第二版写 `bash -c "…; exit 0"` 也不行：§6 校验 action 首词必须是**已定义函数名**或 `bash "$VAR/path"` 形式。最终解 = 在 `maintain.sh` 定义 `do_botmux_status()` 包装函数（吞退出码），action 引用它 —— 与既有 `do_highpriv` / `do_self` 同模式。

## ccbridge 的处置

**仓库保留不动**（`~/git/ccbridge`，用户要求作参考）；`lib/sync.sh` 的 `PERSONAL_REPOS` 仍含 `ccbridge`（仓库还在、仍会同步）。ccconfig 侧**不再有任何 ccbridge 接线**，仅 `init-option.sh` 保留一条旧名 `larkbridge` → botmux 的转发（防既有脚本/肌肉记忆报"未知选项"）。

## 验证

```
bash tests/test-botmux-option.sh    → PASS 18 / FAIL 0
bash tests/test-maintain.sh         → PASS 68 / FAIL 0
bash tests/test-init-option.sh      → PASS 17 / FAIL 0
bash tests/test-syntax.sh           → PASS 87 / FAIL 0
bash tests/test-init-base.sh        → PASS 40 / FAIL 0 (SKIP 1)
全 32 个测试套件                     → 全部通过，0 失败
```

端到端实测（pty 下）：`botmux setup add --create-app …` 正常拉起飞书开放平台扫码流程（输出真实二维码），未留半成品（`setup list --json` 为 `[]`）。**扫码建应用需用户本人完成**（需要飞书账号授权），故未代为执行。

## 下一步（需用户操作）

```bash
bash init-option.sh botmux setup    # 扫码建飞书应用（用专用 app，勿与 lark-cli 共用 appId）
bash init-option.sh botmux start    # 启动 daemon
botmux autostart enable             # 开机自启
```

---

# 追加（2026-10-28）：一条龙引导 —— 消除「手动跑 setup」这道坎

> 起因：用户反馈「botmux 显示未配置飞书应用，需要手动执行，太麻烦了」。
> 目标：`maintain 2D` 装完 botmux 后，**能选择直接进配置流程**，并引导走完。

## 加了什么

**`option-botmux/init.sh` 新增 `do_guide`（一条龙引导）**，三步：

1. **收 owner**（`_read_owner`）—— botmux 的 `--allowed-users` 是必填且不交互询问，故引导自己收集。
   校验接受 `邮箱 / 手机号 / on_xxx union_id`；**拒绝 `ou_xxx`**（open_id 是别的 app 签发的，新建应用认不出）。
   格式错**重问**（最多 3 次），不打断整个引导。
2. **扫码建应用** —— 前置 `has_tty` 检查（非 TTY 下 botmux setup 直接退出、不产二维码）；打印扫码须知（链接 10 分钟有效、单人单次、自动配权限发版、应用是专用的）。
3. **启动 daemon + 问开机自启**。

**接在装完处**：`do_install` 末尾调 `_offer_setup_and_start` —— 交互环境问「现在就配置飞书应用（扫码→启动→自启一次做完）？[Y/n]」，非 TTY / NONINTERACTIVE 只打印指引不问（批处理安全）。

**入口**：`bash init-option.sh botmux guide`（或 `maintain.sh` 菜单 5H）；`init.sh menu` 第 1 项也是引导。

## 途中修掉的 3 个真 bug

1. **P0 — `option-botmux/init.sh` 有两个 `case "${1:-}"` dispatch 块**（编辑时旧块没被替换掉）。第一个块 `exit 1` 落到第二个块，而 `$1` 已被 `shift` 成空 → 匹配 `menu|""` → **所有 `init.sh <子命令>` 静默变成进菜单**。测试 6e 加了「dispatch case 块唯一」守卫。
2. **owner 校验漏判** —— 第一版只匹配 `ou_` **开头**，`bad_openid_ou_xxx` 这种中间含 `ou_` 的漏过去了。改成白名单式（邮箱/手机号/on_ 三选一，其余拒绝）。
3. **升级瞬间误报「未安装」** —— `botmux upgrade` / `npm i -g` 期间 `$LOCAL_BIN` 的 symlink 有短暂失效窗口，裸 `command -v` 会判成未装（实测撞到过：菜单显示 ✗ 而同一条命令直调正常）。新增 `_botmux_bin()` 两级兜底（PATH → npm prefix launcher → 平台子包二进制），所有调用改走 `bmx()` 包装。

## 测试

`tests/test-botmux-option.sh` 从 18 项扩到 **24 项**，新增第 6 节「引导向导」：
非 TTY 明确拒绝、dispatch 含 guide 分支、`do_install` 末尾接引导、NONINTERACTIVE 不弹询问、**dispatch case 块唯一**、菜单含引导项。

```
bash tests/test-botmux-option.sh  → PASS 24 / FAIL 0
全 33 个测试套件                   → 全部通过
```

pty 实测（模拟真实交互）：`init-option.sh botmux` → 答 y 进引导 → owner 输入两次错误格式（`ou_xxx` / `garbage`）被拒并重问 → 第三次 `me@example.com` 通过 → 进入扫码步骤。全程无卡顿、无残留配置。