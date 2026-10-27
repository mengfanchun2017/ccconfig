# Skill 配置架构（2026-10-27 重写）

> 起因：审计发现"两边一起管理很复杂"的真实结构 —— 配置散在 **3 个根、4 种机制**，
> 15 处各自维护路径回退链，7 处裸写 `$HOME/git/ccprivate`，51 处跨 plugin
> `~/.claude/skills/<别家>/` 引用。27 个 plugin 从没跑过一次真实 `/plugin install`。
>
> 关联：ADR-0032（配置分层）、`docs/updates/20261027-*`、memory `skill-repo-split-audit-20261027`

## 1. 一句话架构

**一个解析函数，一条优先级链，两个孪生实现（bash / python）。**

```
skill 实体（公开）          →  ~/git/skill/plugins/<name>/
真值（私有，自用）          →  ccprivate/conf/<name>.yaml
真值（装机用户）            →  settings.json / .credentials.json（官方）
                              ↓
              ffeishu/references/plugin_env.sh   ← 唯一实现（bash）
              ffeishu/references/config_env.py   ← 唯一实现（python 孪生）
                              ↓
              skillconf_get <key>  /  config_env.get("<key>")
```

## 2. 8 级优先级（两实现完全一致，有测试锁死）

| # | 来源 | 谁用 | 位置 |
|---|------|------|------|
| 1 | 环境变量 `SKILLCONF_<KEY>` | 调试 / CI / 临时覆盖 | — |
| 2 | `${CLAUDE_PLUGIN_DATA}/config.json` | 装机用户自填（跨 update 保留） | `~/.claude/plugins/data/<plugin>/` |
| 3 | `pluginConfigs` | **装机用户主力**（`claude plugin configure` 弹窗填） | `settings.json` |
| 4 | `pluginSecrets` | 声明 `sensitive:true` 的键 | `.credentials.json`（权限 600） |
| 5 | `<root>/conf/<plugin>.yaml` | **自用多机同步主力** | ccprivate |
| 6 | `<root>/conf/_shared.yaml` | 多 plugin 共用的值（如 `tenant_domain`） | ccprivate |
| 7 | 旧路径 ×3 | 老机器兼容，新配置**不要**写这里 | `conf/../skill/`、`~/.claude/skill-config/`、`<plugin>/config.yaml` |

`<root>` = `${CCPRIVATE_HOME:-${CCPRIVATE_DIR:-$HOME/git/ccprivate}}` —— 只有一个变量名了。

**实测校正的三条**（此前基于文档推断，都错）：
1. 敏感值**不是** OS keychain，是 `~/.claude/.credentials.json` 里的**明文 JSON** → 脚本可读、也可写
2. 官方两通道都是**磁盘上的确定性文件** → 「官方通道」与「手写回退链」无本质差异，差别只是路径固定且在 cache 外
3. `pluginConfigs` 的结构是 `{"<plugin>@<market>": {"options": {...}}}` —— 多一层 `options`

## 3. 每个 plugin 怎么拿到解析器

`/plugin install` **只复制 plugin 自己的目录**（实测：27 个全装一遍，只有 ffeishu 有
`plugin_env.sh`，其余 26 个无解析器 → 装机即断）。

解法：每个 plugin 带一份 ~40 行的 **boot stub** 去找唯一实现（实现仍只有一处）：

```
plugins/<name>/references/
  ├── _skillconf_boot.sh     ← 生成物（~40 行），找并 source 唯一实现
  ├── _skillconf_boot.py     ← 生成物，Python 版
  └── （无 plugin_env.sh / config_env.py —— 那两个只在 ffeishu 有）
```

stub 的查找顺序（覆盖两种布局）：自己就是 ffeishu → 兄弟目录 `ffeishu/`（git clone）
→ cache 布局 `<cache>/<market>/ffeishu/<ver>/` → `~/.claude/skills/ffeishu/`。

**改实现后必须重跑**：`bash ccconfig/bin/sync-plugin-env.sh`
（`--check` 只校验，有漂移非零退出；脚本会反向断言"实现本体不得散落到别的 plugin"）

## 4. 两类配置的分工（别混）

| | 每 plugin 私有 | 多 plugin 共享 |
|---|---|---|
| 键例 | `wiki_nodes`、`doc_index`、`shared_dir` | `tenant_domain`、`lark_account` |
| 落点 | `conf/<plugin>.yaml` | `conf/_shared.yaml` |
| 取值 | `skillconf_get <key>` | 同左（链上第 6 顺位自动兜底） |
| 覆盖 | per-plugin 优先（第 5 顺位在第 6 之前） | — |

**共享文件**（非每 plugin 一个，而是多个 skill 同读一份）走
`skillconf_file <relpath>` + `skillconf_file_get <relpath> <key...>`：
```
skillconf_file_get writing/case.yaml base_token
skillconf_file_get writing/registry.yaml genres course orchestrator
skillconf_file_get conf/ffeishu.yaml doc_index 0 title    # 支持列表索引
```

## 5. 官方机制怎么用（给装机用户）

每个 plugin 的 `.claude-plugin/plugin.json` 声明 `userConfig`：

```json
{ "userConfig": {
    "tenant_domain": {"type":"string","title":"飞书租户域名","description":"xxx.feishu.cn"},
    "mineru_token":  {"type":"string","title":"MinerU token","description":"...","sensitive":true}
} }
```

用户 `/plugin install` 时弹窗填 → 值落 `pluginConfigs` / `pluginSecrets` → 解析链
第 3/4 顺位读到。**不需要**用户知道 ccprivate 是什么。

> `${user_config.KEY}` 正文内联替换只对 Markdown 生效（敏感值会替换成占位符）；
> 你的 skill 是**脚本**在读配置，所以脚本走解析链读那两个 JSON，不依赖正文替换。

## 6. 多终端同步

| 场景 | 媒介 |
|---|---|
| 你自己的多台机 | `ccprivate/conf/<plugin>.yaml` —— clone + `setup.sh`，改一处全机生效 |
| 装机用户 | `settings.json` 的 `pluginConfigs` + `.credentials.json` 的 `pluginSecrets`（跟着 Claude 配置走） |
| 跨机器搬私有数据 | 同步 `$CLAUDE_PLUGIN_DATA` 那**单个文件**，或继续用 ccprivate |

不需要"每台机 clone ccprivate 再建 symlink 链"那一套了 —— symlink 通道已删。

## 7. 诊断

```bash
source ~/.claude/skills/ffeishu/references/plugin_env.sh
skillconf_diag tenant_domain wiki_nodes    # 每个键实际来自哪个源（值脱敏）
skillconf_path tenant_domain               # 会命中的文件路径
skillconf_require mineru_token             # 缺失时打印"去哪填"并返回非零
```

## 8. 回归护栏（防漂移）

| 测试 | 锁什么 |
|---|---|
| `tests/test-plugin-env-parity.sh` | bash/python 两实现在 8 级每一级必须给出**相同**结果 |
| `tests/test-plugin-install-e2e.sh` | 真跑 `/plugin install` 27 个：能装、能认出自己、能读 userConfig、cache 内无旧 config.yaml |
| `tests/test-ccprivate-boundary.sh` | 已删项不得复活 + 公开仓无凭据形状 |
| `tests/test-ccprivate-sandbox-e2e.sh` | 新机 setup / 二次幂等 / 老机升级清残留 |

CI 已把前两个加进 `.github/workflows/check.yml` 的 unit job。