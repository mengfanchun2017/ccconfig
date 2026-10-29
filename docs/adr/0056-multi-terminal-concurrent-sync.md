# 0056. 多终端共用同一账号：修两处丢弃触发的竞态 + 5min 心跳收敛

> **Status**: ✅ Accepted
> **日期**: 2026-10-29
> **关联**: `lib/monitor.sh`（`commit_and_push` / `start_watch` 的 debounce 循环）、`tests/test-monitor.sh`、systemd 单元 `claude-auto-sync.service`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

用户会在**不同终端、同一 git 账号**下操作同一批仓库（`ccconfig` / `ccprivate` / `skill`）。
auto-sync monitor 独占提交权（inotify → 30s debounce → add+commit+push），因此两端都在往
同一分支推。用户的原始疑问是两点：

```
1. 频率不高的话，两边会不会互相影响？
2. 有时发现"工作区脏"——monitor 是 a 发现变化 → b 拉取最新 → c push 吗？
   这样两个终端就能同时在线、有更新也不冲突了？
```

排查后确认用户的心智模型**大方向对但有三处偏差**，且"工作区脏"有独立的机械成因：

- monitor 是**纯事件驱动**：只在**本机文件被动过**时才启动，启动时才顺带 pull。
  它**没有轮询远程**的能力 —— 对端推了新提交，本机不会因此被唤醒。
- 顺序确实是 commit → `pull --rebase --autostash` → push（这点用户猜对了）。
- "工作区脏"的根因**不是冲突**，而是**两处会静默丢弃 debounce 触发**的竞态（见下）。

### 两处丢弃触发的竞态（实测复现）

**竞态 A —— 同步窗口内的改动被抹掉。**
debounce 块在 `sync_repos`（耗时 4~24s）**之后**才 `rm -f "$DEBOUNCE_FILE"`：

```
t=0    写文件 A          → DEBOUNCE_FILE 建立
t=30   debounce 到       → sync_repos 开跑（A 被提交）
t=31   写文件 B          → inotify 重建 DEBOUNCE_FILE，记下 B
t=35   sync 完成         → rm -f DEBOUNCE_FILE   ← B 的触发被抹掉
       pending 已是 0    → 下个 2s tick 见文件不存在 → 当成空闲
```

实测：写于同步窗口内的文件**持续 200s+ 保持未提交**，直到下一个无关文件事件才被顺带带走。
正常编辑极易撞上这个窗口。用户凌晨那次脏文件即此：`conf/ffeishu.yaml` 于同步窗口内
被写入，一直脏到次日早上手动触发同步才被提交。

**竞态 B —— 紧接上次 push 的改动被忘掉。**
`min_push_gap`（=debounce=30s）的跳过分支同样 `rm` 掉触发文件：

```
[08:51:58] OK pushed
[08:52:00] Change detected, waiting 30s debounce      ← 文件 B 写入
[08:52:25] Skipped: <30s since last push              ← 丢弃触发，不同步
           → B 持续未提交
```

语义是"这次算了"，而不是"稍后再做" —— 与竞态 A 同类。

### 收敛缺口（心跳单独不足以解决）

即使用户设想的周期兜底拉长/缩短，**光有心跳也没用**：`commit_and_push` 在
"本机无改动"路径上**只查本地未推送 commit 就 return，不 fetch/pull**。
所以"对端推了新提交、本机无改动"会走进 `already up to date` —— 本机**永远看不见**
对端进展，心跳只是更频繁地重复这句话。原 12h 兜底同样受此影响。

## Decision Drivers

- **D1 不丢改动**：任何时刻写入的文件最终必须被提交，不允许静默丢弃
- **D2 多终端可收敛**：另一终端推的提交，本机须在有限时间内可见
- **D3 不用破坏性操作**：`reset --hard`/强推不可作为常规路径
- **D4 失败要留证据**：拉取/推送失败必须能事后定位，不能只报"failed"
- **D5 幂等无噪音**：无改动时不产生空提交
- **D6 不静默改本地文件**：自动合并不得在用户不知情时改写工作区内容

## Considered Options

1. **只把两处 `rm` 改成"延后"** — ✅ 解决 D1，❌ 不解决 D2（对端仍不可见）
2. **把 12h 兜底缩短为 5min 心跳** — ✅ 提高触发频率，❌ 单独无用（无改动路径不 fetch，D2 仍破）
3. **另起一个独立轮询器专门 fetch 远程** — ✅ 满足 D2，❌ 新增常驻进程与第二套状态，与"单一提交者"原则冲突
4. **每次事件都强制 fetch 再 push** — ✅ 及时，❌ 事件密集时网络开销翻倍，且不解决空闲期的收敛
5. **修两处竞态 + 5min 心跳 + 在"无本地改动"路径补一次 fetch/整合** — ✅ 三项互补，改动集中在既有函数内

## Decision

**三件事一起做，全部落在 `lib/monitor.sh` 既有函数内，不新增进程。**

1. **两处触发文件改为"先清后同步 / 延后而非丢弃"**（解 D1）
   - debounce 块：`rm -f "$DEBOUNCE_FILE"` 提到 `sync_repos` **之前** → 窗口内到达的新事件
     重新武装 debounce，语义从"丢事件"变"延后一轮"
   - `min_push_gap` 跳过分支：**不再 rm**，保留 `DEBOUNCE_FILE` 与 `pending`，下一 tick
     重算 gap，够了就同步 → 从"丢弃"变"延后"
2. **空闲兜底 12h → 5min（150 ticks × 2s）**，日志改为 `Heartbeat sync (5min idle)`（解 D2 的一半）
3. **"无本地改动"路径补 fetch + 按需整合**（解 D2 的另一半，也是关键的一半）
   - 先显式 `fetch origin <branch>`（复用 `proxy_usable` 的代理/直连双路径）
   - 再由 `origin/<branch>` **缓存**算出落后量 —— 必须 fetch 在前，否则落后量恒 0
   - **确有对端新提交才** `git_pull_rebase`（跳过时不产生第二次网络往返）；工作区干净 →
     `autostash` 不生效，快进即"纯取回对端改动"
   - 本地**没有**本地改动，所以这次整合不可能与本地内容冲突

### 关键实现约束（踩过两次）

- **errexit 必须用 `had_e` 保护**，不能在取完 rc 后无脑 `set -e`。
  实测违反后果：心跳触发后 **11 秒主 loop 自杀**，systemd `Restart=always` 立刻拉起
  （`NRestarts` +1，每 ~5min 一次重启风暴）。此坑 `git_push` 里已有注释警告，本次是重犯。
- **落后量必须在 pull 之前算**。pull 成功会把它归零，算在事后就永远是 0 →
  日志会误报 `already up to date`（实测整合了 1 个提交却打这句）。
- **只 fetch 不自动合并**：`pull --rebase` 的 `autostash` 是保底，不用于"替用户决定"。
  该路径只在工作区**干净**时走，因此不违反 D6。

## Consequences

- ✅ 窗口内写入的改动不再丢失，改为**延后一轮**被提交（实测：写于窗口内的文件自动补齐）
- ✅ 紧接上次 push 的写入不再被忘掉（`Deferred` 日志可辨识）
- ✅ 多终端收敛窗口从 **12h 降到 ≤5min**（心跳），且本地有改动时**即时**收敛
- ✅ 对端提交可见：纯远程领先时日志报 `up to date locally, but N commit(s) behind remote`
  或 `整合其他终端 N 个提交（pull --rebase）`，不再一律 `already up to date`
- ✅ `pull` 失败落真实 rc + 原始输出（此前全历史约 50 次失败**无一条证据**）
- ✅ `skip_push`（冲突兜底/unrelated histories）不再静默 —— 显性报出未推送 commit 数
- ❌ 空闲期每 5min 对每个已跟踪仓库各做一次 `fetch`，网络往返频率上升（换取 D2）
- ⚠️ **冲突兜底仍未改**：`unrelated histories` 或 rebase 冲突时走
  `stash push`（**不带 `-u`**，未跟踪文件不入 stash）→ `rebase --abort` →
  `reset --hard origin/<branch>` → `stash pop` → `skip_push=true`。
  `reset --hard` 属禁用操作清单。全历史**从未触发过**（0 命中），本轮仅加告警未重做；
  待后续评估是否改为"只报警、不动工作区"。
- ⚠️ 心跳的 fetch 在代理/网络抖动时会打 `fetch 失败` 警告，可能形成噪音

## 双终端使用场景（本 ADR 的适用范围）

用户明确需要"两个终端同时在线"这一能力，边界如下：

| 情况 | 行为 | 结论 |
|---|---|---|
| 两端改**不同文件** | 每次 push 前 `pull --rebase`，无冲突 | ✅ 安全 |
| 两端改**同一文件的不同位置** | git 三方合并通常自动完成 | ✅ 一般安全 |
| 两端改**同一文件的同一行** | rebase 冲突 → 走兜底（存 stash + `reset --hard` + `skip_push`） | ❌ 本地工作进 stash，工作区可能残留冲突态 |
| 一端改了、另一端**什么都没动** | 心跳（≤5min）或本地下次改动时 fetch 并整合 | ✅ 延迟收敛 |
| 一端改了、另一端**正在编辑同文件** | 走"两端改同一文件"的三档判定 | ⚠️ 取决于是否撞同一行 |

**频率高低不是关键，关键是否在同一时刻改同一文件的同一段。** 现实中前两行占绝大多数，
因此"多终端同时在线"是可用能力，而非仅理论可行。

两端的**收敛是延迟的、不是即时的**：本机不碰文件时，最长要等一个心跳周期（5min）；
本机有改动时，那次同步会顺带整合远程。这是 D6"不静默改本地文件"的必然代价。

## Implementation

- `lib/monitor.sh`
  - debounce 块：`rm -f "$DEBOUNCE_FILE"` 前置到 `sync_repos` 之前
  - `min_push_gap` 分支：改 `Deferred: ...`，保留触发文件与 `pending`
  - 心跳：`idle_ticks -ge 21600` → `-ge 150`，日志 `Heartbeat sync (5min idle)`
  - `commit_and_push` 无改动路径：`fetch` → 算 `behind` → 按需 `git_pull_rebase`
    （`had_e` 保护 errexit）
  - pull 重试分支：落 `pull rc=$pull_rc err: ...`
  - `skip_push` 分支：报未推送 commit 数
- `tests/test-monitor.sh` 新增 6 组断言（共 23 项 / 35 断言，全绿）：
  `test_debounce_race_guard`（`rm` 行号 < `sync_repos` 行号）、
  `test_min_gap_defer_not_drop`（有 `Deferred`、无多余 `rm`）、
  `test_heartbeat_convergence`（间隔 ≤300 ticks + 日志可辨识）、
  `test_remote_ahead_detected`（含 `git_pull_rebase`、`behind`、`had_e`）、
  `test_pull_failure_evidence`、`test_skip_push_visible`
- 端到端验证（假裸远程 + 双克隆，在 `~/git` 之外建，避免触发本机 monitor）：
  `commit_and_push` 使 `HEAD a4f2cf5 → 8f6ae98`，日志
  `整合其他终端 1 个提交（pull --rebase）`，工作区保持 clean
- 全量套件 33 个测试文件、0 失败

## Related Decisions

- [0032](0032-config-layering.md) — 同为多终端主题的另一半：**哪些文件共享、哪些必须本机**
  （`settings.json`/`.config.json`/`.claudeignore` 是本机文件，绝不可 symlink 回私有仓，
  否则跨机互相覆盖）。本 ADR 管"仓库内容的并发同步"，0032 管"配置的所在层级"
- [0023](0023-pat-expiry-on-failure-only.md) — 同属 auto-sync 的"失败才报"取向；
  本 ADR 的 push/pull 失败留证据是同一原则在两端的延伸
- [0050](0050-bridge-structural-refactor.md) — 同为"判定单点化、不新增并行的同类机制"取向

## Notes

- 排查手法记在私有 memory `monitor-auto-sync-ops`；本文件按公开仓规范不含真实路径/端点
- **复现手法**（用于日后再验）：在另一终端（或 `~/git` 之外克隆的副本）推一个提交，
  保持本机工作区**干净**，观察日志应在 ≤1 个心跳周期内出现
  `整合其他终端 N 个提交`；若只出现 `already up to date`，说明 fetch 缺失或落后量算错位置
- **未做成的事**（用户已知并认可"之后再改"）：
  1. 整合成功后紧跟的 `already up to date` 措辞冗余（同一次调用里先说整合了 N 个）
  2. 心跳对每个仓库都做一次全量 `fetch`，可加 `--no-tags` 或减少频率
  3. 冲突兜底的 `reset --hard` 路径（禁用操作）尚未重做，仅加了告警