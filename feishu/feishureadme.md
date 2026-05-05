# feishu — 飞书集成

> lark-cli 文档操作 + cc-connect 多用户飞书桥接

## 组件

| 组件 | 脚本 | 用途 |
|------|------|------|
| lark-cli | `init-feishu.sh` | 终端创建文档/日历/任务 |
| cc-connect | `init-cconnect.sh` | Bridge 接收飞书消息（WebSocket，多机器人） |

## 快速开始

```bash
# 仅安装 lark-cli（文档/日历/任务）
bash ccconfig/feishu/init-feishu.sh

# 配置 cc-connect Bridge（多机器人飞书桥接）
bash ccconfig/cconnect/init-cconnect.sh
```

## 多机器人架构

```
ccconfig/cconnect/conf/bots.json   ← 单一配置源（所有机器人）
  │
  ↓  scripts/init.sh（自动检测环境 → 安装二进制 → 生成 TOML → systemd）
  │
  ├── 台式机: → ~/cc-connect/config.toml → systemd restart
  └── 笔记本: → 仅生成 TOML，跳过服务管理
```

## 配置

- `cconnect/conf/bots.json` — 所有机器人配置（名称、App ID/Secret、工作目录、权限、频率限制）
- `conf/feishu.json` — lark-cli 凭证

修改 bots.json 后运行 `bash ccconfig/cconnect/init-cconnect.sh` 使配置生效。

## cc-connect 常用命令

```bash
systemctl --user status cc-connect         # 查看状态
systemctl --user restart cc-connect        # 重启
journalctl --user -u cc-connect -f          # 查看日志
bash ccconfig/cconnect/init-cconnect.sh      # 重新配置
bash ccconfig/cconnect/status.sh            # 机器人状态
```

## 添加新机器人

1. 飞书开放平台创建企业自建应用（机器人 + 长连接）
2. 编辑 `cconnect/conf/bots.json` → `bots[]` 新增
3. 运行 `bash ccconfig/cconnect/init-cconnect.sh`
