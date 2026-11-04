# 0058. 技能包分层 — fcore 机械内核 + fhub 总入口

> **Status**: ✅ Accepted
> **日期**: 2026-11-04
> **关联**: `~/git/skill/plugins/fcore`、`~/git/skill/plugins/fhub`、`~/git/ccprivate/conf/fcore.yaml`、`bin/sync-plugin-env.sh`、ADR-0043（撰写系统四层）
> **模板**: MADR 4.0 极简版
> **取代**: 部分取代 ADR-0043 的 L4 路由层（fworch 职责并入 fcore genre）

## Context and Problem Statement

对 28 个 f* skill 做结构审计（2026-11-03），实测出四类问题：

1. **重复实现没有收敛**：27 份 `_skillconf_boot` 副本、2 份已分叉的 `lark_env.sh`、
   5 处 auth 预检其中 **3 处 grep 写成 `'"ok":true'`**（lark-cli 实际输出 `"ok": true`，
   冒号后有空格）→ 认证明明正常也恒报 AUTH_FAILED，三个技能直接拒绝干活。
2. **17/28 个 skill 零脚本**：模型每次要照抄 5-10 行 lark-cli 命令。上面 3 个 bug 就是抄错的产物。
3. **SKILL.md 体积 85.7k token**（6013 行全量进上下文），其中 18% 是可推迟的机械命令与安装/故障段。
4. **触发词三处真相源已漂移**：`~/CLAUDE.md` 曾写「写报告 → fresearchframe」而实际该派
   fworch-report；`registry.yaml` 与各 SKILL.md 的 description 又各写一份。

同时用户提出三个硬需求：
- 技能是**开源**的，隐私内容（token/文档链接/记录/配置）必须在 ccprivate；
- **没配 ccprivate 的人也要能用**，且**自己保存的配置不能因 skill 升级被覆盖**；
- 需要一个**总入口**，用户不必记子技能名。

## Decision Drivers

- **D1 单一实现**：同一件事只有一处代码。改一次不必改 N 处（此前 3 处预检漏改 2 处）。
- **D2 机械与判断分离**：SKILL.md 只写"该怎么判断、走哪条路"，命令下沉到可执行脚本。
- **D3 配置不因升级丢失**：用户自填值必须落在 `/plugin update` 替换范围之外。
- **D4 无配置也能用**：缺配置时降级，不阻断。
- **D5 触发词单一真相源**：派发规则只有一份，不再三处各写。
- **D6 零真值公开**：公开仓只有代码与 .example 模板。

## Considered Options

1. **合并成大 skill（按域合并成 8 个）** — 实测：合并后 f-doc 需 12.8k token、f-write 需
   13.5k，而现状「写报告」只加载 3.6k + 2.6k。**合并把按需加载变回全量加载，token 反而涨**。
2. **维持现状，只修 bug** — 治标：下次再抄一遍命令，还会有下一次。
3. **新增 L0 机械内核 fcore + L1 总入口 fhub，SKILL.md 减肥（采纳）** — 新增层解决重复与
   机械操作；总入口解决"记不住技能名"；减肥解决 token。三者互不冲突。

**Chosen**: 3

## Decision

### 一、分层

```
L0  fcore      机械内核 —— 路径/配置/auth/文档/格式/派发匹配。唯一碰 lark-cli 命令的层
L1  fhub       总入口 —— 判断需求属哪个子技能，派发过去。不执行业务
L1  各域技能   ffeishu / fpdf / fdigest / fresearchframe / flogme / fpptx ...
L2  fwstd-*    内容规范 —— 什么算好，无命令
L3  fworch-*   编排 —— 什么时候做哪一步
```

### 二、fcore 提供什么

| 命令 | 取代 |
|---|---|
| `fcore auth` | 5 处手写 auth 预检（3 处是错的） |
| `fcore conf get/set/path/require` | `plugin_env.sh` + 27 份 boot stub |
| `fcore data / data-ls` | 课程进度这类用户数据的路径拼接 |
| `fcore genre / genres` | fworch 的注册表读取 + 判体裁 + 派发 |
| `fcore doc create/get/ids`、`upload`、`search` | 各 SKILL.md 里照抄的 lark-cli 命令 |
| `fcore fmt-xml / fmt-md` | write-checklist 里可机械判定的部分 |
| `fcore where` | 散落各处的排障命令 |

### 三、配置存放（D3 的核心）

读取顺序 9 级，**用户自填落在第 8 级 `~/.claude/skill-config/<plugin>.yaml`**：

```
1. 环境变量 F_<KEY>
2. ${CLAUDE_PLUGIN_DATA}/config.json
3. ~/.claude/plugins/data/<plugin>/config.json
4. ~/.claude/settings.json → pluginConfigs
5. ~/.claude/.credentials.json → pluginSecrets
6. <ccprivate>/conf/<plugin>.yaml
7. <ccprivate>/conf/_shared.yaml
8. ~/.claude/skill-config/<plugin>.yaml      ← 用户自填（推荐）
9. <plugin目录>/config.yaml
```

**为什么第 8 级安全**：`/plugin update` 整目录替换的是
`~/.claude/plugins/cache/<market>/<plugin>/<version>/`。`~/.claude/skill-config/`
在这个范围之外，升级/重装/卸载都不会碰。

### 四、配置 vs 用户数据

| 类型 | 例子 | 命令 | 落点 |
|---|---|---|---|
| 配置 | tenant_domain、wiki token | `fcore conf get/set` | `skill-config/<plugin>.yaml` |
| 用户数据 | 课程进度、案例索引 | `fcore data` | `skill-config/data/<plugin>/` |

区别：配置是键值对（`skillconf_get` 按 key 查）；用户数据是结构自由的文件
（课程配置有嵌套的 lesson_docs 列表，需要整个文件读写）。
此前 fworch-course 有 4 处、fworch-interview 有 4 处用 `skillconf_file` 读用户数据，
而它只查 ccprivate —— 独立用户直接失效。

### 五、总入口派发

`fhub` 不靠"文档里写一句让模型自己去"，而是**先跑确定性匹配**：

```bash
fcore genre "<用户原话>"     # 输出 domain/genre → 该派哪个技能
```

匹配两级：① 完整触发短语命中（长词加权）；② **中文二元组词元兜底**。
第二级是关键 —— 注册表没写"PDF排到飞书"，但 `PDF`+`飞书` 词元能拼出来。
实测 11 条口语化需求全部正确派发（"帮我写个行业报告"→fworch-report、
"把这个PDF排到飞书"→fpdf、"画个架构图"→ffeishu、"读这份年报总结"→fdigest）。

**为什么不用中文分词库**：正则 `[一-鿿]{2,}` 贪婪匹配会把整句连成一个词元
（"帮我写个行业报告" 匹配不到 "写报告"），实测踩过。二元组无依赖且够用。

### 六、触发词单一真相源

`<ccprivate>/conf/fcore.yaml` 是唯一真相源；公开仓只放
`fcore/references/fcore.default.yaml`（模板级，无真值）作为独立用户兜底。
`~/CLAUDE.md` 不再各写一份触发词清单，改为一句"不确定走 fhub"。

## Consequences

**正面**
- 3 个恒失败预检修复；今后改预检只改 fcore 一处。
- 独立用户：无 ccprivate 时 `fcore genre` 走内置默认，配置走 `~/.claude/skill-config/`。
- 用户自填配置不因升级丢失（在 cache 目录之外）。
- 机械操作有脚本，模型不必照抄命令 —— 抄错这一类 bug 消失。
- 派发有确定性实现，不再是"提示模型自己判断"。

**负面 / 代价**
- 两套配置解析并存（ffeishu 的 `plugin_env.sh` 8 级链 + fcore 的 9 级链）。
  保留旧的只为不破坏已在跑的机器；新代码一律用 fcore，旧的在后续批次迁完再删。
- 30 个 skill 各带一份 `_boot.sh`（40 行生成物）。这是 `/plugin install` 只复制自身目录
  的必然代价，实现仍只有 fcore 一处。
- `fworch` 未删除，只标为「建议改走 fhub」。删除要等 fhub 跑稳（避免用户肌肉记忆断掉）。

**未做（下一批）**
- 六个大 skill 的 SKILL.md 减肥（85.9k → 36.2k token，实测可减 58%）。
- 154 处硬编码 `~/.claude/skills/` 改为经 `_boot.sh` 解析。
- fworch 删除、命名统一（f-doc/f-write）。
