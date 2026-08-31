# CLAUDE.md — ccconfig

> 项目级。仅在 `~/git/ccconfig/` 工作时加载，与用户级 `~/CLAUDE.md` 合并生效。

## 项目定位
ccconfig 是 Claude Code 环境的可复用基础设施。维护 .example 模板（rules/agents/commands/conf）、skills、setup/init 脚本等公开部分。运行时文件在 ccprivate，通过 symlink 穿透访问。用户改 ccprivate 文件不受 ccconfig 更新影响。

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
- `CCCONFIG_REPO=myuser/ccconfig` — fork 用
- `BOOTSTRAP_NOSUDO=1` — 跳过 sudo（git 必须已装）

## 版本管理
- `conf/versions.json` 版本单一真相源
- `lib/path-helper.sh` 动态路径解析，Node 路径用 `find_node_bin` 4级回退

## 已安装插件
- （无）

## 约束
- **每次 Edit/Write 后先 git add + git commit，不等 auto-sync**。auto-sync 只做 push，不做 add/commit 可以避免 inotify 竞争导致 Edit old_string 过期
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