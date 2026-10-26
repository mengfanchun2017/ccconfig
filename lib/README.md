# lib/ 函数库

## 稳定 API（option-* / 外部可 source）
| 文件 | 用途 |
|------|------|
| `colors.sh` | 颜色输出：ok/err/warn/info/section |
| `interact.sh` | 交互菜单：confirm/menu_select/spinner/prompt |
| `dry-run.sh` | 干运行支持：would/run |
| `path-helper.sh` | 路径解析：resolve_conf/find_node_bin/get_version |
| `net.sh` | 网络探测：check_proxy/check_tcp |
| `deps-check.sh` | 依赖检查 |

## 函数 API

| 函数 | 所在文件 | 用途 |
|------|---------|------|
| `atomic_write <file>` | dry-run.sh | 原子写入（mktemp + mv，防写一半断掉）；`ensure-uv.sh` 在用 |

> 历史：`guard_mkdir` / `guard_symlink` / `guard_append_line` / `guard_write_file`
> 四个幂等封装是 ADR-0027 承诺的统一 API，但**从未接线**（生产零调用，只有测试引用）。
> 2026-10-25 三仓 review 确认后**已删除**（连同 5 个对应用例），ADR-0027 标注 Superseded。
> 幂等逻辑现在各脚本自己写 `[ -e ]` / `ln -sf` / `grep -q`，没有统一封装 —— 这是有意的，
> 不是遗漏。

## 内部实现（仅 maintain.sh / 入口脚本调用）
| 文件 | 用途 |
|------|------|
| `monitor.sh` | auto-sync 监控 |
| `sync.sh` | Git 同步 |
| `update.sh` | 组件升级 |
| `status.sh` | 状态检查 |
| `mcp-manager.sh` | MCP 管理 |
| `example-sync.sh` | 模板同步门禁 |
| `setup-links.sh` | 符号链接设置 |
| `menu-data-maintain.sh` | maintain.sh 菜单数据 |
| `ccprivate-upgrade.sh` | 私有配置升级 |
| `shell_init.sh` | shell 初始化 |
| `ensure-bridge.sh` | bridge 看门狗 |
| `bridge-restart.sh` | bridge 重启（watchdog 与冷启动共用） |
| `ensure-libicu.sh` | ICU 依赖 |
| `install-inotify.sh` | inotify 安装 |
| `init-ubuntu.sh` | Ubuntu 初始化 |
| `init-llm.sh` | LLM 切换（预设 + bridge 生命周期 + 真实链路探测） |
| `init-mcp.sh` | MCP 初始化 |
| `init-skill.sh` | Skill 安装 |
| `init-autostart.sh` | 自启动配置 |
| `git-pull.sh` | 仓库拉取单点实现（各仓 pull 统一走这里） |
| `secret-patterns.sh` | 疑似凭据的统一正则（`$SECRET_RE`，pre-commit 与 example-sync 共用） |
| `snapshot.sh` | 关键配置快照 + 回滚（`take`/`list`/`restore`/`prune`） |
| `ensure-uv.sh` | 确保 uv/uvx 可用（Python 工具隔离运行器） |
| `bridge-service.sh` | bridge 的 systemd user 服务管理 |
| `bridge-supervisor.sh` | bridge 前台守护循环（两路共用） |
| `tailscale-guard.sh` | tailscale accept-routes 防护（防单位内网被黑洞） |
| `conf-diff-classify.py` | conf 差异分类（供 example-sync 判断哪些字段需脱敏） |
| `claude-auto-sync.service` | systemd **system** service 模板（`/etc/systemd/system/`，被 init-autostart.sh 使用） |