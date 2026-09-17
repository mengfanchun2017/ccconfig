# 0032. 配置分层：共享预设 vs 本机选择

> **Status**: ✅ Accepted
> **日期**: 2026-09-17
> **关联**: `ccprivate/setup.sh`、`templates/ccprivate-setup.sh`、`lib/init-llm.sh`、`lib/ccprivate-upgrade.sh`、`lib/status.sh`、`init-bootstrap.sh`
> **模板**: MADR 4.0 极简版
> **前序**: [ADR-0020](./0020-llm-current-local-per-machine.md)（LLM 运行时配置本地化）——本 ADR 把它没推到底的部分收口，并修正执行路径上的回退

## Context and Problem Statement

### 症状

多机（公司机 / 家里机）共用一个 git 账号工作时：

1. **A 机切换 LLM → 立刻触发 auto-sync**，随后 push。B 机 pull 后被顶掉。
2. 为解决此问题引入"配置模板 + 每机本地选择"，但现场仍混乱——`maintain status` 持续报 `.config.json ❌`。

### 三次演进留下的债

| 阶段 | 做法 | 遗留 |
|------|------|------|
| ① 全共享 | LLM 配置全在 ccprivate | A 机切换 push 覆盖 B 机 |
| ② 部分本地化（ADR-0020） | `llm-current` 本地 + `settings.json` 本机文件 | `.config.json`/`.claudeignore` 未同步改；执行路径有三套 |
| ③ 本次 | 分层收口 + 单一模板真相源 | — |

### 实测根因（8 项）

**P0**

1. **`write_llm_config` 无条件重写 `conf/llm.json`** —— 即使内容完全相同也落盘。auto-sync 用 inotify 监听**写事件**，故每次切换都触发 60s debounce + pull/push 网络往返（日志实测 13:32、13:38 各一轮）。反向验证：旧版两次切换 mtime `13:49:37.810 → 38.061`。
2. **`ccprivate-upgrade.sh` 仍是旧架构** —— 把 `.config.json`/`.claudeignore` symlink 回 ccprivate。跑一次 upgrade 就把 `setup.sh` 刚建立的本机文件打回跨机共享，**这是"覆盖"反复复发的结构性原因**。
3. **`settings.json.example` 缺失** —— `setup.sh` 拿已 gitignore 的 `link/settings.json` 当模板源，新机 clone 后 `cp` 失败，`set -e` 中断，后续 memory/rules/skills 链接**全部不建**。

**P1**

4. **`llm.json.current` 字段残留** —— 与本地 `llm-current` 已不一致（`homedsflash` vs `deepseek_flash`），且随 push 把 A 机选择带给 B 机。
5. **`status.sh` 仍要求 `.config.json` 是 symlink** —— 每次 startup 必报 ❌，制造"配置乱了"的错觉。

**P2**

6. **`setup.sh` 有三份副本**（实体 / `init-bootstrap.sh` 内嵌 / `ccprivate-upgrade.sh` 内嵌 `SETUP_SH_V3`），已漂移。
7. **`link/settings.json.save`**（含旧 key）已入库；`llmswitch.json` symlink 是 gateway 删除后的死引用（bridge 只读 `openai_bridge` 键，而该键根本不存在）。
8. **`templates/settings.json.example` 是旧结构** —— env/permissions/hooks/mcpServers 全混在一个文件，与 `maintain.sh` 的字段迁移逻辑长期不一致。

## Decision Drivers

- **D1 切换必须零副作用**：切 LLM 是高频动作，不得触发任何网络同步
- **D2 分层要能被机器判定**：`status.sh` 能明确回答"这个文件该共享还是该本机"
- **D3 单一真相源**：同一份 setup.sh 内容不得有两处副本
- **D4 新机引导不能崩**：模板缺失必须降级跳过，不得因 `set -e` 中断整条链

## Decision

### 1. 三层模型（核心）

```
Layer 1  共享同步    ccprivate/conf/llm.json      预设定义（名 / URL / model / key / use_bridge）
          symlink →  ~/CLAUDE.md、rules/、agents/、memory/
          ── 改一处全机生效；切换 LLM 时只读不写

Layer 2  本机不同步  ~/.claude/llm-current         本机选了哪个 preset
                    ~/.claude/settings.json        LLM env（含 key 明文，故必须本地）
                    ~/.claude/.config.json         会话配置（permissions/hooks/mcpServers…）
                    ~/.claude/.claudeignore        context 策略

Layer 3  模板同步    templates/*.example            新机引导（占位符）
```

**不变量**：本机文件只在首次 `cp` 模板时产生，之后**永不回写 ccprivate**。

### 2. 切换 LLM 零写入

`write_llm_config` 生成新内容后与磁盘比对，相同则跳过落盘；`current` 字段一次性清除（此后本机选择只走 `~/.claude/llm-current`）。key 仍会在首次填入某 preset 时同步（那是真变化，值得一次同步）。

### 3. 单一模板真相源

`templates/ccprivate-setup.sh` 是 setup.sh 的唯一内容来源，`init-bootstrap.sh`（新机）与 `lib/ccprivate-upgrade.sh`（老机）都 `cp` 它，删除两处内嵌副本（合计 -199 行）。

### 4. 模板按分层拆分

- `templates/settings.json.example` → 只留 LLM `env`
- `templates/.config.json.example` → permissions / hooks / statusLine / mcpServers

### 5. 检查与告警对齐分层

`status.sh` 按组显示：本机三件套存在即 ✅；**被 symlink 回 ccprivate 反而告警**（那正是跨机覆盖的形态）。

## Consequences

### Positive

- ✅ 切换 LLM 不再触发 auto-sync（T4 反向验证过）
- ✅ 新机 bootstrap 不再因模板缺失中断
- ✅ 三份 setup.sh 副本 → 1 份，漂移不可能再发生
- ✅ `status.sh` 告警从"永远 ❌"变成有信息的判断

### Negative / Risks

- ⚠️ **本机文件丢失需手动恢复**：本机文件不再有 ccprivate 副本，误删只能从 `.example` 重建（key 要重填）。缓解：`init-llm.sh` 会从 `conf/llm.json` 的 preset 重新写入 key
- ⚠️ **旧机器残留 symlink**：升级后需跑一次 `setup.sh` 或 `maintain.sh self cc` 才能把 symlink 转成本机文件。`install_user_file` 检测到 symlink 会自动转换
- ⚠️ **`llm.json.current` 存量读取**：`read_local_current` 仍保留 fallback 读它，供尚未跑过新版 `init-llm.sh` 的机器兼容

## Implementation

| 文件 | 变化 |
|------|------|
| `ccprivate/setup.sh` | 三文件统一 `install_user_file`；删 llmswitch 死引用 |
| `templates/ccprivate-setup.sh` | **新增**，单一真相源 |
| `init-bootstrap.sh` | `gen_setup_sh` 改 cp 模板（-60 行）；`gen_settings_json` 只生成 `.example` |
| `lib/ccprivate-upgrade.sh` | 删 `SETUP_SH_V3` 内嵌（-139 行）+ 两份 `.example` 内嵌；旧架构 symlink 改本机文件 |
| `lib/init-llm.sh` | 幂等写入 + 清 `current` |
| `lib/status.sh` | 分层检查 |
| `templates/settings.json.example` | 拆为两份 |
| `tests/test-init-llm-switch.sh` | 新增 T4（mtime）/ T5（current） |
| `tests/test-init-ccprivate-repo.sh` | 断言改查模板文件；修 3 条指向已删脚本的失效断言 |

### 验证

- `tests/test-init-llm-switch.sh` 6/6，**反向验证**：`d1a2669` 版本 T4/T5 如期失败
- `tests/test-init-ccprivate-repo.sh` 31/0
- `tests/test-bootstrap.sh` 19/0 · `test-monitor.sh` 16/0 · `test-maintain.sh` 35/0

## Related Decisions

- [ADR-0020](./0020-llm-current-local-per-machine.md) — LLM 运行时配置本地化（本 ADR 收口其未完成部分）
- [ADR-0001](./0001-secret-strategy.md) — 真实配置文件不入 git 仓
- [ADR-0031](./0031-init-llm-consolidation-2026.md) — init-llm 收敛（同批修复）

## Related Memory

- `settings-llm-only-local-20260915` — settings.json 仅存 LLM 配置
- `link-session-state-untie-20260917` — 解除 .config.json/.claudeignore 跨设备跟踪（本 ADR 完成其余执行路径）
