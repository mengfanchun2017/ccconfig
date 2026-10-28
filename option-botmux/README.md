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
# 或在运维菜单: bash maintain.sh → 5H（botmux 桥配置（引导））
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
bash init-option.sh botmux menu       # 完整管理菜单（启停/日志/会话/Dashboard/升级）
```

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

菜单入口：`bash maintain.sh` → `5G` 状态 / `5H` 引导 / `5I` 管理菜单。

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