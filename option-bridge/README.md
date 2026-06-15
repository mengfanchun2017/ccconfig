# option-bridge — 飞书消息 Bridge（可选组件）

> lark-cli 文档操作 + cc-connect 多机器人 Bridge，配置源为 `conf/feishu.json`
>
> **状态**: 可选安装，默认不包含在 `init.sh all` 中

## 组件

| 组件 | 脚本 | 用途 |
|------|------|------|
| lark-cli | `init.sh --lark-cli` | 终端创建文档/日历/任务（用户 OAuth） |
| cc-connect | `init.sh --cc-connect` | Bridge 接收飞书消息（机器人长连接） |
| mcp-bridge | `mcp-bridge/install.sh` | 可选：安装 feishu MCP（配合 cc-connect bot 消息） |

## 快速开始

```bash
# 完整安装（lark-cli + cc-connect）
bash ccconfig/option-bridge/init.sh

# 仅安装部分
bash ccconfig/option-bridge/init.sh --lark-cli
bash ccconfig/option-bridge/init.sh --cc-connect

# 多账号切换
bash ccconfig/option-bridge/lark-switch.sh <your-account>
bash ccconfig/option-bridge/lark-switch.sh <another-account>
```

## 机器人管理

```bash
bash ccconfig/option-bridge/bot-status.sh            # 查看状态
bash ccconfig/option-bridge/bot-enable.sh <名称>     # 启用
bash ccconfig/option-bridge/bot-disable.sh <名称>    # 禁用
```

## cc-connect 服务

```bash
systemctl --user status cc-connect
systemctl --user restart cc-connect
journalctl --user -u cc-connect -f
```

## 添加新机器人

1. 飞书开放平台创建企业自建应用（机器人 + 长连接）
2. 编辑 `conf/feishu.json` → `apps[]` 新增，同时配置 `larkCli` 和 `ccConnect`
3. 运行 `bash ccconfig/option-bridge/init.sh`

## lark-cli 授权持久化

systemd timer 每 5 天自动刷新 token：

```bash
systemctl --user status claude-lark-refresh.timer
journalctl --user -u claude-lark-refresh.service
```

## mcp-bridge（可选）

仅在需要 bot 收发消息时安装，配合 cc-connect 使用。如果只用 lark-cli 操作文档/日历/任务，不需要安装。

```bash
bash ccconfig/option-bridge/mcp-bridge/install.sh          # 安装
bash ccconfig/option-bridge/mcp-bridge/install.sh --remove # 移除
```