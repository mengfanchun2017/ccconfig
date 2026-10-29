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

## 追加 2：aiden 深查结论 + CodeM 接入

用户反馈「botmux UI 里**有** aiden 这个选项，我切了报错要安装，你却说没有」——
这个矛盾查清了。

### 矛盾的解释

botmux 的 UI 与「装 CLI」是两件事：

1. **UI 只列适配器、只做可用性探测，不代装**。二进制里搜不到 `installCli` /
   `autoInstall`。它对每个适配器跑 `$SHELL -lc/-ic` + `command -v <exe>`，
   找不到就标 unavailable，并用文案 `botOnboarding.cliMissingHint`「当前机器找不到
   {command}，请先安装或修正 daemon 的 PATH；未就绪前不能创建 Bot」。
   （对比：它对 lark-cli 缺失会提示 `npm i -g @larksuite/cli` —— 那是**文案**，不是自动装。）
2. **`/login bytedcli` 不是装 CLI，是身份注入**。文案原文：「这是 **ByteCloud
   的授权，和飞书 /login 是两回事**，两边都要授权一次」；登录态约 3 周，
   派生 JWT 1~2 小时。它给 session 注入 `BYTEDCLI_USER_CLOUD_JWT` 等凭据
   （每人独立 HOME `~/.botmux/data/bytedcli-home/<openId>`），**不产生任何可执行文件**。

所以「有选项」≠「能装」：选项是适配器清单（静态内置），报错是探测结果（缺 `aiden` 文件）。

### aiden 为什么装不上（三条硬墙）

| 墙 | 证据 |
|---|---|
| 公开文档刻意不给 | botmux `adapters.md` 原文：「各网关的**具体 wrapper 脚本**…**这里不在公开仓库内放内部文档链接或复制原文**」。适配器表里 aiden 唯独没有 `docs/xxx.md` 链接 |
| 公网 npm 不存在 | `aiden` = v0.0.3/ebeloded「AI-powered CLI tool」（**同名无关**）；`aiden-cli` / `cjadk` / `@bytedance-dev/bytedcli` 全 404 |
| 本机内网不通 | `bnpm.byted.org` / `bnpm.bytedance.com` **无 DNS 解析**（本机 resolv.conf 只指 Tailscale `10.255.255.254` + tailnet search domain）。内网 IP `10.150.224.182:18080` 端口虽通，但**内网域名解析不了** → 装不了内网 npm 包 |

**aiden 的真身**：字节内部「网关/装配启动器」，**不是普通 CLI**。源码
`src/setup/cli-selection.ts` 注释：`Aiden × Claude → 底层 cliId=claude-code，
启动前缀 aiden x claude`；`Aiden × Codex → cliId=codex + aiden x codex`。
即它是**套在真 CLI 外面的模型/网关层**（所以 botmux 专门写逻辑剥掉它拒收的
`--settings`、`-c`）。同族内部 CLI：`kaboo-cli` / `aiden-cli` / `cjadk` / `bytedcli`
（四个平级，登录态写 keychain，全在内网）。

> **重要**：即便某天 aiden 到手，正确接法是 botmux `setup` 里的
> **「Aiden × Claude」**选项（= `cliId: claude-code` + `wrapperCli: "aiden x claude"`），
> **不是** `cliId: aiden` —— 后者走它的原生 agent 模式，另一套参数。
> 且 aiden 不给 claude-code 加任何新能力，它的价值只是**拿内部额度调模型**。

### CodeM 接入（新增可行路径）

用户直觉「飞书自己的兼容性会更好」——**对的**，且这条路公网可装：

- **CodeM** = 飞书官方 AI 研发智能体（CLI + Bot + 桌面 App + Web 后台，2026-07 发布）
- 实测可达：安装脚本 `codem-public.tos-cn-beijing.volces.com/codem/install.sh`
  **HTTP 200**（102KB）；npm `@lark-codem/codem-cli` **200**（实装到 0.1.249）
- **botmux 已内建一等适配器**：源码 `SEH()` 做
  `existsSync(~/.codem/bin/codem) ? 该路径 : "codem"`（**路径优先、PATH 兜底**），
  `authPaths: ["~/.codem"]`。故装完 botmux 无需配 PATH 就能认。

已在本机实装验证：`~/.codem/bin/codem` → `0.1.249 (CodeM)`，
`codem auth status` → `{"loggedIn": false, "serverUrl": "https://codem.feishu.cn"}`
（**登录需企业已开通 CodeM 权益 + 扫码**，无法代做）。

doctor/init 的 CLI 依赖层已把 codem 单列 `__CODEM_SH__`（走官方脚本而非
`npm -g` —— 它装进版本化目录 `~/.codem/runtime/versions/<ver>/` + 指针启动器，
`npm -g` 造不出那个布局）。

### 取舍对比

| | botmux + claude-code | botmux + CodeM | aiden |
|---|---|---|---|
| 可装性 | ✅ 已跑通 | ✅ 公网可装（需企业权益） | ❌ 内网 + 内部文档 |
| 模型 | **自带**（可换任何） | **锁定 CodeM 通道** | 内部额度（唯一诱因） |
| 兼容性 | 第三方桥，上游改版会断 | **官方原生，Bot 在飞书内** | 官方内部 |
| 成本 | 免费 | 企业付费（预览期） | 内部额度 |
| 成熟度 | 稳 | 官方标「预览」，迭代快 | 活跃内部件 |

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