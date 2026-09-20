# 2026-09-20 移除 ccbridge 相关菜单项（7F/7G）

> 范围：`maintain.sh` 第 7 类菜单 + 删除 `lib/menu-feishu.sh`
> 起因：用户指出「飞书通道测试的 ccbridge 是移动出去的一个功能，现在跑到了 ccbridge 项目里」—— ccconfig 不该再留它的入口
> 前置：[20260920-maintain-flat-menu.md](20260920-maintain-flat-menu.md)（7F 是这次扁平化时刚立的）

## 移除原因

ccbridge 已独立成仓（`~/git/ccbridge`），飞书 ↔ Claude Code 通道连同它的测试都在那边。ccconfig 里剩下的这两个入口是**跨仓耦合**：

| 项 | 原动作 | 耦合点 |
|---|---|---|
| 7F 账号详情/发测试消息 | `feishu_apps_menu`（`lib/menu-feishu.sh`） | "发测试"要读 ccbridge 的 `~/.lark-channel/config.json` 取收件人 open_id |
| 7G 飞书通道测试 | `bash <ccbridge>/tests/test-feishu.sh` | 直接跑另一个仓库的测试脚本 |

## 改了什么

- **删除 `lib/menu-feishu.sh`**（224 行）。它提供的是「列出 feishu.json 的 app → 切换/OAuth/看授权/编辑/发测试」的二级选择器。
- **`maintain.sh`**：去掉 `source lib/menu-feishu.sh`、去掉顶层 `feishu)` 子命令分支、用法串去掉 `feishu`。
- **`lib/menu-data-maintain.sh`**：删除 7F/7G 两条，第 7 类从 7 项变 5 项。
- **`lib/README.md`**：删掉 `menu-feishu.sh` 那一行。
- **`tests/test-maintain.sh`**：语法检查清单去掉该文件；§12 段名从「feishu 顶层 case 无 local」改为「顶层 case 无 local」（守卫本身仍有效，只是不再特指 feishu）。

菜单项总数 53 → 51。

## 功能没丢的部分

删除前核对过 `lark-switch.sh --list`（7A）的输出，**账号列表视图完整**：

```
  飞书账号列表
 ▶ ailab (当前)
     appId: cli_a97077e327b89bd6
     配置: /home/francis/.lark-cli-ailab
     说明: AI Lab Bot
```

7A–7E 保留，覆盖：列账号 / 切账号（session）/ 切账号（持久化）/ OAuth 状态 / 重置 lark-cli 配置。

**实际丢掉的只有两件事**：① 发飞书测试消息（收件人取自 ccbridge 配置，本就该在 ccbridge 做）；② 在菜单里增删 `feishu.json` 的 app（现在直接编辑 `ccprivate/conf/feishu.json`；7F 的「编辑」选项原本也只是打印 `vim <path>`）。

## 仍然保留的 ccbridge 触点

这些是**指向**而非重复实现，本次未动：

- `lib/status.sh` 的可选组件检查：显示 ccbridge profile 数量，并提示 `bash ~/git/ccbridge/init.sh`
- `init-option.sh` 的 ccbridge 安装/启动引导（转发到 `~/git/ccbridge/init.sh`）
- `lib/path-helper.sh` 的 `resolve_ccbridge()`
- `lib/deps-check.sh` 的 `lark-channel-bridge` 条目

如果要连这些一起摘掉（ccconfig 完全不感知 ccbridge），说一声。

## 验证

```
bash tests/test-maintain.sh   → PASS 84 / FAIL 0（项数随菜单精简而减少）
grep 全仓 menu-feishu/feishu_apps_menu → 仅剩更新日志里的历史记述
```
