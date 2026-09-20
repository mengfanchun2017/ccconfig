# 2026-09-20 Bootstrap init 链路 —— 新机安装 / 配置恢复可靠性

> 范围：`init-base.sh` / `init-bootstrap.sh` / `init-option.sh` / `bootstrap-gh-auth.sh` / `templates/ccprivate-setup.sh` / `lib/status.sh`
> 提交：`511f753`（init 修复）、`7514f74`（status 检测）
> 方法：全部结论用沙箱实证（假 `HOME` + 自建 master 分支 ccprivate + 裸远端 + HEAD 版本前后对比），不靠读代码推断
> 关联：[20260919 配置分层归位](20260919-bootstrap-review-and-config-layering.md) · ADR-0032 配置分层 · ADR-0020 llm-current

## 背景

上一轮（20260919）把 `settings.json` vs `.config.json` 的角色搞清楚了，也修了「设置键放错文件静默失效」。本轮顺着同一个问题往下走：**新终端安装 / 恢复配置这条链路上，还有没有别的"看起来成功、实际没做"**。

结论是有的，而且最重的一条正好命中了上一轮修的那个方向——修了"写错文件"，但没修"根本没写"。

## 发现汇总（11 项）

| # | 严重 | 类别 | 发现 | 状态 |
|---|------|------|------|------|
| 1 | P0 | 静默失效 | **本机文件基线键从不写入**。`init-base.sh all` 顺序是 init-ubuntu(建 hooks) → init-llm(建 env) → setup.sh。前两步都会先创建 `settings.json`，setup.sh 随后判「已存在，跳过」→ `permissions`/`hooks`/`statusLine`/`skipDangerousModePermissionPrompt`/`autoUpdatesChannel`/`$schema` 永不落盘。实测裸文件只剩 `{env,model}` —— 权限白名单整个没有，而 status 照样报绿 | ✅ 已修 |
| 2 | P0 | 实现 | **ccprivate 分支名硬编码 `main`，实际仓库是 `master`**（6 处）。`--update`/`--clone` 的 `git pull origin main` 报 `couldn't find remote ref main`；`set -o pipefail` 把非零码透出 → `set -e` 立刻终止 → 后续"重建配置/符号链接"整段跳过。**恢复配置直接失败** | ✅ 已修 |
| 3 | P0 | 数据 | **`--update` 会破坏仓库侧配置**。它调 `gen_llm_json`（只认 deepseek/minimax 两个 key → 重建整个 `llm.json` 抹掉其余 preset）与 `gen_mcp_servers_json`（无条件 `cp` 占位模板 → 盖掉真实 `mcp-servers.json` 的 key）。而这段只在 `llm.json` 已存在时才跑（否则连 key 都取不到），刷新毫无意义 | ✅ 已修 |
| 4 | P1 | 实现 | 拉取失败被当致命错误：网络/代理抖动会让 `--update` 半途死掉，链接不重建 | ✅ 已修 |
| 5 | P1 | 实现 | `gen_claude_md` 内嵌一份陈旧极简 CLAUDE.md，与 `templates/CLAUDE.md.example` 不一致 → **新机走 bootstrap、老机走 upgrade 拿到两份不同的用户级 CLAUDE.md**。同类漂移上轮只修了 `ccprivate-upgrade.sh` 那侧 | ✅ 已修 |
| 6 | P1 | 实现 | `setup.sh` 缺失无守卫（老 ccprivate 或残缺 clone）→ `set -e` 下 `bash: setup.sh: No such file` 静默死，不给修复路径 | ✅ 已修 |
| 7 | P1 | 实现 | `--clone` 模式漏 `setup_git_ident` → 恢复回来的机器没有 `user.name/email`，auto-sync 提交失败 | ✅ 已修 |
| 8 | P1 | 检测缺口 | `status.sh` 只查"键放错文件"，不查"键缺失"——第 1 条正是从它眼皮底下溜过去的 | ✅ 已修 |
| 9 | P2 | 实现 | 首装不写 `~/.claude/llm-current`（ADR-0020 的权威来源），只写废弃的 `llm.json.current` → `init-base.sh` 的 LLM 步骤只能靠"回落废弃字段"碰巧工作 | ✅ 已修 |
| 10 | P2 | 卫生 | gh 安装用固定 `/tmp/gh-install-$$`，两个 job 并行会互相覆盖解包目录 | ✅ 已修 |
| 11 | P2 | 卫生 | `init-base.sh` 菜单用 `bash "$0" new`（相对路径），改 `$SCRIPT_DIR/init-base.sh` | ✅ 已修 |

## 按主题详解

### 1. 基线键从不写入（#1、#8）—— 本轮最重的发现

复现（沙箱，假 HOME）：

```
步骤2 模拟 init-llm.sh 写 settings.json  → 顶层键 ['env', 'model']
步骤3 模拟 setup.sh 的 install_user_file → info: settings.json: 已存在，跳过
最终顶层键 → ['env', 'model']
模板应有键 → ['$schema','env','model','permissions','hooks','statusLine',
              'skipDangerousModePermissionPrompt','autoUpdatesChannel']
```

`init-ubuntu.sh:467` 的 `setup_hook` 也会创建 `settings.json`（只写 `hooks`），所以**问题在第一步就发生**——单纯调步骤顺序堵不住。

修法：`install_user_file` 从「已存在即跳过」改成**只补模板里缺的顶层键，已有键一律不覆盖**。语义是"模板是基线，谁的机器缺基线就补回来"，也不覆盖用户的自主裁剪（比如他故意删掉某条 `perm`）。非 JSON 文件（`.claudeignore`）直通不处理。

实测三处行为都对：幂等（二三跑都"已存在，跳过"）、手删 `permissions` 后自动补回、真实 `ANTHROPIC_AUTH_TOKEN` 保留。

`status.sh` 补上反向检查（缺基线键时给出 `bash ~/git/ccprivate/setup.sh`），双向都查。

**在本机跑了一次**：本机 `settings.json` 实际缺 `$schema`，已补齐；其余键因之前跑过 `maintain.sh fix` 完好。

### 2. 分支名硬编码（#2）—— 恢复配置的主路径

沙箱自建一个 `master` 分支的 ccprivate（带 4 个 preset + 真实 mcp key），跑同一份 `init-bootstrap.sh --update`：

| 版本 | 结果 |
|---|---|
| HEAD (`2e748f3`) | `fatal: couldn't find remote ref main` → **exit=1**，脚本当场死，符号链接一个没重建 |
| 本次修复 | `branch master -> FETCH_HEAD` → `Already up to date` → 继续重建链接 → **exit=0** |

修复后 `llm.json` 的 4 个 preset 与 `mcp-servers.json` 的真实 key 全部无损。

新增 `default_branch()`：`origin/HEAD` → 本地当前分支 → 回落 `main`。`pull` 用探测值，`push` 改推"当前分支"（新建仓库是 `main`、既有仓库是 `master`，硬编码会把 master 仓库推出个孤儿 main）。

### 3. `--update` 的破坏性"刷新"（#3）

`do_update` 里那段"刷新生成配置"整段删除。`--update` 的职责是**恢复本机侧链接**（symlink / 本机文件），不该动**仓库侧配置**（`llm.json` / `mcp-servers.json`）——后者是用户资产，随 `git pull` 来。

注意这段在 master 仓库上其实**够不着**（第 2 条先把它弄死了），但在 `main` 分支的 ccprivate 上是能跑到的，所以是真 bug。

### 4. 模板漂移（#5）

`init-bootstrap.sh` 的 `gen_claude_md` 内嵌一份只有"核心约定/权限/工作目录"三节的极简副本，还写着 `WebSearch 已 deny`（实际那份 deny 在 `.config.json` 里根本不生效，见 20260919 文档）。改成 `cp templates/CLAUDE.md.example`，与 `ccprivate-upgrade.sh` 同源。

### 5. 其余守卫（#4、#6、#7、#9、#10、#11）

- `pull` 全部降级为 `|| warn`，网络失败不再中断恢复链
- 新增 `ensure_setup_sh()`：缺失时从 `templates/ccprivate-setup.sh` 重新生成，3 个调用点（`do_create` 刷新分支 / `do_create` 建链 / `do_clone` / `do_update`）都加守卫
- `--clone` 补 `setup_git_ident`
- `do_create` 首装时写 `~/.claude/llm-current`；`do_update` 刻意不写（会把本机当前选择覆盖成 `llm.json` 里的陈旧值）
- gh 安装改 `mktemp -d`
- `init-base.sh` 菜单 `$0` → `$SCRIPT_DIR/init-base.sh`

## 校验

| 项 | 结果 |
|---|---|
| `tests/test-init-ccprivate-repo.sh` | **45/45 PASS**（含 7 组新回归守卫：分支不硬编码、pull 降级、ensure_setup_sh、CLAUDE.md 走模板、llm-current、基线键补齐、clone 配 git 身份） |
| 其余 14 个测试 | **全 PASS**（`test-maintain.sh` 90/0） |
| `bash -n` 全部改动文件 | 通过 |
| 非 TTY 跑 `bash init-base.sh` | 快速退出 exit=0，无自旋 |
| 沙箱：`init-bootstrap.sh --update` on master repo | 修复前 exit=1，修复后 exit=0 且 preset/mcp key 无损 |
| 沙箱：裸 `{env,model}` settings.json 过 setup.sh | 基线键全恢复，真实 token/hooks 保留 |
| 真机 | `settings.json` 缺 `$schema` 已被补齐；`lib/status.sh` 报「settings 键都在 settings.json 且基线完整」 |

## 已知遗留

- **`push` 未完成**：github 直连与代理 `127.0.0.1:7897` 当时都不通，`origin/main` 落后若干 commit，靠 auto-sync 重试
- **并发编辑**：本轮进行期间有另一个 Claude session 在同一仓库重构 maintain 菜单（`maintain.sh` / `lib/menu-data-maintain.sh` / `lib/interact.sh` / `lib/menu-feishu.sh` / `lib/monitor.sh` / `tests/test-maintain.sh`，已由其提交 `a0cebe5`）。自动同步曾把双方改动扫进同一个 `Auto-sync:` commit，已用 `reset --soft` 拆开，本轮只提交自己的 4 个文件。**同一仓库多 session 并行时，`git add -A` 式的自动提交会吞掉一事一 commit 的粒度**
- **`bootstrap-gh-auth.sh` 未动**：它已自包含、pull 失败有 `|| warn` 守卫，本轮核查无问题
- **`gen_llm_json` 仍写 `llm.json.current`**（废弃字段）：留着是给 `init-base.sh` 的回落路径兜底；新机已同时写权威的 `llm-current`，但没有清理这个字段——清掉会让老机器首次升级时的回落失效，留着无害
