# 2026-10-18 maintain 菜单板块重构 + 冗余项清理

> 范围：`maintain.sh` 菜单分区重划、冗余菜单项删除、tailscale 状态误报修复
> 起因：用户逐条报「4E 选了没反馈」「4F 是否有实际作用」「getnote 7D/7B/7E 是否重复」「8A tailscale 明明好了却报未就绪」，并提出板块合并五条要求
> 关联：[SH-MENU-CONVENTIONS.md](../SH-MENU-CONVENTIONS.md)
> 关联 ADR：无（交互层实现细节）

## 用户提的五条

1. 1B 一键修复放到更新板块，去掉「（全量）」后缀
2. 2 监控/同步全部并入状态分区，改名为「1 状态/同步」
3. 原 3 更新前移为「2 更新」，后续编号依次前移
4. 原 6 飞书/Lark 与 7 getnote 合并为「5 rag」，小标题加来源前缀
5. 账号列表去掉「当前账号」后缀（进入即可看到）；getnote 侧「状态」改为「getnote 状态」

## 板块对照

| 旧 | 新 |
|----|----|
| 1 状态（检查/一键修复/高权限） | 1 状态/同步（检查/日志跟踪/监控状态/启动/停止/高权限） |
| 2 监控/同步（日志/状态/启停） | ↑ 并入 1 |
| 3 更新（配置仓库/tool/PAT/可选组件） | 2 更新（同四项 + 一键修复） |
| 4 LLM | 3 LLM |
| 5 MCP | 4 MCP |
| 6 飞书/Lark + 7 getnote | 5 rag（lark 4 项 + getnote 2 项） |
| 8 远程 | 6 远程 |

## 发现汇总（7 项）

| # | 严重 | 类别 | 发现 | 状态 |
|---|------|------|------|------|
| 1 | P1 | 冗余 | 4E「修复 /model 污染」是**静默 no-op**：`sync_top_model` 只在 `env.ANTHROPIC_MODEL != model` 时才写文件，正常状态零输出零退出 —— 用户感知即"选了没反馈"。且 `switch_llm` 末尾已自动调用它，手动入口冗余 | ✅ 删菜单项（函数保留，切预设流程依赖） |
| 2 | P1 | 冗余 | 4F「修复 bridge 转 Anthropic」的 `selfheal_bridge` 仍由 `status.sh` 会话冷启动调用，加上 supervisor 守护，独立菜单项价值不大 | ✅ 删菜单项（函数保留，`status.sh:798` 依赖） |
| 3 | P2 | 冗余 | 7D「诊断 doctor」的原始 JSON 只在排查时看；7A 状态本身就取 doctor 的 `ready` 字段判定 | ✅ 删菜单项（`option-getnote/init.sh doctor` 子命令保留） |
| 4 | P2 | 重复 | 7B「安装」与 2D 可选组件列表里的 getnote 项是同一个 `init.sh install`（2D 已装时会短路） | ✅ 删菜单项 |
| 5 | P2 | 覆盖 | 7E「升级」是纯工具版本更新，与 2B 其余组件同类，却单独占项 → 老机器更新要翻两个分区 | ✅ 并入 2B（新增 `update_getnote()`，与 officecli/cloudflare 同模式） |
| 6 | P1 | bug | 8A tailscale「未就绪」误报：`ts_ip` 只在 WSL 内存在 `tailscale0` 网口时赋值。tailscaled 跑在 Windows 宿主时 `ts_ok=true` 但 `ts_ip` 空 → 第一行报 OK、第二行报未就绪，**自相矛盾** | ✅ 修：WSL 无网口时调 `tailscale.exe ip -4` 取真实 IP（状态 + 登录检查两处） |
| 7 | P2 | UX | 菜单第 3 项标「lark-cli」但实际升级 lark-cli + mmx-cli 两个包；提示写 `[0-9]` 但已有 10/11 项 | ✅ 改名「npm 全局包（lark-cli / mmx-cli）」，提示改 `[0-11]` |

## 连带修正

- 系统快捷键 `t`：原指 2A（日志跟踪），重构后日志跟踪移到 1B，`menu_parse` 同步改 `_exec_entry 1 B`
- 菜单标题宽度回归：新标题「lark 切换账号（问账号名）」= 25 显示列，超 24 列上限撑破 cmd 列对齐 → 缩短为「lark 切换账号」(13 列)。此问题由 `test-maintain.sh` §10 对齐回归抓出
- `CAT_NAME` 分类连续性断言从 `0 1..8` 改为 `0 1..6`
- 全库编号引用同步：`maintain.sh`（菜单 4A→3A）、`status.sh`（1B→2E）、`update.sh`（3A/3B→2A/2B）、README、`docs/SH-MENU-CONVENTIONS.md`、`docs/init-llm.md`

## 未改

- `option-getnote/init.sh` 自带的交互菜单仍保留「诊断」项 —— 那是它自己的入口（`bash option-getnote/init.sh doctor` 仍可用），只是不再占 maintain 菜单位
- `docs/updates/20260920-maintain-flat-menu.md` 里的旧编号是历史记录，按归档性质不改