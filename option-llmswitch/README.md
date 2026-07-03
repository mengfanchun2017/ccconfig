# option-llmswitch — LLM 网关自动切换

> Claude Code 的 LLM 代理网关，支持按时段自动切换后端，无需重启 CC。

## 解决的问题

DeepSeek 2026年7月起执行**峰谷定价**：工作日 9:00-12:00、14:00-18:00 价格翻倍。本工具在 CC 和 LLM API 之间插入本地代理，高峰期自动切到 MiniMax，低谷期用 DeepSeek，零重启。

## 路由逻辑

| 时段 | 主模型 (deepseek-v4-pro) | 小模型 (MiniMax-M3) |
|------|--------------------------|---------------------|
| 非高峰 | → DeepSeek API | → MiniMax API |
| 高峰 | → MiniMax API | → MiniMax API |

小模型始终走 MiniMax（便宜且背景任务对质量不敏感）。

## 快速开始

```bash
# 1. 安装
bash ccconfig/option-llmswitch/init.sh --install

# 2. 编辑配置
vim ccconfig/option-llmswitch/conf/llmswitch.json

# 3. 启动代理
bash ccconfig/option-llmswitch/init.sh --start

# 4. 检查状态
bash ccconfig/option-llmswitch/init.sh --status
```

## 模式切换

```bash
# 自动模式（按时段）
bash ccconfig/option-llmswitch/init.sh --mode auto

# 手动模式（固定后端）
bash ccconfig/option-llmswitch/init.sh --mode manual minimax

# 关闭（直通原始后端）
bash ccconfig/option-llmswitch/init.sh --mode off
```

模式切换为**热切换**，下次请求立即生效，无需重启代理或 CC。

## 命令参考

| 命令 | 说明 |
|------|------|
| `--install` / `-i` | 安装依赖，创建配置 |
| `--start` / `-S` | 启动代理 |
| `--stop` / `-K` | 停止代理 |
| `--restart` / `-R` | 重启代理 |
| `--status` / `-s` | 查看状态 |
| `--mode` / `-m` | 切换模式 |
| `--log` / `-l` | 查看日志 |
| `--update` / `-u` | 更新依赖 |
| (无参数) | 交互式菜单 |

## 架构

```
Claude Code ──> 127.0.0.1:8899 (proxy.py) ──> DeepSeek API (off-peak)
                                            ──> MiniMax API (peak/always)
```

代理只做两件事：
1. 检查当前时间是否在高峰时段
2. 重写请求中的 `model` 字段，转发到对应后端

两个后端都是原生 Anthropic API，无需协议转换。

## 与 init-llm.sh 的关系

- `init-llm.sh` 是主入口。Gateway 作为第三个选项（与 MiniMax、DeepSeek 同级）
- 在 `init-llm.sh` 中选择 Gateway 即启动代理并切换；选 MiniMax/DeepSeek 自动停止代理
- 代理运行时，`init-llm.sh` 在菜单中显示当前路由、高峰时段，支持快捷键管理
- 本脚本 (`init.sh`) 仍可独立使用（`--start`/`--stop`/`--mode` 等）

## 监控

- `bash monitor.sh status` — 显示 LLM Gateway 状态行（绿/黄/灰/红）
- `bash status.sh` — 在 `[12] option-*` 区自动显示状态
- `curl http://127.0.0.1:8899/health` — 获取 JSON 格式健康信息

## 已知问题

### 1. 切换后 `API Error: Failed to parse JSON`

**现象**：`init-llm.sh` 切换 LLM 后，当前 CC session 间歇性报错。

**根因**：CC 启动时锁定 model router（含 thinking 参数格式），切换 provider
后 router 不刷新。通过 Gateway proxy 时，DeepSeek→MiniMax 边界切换会导致
thinking 块格式差异 → 后续请求解析失败。

**尝试过的修复**（均不完全生效）：

| 尝试 | 结果 |
|------|------|
| `build_provider_registry` 跳过无 key 条目 | 修复 proxy 502，但不解决 JSON 解析 |
| 共享 `httpx.AsyncClient` 连接池 | 降低延迟，不完全解决 |
| `strip_thinking()` 移除 thinking 块 | 导致 body 双序列化，引入新错误 |
| 响应 `content-length` 头移除 | 修复截断，不完全解决 |
| model 改写改用 regex 精准替换 | 消除全序列化，agent 并发正常 |
| `MAX_THINKING_TOKENS=0` | 影响模型推理质量，已回退 |
| proxy 注入 `thinking=disabled` 给 MiniMax | 影响模型推理质量，已回退 |

**当前方案**：
- proxy 纯透传 thinking 块，零修改
- `init-llm.sh` Gateway 选项标注 `[等 CC 更新后启用]`
- 切换后 `/exit` → 重新 `claude` 恢复 session
- 代码中保留 D/M 强制路由测试选项（已注释），等 CC 修复后启用

**等 CC 支持**：`clear_thinking_20251015` beta header、session 内动态刷新 router

**记录日期**：2026-07-03

### 2. Proxy 透传架构决策

proxy 只改写两条：
1. **model name**：regex 精准替换（`"model":"llmswitch"` → `"MiniMax-M3"`），零 body 序列化
2. **Authorization header**：替换为对应 provider 的 API key

其他所有内容（thinking 参数、tool definitions、SSE 流）完整透传，不做任何修改。
