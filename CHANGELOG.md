# Changelog

All notable changes to ccconfig will be documented in this file.

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
