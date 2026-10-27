# tests/ — ccconfig 自动化测试

## 测试框架

**两种并存**：6 个 `.bats`（Bash Automated Testing System）+ 22 个 `.sh`（自写 `pass()`/`fail()` 计数）。
`.bats` 适合纯函数单测，`.sh` 适合需要 mock 环境/多段断言的流程回归 —— 现状是 `.sh` 占多数。

**新增纯函数单测用 bats**（`.bats`）；流程/端到端回归可继续用 `.sh`（照抄现有 `.sh` 的
`PASS=0; FAIL=0` + `pass()`/`fail()` 约定，不要自创第三种风格）。

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
| `load "setup"` | 加载 setup.bash（提供 `$CCCONFIG_DIR` 等变量） |
| `skip "reason"` | 跳过测试 |

### 测试文件约定
- 文件名：`test-<module>.bats`
- 每个 `@test` 块测试一个行为
- 外部依赖用 `run` 捕获，不写手动的 `PASS++`
- `setup.bash` 提供公共的 `$CCCONFIG_DIR`/`$LIB_DIR` 和 `make_isolated_home()`

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
| `test-init-llm-switch.sh` | LLM 切换端到端（含本机/共享分层、mtime 断言） |
| `test-init-llm-merge.sh` | 三层 LLM 配置合并读取单元测试 |
| `test-init-option.sh` | option 语法检查 |
| `test-maintain.sh` | maintain 菜单回归 |
| `test-monitor.sh` | monitor 核心函数 |
| `test-sync.sh` | sync 核心函数 |
| `test-json-schema.sh` | JSON 结构兼容性 |
| `test-bootstrap.sh` | bootstrap 流程 |
| `test-claude-update.sh` | update.sh 的 claude 更新路径 |
| `test-cross-script-dryrun.sh` | 跨脚本 dry-run |
| `test-dry-run-argv.sh` | `dry_run_parse_argv` 让 `bash lib/x.sh --dry-run` 真正生效 |
| `test-git-pull.sh` | lib/git-pull.sh 单点拉取实现 |
| `test-interact.sh` | interact 函数 |
| `test-init-ccprivate-repo.sh` | ccprivate 初始化 |
| `test-mcp-pywrite.sh` | mcp-manager.sh 的 py_write 变量转义 |
| `test-node-cleanup-guard.sh` | update.sh 的旧 Node 清理白名单 |
| `test-openai-bridge.sh` | Anthropic↔OpenAI bridge 流式链路（端到端，mock upstream） |
| `test-secret-patterns.sh` | 密钥正则单一真相源 + 消费方接线 |
| `test-setup-link.sh` | setup_link 死链处理回归 |
| `test-skill-init.sh` | init-skill.sh 命令入口完整性 |
| `test-ccprivate-boundary.sh` | 公开/私有仓边界：已删项（skill-local / templates/agents / usage / link 副本）不得复活，公开仓无凭据形状 |
| `test-ccprivate-sandbox-e2e.sh` | 假 HOME + 假 ccprivate 跑真实 setup.sh：新机安装落盘本机三件套、幂等不覆盖用户键、老机升级清理残留副本并刷新 setup.sh |
| `test-bridge-protocol.py` | bridge 协议转换单元回归（块顺序/usage/tool_calls/finish_reason/字段丢失）。端到端用例只造 `content+[DONE]` 一种形态，协议层缺陷全在其盲区外，故单独成篇 |
| `test-syntax.sh` | 语法检查（被 test-syntax.bats 替代） |

## bats 测试

| 文件 | 覆盖 |
|------|------|
| `test-colors.bats` | lib/colors.sh 单元测试 |
| `test-guard.bats` | lib/dry-run.sh 原子写入测试 |
| `test-interact.bats` | lib/interact.sh 单元测试 |
| `test-path-helper.bats` | lib/path-helper.sh 单元测试 |
| `test-syntax.bats` | 全仓 shell 语法检查 |
| `test-dry-run.bats` | dry-run 行为 |

## CI 覆盖现状

`.github/workflows/check.yml` 的 unit job 只显式列了部分 `.sh`，其余靠 `bats tests/*.bats` glob。
**没进 CI 的 `.sh` 测试坏了没人知道**（`test-init-llm.sh` 曾长期假失败）。补进 CI 时加到
unit job 的显式列表即可。

## 添加新测试

1. 创建 `tests/test-<module>.bats`
2. 第一行 `load "setup"`
3. 写 `@test "描述" { ... }` 块
4. 跑 `bats tests/test-<module>.bats` 验证
