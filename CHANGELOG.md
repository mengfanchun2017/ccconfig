# Changelog

All notable changes to ccconfig will be documented in this file.

## [Unreleased]

### Added
- `deps-check.sh` — 依赖完整性检查脚本
- `option-officecli/` — OfficeCLI 可选组件
- `LICENSE`、`CHANGELOG.md`、`CONTRIBUTING.md`、`.editorconfig`

### Fixed
- `remote/server/tmux-sshd.sh:100` — 反引号语法错误

### Changed
- `.gitignore` — 新增 `tmp/` 忽略规则

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
- `pushpub.sh` — 导出公开分享版
- `option-bridge/` — 飞书消息 Bridge
- `option-ppt-master/` — PPT 生成环境
- `option-vessel/` — Vessel AI 浏览器
- `remote/` — 远程连接（Tailscale + SSH + tmux）
- `windows/` — Windows/WSL 互操作
- `conf/` — 配置文件单一来源
- `lib/path-helper.sh` — 动态路径解析
- `link/` — ~/.claude/ 符号链接源（rules、skills、agents）
