# CLAUDE.md — ccconfig

> 项目级。仅在 `~/git/ccconfig/` 工作时加载，与用户级 `~/CLAUDE.md` 合并生效。

## 项目定位
ccconfig 是 Claude Code 环境的可复用基础设施。维护 rules、agents、commands、skills、setup/init 脚本等公开部分。私有数据在 ccprivate，通过 symlink 穿透访问。

## 暗号
| 暗号 | 行为 |
|------|------|
| hookstatus | `bash status.sh` 状态检查 |
| @res `<主题>` | 中英文双语搜索 → 飞书文档 + 白板图表（f-feishu skill 编排） |
| ccusage | `npx ccusage@latest daily\|monthly` 用量统计 |
| pullff `[repo]` | `bash sync.sh --pull` 强拉远程 → 自动重建符号链接 |

## 常用命令
- 月度升级: `bash update.sh all`
- LLM 切换: `bash init-llm.sh`
- 符号链接重建: `bash setup-links.sh`
- 状态检查: `bash status.sh`
- auto-sync 全自动运行，无需手动同步

## 版本管理
- `conf/versions.json` 版本单一真相源
- `lib/path-helper.sh` 动态路径解析，Node 路径用 `find_node_bin` 4级回退

## 已安装插件
- cloudflare@cloudflare — Cloudflare 开发者平台。详见 `docs/cloudflare-plugin.md`

## 约束
- 本仓库不记录项目级 memory（架构决策在用户级 memory，`~/.claude/projects/-home-francis-git/memory/`）
- 私有数据（conf 真实值、CLAUDE.md 内容）通过 symlink 引用 ccprivate，不在本仓库提交
- ccconfig 最终目标是可公开
