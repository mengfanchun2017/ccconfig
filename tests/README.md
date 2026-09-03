# tests/ — ccconfig 自动化测试

## 测试框架：bats（Bash Automated Testing System）

**新测试一律用 bats**（`.bats` 文件），不再写自定义 `pass()`/`fail()` 函数。

### bats 测试示例

```bash
#!/usr/bin/env bats
load "setup"

@test "description" {
    source "$CCCONFIG_DIR/lib/dry-run.sh"
    run some_function
    [ "$status" -eq 0 ]
    [ "$output" = "expected" ]
}
```

### bats API
| 函数 | 用途 |
|------|------|
| `run <cmd>` | 执行命令，捕获到 `$status` `$output` `$lines` |
| `[ "$status" -eq 0 ]` | 断言退出码 |
| `[ "$output" = "..." ]` | 断言 stdout |
| `[[ "$output" == *"..."* ]]` | 断言 stdout 包含 |
| `load "setup"` | 加载 setup.bats（提供 `$CCCONFIG_DIR` 等变量） |
| `skip "reason"` | 跳过测试 |

### 测试文件约定
- 文件名：`test-<module>.bats`
- 每个 `@test` 块测试一个行为
- 外部依赖用 `run` 捕获，不写手动的 `PASS++`
- `setup.bats` 提供公共的 `$CCCONFIG_DIR`/`$LIB_DIR` 和 `make_isolated_home()`

### 运行

```bash
# 运行所有 bats 测试
bats tests/*.bats

# 运行单个
bats tests/test-dry-run.bats
```

## 现有 shell 测试（兼容保持）

以下 `.sh` 测试保留供 CI 继续使用，新功能不在此写：

| 文件 | 覆盖 |
|------|------|
| `test-init-base.sh` | init 流程回归（mock 隔离环境） |
| `test-init-llm.sh` | LLM 配置读写 |
| `test-init-option.sh` | option 语法检查 |
| `test-maintain.sh` | maintain 菜单回归 |
| `test-monitor.sh` | monitor 核心函数 |
| `test-sync.sh` | sync 核心函数 |
| `test-json-schema.sh` | JSON 结构兼容性 |
| `test-token-usage.sh` | token 统计 |
| `test-bootstrap.sh` | bootstrap 流程 |
| `test-cross-script-dryrun.sh` | 跨脚本 dry-run |
| `test-interact.sh` | interact 函数 |
| `test-init-ccprivate-repo.sh` | ccprivate 初始化 |
| `test-syntax.sh` | 语法检查（被 test-syntax.bats 替代） |

## 添加新测试

1. 创建 `tests/test-<module>.bats`
2. 第一行 `load "setup"`
3. 写 `@test "描述" { ... }` 块
4. 跑 `bats tests/test-<module>.bats` 验证
