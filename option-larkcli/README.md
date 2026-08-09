# option-larkcli — lark-cli 多账号管理

> 飞书 CLI（`@larksuite/cli`）的多账号切换 + OAuth 授权 + scope 一键开通。

## 组件

| 文件 | 用途 |
|------|------|
| `init.sh` | 装机初始化（npm install + 配置目录创建 + scopes 申请提示） |
| `lark-switch.sh` | 切当前 session 使用的账号（基于 `LARKSUITE_CLI_CONFIG_DIR`） |

## 用法

```bash
bash option-larkcli/init.sh                # 装机 + 引导开通权限
bash option-larkcli/lark-switch.sh ailab   # 切到 ailab 账号
```

## 账号配置

每个账号一个独立配置目录（避免 session 缓存污染）：

- `~/.lark-cli-ailab/` — AI Lab 账号
- `~/.lark-cli-personal/` — 个人账号
- ...

切换通过 `LARKSUITE_CLI_CONFIG_DIR` 环境变量实现，每次新开 session 生效。

## 权限 scopes

`init.sh` 引导用户到飞书开放平台申请以下类别（覆盖文档/Base/日历/白板/PPT/表格/任务/wiki/邮件/视频会议/纪要/OKR/搜索）：

docs, docx, drive, base, bitable, calendar, contact, sheets, slides, task, wiki, mail, vc, minutes, okr, search

`lark-cli --domain all` 时一次性弹出所有 scope 让用户同意，无需手动逐个开通。

## 与 larkbridge 关系

- `option-larkcli/` — user 身份，OAuth 手动授权（自己手动操作文档）
- `option-larkbridge/` — tenant 身份，bot 收发消息（飞书↔Claude Code 通信）

两者共用 `conf/feishu.json` 单一配置源，互不冲突。
