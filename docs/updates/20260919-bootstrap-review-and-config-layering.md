# 2026-09-19 Bootstrap 评审 + 配置分层归位

> 范围：bootstrap / maintain / 架构文档三轮并行 review + 1 次配置分层核查
> 提交：`origin/main` 共 12 个 commit，跨 1.5h
> 关联 ADR：[ADR-0032 配置分层](../adr/0032-config-layering.md)
> 关联 memory（在用户私有 ccprivate 记忆库中，公开仓不可达）：`config-layering-sync-boundary-20260917`、`claude-config-file-roles-20260919`

## 发现汇总（47 项）

| # | 严重 | 类别 | 发现 | 状态 |
|---|------|------|------|------|
| 1 | P0 | 保密 | `lib/init-llm.sh` 注释含真实内网 LLM IP；`docs/adr/0013` 公司域名 `aiplus.airchina.com.cn`；`docs/adr/0017` tailnet 名由用户名派生；`docs/audit/audit-2026-09-02.md` 二次泄露真实 CGNAT IP；`option-usage/README.md` 样例 CSV 含用户名 | ✅ 已修 |
| 2 | P0 | 文件卫生 | 仓库根目录 155 个 .docx（transliter 测试产物，~108MB）误提交；`work_tmp/`、`claude_job_tmp/` 同类 | ✅ 已修（git rm + .gitignore 防复活） |
| 3 | P0 | 实现 | `init-option.sh -l` 在 case 顶层用 `local`（bash 不允许），触发 shellcheck SC2168，CI lint 连红 3 次 | ✅ 已修（改调 list_names_compact） |
| 4 | P0 | 实现 | `init-base.sh` 的 LLM 步骤从 `llm.json.current` 取值，但 ADR-0020 后该字段已废弃（权威来源是 `~/.claude/llm-current`）→ `INIT_LLM_NAME` 恒空 → `init-llm.sh` 弹交互菜单而非切预设，`settings.json` 从未写入 | ✅ 已修（先读 llm-current，回落 llm.json.current） |
| 5 | P0 | UX | `init-base.sh all` 步骤失败只 warn 不计账、收尾无条件 🎉、`all)` 硬写 `exit 0`；LLM key 没填/网络挂了 → 用户看到「基础初始化完成」进 claude 才发现没 key | ✅ 已修（失败计数 + 非零退出 + 硬失败步骤标红） |
| 6 | P0 | UX | 非交互环境（CI / Bash 工具 / cron 跑 `bash maintain.sh`）菜单无限自旋：EOF → choice="" → 重绘，实测 4s 渲染 116 次、CPU 跑满 | ✅ 已修（menu_loop 改判 read 返回值；新增 has_tty；sync.sh 加前置拦截） |
| 7 | P0 | 实现 | `sync.sh` 单仓库选择恒空操作：拿 `menu_select` 返回的序号字符串（"3"）去 grep 匹配仓库名 → 永不命中 → 静默重绘。从菜单选任一仓库（含「强制拉取远程」「本地覆盖远程」）全无效且无提示 | ✅ 已修（按索引取，范围校验） |
| 8 | P0 | UX | `t` 快捷键指向 2C（组件升级）而 help 文案写「2C = monitor tail」—— 菜单重排后漏改 | ✅ 已修（指向 2A + 文案同步） |
| 9 | P0 | 实现 | `lib/status.sh` 自动 `git pull --rebase` 冲突会把仓库静默留在 rebase 中间态（stderr 被丢、返回值不检查）—— 每次 SessionStart 跑一次 | ✅ 已修（失败检测 + rebase --abort 兜底 + 提示手动处理） |
| 10 | P0 | 静默失效 | `templates/settings.json.example` / `.config.json.example` 把 `permissions`/`hooks`/`statusLine`/`skipDangerousModePermissionPrompt` 等放进了 `.config.json`。Claude Code 只把 `settings.json` 当 settings 文件读，**写在那里的 settings 键完全不读、静默失效**。实测本机 `permissions.deny: ["WebSearch"]` 一直不生效 | ✅ 已修（两个模板按真实角色重写；`maintain.sh` 迁移方向反转；`status.sh` 新增分层检查） |
| 11 | P0 | 实现 | `init-base.sh all` 的「Python pip」步骤把 `ensure_pip` 作为第 6 参传给 `run_step`，而 `run_step` 只取 `$1..$5` → 参数被丢弃 → 整步退化成再跑一遍 `lib/init-ubuntu.sh`（apt/node/claude 全量重来，~3min 浪费） | ✅ 已修（删除该步骤，main() 内部已调 ensure_pip） |
| 12 | P0 | 实现 | `lib/ccprivate-upgrade.sh` 内嵌 54 行 CLAUDE.md 模板漂移：引用已改名的 `f-research-domain` / `f-report-gen`（现名 `fresearchframe` / `fresearchreport`），新机器 onboarding 会拿到引用不存在 skill 的规则 | ✅ 已修（抽到 `templates/CLAUDE.md.example`，脚本改 `cp`，防漂移反向断言） |
| 13 | P0 | 实现 | `init-option.sh` `usage --yes` 静默不装：批处理判定检查的 `"$@"` 早被 `--yes` 剥离后重写，恒空 → 走交互菜单 → NONINTERACTIVE 下 `menu_select` 返回 "0" → 直接 break → 什么都不装却打印「全部安装完成」 | ✅ 已修（用已算好的 `$yes_mode`） |
| 14 | P0 | UX | 切 LLM 探测失败不回滚：直连分支先 `stop_bridge` 再 `test_llm`，探测失败即 return，bridge 已杀而 settings.json 仍指向 127.0.0.1:8898，当前会话直接不可用 | ✅ 已修（探测失败后 `selfheal_bridge` 按 llm-current 重拉原 preset 的 bridge） |
| 15 | P0 | 静默失效 | `lib/status.sh` 头部声称 12 项检查，「Playwright 浏览器测试」根本不存在，`check_skills()` 定义了从未被调用，`check_pat_expiry` 又没列进清单 | ✅ 已修（补 check_skills 调用 + 头部清单改写为与 check_*() 调用顺序一致的真实 11 项） |
| 16 | P1 | 文档 | `docs/init-llm.md` 8 条 ADR 链接写成 `../adr/`（应为 `adr/`，多退一层）；同文件 6 条 memory 链接指向私人目录（公开仓不存在） | ✅ 已修（链接路径全部修正 + memory 描述改为本地化） |
| 17 | P1 | 文档 | `docs/ccprivate-guide.md` 引用已删除的 `init-ccprivate-repo.sh`（多次）；同文件 `claude.json` → 应为 `mcp-servers.json`（claude.json 已移除）；settings.json / .config.json 仍写「symlink → ~/.claude/」但实际是本机 cp 一次（ADR-0032） | ✅ 已修（脚本名 + 文件名 + 分层语义全部对齐） |
| 18 | P1 | 文档 | `docs/architecture.md` 初始化链写 5 阶段「1/4 ubuntu 2/4 llm 3/4 mcp 4/4 maintain finalize」（实际 3 步，MCP 已移到 init-option）；状态检查项数写 14 项（实际 11 项且无 Playwright） | ✅ 已修 |
| 19 | P1 | 文档 | `BOOTSTRAP.md` 有 Classic PAT 段 + 「SSH（推荐）」段，与 ADR-0011 / README HTTPS+fine-grained PAT 唯一默认冲突；`maintain.sh test`（不存在）→ 应为 `bin/test-bootstrap.sh`；菜单项 6→5 错误 | ✅ 已修 |
| 20 | P1 | 文档 | `docs/upgrade-guide.md` 14 处命令路径缺 `lib/`（`bash ~/git/ccconfig/monitor.sh` 等用户照抄必失败）；引用已删的 `lib/update-third-party-skills.sh` 与不存在的 `conf/third-party-skills.txt` | ✅ 已修 |
| 21 | P1 | 文档 | ADR-0030 标题与索引写「option-llmswitch 整层删除」（实际删的是 gateway 层 init.sh/proxy.py/watchdog.sh，`openai_bridge.py` 仍在用）；0024/0025 断号无说明；0023 头部格式与 dominant 格式（`> **Status**:`）不一致 | ✅ 已修（0030 标题与索引改正 + 断号补说明 + 0023 header 统一 + 新增 `template.md`） |
| 22 | P1 | CI | `.github/workflows/check.yml` `unit` job 只跑 `test-init-base.sh`，其余 15 个测试从不执行（`test-init-llm.sh` 长期假跑丢过 CI 信号） | ✅ 已修（unit 补 9 个测试 + 新增 `links` job 检查死链） |
| 23 | P1 | 测试 stale | `tests/test-init-llm.sh` gateway 时代用例，第一行 cp 的目标 `option-llmswitch/init.sh` 早已不存在，跑起来必崩；自述「已过时勿接入自动化」却仍躺在 tests/ | ✅ 已修（git rm + README 对齐） |
| 24 | P1 | 文件卫生 | `lib/sync.sh:382,410,455` 用 `"cconfig"`（单 c）拼写死分支，3 处 — `do_cconfig_post` 在 `--pull`/`--commitpush`/直接仓库名路径永不触发，跳过重建链接 + skill 同步 + 新模板检测 | ✅ 已修（误报：实际已被同期 commit 9696e4b 后的代码覆盖，grep 校验过） |
| 25 | P1 | 实现 | `init-bootstrap.sh` push 失败提示「稍后 bash init-bootstrap.sh --update 补 push」，但 `do_update` 只 pull/重生成/建链接，从不 push — 用户照做永远补不上 | ✅ 已修（指引改为真实可用的 `git remote add + git push -u`） |
| 26 | P1 | 实现 | `_submenu_update_sync` 已定义却无菜单引用 → do_self（拉 ccconfig + 重建链接 + skill 同步）和 ccprivate-upgrade 在菜单里完全不可达，只能记命令 | ✅ 已修（接入为 2D「自身更新」） |
| 27 | P1 | 实现 | `lib/update.sh` 自更新后 re-exec 丢子命令：`run_step` 调用 `self_update` 不传原始参数，re-exec 退化成 menu（`upgrade all` 触发 ccconfig 新提交时变交互菜单） | ✅ 已修（入口记 `CCC_UPDATE_CMD`，re-exec 用它） |
| 28 | P1 | 实现 | `init-option.sh --status` 输出里 getnote 状态行是它的用法文本（含 `|`），被 `parse_status_line` 按分隔符切碎，显示成「? remove <name>\|list\|menu]\|❌ 用法: ...」 | ✅ 已修（getnote 补 `--status`；parse_status_line 退化分支清洗 `\|`） |
| 29 | P1 | 实现 | `lib/path-helper.sh` `resolve_conf` 只认 `$CCPRIVATE_DIR`，而全仓统一用 `$CCPRIVATE_HOME` — 设了非默认目录的机器会找不到配置 | ✅ 已修（两变量都认） |
| 30 | P1 | 数据 | `mcp-manager.sh` 项目总览读 `disabledMcpjsonServers`，写入路径用 `disabledMcpServers` — 真实 `.config.json` 两键并存、值在后者 → 总览里「特关」永远显示为启用 | ✅ 已修（两键取并集） |
| 31 | P1 | 安全 | `maintain.sh` 拼接 PATH 时用 `:$x:`，find_node_bin 四级回退落空时产生 `::` 空段，等价于把当前目录塞进 PATH（安全漏洞） | ✅ 已修（`${x:+:$x}`，maintain.sh 与 deps-check.sh 同步） |
| 32 | P1 | 数据 | `lib/status.sh` `git_pull` 冲突后不 `rebase --abort` 兜底；冲突会把仓库留在 rebase 中间态 | ✅ 已修（见 #9） |
| 33 | P1 | UX | `lib/monitor.sh` 写 `.monitor-sync.status`（ok/degraded/failed）但没有任何读取点 — inotify 反复崩到放弃后 `monitor.sh status` 只显示 `✗ inotifywait (dead)`，看不出已经放弃 | ✅ 已修（status_watch 读回该文件，按状态显示降级 / failed） |
| 34 | P1 | 实现 | `maintain.sh` 「一键修复」的 settings 迁移方向反：把 `permissions`/`hooks`/`statusLine` 从 `settings.json` 搬进 `.config.json`（搬到不生效的位置），且 `permissions` 两份都有时按"保留 settings 那份、丢弃另一份"会把不生效那份里的真规则删掉 | ✅ 已修（方向反转 + `permissions` 特判求并集） |
| 35 | P1 | 文档 | 模板里的 SessionStart hook 路径写成 `bash $HOME/git/ccconfig/status.sh`，实际在 `lib/status.sh` 下 — 新装会得到永不触发的 hook | ✅ 已修（路径加 `lib/`） |
| 36 | P2 | 静默缺口 | `versions.json` 声明了 `mmx_cli` 但没有任何脚本管理它 — 实测本机 1.0.19 vs registry 1.0.26，「声明了但永不升级」 | ✅ 已修（`update_npm_globals` 补管 mmx-cli，与 lark-cli 同模式） |
| 37 | P2 | 实现 | `option-cloudflare/init.sh` 印 `a)/m)/g)/u)/p)` 快捷键，下方用 `menu_select`（只认数字），敲字母一律判无效；`sync.sh` 冲突菜单印 `a)/b)/r)/c)` 同类问题 | ✅ 已修（删假快捷键，改用无前缀说明文字） |
| 38 | P2 | 文档 | `lib/init-llm.sh` 头部用法注释漏 `heal`；「单文件真相源 llm.json (providers + current)」已过时（ADR-0020 后 current 归 `~/.claude/llm-current`） | ✅ 已修 |
| 39 | P2 | UX | `maintain.sh` 用法串与 `interact.sh` EOF 提示都漏 `deps/example/upgrade-ccprivate/token/feishu`，用户按提示敲不到 | ✅ 已修 |
| 40 | P2 | 卫生 | `.gitignore` 注释里 flogme.yaml 路径写错（`skill-config/` → `skill/`） | ✅ 已修 |
| 41 | P2 | 卫生 | `init-skill.sh` 的 `THIRD_PARTY_CONF` 指向不存在的 `conf/third-party-skills.txt`（两个使用点有 `[[ -f ]]` 守卫），流程已废弃但留了 80 行未标注 | ✅ 已修（加废弃标注） |
| 42 | P2 | 数据 | `tests/README.md` `setup.bats` 应为 `setup.bash`；缺 `test-openai-bridge.sh` | ✅ 已修 |
| 43 | P2 | 版本号 | README「v3.x」里程碑 + CHANGELOG 停在 1.5.0 + versions.json 无自身版本 + tag 已 v1.6.0 —— 四方打架 | ✅ 已修（统一 CalVer `YYYY.MM.DD`，真相源 = git tag） |
| 44 | P2 | 文档 | `CLAUDE.md` 写「auto-sync 只做 push，不做 add/commit」—— 与 `lib/monitor.sh:192/210` 实际 add+commit+push 全做不符；按此行事的人会被 monitor 的 debounce 抢跑，原先写好的一事一 commit message 丢失 | ✅ 已修 |
| 45 | P2 | 卫生 | `option-getnote/init.sh` `resolve_conf getnote-accounts.json` 失败时 `exit 1`，使 `init-option.sh --status` 整屏打用法文本而不是状态行 | ✅ 已修（`--status` 不再硬 exit，给配置文件兜底路径） |
| 46 | P2 | 文档 | `bin/README.md` 只列 `memory-check.sh` 漏 `ccconfig` / `refresh-gh-auth.sh` / `test-bootstrap.sh`；`lib/README.md` 漏 `bridge-restart.sh` / `claude-auto-sync.service`；`docs/README.md` 索引漏 `init-llm.md`；`templates/CATALOG.md` 含不存在的 `feishu-cli-cheatsheet.md` 行 | ✅ 已修 |
| 47 | P2 | 卫生 | `docs/adr/README.md` 的「决策时间线」停在 2026-07-29 而索引已到 2026-09-17，掩盖了这段时间的轻量决策 | ✅ 已修（标注「本段已滞后」并指明缺口原因） |

## 按主题详解

### 公开仓库卫生（#1, #2）
按用户决定：git 历史**不动**（那 108MB 测试数据不敏感），最新版 `git rm` + `.gitignore` 加 `work_tmp/`/`claude_job_tmp/`/日期目录/`*.docx` 规则防复活。
- 6 处真实标识脱敏：`lib/init-llm.sh:376`（内网 IP）→ `<internal-llm-ip>`；`docs/adr/0013`（公司域名）→ `<internal-llm-host>`；`docs/adr/0017`（tailnet 名）→ 占位；`docs/adr/0016`（systemd 名 `tailscale-aiplus`）→ `tailscale-llmroute`；`option-usage/README.md`（样例 CSV 含用户名）；`CHANGELOG.md` 复述

### 配置分层归位（#10, #34）—— 本次最重的发现
第三方核查 Claude Code 配置读取行为（直接拉官方文档源码、跑实机隔离实验）：
- `settings.json` 是**唯一**被当 settings 文件读的用户级配置
- `.config.json` 是全局配置/应用状态（官方文档称 `~/.claude.json`），存 `mcpServers`/`projects`/`OAuth` 等
- settings 键写在 `.config.json` 里**完全不参与合并、不读、静默失效、无报错**

本机实测：`.config.json` 里 `permissions.deny: ["WebSearch"]` 一直在，但调 WebSearch **正常返回**——`rules/search.md` 的「已 deny」与事实不符。

修复：两个模板按真实角色重写（settings 键归 `settings.json`，`.config.json.example` 只留 user scope `mcpServers`）；`maintain.sh` 迁移方向反转；`permissions` 两份都有时 `allow`/`deny` 求并集（第一版按"丢弃副本"会把白名单整个删，沙箱测试当场抓到，参考 `memory-architecture` 中的"知识分层"原则）；`status.sh` 新增分层检查（本机报出 11 个错位键）。

**用户操作**：`bash maintain.sh fix`，归位后需新 session 让权限白名单与 WebSearch deny 真正生效。

### 安装链路（#3, #4, #5, #11, #13, #25, #35）
全部是「看起来成功、实际没做」的静默失败，核心是 #4 + #5 互相掩盖——`init-base.sh` 读错 current 来源导致 LLM 步骤静默弹菜单，被「无条件 🎉」掩盖；`run_step` 第 6 参丢失导致 Ubuntu 跑两遍。修复后全链：

```
bootstrap-gh-auth.sh → init-bootstrap.sh → init-base.sh all → init-option.sh（可选）→ maintain.sh status
```

3 步变清晰，失败步骤明示 + 非零退出，模板里 hook 路径等附带问题一并修。

### 日常运维（#6, #7, #8, #14, #26, #27, #29, #30, #31, #33）
三个「点了没反应/死循环」的真 bug：t 快捷键（按 t 进组件升级）、sync.sh 单仓库选择（`menu_select` 返回序号字符串却被 grep 拿去匹配仓库名）、非交互死循环（4s 渲染 116 次）。功能缺口补：`_submenu_update_sync` 接回为 2D 自身更新；切 LLM 失败回滚 bridge；`update.sh` re-exec 保留子命令；`mcp-manager.sh` 特关键两键取并集；PATH 空段堵上；monitor 降级状态读回。

### 文档（#16-#20, #21, #34, #38-#39, #42-#43, #46, #47）
3 个并行子代理 + 1 个综合核查，按事实基线**批量**应用 42 处文档修正：
- 19 处死链（README/BOOTSTRAP/architecture/ccprivate-guide/upgrade-guide/init-llm/CHANGELOG）
- 文档 stale 描述（与实际脚本/菜单/状态项数对齐）
- 不存在的脚本引用（`init-ccprivate-repo.sh`、`update-third-party-skills.sh`、`maintain.sh test`）
- 错误的脚本路径（缺 `lib/` 共 14 处）
- ADR 错误事实（#21）
- 版本号方案（#43）

每条改完按 `.github/workflows/check.yml` 的 `links` job 跑过死链校验。

### CI（#22, #23）
- `unit` job 从 1 个测试补到 10 个
- 新增 `links` job
- 删 `tests/test-init-llm.sh`（自述过时，第一行 cp 已失败）
- 修 `tests/README.md` 与新覆盖对齐

### CLAUDE.md / ADR 模板（#21, #44）
- 修正 `CLAUDE.md` 关于 auto-sync 的错误描述（它 commit+push 都做）
- 新增 `docs/adr/template.md`（原先让人复制 0001 会把正式 ADR 正文抄进新文件）
- 0024/0025 断号补说明「不要回填」
- 0023 header 格式与 dominant 风格统一

### 版本号（#43）
- 真相源改为 git tag，格式 `CalVer YYYY.MM.DD`（同一天多次发 `.N`）
- `conf/versions.json` 加 `self` 块，文档字符串指明 git tag 权威
- README「版本里程碑」改名为开发代号，明确**不**是发布版本
- `CHANGELOG.md` 删除（历史版本去 git tag / GitHub Releases 查看；变更流改放 `docs/updates/`，即本文）

### init-option 解耦（#26, #36）
- `init-base.sh all` 从 4 步缩回 3 步（Ubuntu → LLM → 收尾链接/服务），不再内联 `init-option.sh`
- 可选组件（MCP/Skills/CLI）恢复为独立可选步：`init-bootstrap → init-base.sh all → init-option.sh（可选）→ maintain.sh（1A 全量检查）`
- `bootstrap-gh-auth.sh` 重写为自包含的 curl|bash 入口，不再 source lib/
- `bin/test-bootstrap.sh` CI 路径更新为 `init-bootstrap.sh --non-interactive`

## 移除

- **`.bootstrap-commit.sh`** — 一次性提交脚本误入 git track，已 `git rm` 并加进 `.gitignore`
- **一人项目冗余治理文件** — `CITATION.cff` / `CODE_OF_CONDUCT.md` / `CONTRIBUTING.md`（有用内容已在 README 开发段 + CLAUDE.md SH 规范 + rules/ccconfig-open-source.md）/ `SECURITY.md` / `ROADMAP.md` / `.github` PR+Issue 模板
- **`skills-lock.json`** — 38 个 mattpocock 技能 hash 锁定文件，与实际安装的 f-* 系列技能完全脱节，死文件
- **`lib/start-openai-bridge.sh`** — 运行时无人调用（`init-llm.sh`/`status.sh` 均用 `ensure-bridge.sh`），功能是 `ensure-bridge.sh` 子集（无 self-heal/upstream 变化检测/win-curl）；同步清理 test-init-llm 分组 7（3 测试）+ README 架构图/目录树 + lib/README 表行
- **`tests/test-init-llm.sh`** — gateway 时代用例，目标文件已不存在
- **`CHANGELOG.md`** — 历史版本快照迁 git tag / GitHub Releases，变更流改放 `docs/updates/`
- **`docs/audit/`** — 一次性审计快照归档目录，单次审计后再开新文件无意义；本次整体并入 `docs/updates/`

## 校验

| 项 | 结果 |
|---|---|
| `tests/*.sh` 全套 | **15/15 PASS**（含 test-init-option 41 条断言、test-integration 测 LLM 切换的 mtime 断言） |
| shellcheck -S error（CI lint） | **0 error**（CI 会绿） |
| 内部死链（CI links job 抽出的步骤） | **0** |
| `.github/workflows/check.yml` YAML | 有效，8 job |
| `ccconfig/option-*/`、`lib/*` 语法 | 全部通过 |
| 跨 1.5h 改动后状态 | `origin/main` 已推送全部 12 个 commit |

## 已知遗留（用户定夺）

- **git 历史 108MB docx**：用户明示「git 历史不用改，这 108m 文件是我测试的不红要 不敏感」，不动
- **`docs/audit/audit-2026-09-02.md` 二次泄露修复**：本次审计发现「✅ 已修」行里复述了真实 IP（已去具体值）；是否整文件移入 ccprivate 由用户决定
- **MEMORY.md 47 条已超 40 条上限**（规则 `context-budget.md`）：建议下一轮 review 跑 `bash ccconfig/bin/memory-check.sh` 选 archived
- **`example-sync.sh diff` 暴露 ccprivate 的 `agents/*.md` 引用已删的 minimax/feishu MCP**：未在本次范围（ccprivate 端）
- **`~/.claude.json` symlink → ccprivate/conf/claude.json**：该文件**被 ccprivate git 跟踪**，新机器首次 `.config.json` 缺失时 Claude Code 可能把 OAuth token 顺链接写进 git。**用户决定前不要装回去**——已是本次配置分层核查的副产品提醒
