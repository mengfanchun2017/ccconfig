# 0039. 三层 LLM 配置

> **Status**: ✅ Accepted
> **日期**: 2026-10-07
> **关联**: [ADR-0020](0020-llm-current-local-per-machine.md)、[ADR-0032](0032-config-layering.md)、`lib/init-llm.sh`、`lib/ensure-bridge.sh`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

单文件 `ccprivate/conf/llm.json` 混装预设定义（name/base_url/model/use_bridge）与 API Key，带来三个问题：

1. **key 与定义耦合**：公开仓库无模板可参考，`.example` 与实际文件 schema 漂移（`llm.json.example` 与真实数据长期不一致）。
2. **内置预设无处安放**：ccconfig 想提供开箱即用的内置预设（无需 key 的定义），但没有不涉私的存放位置。
3. **桥接组件读源不统一**：preset 合并逻辑（normal/private）与 key 注入散在各处，`ensure-bridge.sh` / `status.sh` 各自读不同文件。

## 决策：三层文件 + 合并缓存

### 文件分层

| 文件 | 位置 | 内容 | key 是否含 |
|------|------|------|-----------|
| `conf/llmnormal.json` | ccconfig（公开） | 内置预设定义，`builtin: true` | ❌ |
| `conf/llmprivate.json` | ccprivate（私有） | 自定义预设定义 | ❌ |
| `conf/llm.json` | ccprivate（私有） | 纯 key：`{"llms": {"<name>": "<key>"}}` | ✅ 只有 key |

- 删除公开库 `conf/llm.json.example`（已被 `llmnormal.json` 取代）。
- 预设定义文件同 schema：name/base_url/model/small_model/use_bridge/host_header，builtin 标记仅 normal 有。

### 合并语义（`lib/init-llm.sh::_llms_merged_py()`）

1. **合并 normal + private 定义**：同名 preset 以 private 覆盖 normal（用户可重定义内置）。
2. **注入 key**：按 preset 名从 `llm.json` 织入。key 缺失不报错（占位场景），运行时探测会拦。
3. **打 `_src` 标记**：`normal` / `private`，供交互菜单分组（--LLM预设-- / --LLM自定义--）+ 内置 preset 拒绝删除。
4. **写合并缓存** `~/.cache/llm-merged.json`：`{"llms": {...}, "current": "<当前 preset>"}`。桥接组件（ensure-bridge.sh / status.sh SessionStart 自愈）统一读它，避免各自拼装。

### 读取链

```
用户菜单/CLI → init-llm.sh
         └→ _llms_merged_py() → ~/.cache/llm-merged.json
                                  ├→ ensure-bridge.sh（起/重启 bridge，读 merged）
                                  └→ status.sh _bridge_cold_start（SessionStart 自愈，读 merged，缺失先跑 `init-llm.sh merge`）
```

- `write_llm_config` / `update_llm_key` 只写 `ccprivate/conf/llm.json`（纯 key），不写定义文件。
- `~/.claude/llm-current` 仍是"当前 preset"权威来源（ADR-0020 不变），merged 缓存的 `current` 是从它读的快照。

### 新增 `merge` 子命令

`bash init-llm.sh merge` 只做合并 + 写缓存（供 status.sh 冷启动兜底），不做切换/探测。

## 影响

- **内置 preset**：`conf/llmnormal.json` 随公开仓库分发，fork 用户直接可用（仅缺 key，填 `llm.json` 即用）。
- **自定义 preset**：写 `ccprivate/conf/llmprivate.json`，key 仍放 `llm.json`，两文件同 schema 学习成本低。
- **桥接一致性**：所有读桥配置的地方收敛到 `llm-merged.json`，消除"各读各文件"的漂移。
- **删除保护**：`delete_preset` 对 `_src == normal` 直接拒绝，"内置预设不可删"从约定变强制。

## 不做的事

- 不把 key 移出 ccprivate（仍是纯 key 单文件，方便备份/迁移时单独保护）。
- 不引入动态发现：normal/private 合并是静态确定的两层，不做运行时插件化。