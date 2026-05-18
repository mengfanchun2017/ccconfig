# lib/ — 共享库

> 被多个脚本 source 的公共函数。

## 文件

| 文件 | 用途 |
|------|------|
| `path-helper.sh` | Node.js 路径发现（4 级回退）、版本文件读写、PATH 清理 |

## 函数

- `find_node_bin()` — 多策略发现 Node.js bin 目录
- `find_node_exe()` — 获取 node 可执行文件路径
- `get_version(component)` — 读取 versions.json 中的版本
- `save_version(component, version)` — 写入版本
- `get_node_pin()` — 读取 Node.js 大版本锁定值
- `recreate_node_symlinks(dir)` — 重建 `~/.local/bin/{node,npm,npx}` 符号链接
- `ensure_path()` — 清理 Windows PATH，确保 Node 和 local bin 在最前

## 使用

```bash
source "$SCRIPT_DIR/lib/path-helper.sh"
```
