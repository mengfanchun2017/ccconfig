# Changelog

All notable changes to ccconfig will be documented in this file.

## [Unreleased]

### Changed
- **f-* skill 三层架构重组**（Layer 1 输出平台 / Layer 2 知识生产 / Layer 3 个人工作流）
  - 新建 `f-search` — 搜索活动统一原语（query 规划 + 调工具 + Python 过滤 + 聚合 + 来源标注 + 搜索清单），从 f-research 抽
  - `f-research` → `f-research-domain` — 瘦身到 4 领域方法论（customer JTBD / generic / market / technical），搜索委派 f-search
  - `f-research-report` → `f-report-gen` — 与 `f-report-std` (std=standard 规范) 配对（xxx-std + xxx-gen 对称）
  - 11 引用方 + 3 memory 文件全部更新（CLAUDE.md / f-doc / f-logme / f-report-std / f-research-deep / agents / README / memory）
- `scripts/publish.sh` — 一键把 ccconfig/link/skills/ 的指定 f-* 同步到 claude-skills/plugins/（默认只 commit，--push 才推）

### Removed
- **Vessel 全线移除** — 浏览器测试统一迁移至 Playwright
  - 删 `option-vessel/`、`bin/vessel-mcp-proxy.cjs`、`bin/vessel-healthcheck.sh`、`link/skills/f-vessel/`
  - 删 `~/.local/bin/vessel*`、`~/.local/lib/vessel/`、systemd `vessel.service`、`~/.config/vessel/`
  - 清 `status.sh` check_vessel → check_playwright、`init.sh`/`init-ubuntu.sh` vessel 引用
  - 清 `.config.json` vessel disabledMcpServers/mcpServers/skillUsageStats
  - 清 `conf/claude.json`、`settings.json` vessel MCP 条目
  - 清 `search.md` Vessel → Playwright 替换
  - <project-name>: `settings.json` vessel → playwright MCP、`f-test-<project-name>` SKILL.md 全 Playwright、ADR 0016 更新
- `~/.claude/skills/f-research` + `f-research-report` symlink（指向旧路径）
- `~/.claude/rules/f-research-report.md` symlink

### Fixed
- `remote/server/tmux-sshd.sh:100` — 反引号语法错误
- `init-ubuntu.sh` 补 `gh auth setup-git` — 之前 SSH key 未注册到 GitHub 时 monitor push 静默失败
- LLM 切换：M2.7 已停服，统一切到 M3（`conf/llm.json`）

### Changed
- `.gitignore` — 新增 `tmp/` 忽略规则
- `init-llm.sh` 默认 deepseek → 从 `conf/llm.json` 的 `current` 字段读取，配置即真相

### Removed
- `init-llm.zip` — init-llm.sh 的旧 zip 副本，全仓 0 引用
- `cccshare/` — 空目录，无作用
- `link/rules/f-research-report.md` 绝对 symlink → 相对 symlink（多机器不再断）
- `init-ubuntu.sh:setup_fonts()` / `setup_officecli()` / `setup_ppt_master()` — main() 不调的死函数
- `option-bridge/lark-current.sh` / `claude-lark-refresh.{service,timer}` — 0 consumer
- `init.sh all` 流程中去重 `init-llm.sh` 调用（由 init-ubuntu.sh 内部 setup_claude_api 负责）
- `setup_ppt_master` 从 init-ubuntu.sh 强制流水线移到 option-* 可选（与 option-ppt-master 重复）
- `link/projects/-home-francis-git-papermaster/` — 仓库已废弃，目录和记忆全删

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
