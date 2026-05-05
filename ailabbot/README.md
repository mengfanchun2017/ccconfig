# ailabbot · cc-connect 多机器人管理中心

统一管理 cc-connect 接入的所有飞书机器人。属于 ccconfig 子模块，随 ccconfig 自动同步。

## 架构

```
cconfig/ailabbot/conf/bots.json   ← 单一配置源（所有机器人）
  │
  ↓  scripts/init.sh（自动检测环境）
  │
  ├── 台式机: → ~/cc-connect/config.toml → systemd restart
  └── 笔记本: → 仅生成 TOML，跳过服务管理
```

## 快速开始

```bash
# 查看所有机器人状态（任何机器）
bash ccconfig/ailabbot/scripts/status.sh

# 台式机：生成配置 + 启动服务
bash ccconfig/ailabbot/scripts/init.sh

# 笔记本/预览：仅生成，不动服务
bash ccconfig/ailabbot/scripts/init.sh --dry-run
```

## 管理机器人

```bash
bash ccconfig/ailabbot/scripts/bot-enable.sh <名称>    # 启用
bash ccconfig/ailabbot/scripts/bot-disable.sh <名称>   # 禁用
```

修改机器人配置：编辑 `ccconfig/ailabbot/conf/bots.json`，提交后 auto-sync 自动同步到所有机器。

## 权限管理

每个机器人在 `bots.json` 中独立配置：

```json
"permissions": {
  "adminOpenIds": ["ou_xxx"],
  "allowFrom": "*",
  "disabledCommands": ["/shell", "/restart"],
  "rateLimit": { "maxMessages": 30, "windowSecs": 60 }
}
```

## cc-connect 服务

```bash
systemctl --user status cc-connect
journalctl --user -u cc-connect -f
```
