# feishu — 飞书集成（统一入口）

> lark-cli 文档操作 + cc-connect 多机器人 Bridge，配置源为 `conf/feishu.json`

## 组件

| 组件 | 脚本 | 用途 |
|------|------|------|
| lark-cli | `init.sh --lark-cli` | 终端创建文档/日历/任务（用户 OAuth） |
| cc-connect | `init.sh --cc-connect` | Bridge 接收飞书消息（机器人长连接） |

## 快速开始

```bash
# 完整安装
bash ccconfig/feishu/init.sh

# 仅安装部分
bash ccconfig/feishu/init.sh --lark-cli
bash ccconfig/feishu/init.sh --cc-connect

# 多账号切换
bash ccconfig/feishu/lark-switch.sh francis
bash ccconfig/feishu/lark-switch.sh ailab
```

## 机器人管理

```bash
bash ccconfig/feishu/bot-status.sh            # 查看状态
bash ccconfig/feishu/bot-enable.sh <名称>      # 启用
bash ccconfig/feishu/bot-disable.sh <名称>     # 禁用
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
3. 运行 `bash ccconfig/feishu/init.sh`

## lark-cli 授权持久化

systemd timer 每 5 天自动刷新 token：

```bash
systemctl --user status claude-lark-refresh.timer
journalctl --user -u claude-lark-refresh.service
```
