# 2026-09-20 auto-sync 独占提交权 + debounce 统一 30s

> 范围：`lib/monitor.sh`、`lib/sync.sh`、`CLAUDE.md`、`README.md`、`BOOTSTRAP.md`、`docs/architecture.md`、`tests/`、`ccprivate/rules/git.md`
> 触发：init 链路复核期间，两个 Claude session 在同一仓库并行工作，auto-sync 把双方改动扫进同一个 `Auto-sync:` commit
> 关联：[20260920 init 安装/恢复可靠性](20260920-init-install-restore-reliability.md)

## 决策

**session 不 commit、不 push；auto-sync 独占提交权。** 提交信息带改动摘要，debounce 由 60s 统一改为 30s。

## 起因：现有规则自相矛盾

同一件事上有三条互斥的规则：

| 出处 | 说什么 |
|---|---|
| `ccconfig/CLAUDE.md`（改前） | 「每次 Edit/Write 后先 git add + git commit，不等 auto-sync」 |
| `rules/git.md` | 「个人项目也保持 commit 质量：一事一 commit，message 写清楚 what+why」 |
| `lib/monitor.sh` 实际行为 | 30s/60s debounce 后 `git add -A` + `git commit -m "Auto-sync: <时间戳>"` + push |

多 session 并行时这套规则直接打架：两边都在手动 commit，auto-sync 的 `git add -A` 又会把双方改动一起扫进同一个 commit；用 `git reset` 拆 commit，如果此时已经 push 出去，就等于改写已发布历史（违反 `rules/git.md` 的「不 amend 已发布的 commit」）。

**改成单一提交者，这些竞争面全部消失。**

## 代价（已知并接受）

1. **提交粒度退化**：从"一事一 commit"变成"一个 debounce 窗口内的全部改动"。30s 窗口比 60s 短，连续编辑不容易攒成一坨，但跨文件的原子重构仍可能被切开。
2. **半成品可能被推上去**：debounce 到期即提交，不等"改到一致状态"。
3. **补偿措施**：提交信息带摘要，别退回纯时间戳——

```
Auto-sync: ccconfig 8 文件

  BOOTSTRAP.md
  CLAUDE.md
  README.md
  docs/architecture.md
  lib/monitor.sh
  lib/sync.sh
  tests/test-init-llm-switch.sh
  tests/test-monitor.sh
```

（>12 个文件时列前 12 个 + `…还有 N 个`；无 staged 改动时回落时间戳。）

## 改动

| 文件 | 变更 |
|---|---|
| `lib/monitor.sh` | `debounce` 60→30、`min_push_gap` 60→30；提交信息由纯时间戳改为「仓库名 + 文件数 + 文件清单」；帮助文案 120s→30s；初始扫描改为显式传仓库列表 + 打印仓库数 |
| `lib/sync.sh` | 个人仓库脏工作区那条自动提交路径，提交信息对齐为 `Auto-sync: <repo> <n> 文件` |
| `CLAUDE.md` | 「每次 Edit/Write 后先 commit」→「session 不 commit、不 push」，写明 why 与代价 |
| `README.md` / `BOOTSTRAP.md` / `docs/architecture.md` | debounce 文案 60s → 30s（BOOTSTRAP 里"等 1-2 分钟"改"等 1 分钟"） |
| `tests/test-monitor.sh` | debounce 测试改为**直接读 `monitor.sh` 真值**（旧版测试写 60、断言标签写 30s、帮助文案写 120s，三方对不上）；新增摘要提交信息与初始扫描的回归断言 |
| `tests/test-init-llm-switch.sh` | 注释里的 60s → 30s |
| `ccprivate/rules/git.md` | 提交规则按「`~/git/` 下受 auto-sync 管的仓库不手动提交」限定；「一事一 commit」限定到非 `~/git/` 仓库 |

## 顺带发现：初始扫描静默空转

重启 monitor 后待提交改动一直不被提交，日志里只有一行 `Initial scan for pending changes...`，之后什么都没有——分不清是"没有改动"还是"没扫到仓库"。

**独立验证过 `list_repos` 本身没问题**（单跑返回 6 个仓库，rc=0）。改成显式传仓库列表 + 打印仓库数后，重启即见：

```
[13:04:28] Initial scan: 6 个仓库待查
[13:04:28] [aiagt] already up to date
[13:04:28] [ccbridge] no local changes, pushing 1 unpushed commit(s)
[13:04:32] [ccbridge] OK pushed → GitHub (3a42c20)
[13:04:32] [ccconfig] * changes detected
```

**连带修好一处历史遗留**：ccbridge 有 1 个卡住的未推送 commit，之前一直没人管，这次被初始扫描带出去了。

⚠️ 旧版静默空转的**根因未定论**——`sync_repos` 无参时会自己调 `list_repos`，与显式传参在逻辑上等价，我没能复现出差异，所以没有声称某个根因。现在的版本至少把"扫到几个仓库"变成可见事实，下次出问题能直接定位。

## 校验

| 项 | 结果 |
|---|---|
| debounce 真值生效 | 日志 `[13:02:11] Change detected, waiting 30s debounce...` → 31s 后 commit |
| 摘要提交信息生效 | commit `d0dd6b6` 实际信息为 `Auto-sync: ccconfig 8 文件` + 8 个文件清单 |
| 初始扫描 | 重启后 `Initial scan: 6 个仓库待查` 并实际执行同步 |
| `tests/test-monitor.sh` | 24 PASS / 0 FAIL（新增 5 条断言） |
| 其余关键测试 | `test-sync` / `test-maintain` / `test-init-ccprivate-repo` / `test-init-llm-switch` / `test-syntax` 全 PASS |
| 全仓同步状态 | 6 个仓库 0 项待提交；ccconfig 与 ccprivate 均 `落后 0 / 领先 0` |

## 遗留

- **`docs/adr/0032` 里仍写 60s debounce**：那是历史决策记录里对当时现象的描述（含实测时间戳），属点-in-time 记录，不改写。
- **半成品可能被推上去**：见「代价 2」，未做缓解。若要缓解，可在 debounce 到期时先跑一次语法检查（`bash -n`）再决定是否提交。
