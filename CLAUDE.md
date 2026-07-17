# CLAUDE.md — ccconfig

> 项目级。仅在 `~/git/ccconfig/` 工作时加载，与用户级 `~/CLAUDE.md` 合并生效。

## 项目定位
ccconfig 是 Claude Code 环境的可复用基础设施。维护 rules、agents、commands、skills、setup/init 脚本等公开部分。私有数据在 ccprivate，通过 symlink 穿透访问。

## 暗号
| 暗号 | 行为 |
|------|------|
| hookstatus | `bash maintain.sh status` 状态检查 |
| @res `<主题>` | 中英文双语搜索 → 飞书文档 + 白板图表（f-feishu skill 编排） |
| ccusage | `npx ccusage@latest daily\|monthly` 用量统计 |
| pullff `[repo]` | `bash maintain.sh sync --pull` 强拉远程 |

## 常用命令
- 运维入口: `bash maintain.sh` (收尾/status/self/upgrade/sync/monitor/fix)
- 自我更新: `bash maintain.sh self all`（拉 ccconfig + 重建链接 + skill 同步）
- 组件升级: `bash maintain.sh upgrade all`（Node.js/Claude 等）
- 初始化入口: `bash init.sh`
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
- cloudflare@cloudflare — Cloudflare 开发者平台。详见 `docs/cloudflare-plugin.md`

## 约束
- 本仓库不记录项目级 memory（架构决策在用户级 memory，`~/.claude/projects/-home-francis-git/memory/`）
- 私有数据（conf 真实值、CLAUDE.md 内容）通过 symlink 引用 ccprivate，不在本仓库提交
- ccconfig 最终目标是可公开