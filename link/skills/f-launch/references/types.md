# f-launch 项目类型索引

> 8 类项目的特征描述。判断用户意图时对照本表。

## 类型速查

| 代号 | 触发关键词 | 复杂度 | 典型场景 |
|------|-----------|--------|----------|
| `static-web-personal` | 礼物/纪念/展示/主页/纪念站/个人站 | ★ | URL 直达内容，5-100 个内容项 |
| `web-api-backend` | API/CRUD/REST/后端/服务端 | ★★★ | 业务后端,长期演进 |
| `cli-tool` | CLI/命令行/工具/脚本/scaffold 工具 | ★★ | 个人/团队工具,npm/brew/cargo 发布 |
| `ai-agent-tool` | AI/Agent/LLM/Claude/工具调用/RAG | ★★★ | 智能助手、Agent、自动化工作流 |
| `data-pipeline` | 数据/ETL/数仓/ML 训练/数据处理 | ★★★★ | 日志聚合、报表、特征工程 |
| `mobile-app` | 移动 App/iOS/Android/小程序 | ★★★★ | 消费类应用、跨平台 |
| `desktop-app` | 桌面/客户端/Electron/Tauri | ★★★★ | 内部工具、跨平台 GUI |
| `game` | 游戏/Godot/Unity | ★★★★ | 独立游戏、游戏原型 |

## 类型判断决策树

```
用户意图
  ├─ 提到"网站/web/站" + 强调"个人/礼物/纪念"   → static-web-personal
  ├─ 提到"网站/web" + 强调"业务/服务/API"        → web-api-backend
  ├─ 提到"命令行/CLI/工具脚本"                   → cli-tool
  ├─ 提到"AI/Agent/智能/自动化"                  → ai-agent-tool
  ├─ 提到"数据/数仓/ETL/训练"                    → data-pipeline
  ├─ 提到"App/移动/手机"                         → mobile-app
  ├─ 提到"桌面/客户端/Electron"                  → desktop-app
  └─ 提到"游戏/Godot"                            → game
```

## 不确定时

问用户 1-2 题确认:
1. "这是个人/学习项目,还是商业/生产级?"(影响合规 + 部署)
2. "预期用户量级(自己/小团队/公众)?"(影响架构选型)
