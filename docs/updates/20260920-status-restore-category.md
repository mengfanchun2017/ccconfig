# 2026-09-20 「状态」域重构：检查 + 一键恢复最新功能

> 范围：`maintain.sh` 的 `do_setup()` 重写 + 菜单第 1 类重排 + 3 个实测出来的 bug
> 起因：用户要「在 `--1 状态--` 这里能够检查、恢复最新的功能」—— `git pull` 到新版本后，希望有一个地方把新版本带来的设定一次启用；并指出 1B 用不上、1C 可与 1D 整合、1D 该扩展
> 关联：[20260920-maintain-flat-menu.md](20260920-maintain-flat-menu.md)（同日菜单扁平化）

## 先查出来的根因：检查用新模板，修复用旧模板

用户要的「启用新设定」一直没生效，原因是一条**方向错位**的链路：

| 环节 | 用的模板 |
|---|---|
| `status.sh` 报「settings.json 缺键」 | `ccconfig/templates/settings.json.example`（**新**） |
| `ccprivate/setup.sh` 补缺键 | `ccprivate/link/settings.json.example`（**旧**本地副本） |
| 刷新上面那份旧副本 | 只有 `ccprivate-upgrade.sh` 的 `fix_link_content` 会做 |

`do_setup()` 里没有 `ccprivate-upgrade` 这一步，于是：status 用新模板检出缺键 → setup.sh 拿旧模板去补 → 补不上 → 用户看到的红叉修不掉，而且**看起来"修复跑过了"**。

`do_setup` 新链路把 `ccprivate-upgrade --yes` 提到最前面，这个问题才真正闭环。

## 覆盖度差距（改前）

对着 `status.sh` 的 11 项检查逐条比对"有没有人能修"：

| 会漂移的东西 | 能查 | 能修 | 改前状态 |
|---|---|---|---|
| settings.json 缺**新**键 | ✅ | ❌（用旧模板） | 本节的根因 |
| conf / agents 新模板 → ccprivate | ✅ | ✅ 但只在 `sync.sh --all` | 一键修复里没有 |
| ccprivate 结构过旧（`.generated` 残留 / setup.sh 是 v2 / link/ 缺文件） | ✅ | ✅ 只在 3C | 一键修复里没有 |
| MCP 注册缺失 | ✅ | ✅ 只在菜单 6D（且 6D 只同步 settings，不注册） | 一键修复里没有 |
| Skill 断链 / CLI 依赖未装 | ✅ | ✅ 只在 3B | 一键修复里没有 |
| `~/.claude/llm-current` 缺失或指向已删预设 | ❌ | ❌ | **完全无人负责** |
| 依赖缺失（inotify 等） | ⚠️ 仅全量 | 只在 2F | 一键修复里没有 |

## 改了什么

### 菜单第 1 类：4 项 → 2 项

```
--1 状态--
1A  检查（只读）          ./maintain.sh status
1B  恢复最新功能（一键）   ./maintain.sh fix
```

- 删 `1B 快速状态`（用户：用 1A 就行）。`status.sh --quick` 作为 CLI 仍在
- 删 `1C 依赖检查`。1A 的输出里本来就有依赖段；全量依赖明细仍是 `./maintain.sh deps`
- `1D 一键修复` → 改名 `1B 恢复最新功能` 并扩展（下面）
- 另在「其他」补 `9D 可选组件安装/补装 → bash init-option.sh`，此前 `init-option.sh` 在菜单里**完全没有入口**

### `do_setup()` = 恢复链（7 步，按依赖顺序）

```
1. ccprivate 结构与模板刷新（前置）   ccprivate-upgrade.sh --yes
2. 符号链接 + 缺失目录                ccprivate/setup.sh
3. 新配置模板跟进                     example-sync.sh sync
4. MCP 注册 + Skill 全量同步          init-mcp.sh sync / init-skill.sh sync
5. settings 键归位                    （内置 python）
6. LLM 当前选择校验                   check_llm_current（新写）
7. auto-sync 与运行依赖               monitor 状态判断 + install_inotify
```

- **步骤失败只记账不中断**（`_fix_step`）——一键恢复不该因某步坏掉就半途而废；末尾报「N 步失败」
- 新增 `check_llm_current()`：读 `~/.claude/llm-current`，为空或不在 `llm.json` 的 llms 里就报出来并指向 4A。**只报不修** —— 换 preset 要走链路探测，不能替用户瞎选
- 依赖只装轻量的 inotify（auto-sync 必需）；node/python/gh 等属全机引导，缺失时只提示 `bash init-ubuntu.sh`，不在一键恢复里跑 apt

## 实测跑出来的 3 个 bug

跑真实恢复链（就是用户以后要跑的那条）依次暴露：

### 1. MCP 同步和 settings 归位互拆台（新引入 + 历史逻辑错）

第 4 步 `init-mcp.sh sync` 把 `mcpServers`/`disabledMcpServers`/`projects` 写进 `settings.json`，第 5 步的归位逻辑立刻把它们删掉，还打印一句吓人的「两份内容不同，以 settings.json 为准并删除 .config.json 副本」。

两个问题：
- **方向判断的依据是错的**。实测 `claude mcp list` 在 `settings.json` **完全没有** mcpServers 的情况下，3 个服务全部 ✔ Connected —— 生效的那份在 `.config.json`。所以归位删得对，是 MCP 那步往不被读的文件写。
- 原代码 `for k in GLOBAL_CONFIG_KEYS` 分支里先 `sd.pop(k)` 再 `sd.get(k) == cd.get(k)` 比较，**pop 之后 get 恒为 None**，所以永远走「内容不同」分支，报的文案也一直是假的。

处置：归位步骤**不再碰这三个键**（它们归 MCP 模块管，`mcp sync` 会主动写），只保留真正有害的那个方向 —— settings 键被错放进 `.config.json`。顺带把那段 pop-before-compare 的死逻辑删掉。

### 2. `monitor.sh status | grep -q` 在 `pipefail` 下条件恒假

新写的 auto-sync 判断：
```bash
if bash "$LIB_DIR/monitor.sh" status 2>/dev/null | grep -q 'Monitor loop (PID'; then
```
auto-sync 明明在跑，却每次都走 `else` 去重装 systemd unit（要 sudo，非 tty 下必然失败）。

根因：`grep -q` 一匹配就退出并关掉管道，写端拿到 EPIPE 退出 141，`set -o pipefail` 把整个管道判成失败 → 条件恒假。**触发条件是「输出 > 管道缓冲 64KB」或「生产者慢」**，实测：

```
seq 1 500000 | grep -q .        → 误判（输出超 64KB）
{ echo x; sleep 3; echo y; } | grep -q x   → 误判（生产者慢）
```

`monitor.sh status` 两者都占（要查 systemd + 输出长），所以必现。改成先取值再比。

**同类站点（未复现，留观察）**：`grep -q` 左侧是外部命令的还有 `lib/monitor.sh:187/341`、`lib/init-mcp.sh:114/122/139/411`、`lib/ensure-libicu.sh:47/62`。它们当前输出都小于 64KB 且生产者快，实测未误判；但形状相同，值得哪天统一改成 `grep ... >/dev/null`（不早退即无 EPIPE）。

### 3. `init-autostart.sh enable` 每次重装系统级 unit

已在跑也照样重装，弹 sudo 认证。第 2 条的判断修好之后自然跳过。

## 验证

```
bash maintain.sh fix          → rc=0，7 步全绿（幂等，连跑两次结果一致）
bash tests/test-maintain.sh   → PASS 83 / FAIL 0
15 个 shell 测试套件           → 全 PASS
```

跑完复查：`claude mcp list` 3 个服务 ✔；`.config.json` 的 3 个 MCP / 19 个项目完好；`settings.json` 无多余键。

## 已知遗留

- `status.sh` 不检查 `~/.claude/agents`、`commands`、`workflows`、`shell_init.sh`、pre-commit hook 的软链存在性（**有修无查**：`ccprivate/setup.sh` + `setup-links.sh` 都会修）。第 2 步会修它们，但 1A 看不到
- `conf/versions.json` 与实际组件版本是否一致，依旧只有 `update.sh` 在升级时比，日常无人查
- `ccprivate/conf/*.json` 与 `conf/*.json.example` 必然"有差异"（前者含真实 key），所以第 3 步每次都会带一句「N 个差异文件未覆盖」—— 这是设计如此（不覆盖用户编辑），不是失败
