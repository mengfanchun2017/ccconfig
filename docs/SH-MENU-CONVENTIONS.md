# SH 菜单统一规范（2026-08-24）

> ccconfig 所有菜单的统一样式和行为约定。

## 顶层菜单（data-driven）

使用 `menu_loop`（`lib/interact.sh`）驱动，数据在 `lib/menu-data-*.sh`：

```bash
# menu-data-maintain.sh
CAT_NAME[1]="状态"  # 灰色 --分组-- 标题
MENU_ENTRIES=(
    "1|A|条目名|灰色描述文字|action|"
    "1|B|条目名|灰色描述文字|action|"
    "2|A|条目名|灰色描述文字||menu:subfunc"
    "0| |退出||exit 0|"
)
```

渲染格式：`  \033[1;32m1A\033[0m  条目名  \033[2m描述文字\033[0m`
- 选项 `1A` 绿色加粗，无空格
- 分类标题 `--状态--` 灰色加粗
- 提示 `选择:` 绿色加粗
- 输入支持：`1A`（cat+letter）、`A`（跨分类首字母）、`1`（分类首项）、`0/q` 退出、`r` 刷新

## 子菜单（menu_select）

```bash
local c; c=$(menu_select "标题" \
    "选项1" \
    "选项2" \
    "返回")  # 最后一项总是 "返回"
[[ -z "$c" || "$c" = "0" ]] && return  # 0 返回
case "$c" in
    1) do_something ;;
    2) do_other ;;
esac
```

渲染格式：
```
  --Monitor--
  1  LLM 链路诊断
  2  状态查看
  0  返回

  选择 [1-2]:
```
- 数字绿色加粗，无 `)`
- 标题灰色 `--分组--` 格式
- `0` 总是返回上一级
- `0` 选项默认不显示在菜单中（`menu_select` 自动处理输入）
- 所有 case 必须含 `0|*)` 或 `[[ "$c" = "0" ]]` 返回分支

## 颜色变量

| 变量 | 用途 | ANSI |
|------|------|------|
| `BOLD_GREEN` | cat+letter、子菜单数字 | `\033[1;32m` |
| `BOLD_GRAY` | 分类标题 `--xxx--` | `\033[1;90m` |
| `DIM` | 描述文字 | `\033[2m` |
| `LIGHT_BLUE` | 状态值/当前标记 | `\033[96m` |
| `YELLOW` | gateway 路由信息 | `\033[1;33m` |

## 行为约定

- 子菜单最后一项总是「返回」，按 `0` 触发
- 顶层菜单 `0` / `q` 退出整个程序
- 不写 `read -p`（不支持 ANSI），用 `printf` + `read -r`
- `menu_select` 输出走 stderr，返回值走 stdout
- `menu_select` 从 `/dev/tty` 读输入（避开管道阻塞）
- 不需要确认步骤的操作用 `info` 输出结果，不弹 confirm
