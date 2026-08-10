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
- `CCCONFIG_BRANCH=release` — 生产用稳定版
- `BOOTSTRAP_NOSUDO=1` — 跳过 sudo（git 必须已装）

## 版本管理
- `conf/versions.json` 版本单一真相源
- `lib/path-helper.sh` 动态路径解析，Node 路径用 `find_node_bin` 4级回退

## 已安装插件
- （无）

## 约束
- 本仓库不记录 memory（memory symlink → ccprivate/link/memory/，由 ccprivate/setup.sh 建立）
- 私有数据（conf 真实值、CLAUDE.md 内容）通过 symlink 引用 ccprivate，不在本仓库提交
- ccconfig 最终目标是可公开

## SH 交互规范
- 颜色/日志函数只用 `lib/colors.sh`（ok/err/warn/info/section/menu_num）
- 交互菜单只用 `lib/interact.sh`（confirm/menu_select/prompt/table/spinner/menu_multi）
- 不自行定义颜色变量或手写菜单循环
- `lib/interact.sh` 自动检测 gum 并降级，脚本调用方不感知
- 写操作类脚本 source `lib/dry-run.sh` 加 `--dry-run` 支持