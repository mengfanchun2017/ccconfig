# Changelog

All notable changes to ccconfig will be documented in this file.

## [1.4.8] — 2026-07-12

### Fixed
- **`init-ubuntu.sh` `setup_ccprivate`** — 从 ubuntu.json 读硬编码 `/home/francis` 路径致 `mkdir` 权限拒绝 → `set -e` 退出，Node/Claude Code 未安装。改用 `$HOME/git/ccprivate` + 已 clone 则跳过
- **`bootstrap.sh`** — `$OLDPWD`→`SCRIPT_DIR`（非 repo 根运行时版本查找静默失败）、GRAY ANSI `\033[0:0m`→`\033[0;90m`、硬编码用户名范化
- **`init-skill.sh`** — `GITHUB_USER` parse 时一次性求值→`_github_user()` 延迟函数；git `insteadOf` 规则冲突（HTTPS↔SSH 互相覆盖）；claude-skills clone 用户 fork 优先→上游公共仓库回退
- **`bin/init-ccprivate.sh`** — feishu.json `$HOME` 字面量→`os.path.expanduser("~")`；`gen_ubuntu_json` typo `cconfig`→`ccconfig` + 读 `CCCONFIG_DIR` 环境变量
- **`init-ubuntu.sh`** — inotify-tools apt 优先 + `uname -m` 架构检测；`setup_claude_api`→`setup_llm_backend`
- **`www/index.html`** — commit hash 断裂、"macOS"→"Ubuntu/WSL"、移动端导航+复制按钮修复
- **`docs/` 安全** — 替换 Feishu Base table ID + Worklog record ID 为占位符；修复 `task_plan.md`/`findings.md` 内部链接
- **Agent 配置** — `assistant.md`/`knowledge-expander.md` 补回 `Skill` 工具
- **`link/` 示例文件** — `settings.json.example`/`claude.json.example` API URL/模型用占位符

### Changed
- **`init.sh`** — 结语提示路径 `ccconfig/…`→`$SCRIPT_DIR/…`
- **CCPRIVATE 变量统一** — `init-skill.sh`/`init-ubuntu.sh` 改用 `CCPRIVATE_HOME`
- **`deps-check.sh`** — 修复建议路径 `ccconfig/…`→`$SCRIPT_DIR/…`

## [Unreleased]

## [1.4.7] — 2026-07-11

### Added
- **`bootstrap.sh`** — 全新 WSL 一行起步脚本。`curl | bash` 即可完成 git 检测 + sudo apt 装 git + clone ccconfig + 输出 init.sh 引导。支持 `CCCONFIG_REPO`/`CCCONFIG_BRANCH`/`BOOTSTRAP_NOSUDO` 环境变量；幂等（重跑 = pull）
- **`tests/test-bootstrap.sh`** — 12 类 24 用例覆盖默认值/4 步结构/curl wget fallback/幂等性/PATH 隔离检测

## [1.4.6] — 2026-07-11

### Fixed
- **`init-ccprivate.sh` gh 缺失自动装** — 新增 `ensure_gh_cli()`，gh 不在 PATH 时引导选择 apt 或 binary 装到 `~/.local/bin/gh`，解决首次初始化 `gh: command not found` 直接退出
- **`init-ccprivate.sh` git identity 缺失** — 新增 `ensure_git_ident()`，git init 前检测 `--global` user.name/email，缺失则用已收集的 `GH_USER`/`GIT_EMAIL` 写入，再缺则交互询问；解决 `fatal: empty ident name ... not allowed`
- **`init-ccprivate.sh` feishu 占位符引导** — 新增 `prompt_feishu_config()`，检测到 `conf/feishu.json` 还是 `.example` 模板时询问「现在填 or 跳过」，填则交互收集 App ID/App Secret/应用名；跳过则保留占位符（晚点手动编辑）
- **`init-ccprivate.sh` gh auth PAT 推荐路径** — `check_gh_auth()` 重写：GH_TOKEN 环境变量 → SSH 检测 → **PAT 引导（带完整 URL + 4 步操作）** → Web OAuth → SSH only；PAT 默认推荐（最稳、不依赖浏览器、跨平台），含 `https://github.com/settings/tokens/new` 链接和 scope 清单（`repo`/`read:org`/`gist`），`read -s` 不回显，自动清理 Windows CRLF 防 `Bad credentials`，格式校验 `^(ghp_|github_pat_)`

## [1.4.5] — 2026-07-10

### Fixed
- **LLM env 不再被覆盖** — `init-mcp.sh sync` 改为 merge env，保留 `init-llm.sh` 写入的 LLM 配置；解决「显示 DS，进来是 minimax」
- **`gen_claude_json` 不再生成 LLM env** — LLM 配置由 `init-llm.sh` 独占管理，避免冲突
- **`deps-check.sh` pip3 检测** — 改用 `python3 -m pip --version`，避免 venv 系统误报缺失
- **`init-ccprivate.sh` cd 强引导** — `do_create` / `do_clone` 末尾加 `cd $CCCONFIG_DIR` 黄色提示，新机器配置更明确

### Removed
- **`init-llm.sh` API Error 死提醒** — 切换后不再弹无意义告警
- **`init-mcp.sh` 大标题框 + [未注册] 列表** — UI 精简
- **`init-mcp.sh` npx 预缓存** — 首次使用自动下载，init 时不再卡 30s
- **`init-mcp.sh` 同步到 GitHub section** — 改为静默写入
- **`init-mcp.sh` 末尾飞书 Bridge 提示** — 已在 init.sh 最终输出列出

## [1.4.4] — 2026-07-10

### Fixed
- **三层交互简化** — `do_create` 本地已有 ccprivate → 直接 setup.sh；GitHub 已有 → 自动 clone；完全新建 → 收集信息
- **`do_clone` 幂等** — 已有 git repo → pull；非 git 目录 → 删除重建；否则 → 新 clone

## [1.4.3] — 2026-07-10

### Changed
- **Skill 源迁移** — mattpocock/skills 官方源；删 caveman；diagnose→diagnosing-bugs；write-a-skill→writing-great-skills

## [1.4.2] — 2026-07-10

### Changed
- **CLI 工具不自动装** — `init-ubuntu.sh` 不再 `sudo apt install bat/glow`，只检查状态；可选工具统一在末尾提醒
- **Python 包移出初始化** — `init.sh all` 步骤 5 纯验证，不再跑 `update.sh python`；Python 包独立命令
- **Cloudflare → option** — `cloudflare.json.example` 移至 `option-cloudflare/`，不再自动链接；按需 `bash ccconfig/option-cloudflare/init.sh`
- **可选组件统一** — 所有 option（Bridge/Cloudflare/OfficeCLI/CLI 工具/Python）集中在 init.sh all 结束提醒

## [1.4.1] — 2026-07-10

### Fixed
- **`.generated` 回退** — `ccprivate/setup.sh` 加回 `.generated/*.json` 链接，兼容旧格式 ccprivate repo（v1.3.7 及更早）。新格式 `conf/` 优先，旧格式 `.generated/` 作为回退
- **步骤 5 `run_step` 崩溃** — `bash bash` 双重嵌套导致 "cannot execute binary file"，改为直接传脚本路径
- **claude-skills 噪音** — `check_first_time` 不再警告 claude-skills 缺失（`init-skill.sh` 自动 clone）

## [1.4.0] — 2026-07-10

### Changed (架构重构)
- **消除 skills 重复初始化** — `setup-links.sh` 移除 `init-skill.sh sync` 调用，skills 统一由 `init.sh all` 步骤 4 管理
- **智能检测已有 ccprivate** — `init-ccprivate.sh` 自动检查 GitHub 是否已有 ccprivate 仓库，有则引导 `--clone`，避免重复创建
- **5 步初始化** — `init.sh all` 重构为 5 步（Ubuntu → LLM → MCP → Skills → 验证），每步后提示下一步
- **下一步提示** — 每个初始化脚本结束时输出清晰的下一步命令，用户无需翻文档

## [1.3.9] — 2026-07-10

### Fixed (review findings)
- **#1 do_update 迁移** — 加 `.generated/` 回退检查，旧 repo 也可刷新配置
- **#2 Shell 注入** — `do_update` 的 `python3 -c` 双引号插值改为 heredoc + env var 安全模式
- **#3 setup-links.sh** — `gen_setup_sh` 加回 `ccconfig/setup-links.sh` 调用，防止新用户丢失 agents/rules/skills 链接
- **#4 .example 占位符** — 复制 `.example` 时检测占位符值（请填入/your key 等），含占位符时 warn
- **#5 python3 合并** — `do_update` 6 次 `python3 -c` 合并为 2 次 heredoc
- **#6 测试** — 重写 `test-init-ccprivate.sh`，13 用例含 .generated 迁移 + placeholder 拒绝 + symlink 解析

## [1.3.8] — 2026-07-10

### Fixed
- **根因修复** — `gen_llm_json`/`gen_claude_json`/`gen_ubuntu_json` 写入 `ccprivate/conf/`（原 `.generated/` 隐藏目录），消除 `.example` 模板覆盖冲突
- **`gen_setup_sh`** — 缺 conf 链接逻辑导致 `cconfig/conf/llm.json` symlink 从未创建，`ensure_config` 复制占位符模板 → init-llm 写入 `请填入你的 DeepSeek API Key` 到 settings.json → Claude 连不上
- **ccprivate/setup.sh** — 移除 `.generated` 4b 段，conf 统一由 4a 段链接；移除 `cconfig/setup-links.sh` 调用避免 skills 在 init-ccprivate + init.sh all 间重复跑两次
- **测试** — `tests/test-init-ccprivate.sh` 14 用例覆盖路径/占位符检测/symlink 解析/settings.json 写入/正则过滤

## [1.3.7] — 2026-07-10

### Fixed
- **`init-llm.sh`** — `_write_llm_config()` 漏 export `CONFIG_FILE` 导致 Python heredoc KeyError，settings.json 被部分写入后崩溃
- **`init-llm.sh`** — 占位符 key 检测：`ensure_config` 复制模板后 key 含「请填入」仍被写入 settings.json，现跳过并警告
- **`init-llm.sh`** — 写顺序调整：先写 `conf/llm.json`（源），后写 `settings.json`（派生），避免源写入失败时派生文件已被污染

## [1.3.6] — 2026-07-10

### Added
- **`init-ccprivate.sh`** — `--update` 模式：已有 ccprivate 时 pull + 刷新 .generated 配置 + 重建 symlink，不再只能用 clone
- **`init-ccprivate.sh`** — `check_gh_auth()` 预检：写操作前验证 `gh auth status`，未认证时引导 `gh auth login`
- **`www/index.html`** — 三步流程中每个 `<code>` 命令旁加 📋 复制按钮；终端模拟器加「复制命令」按钮

## [1.3.5] — 2026-07-10

### Fixed
- **`init-ccprivate.sh`** — GH_USER 为空时无校验导致 `gh repo create "/ccprivate"` 报错，加非空循环验证；GitHub 用户名正则放宽支持单字符

## [1.3.4] — 2026-07-10

### Fixed
- **`init-ccprivate.sh`** — `detect_gh_user()` gh auth 失效时 401 JSON 被捕获为用户名，含 `"` 字符破坏 Python heredoc 语法；加正则校验过滤非用户名输出，Python heredoc 改用 env var 注入替代 shell 插值

## [1.3.3] — 2026-07-10

### Changed
- **域名标准化** — `config.aiagt.dev` (ccconfig) + `skill.aiagt.dev` (ccskills)，互链统一
- **`ensure_claude_skills()`** — gh 未就绪时静默跳过，不在 Step 2 显示无行动力的 warning；gh 就绪时才尝试 clone 并提示

## [1.3.2] — 2026-07-09

### Changed
- **域名迁移** — ccconfiged.pages.dev → cconf.aiagt.dev、ccskills.pages.dev → cskills.aiagt.dev
- **CF Pages 落地页** — `www/index.html` 重写三步流程（ccprivate → init.sh all → 完成）、终端命令更新、I18N 中英双语
- **commit hash 显示** — pre-commit hook 注入 HTML 占位符，纯静态方案，不依赖 GitHub API（不受限流）

### Fixed
- CF Pages 构建失败 — `wrangler.toml` `build.command` 对 Pages 无效，改回纯静态部署
- commit hash 显示 `···` — GitHub API 无认证限流 60req/h 导致 fetch 失败

## [1.3.1] — 2026-07-09

### Added
- **`tests/test-init.sh`** — init 流程自动化测试（17 用例，mock 隔离环境，零网络秒级完成）
- **`check_first_time()`** — `init.sh` 首次初始化引导，自动检测缺失的 ccprivate/claude-skills 并引导创建

### Changed
- **`init-skill.sh`** — 新增 `ensure_claude_skills()` 自动 clone claude-skills 仓库；`do_status()`/`do_list()` 加目录守卫；缺目录时优雅降级不报错
- **`init-ubuntu.sh`** — placeholder 检测（避免用模板值 clone）、`$HOME` 字面量展开修复、`setup_symlinks()` 非致命
- **`init-mcp.sh`** — sync 目标路径修正为 `~/.claude/settings.json`（之前写到不存在的 `cconfig/link/settings.json`）；broken symlink 处理；缺 `~/.claude.json` 容错
- **`setup-links.sh`** — skills 同步失败不中断
- **`sync.sh`** — `do_cconfig_post()` 中 setup-links 非致命
- **`status.sh`** — `check_skills()` 路径改用 `CLAUDE_SKILLS_SRC` 环境变量
- **`lib/path-helper.sh`** — `ensure_config()` 处理 broken symlink（ccprivate 不在时 conf/*.json 断链）

### Fixed
- 新机器首次 `init.sh` → setup-links → init-skill 全链路崩溃（claude-skills 缺失导致 `set -e` 级联退出）
- `conf/ubuntu.json` broken symlink 时 `ensure_config` 的 `cp` 写入失败
- `init-ccprivate.sh` 生成的 `target_dir` 含 `$HOME` 字面量无法展开

## [1.3.0] — 2026-07-09

### Added
- **产品落地页** (`www/`) — Cloudflare Pages 部署，含 commit hash 显示、ccskills 链接、架构介绍
- **Cloudflare 插件管理** (`option-cloudflare/`) — `init.sh` 管理脚本，一键安装/配置 Cloudflare MCP 插件
- **worklog 日报研究 hook** (`hooks/worklog_daily_research.py`) — 每日自动汇总 worklog 并输出研究建议

### Changed
- **ccskills 品牌升级** — claude-skills → ccskills.pages.dev，技能生态联合区域
- **域名迁移** — ccconfig 域名改为 ccconfiged.pages.dev
- **session-end-aggregator** — worklog 字段扩展（新增 model、session_type 等字段）

### Docs
- `docs/cloudflare-plugin.md` — Cloudflare 插件参考文档
- `docs/design/worklog-field-extension.md` — worklog 字段扩展设计文档

## [1.2.0] — 2026-07-08

### Changed
- **session-end-aggregator** — 合并频率从每周改为每日，新增每周总结提醒触发（`WEEKLY_MARKER`），session 结束时自动提示做周总结

## [1.1.0] — 2026-07-08

### Added
- `lib/git-conflict.sh` — Git 冲突解决公共库（sync.sh + update.sh 共用）
- `docs/architecture.md` — 产品架构总文档（三仓库模型 + 配置数据流 + 初始化/升级流程）
- `docs/upgrade-guide.md` — 用户升级指南（月度升级 + 大版本 + 回滚）
- claude-skills README 按需安装表 — 15 个 skill 每个一行 `/plugin install` 命令

### Changed
- **init-llm.sh 重构** — `switch_llm` / `switch_to_gateway` 合并共享 `_write_llm_config()`，消除 ~130 行重复
- **sync.sh / update.sh 重构** — 冲突处理逻辑提取到 `lib/git-conflict.sh`，消除 ~200 行重复
- **claude-skills 公开化** — 仓库可见性 PRIVATE→PUBLIC，marketplace 版本 0.5.0→0.8.0
- **三仓库文档全面审查** — README/BOOTSTRAP/CONTRIBUTING/ROADMAP/RELEASING 共 32 个文件、45 处修正
  - 数字一致性：skill 计数统一为 15、status 检查 12 项、BOOTSTRAP 8 阶段
  - 过期引用清理：f-vessel/f-research-deep 移除、f-doc→f-feishu、task_plan 路径修正
  - 拼写/环境变量名/目录名修正（cconfig→ccconfig、CCONFIG→CCCONFIG、config→skill-config）
- **BOOTSTRAP 流程修正** — gh auth 独立为必须阶段、gh 版本动态读取、smoke test 路径修复
- **单 skill 安装指南** — 15 行按需安装命令表，用户不需要装全部 skills

### Removed
- `option-ppt-master/` — OfficeCLI 已是唯一 PPT 引擎
- Vessel 全线移除，浏览器测试迁移至 Playwright（已于 v1.0.0 完成，本版本清理残留引用）

### Fixed
- docs/README.md 路径修正 — task_plan/findings 实际在 `.github/`
- 清理 23 个过期 snapshot（>30 天）
- BOOTSTRAP.md 环境变量名 CCONFIG_HOME→CCCONFIG_HOME、CCPRIVATE_DIR→CCPRIVATE_HOME

## [1.0.1] — 2026-07-05

### Added
- `docs/ccprivate-guide.md` — 7 步完整搭建个人私有配置仓库
- BOOTSTRAP.md `windows-tools/` 工具参考表

### Changed
- **BOOTSTRAP.md Windows 前置重构** — PowerShell 7 升级从"可选"改为"推荐"、新增 WSL 网络配置优化、Windows Terminal 推荐
- **BOOTSTRAP.md 阶段 3 默认 `--branch release`** — 用户拿稳定版，开发者说明在注释
- BOOTSTRAP.md 常见坑扩充 8 条 WSL/Windows 专属问题
- README.md 快速开始加 ccprivate 指南链接
- RELEASING.md 检查清单 +2 项

## [1.0.0] — 2026-07-05

### Added
- **双仓库公私分离** — 私有数据迁入 ccprivate 仓库
  - `conf/*.json` 真实值、`link/CLAUDE.md`、`link/settings.json`、`link/.config.json`、`link/projects/` → ccprivate
  - ccconfig 保留 `.example` 模板 + symlink，零密钥残留
  - `ccprivate/setup.sh` 编排私有链接，调用 `cconfig/setup-links.sh` 处理公开部分
- `$CCCONFIG_HOME` / `$CCPRIVATE_HOME` 环境变量 — 所有脚本支持自定义仓库路径，默认 `~/git/ccconfig`
- `hooks/pre-commit` — git hook 自动拦截：conf/*.json 非模板文件、API key 模式、私密 link 文件
- `SECURITY.md` — 安全漏洞报告政策
- `conf/f-logme.json.example` 加 `kr_route` 示例
- `option-llmswitch` — 时间路由 LLM 网关代理
  - `proxy.py` 本地代理 (127.0.0.1:8899)，按时段自动选 DeepSeek (非高峰) / MiniMax (高峰)
  - `init.sh` 管理脚本 (start/stop/status/mode)
  - `watchdog.sh` 守护进程 (30s 健康检查 + 自动重启 + 路由变更通知)
  - `init-llm.sh` Gateway 模式集成 (启动 proxy + watchdog，显示路由目标)
- `windows-tools/psupdate/` — PowerShell 7 升级工具，绕过 winget MSI 缓存丢失问题
- `windows-tools/music-convert/` — NCM 解密 + 格式转换工具
- `lib/README.md` + `conf/README.md` + `link/README.md` + `link/skills/README.md` + `link/agents/README.md`

### Fixed
- **proxy: build_provider_registry 遍历 gateway 条目 → KeyError → providers 空 → 全部 502**
  - gateway 条目无 `key` 字段，`cfg["key"]` 抛 KeyError；改为跳过无 key 的非 provider 条目
- **proxy: 每请求 new AsyncClient → 每次 TCP+TLS 握手，并发时累积延迟**
  - 改为 lifespan 创建共享 `httpx.AsyncClient`，全请求复用连接池
- **proxy: strip_thinking() 对 MiniMax 请求体双序列化 (json.loads→json.dumps)**
  - 大型 tool use JSON 经深拷贝后结构完整性受损 → `API Error: Failed to parse JSON`
  - MiniMax 直连不报错，移除 body 修改，纯透传（仅改 model name + auth header）
- **proxy: 响应 content-length 头未移除，github 解压后长度不匹配导致 JSON 截断**
  - 上游 gzip 响应 content-length 是压缩后大小，httpx 解压后 r.content 变大
  - Starlette 发现 headers 有 content-length 不重新计算 → CC 按错误长度读 → 截断
- **init-llm: 切直连后 CC 配置被 watchdog 自动重启覆盖**
  - watchdog 检测 proxy 死亡 → 自动调 `init.sh --start` → `write_cc_env` 覆写 CC 为 Gateway URL
  - 修复：切直连前先杀 watchdog
- **init-llm: switch_to_gateway 不启动 watchdog**
  - 修后: proxy 启动后自动拉起 watchdog daemon
- **monitor: llmswitch 路由事件颜色从 cyan 改为橙色 (256-color 208)**，高峰切换更醒目
- **BOOTSTRAP.md**: 新增 Windows WSL 2 安装指南 + PowerShell 7 升级说明
- **安全清理**: 移除 `conf/f-moocrec.json.example` 和 `link/skills/` 中的真实飞书 tenant domain
- **安全清理**: `.gitignore` 加 `*:Zone.Identifier` 防止 Windows ADS 文件误提交
- `conf/cloudflare.json.example` + `conf/supabase.json.example` 模板

### Security
- **git filter-repo** — 从全部 1144 commits 中永久删除历史密钥（conf/*.json、link/CLAUDE.md、link/projects/ 等 12 个私密文件）
- **去标识化** — `<your-github-username>` → `<your-github-username>`，`/home/francis` → `$HOME`
- `.gitignore` 加固 — 加 `__pycache__/`、`*.pyc`、`link/skills/f-doc/config.yaml`、`.env`

### Changed
- `f-*` skill 三层架构重组（Layer 1/2/3），search/research/report 职责拆分
- `scripts/publish.sh` — 一键同步 f-* 到 claude-skills marketplace
- `README.md` — 重写架构图、隐私模型、快速开始（含 ccprivate）

### Removed
- Vessel 全线移除，浏览器测试迁移至 Playwright
- `link/projects/` 下旧项目 CLAUDE.md + memory（已迁 ccprivate）
- `init-llm.zip`、`cccshare/`、死函数 `setup_fonts/setup_officecli/setup_ppt_master`

## [1.0] — 2026-05-21

### Added
- 初始版本，从私有配置整理为结构化仓库
- `init.sh` — 统一入口，交互式两级菜单
- `init-ubuntu.sh` — Ubuntu/WSL 全环境初始化
- `init-llm.sh` — LLM 多后端切换（DeepSeek、MiniMax、Claude）
- `init-mcp.sh` — MCP 服务器管理
- `init-skill.sh` — Skills 同步管理
- `init-autostart.sh` — auto-sync systemd 自启动
- `update.sh` — 月度组件升级（9 组件）
- `status.sh` — 8 项状态检查
- `monitor.sh` — 多仓库文件监控 + 自动 Git 同步
- `sync.sh` — 多仓库智能同步（合并原 gitforce.sh）
- `setup-links.sh` — 符号链接重建
- `option-bridge/` — 飞书消息 Bridge
- `option-ppt-master/` — PPT 生成环境
- `option-vessel/` — Vessel AI 浏览器（已于 2026-06-14 移除，全线迁移至 Playwright）
- `remote/` — 远程连接（Tailscale + SSH + tmux）
- `windows/` — Windows/WSL 互操作
- `conf/` — 配置文件单一来源
- `lib/path-helper.sh` — 动态路径解析
- `link/` — ~/.claude/ 符号链接源（rules、skills、agents）
