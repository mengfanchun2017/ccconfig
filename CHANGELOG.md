# Changelog

All notable changes to ccconfig will be documented in this file.

## [Unreleased]

### Added
- **双仓库公私分离** — 私有数据迁入 ccprivate 仓库
  - `conf/*.json` 真实值、`link/CLAUDE.md`、`link/settings.json`、`link/.config.json`、`link/projects/` → ccprivate
  - ccconfig 保留 `.example` 模板 + symlink，零密钥残留
  - `ccprivate/setup.sh` 编排私有链接，调用 `cconfig/setup-links.sh` 处理公开部分
- `$CCCONFIG_HOME` / `$CCPRIVATE_HOME` 环境变量 — 所有脚本支持自定义仓库路径，默认 `~/git/ccconfig`
- `hooks/pre-commit` — git hook 自动拦截：conf/*.json 非模板文件、API key 模式、私密 link 文件
- `SECURITY.md` — 安全漏洞报告政策
- `conf/f-logme.json.example` 加 `kr_route` 示例
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
