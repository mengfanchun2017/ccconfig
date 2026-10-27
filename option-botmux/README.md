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

## 安装

```bash
bash init-option.sh botmux            # 装二进制（npm -g botmux + ~/.local/bin 链接）
bash init-option.sh botmux setup      # 扫码建飞书应用（自动配权限 + 发版）
bash init-option.sh botmux start      # 启动 daemon
botmux autostart enable               # 开机自启
```

或经运维菜单：`bash maintain.sh` → `5G/5H/5I`。

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
bash init.sh --install     # 装/补链
bash init.sh --update      # 升级（botmux upgrade）
bash init.sh setup         # 扫码建应用
bash init.sh start|stop|restart
bash init.sh logs          # 看日志
bash init.sh sessions      # 会话列表（非 TTY 自动 --plain）
bash init.sh dashboard     # Web Dashboard 登录链接
bash init.sh menu          # 交互菜单
```

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