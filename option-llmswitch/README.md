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

- **代理运行时**：`init-llm.sh` 会检测到代理并显示提示，菜单增加 `G) 管理 LLM 网关` 选项
- **代理停止后**：`init-llm.sh` 照常工作（写 env 文件，需重启 CC）
- 切换主模型/小模型配置通过 `init-llm.sh` 或直接编辑 `conf/llm.json`

## 监控

- `bash monitor.sh status` — 显示 LLM Gateway 状态行（绿/黄/灰/红）
- `bash status.sh` — 在 `[12] option-*` 区自动显示状态
- `curl http://127.0.0.1:8899/health` — 获取 JSON 格式健康信息
