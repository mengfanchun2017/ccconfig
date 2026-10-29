# 0057. 飞书 ↔ AI CLI 桥选型：botmux 取代 ccbridge，aiden 判死，CodeM 弃用

> **Status**: ✅ Accepted
> **日期**: 2026-10-29
> **关联**: `option-botmux/`（`init.sh`、`lib/doctor.sh`、`README.md`）、`init-option.sh`、`maintain.sh`、`lib/menu-data-maintain.sh`、`lib/status.sh`、`lib/update.sh`、ADR [0006](0006-feishu-communication-strategy.md)、[0050](0050-bridge-structural-refactor.md)、[0054](0054-external-harness-bridge-anthropic-only.md)
> **模板**: MADR 4.0 极简版
> **取代**: [ADR-0006](0006-feishu-communication-strategy.md) 中关于「ccbridge 作为飞书↔CLI 桥」的部分

## Context and Problem Statement

用户要把「在飞书里遥控本机 AI 编程 CLI」这件事做成 ccconfig 的长期组件。
三个阶段逐步逼近结论：

1. **选桥**：旧 `ccbridge`（封装 npm `lark-channel-bridge`）是否还值得续用？
2. **落地后的真实故障**：飞书里发消息**零反馈**，但 `botmux status` / `list` 全绿。
3. **适配器选型**：`aiden`（字节内部）与 CodeM（飞书官方）到底能不能用、该不该用。

三条都涉及「以后不再重查」的判断，故合并立此 ADR。

## Decision Drivers

- **D1 可长期维护**：上游是否活跃。桥是长期基础设施，上游停更即等于技术债。
- **D2 架构简单**：组件越少、链路越短越好；能自包含就不引入 Node 依赖链。
- **D3 故障可诊断**：出问题时**能否被本地检查发现**，而不是靠人肉翻日志。
- **D4 不绑定不可得资源**：不能把核心能力挂在拿不到的东西上（内部渠道、企业权益）。
- **D5 可自带模型**：用户已有自建 LLM 通道（bridge），不应被桥强制锁模型。

## Considered Options

### 桥的实现

1. **续用 ccbridge** — 已有实现、功能完整；但上游 `lark-coding-agent-bridge` 停更 2 月、272 open issues、无活跃 fork。**违反 D1**。
2. **Claude Code 原生 Remote Control** — 官方、零第三方依赖；但硬性要求 claude.ai 订阅 + `ANTHROPIC_BASE_URL` 指向 api.anthropic.com + `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` 未设，用户环境**两条都撞上**，被网关门禁挡死。**不可行**。
3. **botmux** — 近乎日更、MIT、自包含单文件二进制（内嵌 PTY，运行不依赖本机 Node）、多适配器、可 BYO。**满足 D1/D2**。

### 适配器（底层 CLI）

1. **`claude-code`** — 公网 npm 可装、可自带模型、免费。**满足 D4/D5**。
2. **`aiden`**（字节内部网关） — 唯一价值是「拿内部额度调模型」。**违反 D4**。
3. **CodeM**（飞书官方 AI 研发智能体） — 官方原生、飞书内闭环；但**模型通道锁定**（不能用自带 Claude）+ **需企业购买权益**。**违反 D5**。
4. **其他公网适配器**（codex / gemini / opencode / copilot / kimi / grok…） — 均可装，但相对 `claude-code` 无额外收益，只增加故障面。

## Decision

1. **桥用 botmux**，作为 `option-botmux/` 接入 ccconfig；ccbridge 仓库保留作参考、不再接线。
2. **底层 CLI 用 `claude-code`**，不用 aiden、不用 CodeM。
3. **新增 doctor 体检层**（`option-botmux/lib/doctor.sh`），补上 botmux 自带状态命令的盲区。
4. **菜单归 `6 远程/桥接`**（非 `5 rag`），4 项合并为 2 项。

## Consequences

### 关于桥的选择

- ✅ botmux 上游活跃（版本 3.54.0 → 3.55.0 实测可升）；自包含二进制，无 Node 运行时依赖链。
- ✅ 记录可查：daemon + 会话落盘 + Dashboard。
- ⚠️ **飞书长连接不广播** —— 同一 appId 只能有一套长连接，故 botmux **必须独占专用应用**，不能与 lark-cli 共用 appId（否则互抢消息）。**缓解**：文档与引导里明确「专用应用」约束。

### 关于「状态全绿但零反馈」这一核心盲区

实测故障（2026-10-29）：`botmux status` 三个进程 `online`、`list` 还列着「活跃会话」，
但飞书里发消息**毫无反应**。真因是两条叠加：

| 信号 | 证据 | 含义 |
|---|---|---|
| pane 已死 | `tmux list-panes -F '#{pane_dead}'` → `1` | 会话前端没了 |
| worker 卡死 | `/proc/<pid>/stat` state=`D`，`wchan=anon_pipe_write` | 不可中断 I/O，`SIGKILL` 无效 |
| 自锁成因 | `/proc/<pid>/fd` 中 fd 11 读 + fd 12 写**同一 FIFO** | 进程自持读写端 → 读者永不消失 → 缓冲写满后永久阻塞 |
| 队列积压 | `~/.botmux/data/queues/*.jsonl` 10 条 | 消息进来了，无人消费 |
| 运行时记录丢失 | `botmux observe --session <id>` → `probe.status: not_found` | daemon IPC 已不认该会话 |
| botmux 自证 | 日志 `worker did not exit after SIGTERM; escalating to SIGKILL` | 确认 worker 无响应 |

**结构性结论**：> **`botmux status` / `list` 只反映 daemon 与 supervisor 存活，不反映「会话能否真的干活」。**

- ✅ 新增 `doctor` 五项检查补齐该盲区：配置（`allowedUsers` 空值 / `cliId` 指向的 CLI 是否真装了 / `cliPathOverride` 有效性 / `cliRuntime` 跳过）/ 会话健康（`pane_dead` + worker `D` 状态）/ 队列积压（**有积压但无活跃会话 = 死锁**）/ 上游（`Daemon WSClient started`、worker SIGTERM 无响应）/ cliId 表漂移（现扫二进制比对）。
- ✅ `fix` 三项修复，改配置前一律先问，非交互只提示。
- ❌ `worker` 卡 D 状态时 `botmux delete` 会超时（信号无效），**唯一解是重启 daemon**。

### 关于 aiden（判死）

**矛盾的解释**：用户反馈「UI 里**有** aiden 选项，切了报错要安装」—— 与「装不了」不矛盾：

1. **UI 只列适配器 + 只探测，不代装**。二进制里搜不到 `installCli` / `autoInstall`。它跑 `$SHELL -lc/-ic` + `command -v <exe>`，找不到就标 unavailable + 文案 `botOnboarding.cliMissingHint`「当前机器找不到 {command}，请先安装或修正 daemon 的 PATH」。**选项是静态适配器清单，报错是探测结果。**
2. **`/login bytedcli` 不是装 CLI，是身份注入**。原文：「这是 ByteCloud 的授权，**和飞书 /login 是两回事**」。注入凭据到 `~/.botmux/data/bytedcli-home/<openId>`，**不产生任何可执行文件**。

**三条硬墙**（任一即可判死，实际三条都成立）：

| 墙 | 证据 |
|---|---|
| 公开文档刻意不给 | botmux `adapters.md` 原文：「各网关的**具体 wrapper 脚本**…**这里不在公开仓库内放内部文档链接或复制原文**」。适配器表里 aiden 唯独没有 `docs/xxx.md` 链接 |
| 公网 npm 无 | `aiden` = v0.0.3 / ebeloded「AI-powered CLI tool」（**同名无关**）；`aiden-cli` / `cjadk` / `@bytedance-dev/bytedcli` 全 404 |
| 本机内网域名不解析 | `bnpm.byted.org` / `bnpm.bytedance.com` **无 DNS**（本机 `resolv.conf` 只指 Tailscale `10.255.255.254` + tailnet search domain）。内网 IP `10.150.224.182:18080` 端口虽通，但**域名解析不了** → 装不了内网 npm 包 |

**升级复核（3.54.0 → 3.55.0）**：aiden 适配器定义**逐字未变**
（`resolvedBin='aiden'`、`--permission-mode agentFull`、`authPaths` 含 `~/.local/share/bytedcli`
+ `byted-cloud-auth.json`）。**结论不因升级改变。**

**aiden 真身**：字节内部**网关/装配启动器**，**不是普通 CLI** —— `Aiden × Claude` 底层仍是
`cliId=claude-code`，只加启动前缀 `aiden x claude`。故即便某天到手，**正确接法是 setup 里的
「Aiden × Claude」选项（`cliId=claude-code` + `wrapperCli`），不是 `cliId: aiden`**。

- ✅ **判死**：aiden 不作为受支持路径。`doctor` 把 `aiden`/`traex`/`coco` 归入 `__INTERNAL__`，**拒绝给出 npm 命令** —— 因为 `npm i -g aiden` 会装到无关包，比"不给命令"更糟。
- ⚠️ **反向关系澄清**：`claude-code` 与 `claude+aiden` 的差别不是"两个 CLI"，而是**裸跑 vs 套网关**（底层同一个 Claude Code）。aiden 外层**不加任何功能**，唯一价值是内部额度计费。

### 关于 CodeM（弃用）

CodeM = 飞书官方企业级 AI 研发智能体（CLI + Bot + 桌面 App + Web 后台）。实测**公网可装**
（安装脚本 HTTP 200、npm `@lark-codem/codem-cli` 200），且 botmux **已内建一等适配器**
（源码 `existsSync(~/.codem/bin/codem) ? 该路径 : "codem"`，路径优先、PATH 兜底）。

- ❌ **弃用理由（D5 + D4）**：**模型通道锁定**（不能用自带 Claude 通道）+ **需企业购买权益**（飞书 AI 套餐量级 ¥99,000/年）。
- ✅ **清除干净**（用户决定不用内部产品）：`~/.codem`（269MB）、`~/.bashrc` / `~/.profile` 的 PATH 行、ccconfig 里全部 codem 引用（doctor 分支 / EXEC / PKG 表项 / 测试断言 / README 段落）。备份 `~/.bashrc.bak.codem-clean` / `~/.profile.bak.codem-clean`（**未完成登录，无凭据残留**）。
- 注：**ByteCloud**（字节内部云控制面，`bytedcli --site` 即选它）与 **火山引擎**（字节对外商用云）是同源的**内/外两条线**，本机从无 ByteCloud 痕迹。

### 关于菜单归类

- `5 rag` 是**检索类**（lark 文档/表格 + getnote 笔记），共性是「读写远端知识库」。
- botmux 本质是「**从飞书这个远端入口，遥控本机 CLI**」，与 SSH、tailscale 是**同一类**（远端接入本机）。
- ✅ 归 `6 远程/桥接`（分类名从「远程」改为「远程/桥接」，给 IM 桥明确位置）；`5 rag` 从 8 项降到 6 项，分类变纯粹。
- ✅ 4 项合并为 2 项：
  - `6C botmux 桥状态体检` = 原「桥状态」+「体检」——状态那行**本就是体检的头部摘要**，单列纯重复。
  - `6D botmux 桥配置管理` = 原「桥配置（引导）」+「管理菜单」——菜单第 1 项本身就是一条龙引导，已覆盖。

## Implementation

| 文件 | 变更 |
|---|---|
| `option-botmux/init.sh` | 新增组件（status/install/update/guide/manual/setup/start/stop/restart/logs/sessions/dashboard/doctor/fix/menu）；`_botmux_bin()` 三级兜底（PATH → npm prefix launcher → 平台子包）；`_bmx_hint_base_cli` 装完提示底层 CLI |
| `option-botmux/lib/doctor.sh` | 新增 —— 五项体检 + 三项修复 |
| `init-option.sh` | 分组 `--飞书--\|larkcli botmux`；botmux 交互安装分支；旧名 `larkbridge` 转发 botmux |
| `maintain.sh` | `botmux` 子命令；`do_botmux_status` / `do_botmux_doctor`（吞三态 rc，防 set -e 陷阱） |
| `lib/menu-data-maintain.sh` | `6C` 桥状态体检 + `6D` 桥配置管理；`CAT_NAME[6]="远程/桥接"` |
| `lib/status.sh` | 飞书段补体检指引；`OK` 基础上叠加队列积压探测（有积压降级 warn） |
| `lib/update.sh` | botmux 升级段 + 升级后自动体检 |
| `lib/deps-check.sh` | 可选依赖 `lark-channel-bridge` → `botmux` |
| `lib/path-helper.sh` | 删无调用方的 `resolve_ccbridge()` |
| `tests/test-botmux-option.sh` | 83 项（含 doctor 回归、CLI 依赖层、菜单归类断言） |
| `docs/updates/20261029-*` | 3 篇变更日志 |

## Related Decisions

- [ADR-0006](0006-feishu-communication-strategy.md)（`0006-feishu-communication-strategy.md`）— 本 ADR 取代其中「ccbridge 作为飞书↔CLI 桥」的部分；飞书通信的其他结论（lark-cli 作为飞书操作入口、不引入飞书 MCP）不受影响。已在 0006 头部加取代标注。
- [ADR-0050](0050-bridge-structural-refactor.md)（`0050-bridge-structural-refactor.md`）— 同为 bridge 类重构；那个针对 LLM protocol bridge（`openai_bridge.py`），与本 ADR 的 IM↔CLI 桥是**不同层的两件事**。
- [ADR-0054](0054-external-harness-bridge-anthropic-only.md)（`0054-external-harness-bridge-anthropic-only.md`）— 外部 harness 走内网 LLM 的接法；与本 ADR 同属「本机与外部通道对接」问题域。

## Notes

**升级过程踩坑（botmux 3.54.0 → 3.55.0 实测）**：`botmux upgrade` 内部走
`npm install botmux@latest`，与上述决策无关但值得记：

1. 与**正在运行的 daemon 抢同一个 ~130MB 二进制** → `Text file busy`，且留下半成品目录 `.botmux-*`（后续 `ENOTEMPTY` 阻塞）。
2. `registry.npmjs.org` 拉大文件**极慢**（实测卡 12 分钟无进展，连接 ESTAB 但零字节增长）。
3. **不能用 npmmirror 装 botmux** —— 它没同步平台子包，报 `no prebuilt binary package for linux-x64`。
4. 中断会**写坏二进制**（129MB 但 `Bus error` / Bun crash）。**完整二进制应为 188MB**，下载中会看到 57MB / 120MB 中间态，别误判损坏。

正确姿势：先停 daemon（遍历 `/proc/*/cmdline` 精确匹配 `__supervisor|__daemon|__dashboard`，
**别用 `pgrep -f botmux` —— 它会匹配到自己 shell 把自身杀掉**）→ 清 `.botmux-*` → 官方源
`npm_config_fetch_timeout=600000` 重装 → 重建 `~/.local/bin/botmux` 链接。

**待观察**：botmux 版本迭代快（近乎日更），`doctor` 的 `cliId` 表靠**现扫二进制**做漂移检测，
上游新增适配器时能自动发现并提示更新 —— 不必手动跟进。