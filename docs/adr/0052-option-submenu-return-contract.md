# 0052. option 子菜单不再坠入（一次性子命令 + 菜单循环化）

> **Status**: ✅ Accepted
> **日期**: 2026-10-24
> **关联**: 修正 [0044-agent-smb-file-bridge](0044-agent-smb-file-bridge.md) 的 filepull status 语义
> **模板**: MADR 4.0 极简版
> **目的**: 修掉"在 maintain 2D 装完一个可选组件后，不回菜单、卡在组件自己的界面"这一类缺陷

## Context and Problem Statement

2026-10-24 在 i7 新升级的终端上实测，2D「可选组件安装」有多处"装完不返回"：

- getnote：选它 → 装完停在 **getnote 自己的 5 项菜单**（那是给直接调用用的）
- evalscope：选它 → 停在 evalscope 菜单，且 `show_menu` 是**尾递归**（每操作一次套一层调用栈）
- skill：同类问题；且 `skill` 在 `maintain status` 里被列**两次**
- officecli：选它 → **卡住**（详见下方独立根因）
- filepull：报 `MISSING filepull 0/1 台可达`，但配置是好的、目标机只是离线

根因是同一类：`init-option.sh` 交互分支**裸调用** `option-<name>/init.sh`（无参数），
而多数 option 的无参数入口被设计成"常驻菜单"（`while true` 或递归 `show_menu`），
于是控制权交给了对方、不再回来。`cloudflare` 的菜单"退出"更狠——直接 `exit 0` 杀掉整个安装流程。

## Decision Drivers

- 2D 的语义是"列表里可以连续选多项、装完回列表"（`interactive_menu` 是 `while` 循环 + `pause_enter`）
- 每个 option 的"常驻菜单"对**直接调用**仍有价值（`bash option-x/init.sh` 逐项管理）
- 不该为修这个而给每个 option 加 flag、或删掉它们的菜单

## Considered Options

### 1 — caller 侧显式派发到一次性子命令（选定）

`init-option.sh` 加 `_interactive_install_args <name>`，把交互安装映射到各 option 已有的
"装完即返回"子命令：

| option | 派发 |
|---|---|
| getnote | `install` |
| evalscope / skill / officecli / mineru / playwright / cloudflare / filepull | `--install` |

`remote` 仍走 `--run`（保持原特殊处理）。返回空串的（larkcli 等本就一次性）走原路径。

代价：filepull 与 cloudflare 原本**没有** `--install`（前者只有 `--yes`，后者只有 `--install`
但语义是"全部安装"），需补一个真幂等的 `--install`。

### 2 — 给每个 option 加 `--once` / 环境变量（否决）

要改 N 个文件、加 N 份约定，且与各 option 已有的子命令（`install` / `--install` / `--run`）
重复。caller 侧一张表更集中、更好审。

### 3 — 让常驻菜单统一"检测到被 sourced/dispatch 就只跑一次"（否决）

隐式行为，难以从代码看出；且依赖调用方传标记，和方案 2 一样扩散。

## Decision

采用 **方案 1**，并配套三处修正：

1. **caller 派发**：`init-option.sh` 新增 `_interactive_install_args`，交互分支优先用一次性子命令
2. **消除尾递归**：`option-evalscope` / `option-skill` 的 `show_menu` 从尾调自身改为 `while` 循环
   （递归每次操作套一层，长会话/多次操作会无限加深调用栈）
3. **补 `--install`**：`option-filepull` 增加幂等 `--install`（已配置即 OK，否则提示手动 `add`）；
   `cloudflare` 已存在，纳入派发表

### filepull status 语义修正（关联 0044）

`0/N 台可达` 原本报 `MISSING`。但"已配置但目标机离线"≠"未安装"，
`MISSING` 会让 `maintain status` 打 ✗，与"根本没配"混淆，且目标机休眠/离线时天天误报。
改为 **`WARN filepull 已配置 N 台，当前 0 台可达`** —— 通道是好的，只是对端今天没上线。

### 顺带修：`skill` 重复显示 + 组件被静默丢弃

`lib/status.sh` 的 `--other--` 组用 `grep -vE` 排除了一批 option，而下面的
`handled` 名单是**另写一份**的排除名单。两份漂移 → `officecli`/`remote`/`cloudflare`/`getnote`
既不进 `--other--`、又不在 `handled` 里 → **完全不显示**；`skill` 则同时出现在
`--claude--` 和 `--other--` → **显示两次**。
改为：`--other--` 排除 `skill`，`handled` 从"分组里实际列过的 `shown` 数组"派生，
不再手写 —— 手写必然与分组漂移。

## Consequences

### Positive

- 2D 选任意组件都装完即回列表，可连续装多个
- 消除 evalscope/skill 的无限递归；消除 cloudflare"退出"杀整个安装流程
- `maintain status` 可选组件区不再漏项/重复
- filepull 的 ✗ 只代表"真没配置"，离线改为 ⚠（更准，少误报）

### Negative / Risks

- 派发表是**手写映射**，新增带常驻菜单的 option 时要记得登记，否则又会坠入对方菜单。
  缓解：`_interactive_install_args` 的 `*)` 返回空串 → 退化为原行为（不会更糟），
  但会重新出现"停在对方界面"。后续可考虑改为探测 option 是否支持 `--install`。

## Notes（实测坑清单）

1. 裸调 `option-x/init.sh` 而它的无参入口是 `while true` / 递归 `show_menu` → 控制权不返回
2. `cloudflare` 菜单"退出"分支是 `exit 0` —— 会连带杀掉**整个** `init-option.sh` 进程
3. `filepull` 的 `--yes` 原先与 `--install` 同分支，但 `init-option` 派发的是 `--install`，
   必须补别名，否则落到 `*)` 打印 usage 后 `exit 1`

## Related

- [0044-agent-smb-file-bridge](0044-agent-smb-file-bridge.md) — filepull 本体与凭据模型