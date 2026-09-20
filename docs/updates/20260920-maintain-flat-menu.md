# 2026-09-20 maintain 菜单扁平化 + set -e 退出 bug

> 范围：`maintain.sh` 交互菜单结构重做 + 菜单动作中断进程的根因修复
> 起因：用户报「有些选择了、再选返回，回直接退出（选 2a 后选 7）」，并提出菜单重做四条要求
> 关联：[SH-MENU-CONVENTIONS.md](../SH-MENU-CONVENTIONS.md)（schema 已同步改写）
> 关联 ADR：无（交互层实现细节，未上升到架构决策）

## 用户提的四条

1. 有些选择了再选返回会直接退出（复现路径 `2a` → 监控子菜单 → `7` 返回上层）
2. 不要子菜单了：每个功能大类放到一级，二级用 ABC 标记，这样就不需要"返回"
3. 一级菜单按实际拆开 —— LLM 项多，单独一个 `--LLM--`，其余由我判断
4. 每个选项后面附上**对应的子脚本和参数**，要能看出怎么直接调用、调的是哪个脚本
5. 一二级具体划分可合并可调整

## 发现汇总（6 项）

| # | 严重 | 类别 | 发现 | 状态 |
|---|------|------|------|------|
| 1 | P0 | 根因 | `_exec_entry` 在子菜单/未知项/动作失败时 `return 3`。`maintain.sh` 带 `set -euo pipefail`，而 `menu_parse` 是裸调 `_exec_entry` → **函数返回非零的那一刻 shell 直接 exit**，后面的 `return $?` 永远执行不到。所以「进子菜单 → 返回」＝退出进程。实测 `bash -c 'set -e; f(){ return 3; }; f; echo REACHED'` **不打印 REACHED，退出码 3** | ✅ 已修（`\|\| rc=$?` 捕获 + `menu_loop` 同样捕获；新增 §9 回归） |
| 2 | P0 | UX | 同一个 set -e 机制让**任何** `menu:` 子菜单在退出时都杀掉 maintain.sh（不只是"返回上层"，子菜单里选 1..6 同样触发）。用户只在对 7 时注意到 | ✅ 已修（同 #1；子菜单机制整体移除） |
| 3 | P0 | 结构 | 二级菜单嵌套导致"返回上层"心智负担，且有 4 个 `_submenu_*` 函数 + `menu:xxx` 分发机制要维护 | ✅ 已修（菜单改扁平：9 个功能域 × 字母项，选中即执行） |
| 4 | P1 | UX | 菜单只显示"条目名 + 灰色说明"，看不出背后调的是哪个脚本、什么参数 —— 想绕过菜单直接跑得翻 README | ✅ 已修（schema 增加 `cmd` 字段，渲染成右侧灰列，如 `./maintain.sh status --quick`） |
| 5 | P1 | bug | 菜单列用 `printf %-20s` 补齐，bash 按**字节**算宽度 → 中文标题宽度参差（`监控` 6 字节补 14 空格 vs `一键修复` 12 字节补 8 空格），加 `cmd` 列后必然对不齐 | ✅ 已修（`_pad_to()` 按显示宽度算，非 ASCII 记 2 列；新增对齐回归） |
| 6 | P2 | UX | 裸字母跨分类匹配：9 个分类每个都有 A–Z，敲 `a`/`b` 只命中"第一个匹配项"，按错就执行了不想要的操作（如 `b` 落到 1B 一键修复） | ✅ 已修（移除裸字母匹配，保留 `s`/`t`/`r`/`q`/`?` 系统键） |

## 新菜单结构（52 项，9 域；后续 3/5 类又各减一项，见同日另一篇）

| 分类 | 项数 | 覆盖 |
|------|------|------|
| 1 状态 | 4 | 全量/快速状态、依赖检查、一键修复 |
| 2 监控/同步 | 7 | 状态/启停/**重启**/追踪日志/修 inotify/git 拉取 |
| 3 更新 | 5 | 自更新、skill 同步、ccprivate 升级、升级工具链、全部仓库同步 |
| 4 LLM | 8 | 切换/列表/诊断/探测/修 model/sync/heal/删除/bill |
| 5 用量 | 8 | 统计/报告/归档/快照/重算/timer 三件套 |
| 6 MCP | 4 | 配置/状态/填 Key/同步 |
| 7 飞书 | 7 | 账号列表/切换×2/OAuth/重置/app 详情/通道测试 |
| 8 getnote | 6 | 列表/状态/增删/切换×2 |
| 9 其他 | 3 | PAT 刷新、模板差异/推广 |

原来的 4 个子菜单拆分去向：

- `_submenu_monitor` → `2A–2G`
- `_submenu_usage` → `5A–5H`（原顶部状态横幅移到 `5F` 定时器状态）
- `_submenu_getnote` → `8A–8F`
- `_submenu_update_sync` → `3A–3E`
- `_submenu_feishu`（飞书 4 项外壳）→ 7A–7G
- `_submenu_feishu_accounts` → **保留为叶子动作** `7F`（它本身是"从账号列表挑一个"的选择器，不是功能分组）；`_submenu_feishu_app_menu` / `_submenu_feishu_send_test` 相应改名 `feishu_app_menu` / `feishu_send_test`

## 设计决定

**需要输参数的叶子动作不再开一层菜单**，改用 `ask_run` / `ask_run_p` helper 就地 prompt：

```bash
# 4D 真实探测：问一个预设名，追加为最后一个参数
"4|D|真实探测（问预设名）|./maintain.sh llm test <名>|ask_run \"预设名（4B 可查）\" \"\$LIB_DIR/init-llm.sh\" test"
```

**`cmd` 必须真实可跑**。约定：能走 `maintain.sh` 子命令的用 `./maintain.sh <sub>`（最短、cwd=仓库根），其余用 `bash lib/xxx.sh`。`lib/menu-feishu.sh` 为此加了 script 直跑 guard，让它的 `cmd` 列不是空头承诺。

**`menu_select` 的 prompt 文案 `(0=返回上层)` → `(0=取消)`**：已经没有"上层"了，`0` 在所有调用点都意味着放弃本次选择。

## 新增/改动的回归测试

`tests/test-maintain.sh` 重写（旧版 84 条里 13 条随 schema 变更失效，现 90 条全绿）：

- §4 schema 改 5 字段；补分类连续（必须恰好 `0..9`）、字母不重复
- §5 **cmd 可跑性**：脚本路径存在 \+ `./maintain.sh <sub>` 的子命令真的在顶层 `case` 里注册（防"文档说能跑、实际没这子命令"）
- §6 action 引用解析（路径/函数存在）
- §9 **set -e 回归**：`menu_parse` 遇到 `false` 动作 / 未知键后进程必须仍活着 —— 直接锁住本次 P0
- §10 cmd 列显示列对齐（CJK 按 2 列）
- §11 无子菜单机制残留、无「返回上层」文案（注释里解释性的提及不算）
- §16 **pty 端到端**：跑一个动作后必须重绘主菜单（banner ×2）—— 复现用户原话"选完就退出"

## 验证

```
bash tests/test-maintain.sh        → PASS 90 / FAIL 0
15 个 shell 测试套件                → 全 PASS
bash -n 全部改动文件                → OK
```

## 遗留

- `shellcheck` 本机未安装（CI 的 lint job 仍会跑）
- MEMORY.md 45 条 > context-budget 规则的 40 条上限，待季度 review 清理
