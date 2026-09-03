# lib/ 函数库

## 稳定 API（option-* / 外部可 source）
| 文件 | 用途 |
|------|------|
| `colors.sh` | 颜色输出：ok/err/warn/info/section |
| `interact.sh` | 交互菜单：confirm/menu_select/spinner/prompt |
| `dry-run.sh` | 干运行支持：would/run |
| `safe-exit.sh` | 统一 trap 清理：safe_exit/_register_temp |
| `path-helper.sh` | 路径解析：resolve_conf/find_node_bin/get_version |
| `net.sh` | 网络探测：check_proxy/check_tcp |
| `deps-check.sh` | 依赖检查 |

## 函数 API
| 函数 | 所在文件 | 用途 |
|------|---------|------|
| `guard_mkdir <dir>` | dry-run.sh | 幂等创建目录（等价 mkdir -p，dry-run 感知） |
| `guard_symlink <target> <link>` | dry-run.sh | 幂等符号链接（dry-run 感知） |
| `guard_append_line <file> <line>` | dry-run.sh | 幂等追加行（dry-run 感知） |
| `guard_write_file <file> <content>` | dry-run.sh | 幂等写入（内容不同才覆盖，dry-run 感知） |
| `atomic_write <file>` | dry-run.sh | 原子写入（mktemp + mv，防写一半断掉） |
| `safe_exit [code]` | safe-exit.sh | 统一清理退出（注册 trap 后用） |
| `_register_temp <path>` | safe-exit.sh | 注册清理目标 |

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
| `menu-feishu.sh` | 飞书子菜单 |
| `ccprivate-upgrade.sh` | 私有配置升级 |
| `shell_init.sh` | shell 初始化 |
| `ensure-bridge.sh` | bridge 看门狗 |
| `ensure-libicu.sh` | ICU 依赖 |
| `install-inotify.sh` | inotify 安装 |
| `init-ubuntu.sh` | Ubuntu 初始化 |
| `init-llm.sh` | LLM 配置 |
| `init-llm-bill.sh` | LLM 账单 |
| `init-mcp.sh` | MCP 初始化 |
| `init-skill.sh` | Skill 安装 |
| `init-autostart.sh` | 自启动配置 |