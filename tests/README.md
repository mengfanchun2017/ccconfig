# tests/ — ccconfig 自动化测试

## test-init.sh

init 流程回归测试。在隔离的临时目录中模拟新机器环境，mock git/gh/npm/claude/curl 等外部命令，验证所有 init 路径不报错。

**零网络调用，纯本地，秒级完成。**

### 用法

```bash
bash ccconfig/tests/test-init.sh              # 全部测试
bash ccconfig/tests/test-init.sh --verbose    # 详细输出
bash ccconfig/tests/test-init.sh --list       # 仅列出测试用例
```

### 覆盖范围

| 类别 | 测试项 |
|------|--------|
| `ensure_config` | broken symlink / 已有配置 / 缺配置缺模板 |
| `check_first_time` | ccprivate 缺失 / ccprivate 存在 |
| `ensure_claude_skills` | 无 gh 认证 / 有 gh 认证 |
| symlink | SKILLS_SRC 目录缺失不崩溃 |
| placeholder | 中文模板值检测 / 真实值识别 |
| home_expand | `~` 和 `$HOME` 展开 |
| init --dry-run | 输出预览内容 |
| sync | setup-links 失败不中断同步 |
| mcp sync | 写入正确路径 / 缺文件不崩溃 |

### Mock 策略

对外部命令全部替换为 stub（`~/.local/bin/` 优先于系统 PATH）：
- `git` / `gh` / `npm` / `npx` / `claude` — 返回 mock 输出
- `curl` / `systemctl` / `inotifywait` / `sudo` — 返回成功
- `python3` — 真实二进制（JSON 解析需要）

### 添加新测试

1. 在 `test-init.sh` 写一个 `test_xxx()` 函数
2. 加入 `all_tests` 数组：`"描述文字" test_xxx`
3. 跑 `bash ccconfig/tests/test-init.sh` 验证
