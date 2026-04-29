# feishu — 飞书集成

> lark-cli 文档操作 + cc-connect 多用户飞书桥接

## 组件

| 组件 | 脚本 | 用途 |
|------|------|------|
| lark-cli | `init-feishu.sh` | 终端创建文档/日历/任务 |
| cc-connect | `init-cconnect.sh` | Bridge 接收飞书消息（WebSocket，多用户） |

## 快速开始

```bash
# 仅安装 lark-cli（文档/日历/任务）
bash ccconfig/feishu/init-feishu.sh

# 配置 cc-connect Bridge（多用户飞书桥接）
bash ccconfig/feishu/init-cconnect.sh
```

## 多用户架构

```
用户A → 飞书App A → cc-connect Project "userA"
    ├── workDir: /home/francis/git
    ├── configDir: ~/.claude（共享 MCP、API Key）
    └── sessions: 按 chatId 独立

用户B → 飞书App B → cc-connect Project "userB"
    ├── workDir: /home/francis/git/friend1
    ├── configDir: ~/.claude-friend1（独立 Claude 账号）
    └── sessions: 按 chatId 独立
```

## 配置

配置在 `conf/feishu.json`，包含两段：

- `lark` — lark-cli 凭证（所有环境一套即可）
- `ccconnect.users[]` — cc-connect 多用户列表

修改后运行对应 init 脚本生效。

## cc-connect 常用命令

```bash
systemctl --user status cc-connect    # 查看状态
systemctl --user restart cc-connect   # 重启
journalctl --user -u cc-connect -f    # 查看日志
bash ccconfig/feishu/init-cconnect.sh # 重新配置
```

## 添加新用户

1. 飞书开放平台创建企业自建应用（机器人 + 长连接）
2. 编辑 `conf/feishu.json` → `ccconnect.users[]` 新增
3. 运行 `bash ccconfig/feishu/init-cconnect.sh`
