---
paths:
  - "**/*.gd"
  - "**/*.tscn"
  - "**/project.godot"
---

# Godot / GDScript 规范

> **可选模块**：仅在 Godot 游戏引擎项目中自动加载（`**/*.gd` 路径匹配）。非 Godot 用户可安全忽略此文件。

## 项目特征识别
- 场景文件 `.tscn` 是文本格式，可读写
- `.gd.uid` 文件是 Godot 自动生成的脚本 UID，不要手动修改
- `project.godot` 的 config_version=5 对应 Godot 4.x
- `.godot/` 目录是编辑器缓存，已在 .gitignore

## 代码风格
- GDScript 使用 `static typing` (GDScript 2.0): 参数和返回值加类型
- 信号声明放在文件顶部，extends 之后
- 用 `@export` 暴露可配置参数给编辑器
- `_process` 用于帧更新，`_physics_process` 用于物理移动
- 节点查找用 `get_tree().get_first_node_in_group()` (Godot 4 方式)
- 场景实例化: `PackedScene.instantiate()` 不是 `.instance()` (Godot 4 API)

## 项目约定
- 信号驱动: game_manager 发信号 → UI/其他节点响应
- group 系统: "player", "enemy", "game_manager" 用于跨节点查找
- 程序生成: 音效/视觉效果用代码生成，不依赖外部资源文件
- 坐标系统: 1 单位 = 32 像素 (pixel art scale)

## Godot CLI
- 运行项目: `godot --headless --quit` 或 `godot -e` (编辑器)
- 检查项目: `godot --headless --quit --check-only`
- 导出: `godot --headless --export-release "platform" output`
