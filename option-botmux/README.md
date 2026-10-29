# option-botmux — 飞书 ↔ AI 编程 CLI 桥

> botmux = 在飞书里遥控本机的 AI 编程 CLI（Claude Code / Codex / Gemini / …）。
> 一条消息启动一个会话，每个会话一个独立 CLI 进程，输出实时流式回传成飞书卡片；
> 手机、电脑、终端三端同步。会话可用 `/adopt` / `/relay` 接管、搬运，记录可查。

## 为什么是 botmux（而非 ccbridge）

本 option 取代已弃用的 **ccbridge**（`~/git/ccbridge`，仅作参考保留）：

| 维度 | ccbridge（旧） | botmux（现） |
|------|---------------|-------------|
| 底层 | npm `lark-channel-bridge` | 自包含单文件二进制 |
| 上游状态 | **停更 ~2 月**（pushed 2026-08-31，npm 0.7.1=2026-09-01） | 活跃（近乎日更） |
| 上游 issue | **272 open**，关键 bug 全未修（WS 半开静默失聪 / 卡片 10 分钟钉死 / keystore 绑主机名） | — |
| 依赖 | Node + `@larksuite/channel` + 上游壳 | 运行**不依赖本机 Node**（内嵌 PTY） |
| 会话模型 | 单发 `claude -p`，每轮冷启动 | 每会话独立常驻进程，可接管/旁观 |
| 建应用 | 手工申请 scope（自带 feishu-perms.sh） | 一次扫码自动建应用+配权限+发版 |

## 安装（推荐：一条龙引导）

```bash
bash init-option.sh botmux            # 装二进制；装完直接问「现在配置吗？」
# 或在运维菜单: bash maintain.sh → 6D（botmux 桥配置管理）
```

**引导一次走完三步**，不用自己拼命令：

1. **指定 owner** —— 谁有权用这个 bot（完整邮箱 / 手机号 / `on_xxx`）。填错会重问，格式错会提示。
2. **创建飞书应用** —— 终端出二维码，手机飞书 App 扫一下；botmux 自动配齐权限、长连接事件、发版。
   二维码是**实时**画出来的（走 stderr 直通终端），见到就当场扫，别等。
3. **启动 daemon + 询问开机自启**。

完成即可在飞书里私聊该 bot。单步命令（按需）：

```bash
bash init-option.sh botmux guide      # 只跑引导（幂等：已有 bot 则直接到启动步）
bash init-option.sh botmux manual     # 手动建应用（不走扫码）—— SSH/远端场景用
bash init-option.sh botmux setup      # 只建应用（botmux setup 原始交互）
bash init-option.sh botmux start      # 只启动
bash init-option.sh botmux doctor     # 体检（飞书发消息无反馈时先跑这个）
bash init-option.sh botmux fix        # 体检 + 自动修复
bash init-option.sh botmux menu       # 完整管理菜单（启停/日志/会话/Dashboard/升级）
```

## 飞书发消息没反馈？先跑体检

**这是本 option 最容易踩的坑，且 botmux 自带命令看不出来。**

`botmux status` / `botmux list` 只反映 **daemon 与 supervisor 存活**，不反映
「会话能不能真的干活」。2026-10-29 实测故障：`status` 全程显示两个进程 `online`、
长连接正常，但飞书里发消息**毫无反应**。真因是会话的 worker 卡死
（`D` 状态不可中断 I/O，`SIGKILL` 都杀不掉）+ tmux pane 已死，消息只堆进
`~/.botmux/data/queues/*.jsonl` 无人消费。

```bash
bash init-option.sh botmux doctor     # 只体检
bash init-option.sh botmux fix        # 体检 + 自动修复（会先问再改）
# 运维菜单: bash maintain.sh → 6C
```

体检覆盖四类盲区：

| 检查项 | 抓什么 |
|---|---|
| 配置 | `allowedUsers` 是否为空；`cliId` 指向的 CLI **本机是否真装了**；`cliPathOverride` 是否有效 |
| 会话健康 | tmux pane 是否已死；worker 是否卡 `D` 状态 |
| 队列积压 | 无活跃会话却堆着消息 = 死锁的直接症状 |
| 上游 | 飞书长连接是否建立（`WSClient started`）；先前是否出现 worker SIGTERM 无响应 |

`fix` 只做安全且确定的动作，改配置前一律先问；非交互环境只提示不动手。

> **最隐蔽的一种**：`cliId` 指向一个本机没装的 CLI（例如在飞书里
> `/botconfig set cli aiden` 但没装 aiden）。daemon 与长连接都显示正常，
> 每次消息都起不来 CLI —— 表现就是**完全无反馈**。体检会直接点名报错。
> 修法：装那个 CLI，或 `/botconfig set cli claude-code` 改回已装的。

## 底层 CLI 是前置依赖（botmux 只桥接，不装 CLI）

**botmux 不负责安装它要驱动的 CLI。** 装完 botmux 但没装底层 CLI =
静默失败：daemon 与长连接全绿，飞书里发消息零反馈。`do_install` 会在装完时
检测并提示，`doctor` 会直接点名报错。

默认 `cliId` 是 `claude-code`，所以**至少要装 claude**：

```bash
npm install -g @anthropic-ai/claude-code
```

其他可选底层 CLI（botmux 适配器已内建，装了即可 `/botconfig set cli <cliId>` 切换）：

| cliId | 安装 | 说明 |
|---|---|---|
| `claude-code` | `npm i -g @anthropic-ai/claude-code` | **默认** |
| `codex` | `npm i -g @openai/codex` | |
| `gemini` | `npm i -g @google/gemini-cli` | |
| `opencode` | `npm i -g opencode-ai` | |
| `mtr` | `npm i -g @metamove-code/mtr-cli` | 社区贡献 |
| `codem` | 官方脚本（见下） | **飞书官方** AI 研发智能体 CLI |
| `aiden` | ⚠️ **内部渠道** | 字节内部工具（bytedcli 生态），botmux 公开文档明确不提供安装方式，公网 npm 上的 `aiden` 是**同名无关包**，别装 |
| `coco` / `traex` | ⚠️ **内部渠道** | TRAE 系，非公开 npm |
| `codex-app` / `mira` / `riff` | — | 非本地 CLI（桌面 App / Web API / 内建 agent），无需装 |

### CodeM（飞书官方）

想要「飞书内遥控 + 官方出品」，用 CodeM —— 它是飞书（Lark）官方的 AI 研发智能体，
公网可装，botmux **已内建适配器** `cliId: "codem"`：

```bash
curl -fsSL https://codem-public.tos-cn-beijing.volces.com/codem/install.sh | bash -s -- --no-sudo
codem login          # 扫码/浏览器授权（需企业已开通 CodeM 权益）
codem auth status    # 确认 loggedIn: true
codem daemon         # 常驻
```

装完 botmux **无需额外配置 PATH** —— 它的 codem 适配器直接探
`existsSync(~/.codem/bin/codem) ? 该路径 : "codem"`（路径优先、PATH 兜底）。
之后飞书里 `/botconfig set cli codem` 即可切换。

**取舍**：CodeM 稳（官方原生，不像第三方桥会被上游改版打断），但**模型通道锁定**
（不能用你自己的 Claude），且**需企业购买权益**（官方标注「预览」）。
`claude-code` 则相反：可自带模型、免费，但属第三方桥接。

> **注意**：`npm i -g aiden` 会装到 `aiden@0.0.3`（2025-01，作者 ebeloded）
> —— 那是个无关项目，不是 botmux 要的 Aiden。`doctor` 对这类内部渠道适配器
> 只报「仅仅内部渠道发行」并拒绝给出 npm 命令，避免把人带沟里。

## 配置输入输出显示

飞书里对 bot 发 `/botconfig` 查看/修改（写盘即热更新，无需重启）：

| 字段 | 作用 |
|---|---|
| `cliId` | 底层驱动哪个 CLI。可取值见 `botmux doctor` 的漂移检测段 |
| `cliPathOverride` | 覆盖 CLI 可执行路径（网关/wrapper 场景用） |
| `wrapperCli` / `cliLaunchMode` | 网关包装（如 `aiden x claude`），底层 CLI 仍需已装 |
| `replyCardMode` | `legacy`=两张卡 / `unified`=一张卡 |
| `disableStreamingCard` | 关掉流式卡片（改用固定卡） |
| `cotEnabled` | 思维链显示 |
| `brandLabel` / `showUsageInCardFooter` | 卡片页脚品牌与用量 |
| `lang` / `model` | 语言与模型 |
| `backendType` | `tmux` / `pty` / `herdr` / `zellij` |

完整字段表见上游文档：https://deepcoldy.github.io/botmux/

### SSH / 远端会话怎么建应用

二维码画在**远端**终端里，手机扫不到那块屏幕；而 botmux 二进制**不提供"输出登录链接"的开关**
（实测：TTY 与非 TTY 下都只给二维码 + 一句"如果无法扫码，可加 `--no-open-platform-auto`"）。
故有两条件用路径，引导会在检测到 `SSH_CONNECTION` 时主动列出：

- **A. 本机终端跑引导**（最省事）—— 二维码直接画在你面前的屏幕上
  `bash ~/git/ccconfig/init-option.sh botmux guide`
- **B. 手动建应用，全程浏览器**：
  1. https://open.feishu.cn/app → 创建「企业自建应用」
  2. 「凭证与基础信息」复制 App ID / App Secret
  3. `bash init-option.sh botmux manual` 粘贴两个值（Secret 不回显）

权限如需手动导入，JSON 在 `~/.botmux/lark-scopes.json`。

菜单入口：`bash maintain.sh` → `6C` 桥状态体检 / `6D` 桥配置管理（均在「6 远程/桥接」下）。

## 中文字体（WSL 必看）

botmux 的 Web 终端要在浏览器里渲染中文，需要一份 CJK 字体。它按**固定 Linux 路径**查找：

```
/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc
/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc
```

**WSL 默认一个 CJK 字体都没有**（`fc-list :lang=zh` 返回空），于是 botmux 会去 GitHub
下 Noto Sans Mono CJK（约 16MB）—— 受限网络下 60 秒超时，启动时挂一个
`字体下载失败 [CJK]: 下载超时 (60000ms)` 警告。

**装一次永久解决**（装到它认的路径上）：

```bash
sudo apt-get install -y fonts-noto-cjk
```

> 注意：WSL 里能读到 `/mnt/c/Windows/Fonts/`（微软雅黑等），但 botmux 是编译好的二进制，
> **只查上面那几条 Linux 路径**，不会去读 Windows 目录 —— 所以"拷 Windows 字体"不是它的路径。

引导（`guide`）在启动前会做预检，缺字体时直接提示上面这条 apt 命令。

## 前提

- **Linux / macOS（x64 / arm64）**；Windows 请走 WSL2（WSL2 上报为 linux）
- `tmux` 为核心依赖（每会话一个 pane）— `lib/deps-check.sh` 已列必需项
- 飞书**企业自建应用**（长连接模式不支持商店应用）
- **一个飞书应用只能挂一套长连接**：飞书长连接是集群模式、不广播，同一 appId 多个
  client 时**只有一个随机 client 收到消息**。故 botmux 应独占一个专用应用，
  不要与 `lark-cli` 共用 appId（后者也走长连接时会互抢消息）

## 用法

```bash
bash init.sh --status      # 状态（首行 OK/WARN/MISSING，供 init-option 解析）
bash init.sh --install     # 装/补链；装完问「现在配置吗」→ y 直接进引导
bash init.sh --update      # 升级（botmux upgrade）
bash init.sh guide         # 一条龙引导（建应用→启动→自启）
bash init.sh setup         # 只建应用（原始 setup）
bash init.sh start|stop|restart
bash init.sh logs          # 看日志
bash init.sh sessions      # 会话列表（非 TTY 自动 --plain）
bash init.sh dashboard     # Web Dashboard 登录链接
bash init.sh menu          # 交互菜单（菜单第 1 项即引导）
```

### owner 怎么填

`--allowed-users`（owner = 谁有权用这个 bot）是 botmux 的**必填**参数，且它不会交互询问 —— 所以引导自己收集。接受三种：

| 格式 | 例 | 说明 |
|------|-----|------|
| 完整邮箱 | `name@company.com` | **最推荐** |
| 手机号 | `+8613800138000` | 带不带 `+` 都行 |
| union_id | `on_xxxxxxxx` | 飞书通讯录里的 union_id |

⚠️ **`ou_` 开头的 open_id 不能用** —— 那是**别的应用**签发的，新建应用认不出它。引导会拒绝并让你重填。

## 状态语义

| 首行 | 含义 |
|------|------|
| `OK botmux 运行中` | 已装 + 有 bot + daemon 在跑 |
| `WARN botmux 已装未就绪` | 已装，但没配 bot（未扫码）或 daemon 没跑 |
| `MISSING botmux 未安装` | 二进制不在 PATH |

## 配置落点

- `~/.botmux/` — botmux 运行时目录（bots.json / logs / bin）
- 应用凭据由 botmux 自管（`~/.botmux/` 下），**不进 ccprivate**（与 lark-cli 的
  `~/.lark-cli-<account>/` 同思路：OAuth/凭据属本机，不入 git）

## 相关

- 上游：<https://github.com/deepcoldy/botmux>（MIT）
- 文档：<https://deepcoldy.github.io/botmux/>
- 飞书桥选型调研（为何弃 ccbridge）：memory `feishu-bridge-selection-20261027`