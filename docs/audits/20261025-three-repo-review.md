# 三仓联合 Review 审计报告（ccconfig / ccprivate / skill）

- 日期：2026-10-25
- 范围：三个仓库联合审查 —— `ccconfig`（公开 infra）、`ccprivate`（私密数据层）、`skill`（公开 skill 市场）
- 方法：先读架构文档与 ADR 建立全景 → 4 个维度并行只读审查（多机同步幂等性 / 公开库泄露 / skill 规范 / shell 可靠性）→ 逐条实证复核（关键结论均亲自跑过命令验证）→ 落地修复 → 回归测试
- 规模：ccconfig ~15k 行 shell（29 lib + 3 入口 + option-*）、ccprivate 222 tracked 文件、skill 26 plugin
- 前序：本文**取代并延续** [20261010-architecture-audit](20261010-architecture-audit.md)（下称 1010 审计）
- 状态：报告 + 修复已落盘（见 §7），全部测试 0 失败

> 说明：行号基于审计当日 HEAD。已修项标注 ✅。

---

## 0. 执行摘要

**与 1010 审计的关系**：1010 已抓出"保密红线被历史突破"与"dry-run 未接线"，并决策**不改写历史**（§1.1，确认历史凭据为已失效旧 key）。本轮：

- **确认 1010 的结论正确**（我实证了：历史 PAT 打 API 返回 401、Tavily/Supabase 现值与历史值不同）→ 本轮不再建议吊销，**安全项降级为可选清洁**
- **dry-run 问题找到了真根因并修复**（1010 只说"未接线"，实际是 `run()` 在被包装命令的参数里找开关，永远找不到）
- **新发现 3 个 P0 地雷**（1010 未覆盖：`rm -rf ~/.local`、setup.sh 覆盖、换账号 remote 残留）
- **新发现目标级缺口**：多机"本机配置"无版本水位、账号级数据（MCP key）不随私密仓到新机

整体判断：架构方向正确（三分离 + 动态账号解析），但"多机一致"靠**约定**维持而非**机制**。本轮把关键约定机制化。

---

## 1. P0 —— 会丢数据 / 坏环境（本轮新发现）

### 1.1 ✅ `update.sh` 可能 `rm -rf` 整个 `~/.local`

`lib/update.sh:289` `old_node_dir=$(dirname "$(find_node_bin)")` → `:310` `rm -rf "$old_node_dir"`。

`find_node_bin`（`lib/path-helper.sh:89-119`）策略 1–3 落空时，**策略 4 兜底输出 `$HOME/.local/bin`**（实测确认）→ `dirname` = `$HOME/.local`。守卫只排除 `!= "$new_node_dir"`，拦不住。

**后果**：删掉 `~/.local/`（claude 本体、gh、uv、lark-cli、libinotifytools 全在内）—— 升级脚本把自己和 auto-sync 一起抹掉。
**触发条件**：新机 / 用 apt 或 nvm 装 node（`~/.local` 下无 `node-v*` 目录）。本机因 `~/.local/bin/node` 是真 symlink（走策略 1）而安全，属**未引爆的地雷**。

**修复** ✅：`case "$old_node_dir" in "$HOME"/.local/node-v*-linux-x64)` 白名单，非白名单路径只告警不删。回归测试 `tests/test-node-cleanup-guard.sh`（9 例）。

### 1.2 ✅ 升级无条件覆盖 `ccprivate/setup.sh`，静默丢本机自定义

`lib/ccprivate-upgrade.sh:160} fix_setup_sh` 无条件 `cp 模板 → setup.sh`。

检测函数 `check_setup_sh_version` 用 `grep -q 'resolve_conf'` && `grep -q 'link/memory'` 判"是否最新"——**这两个串在注释里就命中**，于是任何被本机改过的 setup.sh 都被误判"已是最新"，自定义**靠假阳性偶然幸存**；一上游改注释就突然判 fix → 覆盖 → 丢功能。

**本机实证**：`ccprivate/setup.sh` 比模板多 16 行（`3b. 项目级记忆` 段，建 `~/.claude/projects/<id>/memory → ccprivate/link/memory-projects/` 的 symlink）。本机现存的那个 project memory symlink 就是这段建的。

**附带**：备份名只到日（`setup.sh.bak.$(date +%Y%m%d)`）→ 同日第二次升级覆盖当天备份；且 `ccprivate/.gitignore` 的 `*.bak` 不匹配 `setup.sh.bak.20261025` → 备份会被 auto-sync 提交进私密库。

**修复** ✅：
- 把「3b 项目级记忆」段**上游进 `templates/ccprivate-setup.sh`**（其他账号同受益，本机不再算"自定义"）→ 模板与 `ccprivate/setup.sh` 现**逐字节一致**
- 检测改严格 `diff -q`（不再 grep 关键词）
- 覆盖改保护式：本机有改 → 存 `setup.sh.new` + 提示合并，`CCPRIVATE_SETUP_FORCE=1` 才强覆盖
- 备份带时分秒 + `ccprivate/.gitignore` 加 `*.bak.*`

### 1.3 ✅ 换账号时三仓 remote 不跟随，且无一致性校验

- `lib/init-skill.sh:59-63`：`~/git/skill` 已存在就只 `git pull --ff-only origin main || true`，**从不检查/更新 remote**
- 三仓**没有任何** remote↔当前 gh 账号一致性检查（grep 确认 status/maintain/sync/monitor 都无）

**后果**：换账号复用同一 HOME 时，pull 用旧 remote + 旧 PAT，失败被 `|| true` 吞掉 → 新账号静默拿不到 skill 仓；候选列表 `[$gh_user/skill, upstream]` 根本没机会执行。

**修复** ✅：
- `ensure_claude_skills` 加守卫：remote 属主 ≠ 当前账号 且 ≠ upstream → `git remote set-url`
- `lib/status.sh` 新增三仓 remote 属主核对告警

---

## 2. P1 —— 功能不达目标

### 2.1 ✅ `--dry-run` 全线失效（信任链破口）

`lib/dry-run.sh` 的 `run()` 内部调 `_dry_run_enabled "$@"`，但 `"$@"` 是**被包装命令自己的参数**（`run npm install -g foo` 里就是 `npm install -g foo`），而 `_dry_run_enabled` 只读全局 `CCC_DRY_RUN` 和脚本参数 → **永远找不到 `--dry-run`**。

grep 确认**没有任何地方**把 argv 转成 `CCC_DRY_RUN`。于是文档承诺的 `bash lib/x.sh --dry-run`（`dry-run.sh:7` 注释、`init-skill.sh:9`）**不生效**，而 `init-skill.sh` 有 `sudo apt-get` / `npm install -g` —— 用户以为在预览，**实际在装包**。

**修复** ✅：
- `run()` 改为只认全局 `CCC_DRY_RUN`
- 新增 `dry_run_parse_argv`，并在 `dry-run.sh` 末尾**自动调用**：bash `source` 不带参数时，被 source 的文件能读 `/proc/$$/cmdline` 拿到调用者参数 → 一处覆盖全部 30 个入口，不靠各脚本记得调
- 回归测试 `tests/test-dry-run-argv.sh`（4 例，含"dry-run 下 run() 不得真执行"）

### 2.2 ✅ 账号级数据（MCP key）不随私密仓到新机

`~/.claude/settings.json` 混装两类数据：
- **每机独立**（LLM env）—— `maintain.sh:237-243` 自己写明
- **账号级**（MCP 的 tavily/exa key）—— 每台机都一样，被塞进了同一个 gitignore 文件

真实 key 的**正确**来源 `ccprivate/conf/mcp-servers.json`（受跟踪、含真值：tavily/exa/cloudflare）存在，但新机流程 `init-base.sh → init-ubuntu → ccprivate/setup.sh` **不跑 `init-mcp.sh sync`**（只有手动 `maintain.sh fix` 才跑）→ 新机装完，MCP key 不会出现在运行时。

**修复** ✅：`init-base.sh` 在"收尾（私有链接）"后加 `init-mcp.sh sync` 步骤（账号级数据随私密仓下发；往返闭环早就有：`export` 原子写 conf → `sync` 下发）。

### 2.3 ✅ 新机 `init-base.sh all` 会挂住

`init-base.sh:108-115` 依赖 `~/.claude/llm-current`，而 `init-bootstrap.sh do_clone`（换机路径）**不写**它，`llm.json` 也已不写 `current`（ADR-0020）→ `INIT_LLM_NAME` 空 → `init-llm.sh` 掉进交互菜单 → `NONINTERACTIVE=true` 下挂死。只有 `do_create`（全新账号）才写。

**修复** ✅：`do_clone` 补 `llm-current`（从 `llm.json` 的 current 或首个 preset 解析；实测解析出 `minimax31`）。

### 2.4 ✅ 模板补键只比顶层键，嵌套缺键永远补不上

`ccprivate/setup.sh` 与 `lib/status.sh` 都做 `[k for k in t if k not in d]`（仅顶层）。若 `settings.json` 已有 `permissions` 顶层键（哪怕 `{}` 空壳），`permissions.allow` 26 条缺失也判"已就绪"→ **status 报绿，白名单实际没生效**。

**本机实测**：`permissions.allow` 缺 **22 条**（Read/Edit/Grep/Glob/mcp__tavily 等基线）—— 一直没被发现。

**修复** ✅：
- `install_user_file` 改下钻一层（dict 递归 + `allow`/`deny`/`ask` 取并集，不删本机已有）
- `status.sh` 的 `missing` 检查改同款 `missing_paths`
- 实测补齐 22 条后 status 转绿

### 2.5 ✅ 私有 skill 的 `deps.txt` 被静默跳过

`lib/init-skill.sh:126` 扫依赖只遍历 `$SKILLS_SRC`（公开源），而 `_collect_all_deps`（`:539`）与 `do_link_self_built`（`:381`）都是**两源** → `ccprivate/skill-local/` 自建 skill 声明的 npm/apt/pip 依赖，`sync` 时不装。

**修复** ✅：`do_install_cli_deps` 改扫两源。

### 2.6 ✅ `libicu78` 硬编码发行版号

`skill/plugins/{fdocx,fxlsx,fpptx}/deps.txt:2` 写死 `libicu78`（Ubuntu 26.04 包名）。Ubuntu 24.04 只有 `libicu74` → 安装失败 → .NET 二进制报 `Couldn't find a valid ICU package`。ccconfig 侧的 `lib/ensure-libicu.sh` 早已是自适应（`apt-cache search` 挑最高版本），**skill 侧没跟上**。

**修复** ✅：`init-skill.sh` 的 apt 分支加 `libicu[0-9]+` 包名按本发行版改写（与 `ensure-libicu.sh` 同口径）。

### 2.7 ✅ `example reverse` 会把真实 key 写进公开仓

`lib/example-sync.sh` 的 `reverse_one` 做 `cp ccprivate → ccconfig/**/*.example`，只有一行 `warn "conf 文件可能含密钥"`，**无扫描**。且 pre-commit **只装在 ccconfig**（skill 仓当时无 hook）→ 写进 `.example` 后无第二道防线 → 直接推公开库。

**修复** ✅：
- 抽 `lib/secret-patterns.sh`（`$SECRET_RE` 单一真相源；pre-commit 与 example-sync 曾各写一份、漂移过）
- `reverse_one` 加硬闸：命中即中止（打码回显）+ 写后复检 + `FORCE_REVERSE=1` 越权口
- pre-commit 装到**两个公开仓**（ccconfig + skill）；`ccprivate` 是私密仓（本就存 key）**不装**，避免自拦截
- 测试文件例外（`tests/*`、`*test*.sh|bats|py` 跳过密钥扫描——它们需要密钥形状的样本；约定样本运行时拼装，`tests/test-secret-patterns.sh` 有自查断言）

---

## 3. P2 / 系统性

### 3.1 ✅ 每机配置漂移无版本水位（目标级缺口）

`settings.json` / `.config.json` / `.claudeignore` 是每机独立文件，模板更新后**没有任何机制**知道某台机落后了几代。`status.sh` 只查基线键存在性，不查内容过期。

**修复** ✅：
- `ccprivate/setup.sh` 写 `~/.claude/.ccconfig-init`（version / applied_at / template_hash）
- `status.sh` 新增「本机配置代次」段，比对 template_hash 并给修复指引
- `maintain.sh fix` 第 3 步纳入"本机配置补到当前模板"

### 3.2 ✅ 升级无回滚

全仓只有 `update.sh` 往 `.snapshots/` 存**版本号**（不存文件），`ccprivate-upgrade` 只备份 setup.sh 一份。

**修复** ✅：新增 `lib/snapshot.sh`（`take|list|restore|prune`），升级/初始化前打包关键文件到 `~/.claude/ccconfig-snapshots/`（700 权限，含真实 key）。`update.sh all` 已接入。

### 3.3 ✅ `fskillcreat` 教用户手动 git 提交（与 auto-sync 冲突）

`skill/plugins/fskillcreat/SKILL.md:67-68` 教 `git add . && git commit && git push`，与 `ccconfig/CLAUDE.md`「auto-sync 独占提交权」+ `rules/git.md`「`~/git/` 下不手动 add/commit」直接冲突（手动提交会与 monitor 抢跑，两边改动被扫进同一 commit）。

**修复** ✅：改为"改完即止，等 monitor 自动提交"+ 说明原因。

### 3.4 ✅ 4 个 `config.yaml.example` 指向不存在的路径

`ccprivate/config/<x>.yaml` → 实际是 `ccprivate/skill/<name>.yaml`（`apply-config.sh:17` 的 `CCPRIVATE_CONFIG=$CCPRIVATE_DIR/skill`）。影响 fsearch / fresearchframe / fsysarchi / fworch-report。

**修复** ✅。

### 3.5 ✅ 5 个 skill 的 description 残留英文 `Use when`

违反 `ccprivate/rules/skill.md:5`「description 必须全中文」。fdocx / fxlsx / ffeishu / fmoocrec / fsysarchi，且已污染 `marketplace.json` 5 条。

**修复** ✅：改中文主动式「用法：用户说…」+ 重跑 `sync-marketplace.py` 同步。

### 3.6 ✅ `sync-marketplace.py` 不自动登记新插件

只报 `ORPHAN` 不自动加条目 → 新 skill 永远漏登记（要人肉补 marketplace，否则 `/plugin` 列表里看不见）。

**修复** ✅：`--write` 现在为每个"有 SKILL.md 而无条目"的目录自动建条目。新增 `fsecretcheck`（第 26 个 plugin）即靠此登记。

### 3.7 ✅ 其他

- `~/git/ccprivate` 硬编码改 `${CCPRIVATE_HOME:-$HOME/git/ccprivate}`（fworch-course / fworch-interview 及其 comm-contract）
- README/CLAUDE.md 的 plugin 计数 24 → 26
- 删死代码：`lib/safe-exit.sh`（零引用）、`sv_ct.html`（492KB tracked 页面 dump）、`lib/__pycache__/`
- `update.sh` 锁文件 `/tmp/ccconfig-update.lock` → `${XDG_RUNTIME_DIR:-/tmp}/ccconfig-update-$(id -u).lock`（避免多用户共享 `/tmp` 时 PID 复用误判）
- 新增 skill `fsecretcheck`（公开仓密钥守门员；**私密仓只报告不拦截**）

---

## 4. 未修（有明确理由）

| 项 | 理由 |
|---|---|
| **ADR-0032 决策 4「模板拆分」** | 该决策**本身是错的**：说把 `permissions`/`hooks`/`statusLine` 移到 `.config.json.example`，但官方文档 + `maintain.sh` 自身告警都是"放 `.config.json` 完全不读、静默失效"。**从未实施是对的**，本轮未照它改。建议后续更新该 ADR 的措辞（见 §5） |
| **6 套仓库拉取实现已合并** | ✅ 已抽 `lib/git-pull.sh` 单点实现（`git_pull_repo`：分支自适应 + 代理注入/剥死代理 + 冲突 abort 回滚）。6 处调用点已全部改调（maintain / status / init-skill / sync×2 / update）。**monitor 保留自有实现**——auto-sync 热路径、行为即参考来源，且其冲突检测需要 rebase 中间态（共享版"冲突即 abort 回滚"，语义不同）。回归测试 `tests/test-git-pull.sh`（9 例：四种行为 + 分支自适应 + 无残留裸 pull 断言） ✅ |
| **monitor 的 90s stale 锁阈值** | 短于单次 `commit_and_push` 最坏耗时（可 >120s）→ 第二调用者可能 rm 掉仍被持有的锁。属并发边缘场景，改动需谨慎验证 |
| **历史改写（filter-repo）** | 凭据已失效（§6），1010 已决策不改写；维持现状 |

---

## 5. 待办（建议排期）

1. ~~**合并 6 套仓库拉取**~~ ✅ 本轮已完成（`lib/git-pull.sh`，见 §4）
2. **ADR-0032 措辞修正**（把错误的"模板拆分"决策改为"不拆，并说明为什么"）
3. **MCP 双文件冗余**：`init-mcp.sh` 同时写 `settings.json` 与 `.config.json`，代码注释自承"settings.json 里的 mcpServers 不生效"。官方文档确认 MCP 存 `~/.claude.json`（即此处的 `.config.json`）→ settings.json 那份是死代码，可删
4. **MCP 双实现合并**：`init-mcp.sh`(614) + `mcp-manager.sh`(611)，后者 3 处转发前者，且**两份都非原子写**
5. **bridge 子系统零测试**：`ensure-bridge.sh`(511) / `bridge-service.sh` / `bridge-supervisor.sh` / `bridge-restart.sh` / `init-autostart.sh` 全无测试，而 ADR-0050 刚做过结构性重构
6. **菜单分组三套定义**（`init-option.sh:40` / `menu-data-maintain.sh` / `status.sh:537`）统一到 `MENU_ENTRIES` schema
7. **`option-skill/README.md` 整篇过时**（仍描述已废弃的 npx 第三方流程）

---

## 6. 安全结论（更正本轮早先判断）

本轮一度建议「吊销历史泄露的 GitHub PAT」——**经实证该建议错误，特此更正**：

| 凭据（按服务） | 实测结论 |
|---|---|
| GitHub PAT（旧 fine-grained token） | 拿历史值打 `api.github.com/user` → **HTTP 401（已失效）**；当前在用的是另一个 token（ID 不同） |
| Tavily（两个旧 dev key） | 当前 key 已换成新值，**两者均已轮换** |
| Supabase（旧 service_role key） | 当前 key 已换成新值，**已轮换** |
| `sk-cp-…`（2026-03-19 老值，当时作 `ANTHROPIC_AUTH_TOKEN`/`MINIMAX_API_KEY`） | 当前 ccprivate 已换新值，**已轮换** |

**与 1010 审计 §1.1 结论一致**（该处已确认"历史凭据为已失效旧 key，不改写历史"）。工作树干净；skill 仓历史干净。

**结论：无需吊销，filter-repo 属可选清洁**（凭据已失效，重写历史只是让 clone 者看不到旧快照）。

---

## 7. 本轮变更清单

**ccconfig（公开）**

| 文件 | 变更 |
|---|---|
| `lib/update.sh` | 旧 Node 清理加白名单；锁文件按用户隔离；升级前接入 snapshot |
| `lib/ccprivate-upgrade.sh` | setup.sh 检测改严格 diff；覆盖改保护式；备份带时分秒 |
| `lib/status.sh` | 加三仓 remote 账号核对；加「本机配置代次」段；嵌套缺键检测 |
| `lib/init-skill.sh` | skill remote 账号守卫；依赖扫两源；libicu 包名自适应 |
| `lib/example-sync.sh` | 反向同步加密钥硬闸 + 写后复检 |
| `lib/dry-run.sh` | `run()` 只认全局开关；自动解析 argv |
| `lib/setup-links.sh` | pre-commit 装到 ccconfig + skill 两个公开仓 |
| `lib/snapshot.sh` | **新增**：配置快照 + 回滚 |
| `lib/secret-patterns.sh` | **新增**：密钥正则单一真相源 |
| `hooks/pre-commit` | 规则 1/2 限 ccconfig；测试文件例外；规则 3 两公开仓生效 |
| `templates/ccprivate-setup.sh` | 上游项目级记忆段；嵌套补键；版本水位；代次标记 |
| `init-base.sh` | 新机流程加 `init-mcp.sh sync` |
| `init-bootstrap.sh` | `do_clone` 补 `llm-current` |
| `maintain.sh` | fix 第 3 步纳入本机配置补齐 |
| `tests/` | 新增 `test-node-cleanup-guard.sh`(9) / `test-secret-patterns.sh`(16) / `test-dry-run-argv.sh`(4)；`test-init-ccprivate-repo.sh` 测试 23 改行为断言 |
| 删除 | `lib/safe-exit.sh`、`sv_ct.html`、`lib/__pycache__/` |

**ccprivate（私密）**

| 文件 | 变更 |
|---|---|
| `setup.sh` | 同步模板（含项目级记忆段 + 嵌套补键 + 版本水位） |
| `.gitignore` | 加 `*.bak.*` |
| `link/memory/MEMORY.md` | 加本轮 memory 索引条目 |

**skill（公开）**

| 文件 | 变更 |
|---|---|
| `plugins/{fdocx,fxlsx,ffeishu,fmoocrec,fsysarchi}/SKILL.md` | description 去英文 `Use when` |
| `plugins/fskillcreat/SKILL.md` | 删手动 git 提交指引 |
| `plugins/fsecretcheck/SKILL.md` | **新增**：密钥泄露检查 skill（第 26 个 plugin） |
| `plugins/{fsearch,fresearchframe,fsysarchi,fworch-report}/config.yaml.example` | 修正指向不存在的路径 |
| `plugins/{fworch-course,fworch-interview}/**` | `~/git/ccprivate` → `${CCPRIVATE_HOME:-…}` |
| `scripts/sync-marketplace.py` | 自动登记新插件 |
| `.claude-plugin/marketplace.json` | 26 plugin，version 0.14.0 |
| `CHANGELOG.md` / `README.md` / `CLAUDE.md` | 0.14.0 条目；计数 24 → 26 |
| `.git/hooks/pre-commit` | 新装（公开仓密钥防线） |

**验证**：全部 shell 测试 0 失败（含 6 个 bats 文件 57 例 + 20 个 shell 测试文件）；skill 仓 CI 三项本地通过（config 卫生 / marketplace JSON / description 无漂移）；30 个入口 `bash -n` 通过。