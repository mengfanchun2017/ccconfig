# option-evalscope

用 [EvalScope](https://github.com/modelers/evalscope)（阿里 ModelScope 开源 LLM 评估框架）对不同模型做**性能压测**和**精度评估**，统一从 ccconfig 的 `llm.json` presets 读取模型端点，一次脚本跑多个模型对比，评估哪个模型更快、更准。

## 为什么选 EvalScope

`eval perf` 一行压出**并发数 × TPS × 延迟百分位**（TTFT/TPOT/ITL/E2E），`eval eval` 一行测出 **MMLU/GSM8K 等精度分**，还能用 `--collect-perf` 在精度评估**同时记录推理性能**——性能+精度一张报告。纯本地 CLI，无需 MCP / skill 集成。

## 安装

```bash
bash ccconfig/option-evalscope/init.sh --install
```

用 `uv` 建独立 Python 3.11 venv（`.venv/`）装 evalscope，**不污染**系统 Python 3.14。装完 `init.sh --status` 显示 OK 即就绪。

## 用法

所有命令按 `llm.json` 的 preset 名驱动（`cconfig/conf/llm.json` → `ccprivate/conf/llm.json`）。

查看可用 preset：

```bash
bash ccconfig/option-evalscope/run-perf.sh --list
```

### 性能压测（并发/TPS/延迟）

```bash
bash ccconfig/option-evalscope/run-perf.sh \
  --preset home-deck-flash \
  --parallel 1 5 20 50     # 依次测这 4 个并发
  --number 50              # 每并发发 50 个请求
  --max-tokens 256         # 输出上限
  --stream                 # 流式（默认），测 TTFT/TPS
```

### 精度评估（MMLU/GSM8K）

```bash
bash ccconfig/option-evalscope/run-eval.sh \
  --preset home-deck-flash \
  --datasets mmlu gsm8k \
  --limit 50               # 每 benchmark 采样 50（正式评估请去掉）
  --collect-perf           # 同时记录性能（默认开）
```

### 一键 性能+精度

```bash
bash ccconfig/option-evalscope/run-all.sh --preset home-deck-flash
```

结果默认落在 `~/.cache/evalscope/<preset>/<kind>-<时间戳>/`，可用 `EVAL_OUTPUT_ROOT` 覆盖。

## 端点连接策略

| preset 类型 | perf | eval |
|-------------|------|------|
| OpenAI `/v1` | 直连 | 直连 |
| Anthropic `/anthropic` | 走 bridge(8898) | 走 bridge(8898) |
| `use_bridge: true` | 走 bridge(8898) | 走 bridge(8898) |

对需 bridge 的 preset，脚本调用 `ensure_bridge` 切到 `127.0.0.1:8898` 的 OpenAI bridge 完成转换；**测完恢复原 `llm-current` 的 bridge**，不改动 `~/.claude/llm-current`。

## 文件

| 文件 | 作用 |
|------|------|
| `init.sh` | 安装 / 状态 / 移除（option 组件规范） |
| `lib.sh` | 共享：读 preset、端点判定、输出目录 |
| `run-perf.sh` | 性能压测 |
| `run-eval.sh` | 精度评估 |
| `run-all.sh` | 一键 性能+精度 |
| `.venv/` | evalscope 独立 Python 3.11 环境（init.sh 创建） |

## 成本说明

全部开源免费。唯一消耗是跑评估时你的模型 API 被调用产生的**推理计算量**（本地推理=电费 / 云端=按量计费），这是模型本身的运行成本。MMLU/GSM8K 走**标准答案比对**，不需额外 judge 模型，无第三方费用。