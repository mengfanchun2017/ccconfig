# game — 游戏项目

> 场景:2D / 3D 游戏(独立 / 原型 / 商业)
> 复杂度:★★★★

## 适用

- 2D 独立游戏(像素风 / 卡通 / 解谜)
- 3D 中小规模(生存 / 模拟 / 沙盒)
- 游戏原型(快速验证玩法)
- Godot 教程项目

## 默认技术栈

| 引擎 | 选型 | 理由 |
|------|------|------|
| 首选 | Godot 4.x (GDScript / C#) | 开源 + 轻量 + 2D 强 + 自带工具链 |
| 备选 | Unity 2026 (C#) | 3D 强 + 生态厚 + Asset Store |
| 备选 | Unreal Engine 5 (C++ / Blueprint) | AAA 3D + 写实 |
| 备选 | Bevy (Rust) | 纯 ECS + 高性能 + 轻量 |
| 备选 | Pygame / Love2D | 学习 / 简单 2D 原型 |

## Godot 优势(独立游戏首选)

- 零安装费 + 零分成(Steam 100% 收入)
- 2D 引擎一流
- GDScript 简单易学
- 跨平台(Windows / macOS / Linux / Android / iOS / Web)
- 内置编辑器 + 调试器 + 物理引擎

## 脚手架结构(Godot 4)

```
<代号>/
├── project.godot          # Godot 项目配置
├── .godot/                # 编辑器缓存(已在 .gitignore)
├── scenes/                # .tscn 场景文件
│   ├── main/
│   │   └── main.tscn
│   ├── levels/
│   │   ├── level_1.tscn
│   │   └── level_2.tscn
│   ├── characters/
│   │   ├── player.tscn
│   │   └── enemy.tscn
│   └── ui/
├── scripts/               # .gd 脚本
│   ├── main.gd
│   ├── player.gd
│   ├── enemy.gd
│   └── game_manager.gd
├── assets/                # 资源
│   ├── art/               # 美术(Pixel art / 3D model)
│   ├── audio/             # 音效 + 音乐
│   ├── fonts/
│   └── data/              # JSON / 二进制数据
├── tools/                 # 构建 / 工具脚本
│   └── build.sh
├── export_presets/        # 导出预设
├── CLAUDE.md
├── README.md
├── LICENSE
└── .gitignore
```

## 关键决策

- **GDScript vs C#**:GDScript 简单快上手 + 引擎集成最好;C# 性能更好 + 强类型 + 复用 .NET 生态
- **信号驱动 vs 直接调用**:游戏对象间通信优先信号(松耦合)
- **状态机**:每个角色/关卡用状态机(自实现 / 库)
- **保存系统**:JSON / 二进制 / SQLite,按数据复杂度选
- **资源管理**:场景复用(.tscn 实例化)+ 池(对象池/子弹池)
- **构建**:Godot 内置导出 + Steamworks SDK

## 风险点

1. **范围蔓延(scope creep)** — 加功能没止境。缓解:MVP 锁定 + 严格 backlog 管理。
2. **美术 / 音效缺失** — 资源是最大瓶颈。缓解:程序化生成(noise / synth)+ 占位资源(kenney.nl / freesound.org)。
3. **性能优化被忽视** — 后期重构痛苦。缓解:Profiling 工具(Godot 内置)+ 早优化热点。
4. **跨平台发布复杂** — 不同平台 SDK / 审核 / 商店政策。缓解:Godot 导出预设 + 平台政策清单。
5. **协作成本** — 美术 / 音频 / 程序协调难。缓解:Git LFS 大文件 + 命名规范 + 场景 lock 机制。

## 学习路径(8-16 周,看规模)

| 周 | 任务 |
|----|------|
| 1-2 | Godot 入门 + 第一个场景 + 玩家移动 |
| 3-4 | 状态机 + 敌人 AI + 碰撞 |
| 5-6 | UI + 菜单 + 暂停 / 死亡 |
| 7-8 | 关卡系统 + 存档 / 读档 + 进度 |
| 9-12 | 美术 / 音效 + 打磨 + 性能优化 |
| 13-14 | 跨平台构建 + 商店页面(Steam / itch.io) |
| 15-16 | Beta 测试 + 修复 + 发布 |

## 关联资源

- Godot 文档:https://docs.godotengine.org/
- Godot 教程:https://gdquest.github.io/
- Kenney(免费美术资源):https://kenney.nl/
- Freesound(免费音效):https://freesound.org/
- Steamworks SDK:https://partner.steamgames.com/doc/sdk
