# Project Memory - projectu

This file persists across Claude Code conversations for projectu project.

## Quick Links
- Project root: /home/francis/git/projectu
- ccconfig: /home/francis/git/ccconfig

## Project Info
- **projectu** is a Godot 4.x 2D pixel art survival game
- 隐形怪物生存者：玩家通过放置探测器寻找隐形怪物，躲避或击杀
- Language: GDScript
- Claude Code starts from ~/git/ (总目录)

## Project Structure
```
projectu/
├── project.godot      # Godot 项目配置
├── scenes/           # 场景文件 (.tscn)
│   ├── main.tscn     # 主场景
│   ├── player.tscn   # 玩家
│   ├── enemy.tscn    # 敌人
│   └── detector.tscn # 探测器
├── scripts/          # GDScript 脚本
│   ├── game_manager.gd  # 游戏状态/分数/难度
│   ├── player.gd        # 玩家控制 (WASD/方向键移动，空格放置探测器)
│   ├── enemy.gd        # 敌人AI
│   ├── detector.gd     # 探测器机制
│   ├── spawner.gd      # 怪物生成
│   └── ui_manager.gd   # UI管理
├── assets/          # 资源文件
├── docs/            # 开发文档
└── README.md        # 项目说明
```

## Implemented Features
- 玩家移动 (WASD + 方向键)
- 隐形怪物系统
- 探测器放置机制 (空格键)
- 分数系统
- 怪物1击必杀
- 攻击功能
- 难度递增系统 (每30秒+10%)
- 音效系统

## Controls
- WASD / 方向键: 移动
- 空格键: 放置探测器

## Configuration
- Skills: ~/.claude/skills → ccconfig/.agents/skills/
- MCP: ~/.claude.json (全局)
- sync: monitor-sync.sh (在 ccconfig 目录运行)

## Memory Storage
- Actual path: /home/francis/.claude/projects/-home-francis-git-projectu/memory/
- Linked from: /home/francis/git/ccconfig/link/-home-francis-git-projectu/
- auto-sync: ✅ 运行中 (PID: 1055)

---
Last updated: 2026/04/19
