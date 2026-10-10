# ccconfig 架构 & 代码审计报告

- 日期：2026-10-10
- 范围：全仓库（lib/ 29 文件 + 3 入口 + option-*/ 17 脚本 + openai_bridge.py）
- 方法：7 个维度并行初审 → 4 组对抗式复核（逐条复现/证伪）→ 汇总
- 规模：196 tracked 文件 / ~30k 行；67 个 `*.sh` 全部 `bash -n` 通过
- 状态：报告 + 低风险项已修（见 §6 变更清单）

> 说明：本报告所有行号基于审计当日 HEAD。已修复项标注 ✅。

---

## 0. 执行摘要

整体健康度 **中上**：`set -euo pipefail` 近乎全覆盖，JSON 写入普遍原子化，monitor 的自愈/锁逻辑经实战打磨，流式 bridge 核心（块索引/usage 合并/心跳）成熟。**但存在三类系统性缺口与一批真 bug**：

1. **保密红线被突破（最高优先）** —— 真实凭据/内网信息存活在可从 `origin/main` 到达的 git 历史里（PAT、LLM key、内网 IP+用户名、企业域名、个人邮箱），且 `pre-commit` 密钥正则漏检正是泄漏入口。
2. **单一函数 `find_node_bin` 与 `set -e` 不兼容** —— 全局单点，波及所有 `$(find_node_bin)` 调用点，在无 `~/.local` node 的机器上直接杀进程。
3. **"文档化的规范"从未落地** —— ADR-0027 承诺的 `guard_*` / `atomic_write` / `safe_exit` 等 API 被 README 明列为规范，实际**零调用**（死代码），各脚本各写各的幂等 guard；dry-run 在 sync/ccprivate-upgrade 中未接线（"半真"）。

---

## 1. P0 —— 保密与数据完整性

### 1.1 🔴 真实凭据存活于 git 历史（需人工处置）

当前 HEAD 树干净，但下列内容在 **reachable from origin/main** 的历史中（`git clone` 后 `git log -p` 即得）：

| 类型 | 位置 | 复核 |
|------|------|------|
| 真实 fine-grained GitHub PAT | `.claude.json`，commit `1a9c67b`、`dc69e4d` | CONFIRMED（脱敏核验） |
| 真实 LLM API key | `conf-llm.json`（`8eee9d4`）、`archive/conf-llm.json`（`ebeccf2`） | CONFIRMED |
| 内网 IP + 用户名 | `remote/*.ps1`，commit `4a6a623` | CONFIRMED |
| 企业域名 `airchina.com.cn` | 多个 commit + 远程分支 `origin/worktree-rename-airchina` | CONFIRMED |
| 个人邮箱 | 全部 commit 的 author（`git log` 即暴露） | 无法不改史移除 |

**处置建议（需用户决策，未执行）**：
1. **立即吊销**上述 PAT 与 API key（已 push = 已泄露）。
2. 如接受改写已发布历史：`git filter-repo` 清除 4 处 → `git push --force-with-lease` → `git reflog expire --expire=now --all`；删除远程分支 `origin/worktree-rename-airchina`。**须与 auto-sync monitor 协调（先停 monitor）。**
3. 如不改史：至少视为已公开，凭据轮换 + 后续提交不再引入。

### 1.2 ✅ `hooks/pre-commit` 密钥正则漏检（泄漏入口，已修）

`hooks/pre-commit:54` 旧正则漏 `github_pat_*`（含下划线）与带连字符的 `sk-ant-*`——实测两者均 BYPASS。**已补**：
```
sk-[a-zA-Z0-9]{20,}|sk-ant-[a-zA-Z0-9_-]{20,}|gho_...|ghp_...|github_pat_[a-zA-Z0-9_]{20,}|eyJ...
```
实测 `github_pat_*`、`sk-ant-*` 现均 MATCH。

### 1.3 ✅ `lib/path-helper.sh:103` find_node_bin 与 set -e 不兼容（已修，全局单点）

裸管道 `found=$(ls ... | sort -V | tail -1)` 无 `|| true`；`~/.local` 无 `node-v*` 时 `ls` rc=2 经 pipefail 传播、赋值即触发 errexit，**在策略 3/4 的 graceful `return 1` 之前杀死调用方进程**（复核实测 rc=2）。受害点如 `lib/update.sh:316`（未 guard）。
**已修**：追加 `|| true`。隔离测试确认无 node 环境下函数存活返回。

### 1.4 历史中企业名/内网信息（随 1.1 处置）

同上，属 1.1 的历史重写范围。

---

## 2. P1 —— 正确性 / 契约 / 静默失败

| 文件:行 | 状态 | 缺陷 | 触发场景 |
|---------|------|------|----------|
| `lib/update.sh:428,459` | 待修 | 用本机 `pip3 freeze --user` 回写**公开且被 track** 的 `conf/python-requirements.txt`，auto-sync 随即 commit+push | 本机环境与声明不一致 → 版本漂移扩散全机群 |
| `lib/monitor.sh:310` | 待修 | pull 冲突兜底 `git reset --hard origin/$branch` 丢本地 commit/工作区；前置 `stash push ... \|\| true` 静默吞失败 | rebase 冲突 + 并发写时 |
| `lib/mcp-manager.sh:30-32,407-410` | 待修 | `$CONFIG_JSON`/`$name`/`$desc` 直接插进 `python3 -c` 源码 —— 单引号即 SyntaxError，且属注入面 | 值含单引号（如 `it's`）→ 写入失败 |
| `lib/init-mcp.sh:195,525` | 待修 | `configure_mcp_env … \|\| true` 吞掉 Key 写入失败 → 运行时留占位符 | 新机 401（正是该文件注释警告的模式） |
| `option-llmswitch/openai_bridge.py:911` | ✅ 已修 | `/admin/reload` 无鉴权返回 `dict(state)` 含 `upstream_key` 明文 | POST 即读出上游 key |
| `option-llmswitch/openai_bridge.py:111,135` | 待修 | Anthropic image 块转 dict 后 `"".join(p for p in text_parts if isinstance(p,str))` 只留 str → 图片静默丢弃 | 多模态请求数据丢失 |
| `option-llmswitch/openai_bridge.py:478` | 待修 | 非流式 `json.loads(fn.get("arguments","{}"))` 无 try | 上游畸形 arguments → 整个请求 500 |
| `bin/memory-check.sh:33` | ✅ 已修 | `[[ "$1" == "--stale-only" ]]` 无参 unbound，set -u 崩溃 | 无参运行必崩 |
| `lib/init-mcp.sh:572` | ✅ 已修 | 拿 menu_select 序号字符串比 item 文本，恒不等 → tname 空 → **启停 MCP 恒失败** | 菜单 4 |
| `lib/deps-check.sh:217,283` | 待修 | `--json` 把人类可读标题行混进 JSON 数组 → 非法 JSON | `deps-check --json \| jq` |
| `lib/interact.sh:132` | 待修 | 非 tty 分支 `read -r sel \|\| true`，stdin 关闭 → 静默返回 "0" 取消菜单 | 管道喂入脚本 |
| `lib/interact.sh:271-282` | 待修 | spinner 子 shell 丢弃 `wait` 返回码 → 命令失败也打印 ✓ 且返回 0 | 任意 `spinner "…" <失败命令>` |
| `option-skill/init.sh:57` / `option-evalscope/init.sh:79` | ✅ 已修 | 取消判定只判 `-z "$c"`，漏判 "0" → 与 menu_select 新契约不符，子菜单无法返回 | 输入 0/越界 |
| `option-larkcli/init.sh:104-121` | 待修 | 已存在 config.json 只检测 auth，不校验 appId/secret 与 feishu.json 一致 | 改 appId 后重跑静默沿用旧凭证 |
| `lib/ensure-bridge.sh:169-181` | ✅ 已修 | wrapper 把 `OPENAI_BRIDGE_KEY` 明文写 `/tmp/…sh`（0644） | 启动窗口期 key 暴露 |

---

## 3. P2 / 系统性 —— 架构 & 一致性

### 3.1 幂等 guard 模式未落地（三度交叉印证）

ADR-0027 承诺 `lib/guard.sh` + `_is_installed/_is_not_file/_is_executed/_mark_executed`；`lib/README.md` 亦把 `guard_mkdir/guard_symlink/guard_write_file/atomic_write` 列为规范。**实际：`lib/guard.sh` 不存在**；四个 `_is_*` 全库零命中；`lib/dry-run.sh` 里的 `guard_*` 系列**定义外零调用**（死代码）。各脚本各写各的 `[ -e ]`/`ln -sf`/`grep -q`。

### 3.2 已确认死代码清单（定义外零调用，tests/ 除外）

| 文件:行 | 函数 |
|---------|------|
| `lib/dry-run.sh:110` | guard_mkdir |
| `lib/dry-run.sh:117` | guard_symlink |
| `lib/dry-run.sh:130` | guard_append_line |
| `lib/dry-run.sh:137` | guard_write_file |
| `lib/dry-run.sh:146` | guard_command_exists |
| `lib/dry-run.sh:153` | atomic_write（仅被死的 guard_write_file 调） |
| `lib/safe-exit.sh:13,17` | _register_temp / safe_exit（**整文件无人 source**） |
| `lib/interact.sh:244` | table（仅 tests 调用） |
| `init-option.sh:500/535/561` | _feishu_add_app / _feishu_edit_key / _feishu_delete_app |
| `lib/mcp-manager.sh:50,111` | list_git_repos / all_projects_status |
| `lib/colors.sh:41-56` | `if ! type ok` fallback 块（守卫检查的函数在守卫之前已定义 → 恒假） |

> 复核**证伪**两条"死代码"：`lib/interact.sh:365 menu_render`（menu_loop 调用）、`lib/interact.sh:325 trim`（内部在用）——均为活代码。

### 3.3 颜色层未单点

- `lib/monitor.sh:50-53` 重定义 `warn/info/error` 遮蔽 `lib/colors.sh`（monitor.sh 自身 :37 又 source colors.sh）。monitor.sh:98 注释自述为已知冲突的 workaround。
- `bootstrap-gh-auth.sh:25-28`、`lib/path-helper.sh:160-171` 退回硬编码 `\033` 颜色。

### 3.4 dry-run "半真"

`lib/sync.sh:69,85`（cp 覆盖 ccprivate/conf + agents）、`lib/ccprivate-upgrade.sh:140-192`（cp/rm/mkdir）均 source 了 dry-run.sh 但**从不调 `run`/`would`**，且两脚本根本未解析 `--dry-run`（latent）。`option-remote/deploy.sh:20,39,48` 同。

### 3.5 隐式全局回传

`lib/status.sh:581` `_check_component` 靠给全局 `icon`/`detail` 赋值回传结果，caller 未 `local` 声明（全文件零 `local.*icon`）——正确性依赖调用约定，重构即断。

### 3.6 其它 P2 聚合

- 未引号数字变量：32 处（update 8 / monitor 12 / status 4 / sync 2 / ccprivate-upgrade 2），均有紧邻赋值保证非空 → 非真 bug。
- `local x=$(cmd)` 掩盖退出码：173 处，绝大多数 `cmd` 为 `echo|cut|awk`，真风险仅 mcp-manager python 组。
- `|| true`：197 处，多数为刻意的 probe/hash 兜底。
- `while read` 缺 `-r`：4 处（init-skill:627、monitor:222、sync:136、cloudflare/init:91）。
- 固定名 `/tmp` 路径（无 mktemp 隔离）：update.sh:534/587/266、init-ubuntu.sh:129、officecli/init.sh:78、install-inotify.sh:84、init-option.sh:351/389。
- 重复代码：`do_status`×9、`getnote-switch ↔ lark-switch` 5 函数近似 copy-paste（~300 行）。
- 单文件过长：update.sh 1053 / init-llm.sh 986 / monitor.sh 967 行。

---

## 4. 文档漂移（已确认）

| 文档:行 | 缺陷 | 实际 |
|---------|------|------|
| `CLAUDE.md:11-12` | 暗号 `hookstatus`/`pullff` 全库无代码定义（仅文档命中，二者互相矛盾） | 无实现 |
| `README.md:21,288,337` | 括号拆分"16 f-* + getnote"错误（getnote 非 marketplace 插件） | 实为 16 marketplace + 1 内部 fskillcreat |
| `docs/architecture.md:280`、`docs/ccprivate-guide.md:48,94,110` | 路径写 `link/projects/` | 实为 `link/memory-projects/` |
| `docs/adr/0027` | 承诺 `lib/guard.sh` + `_is_*` API | 未实现（见 §3.1） |
| `option-skill/README.md:32-169` | 整篇描述已废弃的第三方 npx skill 流程 | init-skill.sh:32 明确已移除，`conf/third-party-skills.txt` 不存在 |
| `BOOTSTRAP.md:793,806` | 服务名 `cconfig-monitor.service` + `systemctl --user` | 实为系统级 `claude-auto-sync.service` |
| `docs/architecture.md:199,213` | "11 项检查"/"--quick 跑前 6 项" | 实约 12 项 / quick 跑 9 项 |

> 复核**证伪**：`README` 总数"17"可辩护（=16 marketplace + 1 内部 fskillcreat），仅括号拆分错误。
> 核心入口命令（init-base.sh、maintain.sh 各子命令、init-option.sh、update.sh 各域）经逐条核对**全部一致**。

---

## 5. Python 专项（option-llmswitch/openai_bridge.py）

| 行 | 缺陷 |
|----|------|
| 911 | ✅ `/admin/reload` 泄露 upstream_key（已修） |
| 111,135 | image 块静默丢弃 |
| 478 | 非流式 tools arguments 无 try |
| 467-479 | 非流式遍历所有 choices 混入同一 message，usage 取顶层 |
| 482-487 | 非流式 finish_reason 漏映射 length→max_tokens |
| 199 | tool_choice "any" 应映射为 "required" |
| 130 | tool_result 只取首个 text 块，多块丢失；text_parts 顺序错位 |
| 722,748 | `_iter_with_idle_ping` 无界 queue 无背压；finally 只 cancel 不 await |
| 587,868 | win_curl 失败 status=0，caller 只判 `>=400` → 误报 "upstream non-json" |
| 46 | `except Exception: cfg={}` 吞 llmswitch.json 解析错，静默空配置启动 |
| 456-458 | 行缓冲超 1MB 强 yield 半行，破坏 chunk 边界 |
| 329 | 非法 SSE data 行静默 continue |

**未发现**：裸 `except:`、`eval`/`exec`/`pickle`、`subprocess shell=True`、线程竞争、未关闭响应。

---

## 6. 本轮已落盘的低风险修复

| 文件 | 变更 |
|------|------|
| `hooks/pre-commit` | 密钥正则补 `github_pat_*` / `sk-ant-*`（堵泄漏入口） |
| `bin/memory-check.sh` | `$1` → `${1:-}`，无参不再崩 |
| `lib/path-helper.sh:103` | find_node_bin 裸管道加 `\|\| true`，修 set-e 杀进程 |
| `lib/init-mcp.sh:572` | 菜单序号按 index 取 name，修"启停 MCP 恒失败" |
| `option-skill/init.sh:57` / `option-evalscope/init.sh:79` | 取消判定补 `"$c" == "0"` |
| `lib/monitor.sh:195` | 删 index.lock 前检查活跃 git 进程（`pgrep -x git`） |
| `option-llmswitch/openai_bridge.py:911` | `/admin/reload` 脱敏 `upstream_key` |
| `lib/ensure-bridge.sh:180` | wrapper 权限 `chmod +x` → `chmod 700`（含 key 明文） |
| `option-remote/server/tmux-portforward.ps1:115` | 用户名 `francis` → `<user>` |
| `.gitignore` + `git rm --cached` | 停跟踪 `.playwright-mcp/`（6 文件移出索引，工作区保留） |

验证：改动文件 `bash -n` 全过；`py_compile` 过；pre-commit 正则实测已堵；`memory-check.sh` 无参 rc=0；`find_node_bin` 无 node 环境存活；`test-syntax`/`test-interact` 通过。

---

## 7. 待办（未修，需决策或较大改动）

**需用户决策**：
- §1.1 凭据轮换 + 历史重写（不可逆，需停 monitor）
- `lib/update.sh:428,459` pip-freeze 回写公开文件（改策略：只更新已列出的包名，绝不新增/降级）

**建议排期**：
- 重构：抽 `lib/account-switch.sh`（getnote↔lark 同构）、`lib/option-status.sh`（状态契约单点）、收敛颜色层
- 清理死代码（`grep -rn <name>` 复确认后删 §3.2 清单）
- 让 dry-run 真正接线（sync/ccprivate-upgrade/deploy）或移除其 source
- bridge 非流式路径修复（image/arguments/finish_reason/choices）
- 文档重写：`option-skill/README.md`（第三方流程）、`docs/architecture.md`（memory-projects 路径 / 项数）、`BOOTSTRAP.md`（服务名）、ADR-0027 标注 Superseded
