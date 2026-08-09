# option-larkbridge — lark-channel-bridge 飞书↔Claude Code

> npm 包 `@larksuiteoapi/lark-channel-bridge` 的安装 + systemd profile 管理。
> 把飞书 Bot 收到的消息路由到本地 Claude Code session，实现双向对话。

## 组件

| 文件 | 用途 |
|------|------|
| `init.sh` | 装机初始化（npm install + systemd profile create/run/stop/status） |

## 用法

```bash
bash option-larkbridge/init.sh                # 交互菜单
bash option-larkbridge/init.sh --run          # 跑 default profile（最常用）
bash option-larkbridge/init.sh --status       # 看 systemd 状态
```

## Profile 管理

每个 profile 一个 systemd unit：

- `lark-channel-bridge@default.service`
- `lark-channel-bridge@work.service`
- ...

通过 `init.sh` 菜单可创建/启停/删除 profile，自动写 `conf/feishu.json` 的 `larkbridge` 段。

## 权限 scopes

bot 端需在飞书开放平台开通：

- `im:message`, `im:message:send`, `im:message:send_as_bot`
- `im:message:send_multi_depts`, `im:message:send_multi_users`, `im:message:send_sys_msg`
- `im:message.p2p_msg:readonly`, `im:message.reactions:write_only`
- `im:chat:readonly`
- `admin:app.info:readonly`, `application:application:self_manage`
- `cardkit:card:write`

一键申请 URL：`bash maintain.sh → 13 → 7`

## 与 larkcli 关系

- `option-larkcli/` — user 身份 OAuth，操作文档
- `option-larkbridge/` — tenant 身份 Bot，收发消息

共用 `conf/feishu.json`，互不冲突。
