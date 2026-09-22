# SH 菜单统一规范（2026-08-24，2026-09-20 扁平化改版）

> ccconfig 所有菜单的统一样式和行为约定。

## 一级菜单（data-driven，扁平结构）

使用 `menu_loop`（`lib/interact.sh`）驱动，数据在 `lib/menu-data-*.sh`：

```bash
# menu-data-maintain.sh
CAT_NAME[1]="状态"  # 灰色 --1 状态-- 标题
MENU_ENTRIES=(
    "1|A|状态检查（全量）|./maintain.sh status|bash \"\$LIB_DIR/status.sh\""
    "1|B|快速状态|./maintain.sh status --quick|bash \"\$LIB_DIR/status.sh\" --quick"
    "0| |退出||exit 0"
)
```

**schema: `cat|letter|title|cmd|action`（5 字段）**

| 字段 | 含义 |
|------|------|
| `cat` | 全局分类 ID，1-N 连续不跳号；`0` 保留给退出项 |
| `letter` | 分类内字母 A-Z；`<cat><letter>` 即执行键 |
| `title` | 显示标题，建议 ≤ 24 显示列（CJK 记 2 列） |
| `cmd` | 右侧灰色列：**绕过菜单的直接调用命令**，必须真实可跑（cwd = 仓库根） |
| `action` | 实际执行的命令或函数名（eval 上下文，可用 `$LIB_DIR` / `$CCCONFIG_DIR`） |

注：`action` 里写 `\$LIB_DIR` 转义，让展开发生在 eval 时而不是 source 时。

## 扁平化原则（2026-09-20）

**没有二级菜单，因此没有"返回上层"。**

- 一级 = 功能域（状态/监控/更新/LLM/MCP/飞书/getnote/其他）
- 二级 = 该域下的字母项，**选中即执行**
- 需要用户输一个参数的叶子动作（删预设、切账号），用 `maintain.sh` 里的
  `ask_run` / `ask_run_p` helper 就地 prompt，**不要为此再开一层菜单**
- 真正的列表选择器（如飞书账号挑一个 app）可以是叶子动作，按 `0` 即回主菜单，
  但它不是"上层"关系

## 渲染格式

```
  --4 LLM--
  4A  切换预设（交互）        ./maintain.sh llm
  4B  列出预设                ./maintain.sh llm list
```

- 键 `4A` 绿色加粗，无空格
- 分类标题 `--4 LLM--` 灰色加粗（分类号 + 名称）
- 标题列宽 24 显示列，右侧灰色 (`DIM`) 是 `cmd`
- 退出行 `  0   退出` 绿色加粗
- 提示 `选择:` 绿色加粗
- 分类编号连续无跳号

### 对齐必须按显示列算

`printf %-24s` 在 bash 里按**字节**补齐，中文标题会参差。统一用
`_pad_to()`（`lib/interact.sh`）计算显示宽度（非 ASCII 记 2 列）后补空格。
`tests/test-maintain.sh` 有对齐回归（所有 `cmd` 起始列必须一致）。

## 输入键

| 输入 | 行为 |
|------|------|
| `<cat><letter>` | 执行该项（`2A`、`4H`） |
| `<cat>` | 执行该分类首项 |
| `s` | 状态检查（= 1A） |
| `t` | 监控状态（= 2A） |
| `r` | 刷新重绘 |
| `q` / `0` | 退出 |
| `?` / `h` | 帮助 |

**不提供**裸字母跨分类匹配。九个分类每个都有 A-Z，裸字母只能命中"第一个"，
按错就执行了不想要的操作 —— 已移除。

## set -e 陷阱（必须遵守）

`_exec_entry` 失败时返回 3。在 `set -euo pipefail` 下，**裸调一个返回非零的
函数会直接杀掉整个进程** —— 表现为"点了某项（或从任何返回 3 的分支出来）
maintain.sh 自己退出了"。

```bash
# ❌ 错：f 返回 3 时 set -e 立即 exit，后面的 return 永远到不了
_exec_entry "$cat" "$letter"
return $?

# ✅ 对：捕获返回码，自己 return
_exec_entry "$cat" "$letter" || rc=$?
return "$rc"
```

调用方同理：`menu_parse "$choice" || rc=$?`。回归测试见
`tests/test-maintain.sh` §9。

## 子菜单 / 列表选择器（menu_select）

只剩"从列表里挑一个"的场景，不再用于功能分组：

```bash
local c; c=$(menu_select "标题" "选项1" "选项2" "返回")
[[ -z "$c" || "$c" = "0" ]] && return  # 0=取消
case "$c" in
    1) do_something ;;
esac
```

渲染格式：
```
  --飞书账号--
  1)  ailab
  2)  test
  3)  返回

  选择 [1-3] (0=取消):
```
- 数字绿色加粗（`BOLD_GREEN`），格式 `N)  项`
- 标题灰色 `--分组--` 格式
- prompt 统一 `(0=取消)`
- `0`/末项/越界/EOF 一律返回 `"0"`（取消哨值）

## 颜色变量

| 变量 | 用途 | ANSI |
|------|------|------|
| `BOLD_GREEN` | cat+letter、子菜单数字 | `\033[1;32m` |
| `BOLD_GRAY` | 分类标题 `--xxx--` | `\033[1;90m` |
| `DIM` | 直接调用命令列 / 描述文字 | `\033[2m` |
| `LIGHT_BLUE` | 状态值/当前标记 | `\033[96m` |
| `YELLOW` | 警告/需注意的信息 | `\033[1;33m` |

## 行为约定

- 顶层菜单 `0` / `q` 退出整个程序
- 不写 `read -p`（不支持 ANSI），用 `printf` + `read -r`
- `menu_select` 输出走 stderr，返回值走 stdout
- `menu_select` 从 `/dev/tty` 读输入（避开管道阻塞）
- 不需要确认步骤的操作用 `info` 输出结果，不弹 confirm
- `cmd` 列必须与 `action` 指向同一个脚本 —— 测试会校验路径与 `maintain.sh` 子命令存在
