# CLAUDE.md — ccconfig

> 项目级。仅在 `~/git/ccconfig/` 工作时加载，与用户级 `~/CLAUDE.md` 合并生效。

## 项目定位
ccconfig 是 Claude Code 环境的可复用基础设施。维护 .example 模板（agents/conf）、skills、setup/init 脚本等公开部分。运行时文件在 ccprivate，通过 symlink 穿透访问。用户改 ccprivate 文件不受 ccconfig 更新影响。

## 暗号
| 暗号 | 行为 |
|------|------|
| hookstatus | `bash maintain.sh status` 状态检查 |
| pullff `[repo]` | `bash maintain.sh sync --pull` 强拉远程 |

## 常用命令
- 运维入口: `bash maintain.sh` (收尾/status/self/upgrade/sync/monitor/fix)
- 自我更新: `bash maintain.sh self all`（拉 ccconfig + 重建链接 + skill 同步）
- 组件升级: `bash maintain.sh upgrade all`（Node.js/Claude 等）
- 初始化入口: `bash init-base.sh`
- LLM 切换: `bash lib/init-llm.sh`
- auto-sync 全自动运行，无需手动同步

## 新机器起步（一行命令）
全新 WSL/Ubuntu 只需一行：
```bash
curl -fsSL https://raw.githubusercontent.com/mengfanchun2017/ccconfig/main/bootstrap-gh-auth.sh | bash
```
`bootstrap-gh-auth.sh` 自动装 git → clone ccconfig → 输出下一步命令。完整流程看 `BOOTSTRAP.md`。

支持环境变量：
- `CCCONFIG_REPO=myuser/ccconfig` — fork 用（默认 mengfanchun2017/ccconfig）

## 版本管理
- `conf/versions.json` 版本单一真相源
- `lib/path-helper.sh` 动态路径解析，Node 路径用 `find_node_bin` 4级回退

## 约束
- **session 不 commit、不 push**。auto-sync 独占提交权：inotify 监听 `~/git/`，30s debounce 后 `git add -A` + commit + push 全做（`lib/monitor.sh`）。改完文件就继续干别的，别手动 `git add`/`git commit`
- **why 这样定**：多 session 并行时手动 commit 会互相抢（两边改动被扫进同一个 commit）、会和 monitor 的 debounce 抢跑、`git reset` 拆 commit 在已 push 时等于改写发布历史。交给一个提交者，这些竞争面全部消失
- **代价（已知并接受）**：提交粒度 = 一次 debounce 窗口内的全部改动，不是"一事一 commit"；因此 `rules/git.md` 的「一事一 commit」在本仓库不适用。补偿办法是 monitor 的提交信息**带改动摘要**（仓库名 + 文件数 + 文件清单前 12 项），别把它退回成纯时间戳
- **不要 `git add` 后又不等**：手动 stage 中途被 debounce 触发，会连同别人的改动一起提交。要改就整段改完
- **auto-sync 实际是 add + commit + push 全做**（`lib/monitor.sh` 的 `git add -A` 与 `git commit -m "$commit_msg"`）。此前本行误写成"只做 push"，与实际不符
- 本仓库不记录 memory（memory symlink → ccprivate/link/memory/，由 ccprivate/setup.sh 建立）
- 私有数据（conf 真实值、CLAUDE.md 内容）通过 symlink 引用 ccprivate，不在本仓库提交
- ccconfig 最终目标是可公开

## SH 交互规范
- 颜色/日志函数只用 `lib/colors.sh`（ok/err/warn/info/section）
- 交互菜单只用 `lib/interact.sh`（confirm/menu_select/prompt/prompt_password/table/spinner/menu_multi）
- 不自行定义颜色变量或手写菜单循环
- 写操作类脚本 source `lib/dry-run.sh` 加 `--dry-run` 支持
- **菜单 API 约定**: menu_select items 传纯文本（不带数字），自动加 "1) 2) 3)"；返回选中**序号字符串**（"5"），末项是"返回"项返回 N（${#items[@]}）
- **避坑**: menu_select 显示走 stderr（避开 `c=$(...)` 截走）；read 从 /dev/tty（避开管道阻塞）；while+case 不能 continue 重入菜单。详见 memory `menu-migration-pitfalls-20260810`
- **item 文本必须纯文本**：caller 传 `"auto"` 不要传 `"1) auto"`——后者会让菜单显示双前缀 (`1) 1) auto`)。case pattern 匹配 menu_select 返回的**序号字符串**（"1"），不是 item 文本
- **每次 Edit 后必跑 bash -n**：防 P0 行合并 bug（Edit replace 时跨行易把多行压成一行导致运行时 `[: missing ']'`）。`bash -n <file>` 0.1s 即可检出
- **菜单完整规范**（渲染格式、颜色变量、MENU_ENTRIES data-driven 模式）见 [docs/SH-MENU-CONVENTIONS.md](docs/SH-MENU-CONVENTIONS.md)