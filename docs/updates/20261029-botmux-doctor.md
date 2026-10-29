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

## 追加：底层 CLI 依赖层

`aiden` 那条次因暴露了一个更普遍的问题：**botmux 只桥接，不负责装它要驱动的 CLI**。
装了 botmux 但没装底层 CLI = 静默失败（daemon 全绿、飞书零反馈），新用户踩中概率高。

### aiden 是什么（调查结论）

- botmux 内建的**本地 CLI 适配器**，`resolvedBin` = 命令 `aiden`
- 字节内部工具：源码 `src/adapters/cli/aiden.ts`；二进制里 `authPaths` 含
  `~/.local/share/bytedcli`、`byted-cloud-auth.json`（字节统一登录 bytedcli 生态）
- 启动参数 `--permission-mode agentFull`（非 Claude 的 `--dangerously-skip-permissions`）
- 内建 `bytedcli` 登录流程与 login-shell PATH identity shim

**⚠️ 装不了，且不能乱装**：botmux 公开文档在「套 wrapper / 网关」一节明确写
「**不在公开仓库内放内部文档链接或复制原文**」，适配器表里 aiden 也只有一行
「Aiden 本地进程」——**整个公开文档没有任何安装说明**。本机实测：
`bnpm.byted.org` / `registry.npm.byted.org` 等内部源全部不可达（HTTP `000`）。
而**公网 npm 上的 `aiden@0.0.3`（2025-01，作者 ebeloded）是同名无关包**——
`npm i -g aiden` 会装错东西。

### 变更

| 位置 | 变更 |
|---|---|
| `lib/doctor.sh` | 新增 `_bmx_cli_install_pkg`（cliId → 公开 npm 包）；检查项区分「公开可装 / 仅内部渠道 / 非 CLI 型」；`fix` 可确认后自动 `npm install -g` |
| `init.sh` | 新增 `_bmx_hint_base_cli`：`do_install` 装完检测底层 CLI，缺 claude 则提示 + 列出可选 CLI 命令；已装则静默 |
| `README.md` | 新增「底层 CLI 是前置依赖」表，标注内部渠道与同名包陷阱 |
| `tests/test-botmux-option.sh` | 新增第 13 组 9 项（含「内部渠道不得发假包名」的实测断言） |

### 设计取舍

- **不代装 CLI**：选哪个 CLI 是用户的路由决策（涉及内网网关、成本、合规），
  cconfig 不替他定。`do_install` 只提示，`fix` 要先确认。
- **宁可不说，不给错命令**：只有实测 `npm view <pkg> version` 可解析的包才写进表；
  内部渠道单列 `__INTERNAL__`，未知的单列 `__UNVERIFIED__`。

## 追加 2：aiden 深查结论（含 botmux 3.55.0 复核）

用户反馈「botmux UI 里**有** aiden 这个选项，切了报错要安装」——矛盾查清：

1. **UI 只列适配器 + 只探测，不代装**。3.54.0 与 **3.55.0 均无** `installCli`/`autoInstall`；
   它跑 `$SHELL -lc/-ic` + `command -v <exe>`，缺了标 unavailable + 文案
   `botOnboarding.cliMissingHint`「当前机器找不到 {command}，请先安装或修正 daemon 的 PATH」。
   **选项是静态适配器清单，报错是探测结果。**
2. **`/login bytedcli` 是身份注入，不是装 CLI**。原文：「这是 ByteCloud 的授权，
   **和飞书 /login 是两回事**」。注入凭据到 `~/.botmux/data/bytedcli-home/<openId>`，
   **不产生可执行文件**。

**aiden 三条硬墙**：① 公开文档刻意不给（`adapters.md` 原文「不在公开仓库内放内部文档
链接或复制原文」）；② 公网 npm 无（`aiden` = ebeloded 的**同名无关包**）；③ **本机内网
域名解析不了**（`bnpm.byted.org` 无 DNS，resolv.conf 只指 Tailscale）。

**aiden 真身**：字节内部**网关/装配启动器**（非普通 CLI）—— `Aiden × Claude` 底层
仍是 `cliId=claude-code`，只加启动前缀 `aiden x claude`。故即便到手，**正确接法是
setup 里的「Aiden × Claude」，不是 `cliId: aiden`**。

**升级复核（3.54.0 → 3.55.0）**：aiden 适配器定义**逐字未变**
（`resolvedBin='aiden'`、`--permission-mode agentFull`、`authPaths` 含 `~/.local/share/bytedcli`
+ `byted-cloud-auth.json`）。**结论不因升级改变。**

> 升级过程踩坑：`botmux upgrade` 内部走 `npm install botmux@latest`，与**正在运行的
> daemon 抢同一个 130MB 二进制** → `Text file busy` + 留下半成品目录
> （`.botmux-*`）。且 npm 从 registry.npmjs.org 拉大文件**极慢**（实测卡 12 分钟无进展）。
> 正确姿势：先停 daemon → 清 `.botmux-*` 临目录 → 官方源（**不能用 npmmirror**，
> 它没同步平台子包 `botmux-linux-x64`，会报 `no prebuilt binary package`）重装。

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
8. **`npm i -g aiden` 会装到无关包** —— 公网 `aiden@0.0.3`（作者 ebeloded）与
   botmux 要的字节 Aiden 毫无关系。**内部渠道适配器绝不给 npm 命令**，
   只报「仅仅内部渠道发行」。