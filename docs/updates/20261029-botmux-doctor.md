# option-botmux 健康体检（doctor / fix）

日期：2026-10-29
组件：`option-botmux`
触发：用户报告「飞书上跟 botmux 说话都没有反馈」

## 症状与真因

### 症状
`botmux status` 显示 supervisor 与 botmux-0、botmux-dashboard 三个进程全部 `online`，
版本 3.54.0，长连接正常。但飞书里对 bot 发消息**毫无反应**，且 `botmux list`
仍列出一个「活跃会话」，看起来一切正常。

### 排查过程（证据链）

| 证据 | 命令/文件 | 结论 |
|---|---|---|
| pane 已死 | `tmux -L botmux list-panes -F '#{pane_dead}'` → `1` | 会话前端没了 |
| worker 卡死 | `/proc/1163349/stat` state = `D`，`wchan` = `anon_pipe_write` | 不可中断 I/O，信号无效 |
| 自锁成因 | `/proc/1163349/fd` → fd 11 读 + fd 12 写**同一个 FIFO** | 进程自持读写端 → 读者永不消失 → 写完缓冲区后永久阻塞 |
| 队列积压 | `~/.botmux/data/queues/oc_….jsonl` 10 行 | 消息进来但无人消费 |
| 运行时记录丢失 | `botmux observe --session …` → `probe.status: not_found` | daemon IPC 已不认这个会话 |
| botmux 自证 | 日志 `worker did not exit after SIGTERM; escalating to SIGKILL` | 确认 worker 无响应 |

时序（UTC，本地 = UTC+8）：

```
23:44:36  pane 死亡（status 143 = SIGTERM）
23:46:41  飞书 /botconfig set cli: claude-code -> aiden   ← 在 pane 死之后
00:50:20  最后一条消息进队列（本地 08:50）
01:11     delete 会话：SIGTERM 无效 → 升级 SIGKILL
01:12     restart daemon → 新 supervisor 起，卡死 worker 消失
```

**两个独立故障叠加**：
1. **worker 卡死 + pane 已死** → 消息积压无人消费（主因，造成零反馈）
2. **`cliId` 被改成 `aiden`，但本机根本没装 aiden** → 即便会话恢复，也起不来 CLI

### 结构性教训

> **`botmux status` / `list` 只反映 daemon 与 supervisor 存活，不反映
> 「会话能否真的干活」。** 这正是本次故障全程「状态全绿」的原因。
> 健康检查必须自己补：会话健康（pane 死活 / worker 状态）、队列积压、
> 长连接、`cliId` 可执行性。

## 变更

### 新增 `option-botmux/lib/doctor.sh`

五项检查 + 自动修复：

| 函数 | 检查内容 |
|---|---|
| `_bmx_check_bots` | `allowedUsers` 空值；`cliId` → 可执行名是否真装了；`cliPathOverride` 有效性；`cliRuntime` 跳过而非误报；`wrapperCli`/`cliLaunchMode` 网关提示 |
| `_bmx_check_sessions` | tmux pane `pane_dead`；worker `/proc/$pid/stat` 状态 `D` |
| `_bmx_check_queue` | 队列行数；**有积压但无活跃会话 = 死锁**（有会话则属正常消费中） |
| `_bmx_check_upstream` | `Daemon WSClient started`（长连接）；`worker did not exit after SIGTERM`；`Ignored unbound input commit`；VC 权限缺口；`runtime-sweep` 残留噪音 |
| `_bmx_check_version_drift` | 从二进制现扫 `cliId` 集合，与本脚本表比对 —— 上游加适配器时能自动发现 |

`bmx_doctor_fix` 三项修复，改配置前一律先问，非交互只提示：
1. `cliId` 指向未安装 CLI → 给两条修法（装它 / `/botconfig set cli claude-code`）
2. 卡死 worker（`D` 状态）→ 重启 daemon
3. 队列积压 → 备份到 `~/.botmux/data/queues.bak/` + 清空 + 重启

### 接线

| 位置 | 变更 |
|---|---|
| `option-botmux/init.sh` | `source lib/doctor.sh`；新增 `do_doctor`/`do_fix`；分发器加 `doctor`/`fix` 分支；菜单首项改为「体检 + 自动修复」并顺延后续序号 |
| `maintain.sh` | 新增 `do_botmux_doctor`（吞 rc，防 set -e 陷阱） |
| `lib/menu-data-maintain.sh` | 新增 `5\|J\|botmux 体检（无反馈）` |
| `lib/status.sh` | 飞书段补体检指引；`--lark--` 分支在 `OK` 基础上叠加队列积压探测（有积压则降级为 warn 并提示跑 doctor） |
| `lib/update.sh` | botmux 升级后自动跑一次体检，有问题则告警并给命令 |
| `option-botmux/README.md` | 新增「飞书发消息没反馈？先跑体检」与「配置输入输出显示」两节 |
| `tests/test-botmux-option.sh` | 新增第 12 组 26 项 doctor 回归测试 |

### 上游适配器表（从 v3.54.0 二进制提取）

`cliId` → 本机可执行名，用于「CLI 是否真装了」判定：

| cliId | 命令 | cliId | 命令 |
|---|---|---|---|
| `claude-code` | `claude` | `mir` | `mircli` |
| `codex` | `codex` | `oh-my-pi` | `oh-my-pi` |
| `aiden` | `aiden` | `pi` | `pi` |
| `traex` | `traex` | `dsh` | `dsh` |
| `coco` | `coco` | `dsh-tui` | `dsh-tui` |
| `gemini` | `gemini` | `codex-app` | （桌面 App，无 CLI） |
| `opencode` | `opencode` | `mira` | （Web API，无 CLI） |
| `opencode2` | `opencode2` | `riff` | （内建原生 agent，无 CLI） |
| `cursor` | `cursor` | | |

另有 `botmux-gateway`、`unknown` 两个**内部哨兵值**，不是适配器，
但会出现在二进制的 `cliId:"…"` 文本里，故漂移检测的白名单需包含它们，
否则误报「未收录」。

## 实测踩坑（本次新增）

1. **`IFS=$'\t'` 不能用来解析含空字段的 TSV** —— tab 属空白字符，`read` 会把
   连续 tab 塌缩，导致列错位（本次把 `wrapperCli` 读成了 `allowedUsers`，
   报出「cliPathOverride: no」这种荒谬结果）。**改用 python 直接输出结论行**。
2. **`set -e` + 检查函数末尾的 `[ -n "$x" ] && cmd`** —— 条件不成立时返回 1，
   整个脚本静默中止。症状：doctor 只打印了第一段就没了。**所有对外函数末尾必须 `return 0`**。
3. **`ERR/WARN` 计数器跨子 shell 丢失** —— `... | while read` 的 while 在子 shell 里，
   计数改动传不回父 shell。**必须用 `< <(...)`**。已加测试固化。
4. **launcher ≠ 真二进制** —— `command -v botmux` 拿到的是 npm launcher（128 字节脚本），
   里头没有预设表，扫 `cliId` 永远为空。**必须解析到 `botmux-linux-x64/botmux`（~133MB）**，
   用 1MB 阈值判定。
5. **`grep -E` 下交替写 `\|` 是错的** —— `\|` 在 ERE 里是字面竖线，不是 or。
   测试里踩到，导致两个断言恒假。
6. **菜单 `TITLE_W=24`** —— 标题超宽 renderer 无法收缩，会让 `cmd` 列错位，
   被 `test-maintain.sh` 第 10 组抓到。新菜单项标题宽度必须 ≤24 显示列（CJK 记 2）。
7. **worker 卡 D 状态时 `botmux delete` 会超时** —— 信号无效，命令挂住
   （实测 `timeout 30 botmux delete` 被 kill）。**唯一解是重启 daemon**。