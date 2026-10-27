# 2026-10-27 公开仓/私有仓边界收口（skill-local / agents / usage 清理）

> 范围：`ccprivate` 私有仓结构清理 + `ccconfig` 侧所有指向已删项的引用
> 起因：全量审计发现"两边一起管理很复杂"的真实结构 —— 配置散在 3 个根、4 种机制并存；
> 且若干既有叙述与实际不符（`~/git/skill` 里其实零 agent / 零 workflow；
> `ccprivate/skill-local/` 建好但从未使用）。
> 关联 memory：`skill-repo-split-audit-20261027`
> 关联 ADR：0032（配置分层）、0021 / 0043（skill 分层源 —— 本次推翻其 skill-local 前提）
> 新增测试：`tests/test-ccprivate-boundary.sh`、`tests/test-ccprivate-sandbox-e2e.sh`

## 一、删除项（4 项）

| 删除内容 | 位置 | 依据 |
|---|---|---|
| `skill-local/` 整个目录 | ccprivate | 层内从未放过 skill（长期只有 `.gitkeep`）；实体统一放公开的 `~/git/skill/plugins` |
| `agents/assistant.md` + `agents/knowledge-expander.md` | ccprivate | 用户判定无用 |
| `templates/agents/`（含 2 个 `.md.example`） | ccconfig | agent 实体放公开 skill plugin，不再走"公开模板 → 私有实例"同步链 |
| `usage/`（44 个 CSV） | ccprivate | ADR-0036 早已决策删除，ccconfig 侧删了、私有侧数据残留 |
| `link/{settings.json,.config.json,.claudeignore}.example` | ccprivate | 与 `ccconfig/templates/*.example` **逐字节相同**（实测 diff rc=0）→ 两处模板必然漂移 |
| `CLAUDE.md` | ccprivate | 该仓不按项目启动（工作目录在 ccconfig），文件永不加载（内容并入 README） |

## 二、关键修复：本机文件模板的单一真相源

`setup.sh` 此前从 `ccprivate/link/*.example` 拷贝本机三件套模板，而
`status.sh` / `maintain.sh` 用 `ccconfig/templates/*.example` 判断 —— 两份副本一旦漂移，
就出现"status 用新模板报缺键、setup 用旧模板补不上"（键看着修了其实没进来）。

**改为**：`setup.sh` 直接从 `$CCCONFIG_DIR/templates/` 取；`ccprivate-upgrade.sh`
的 `fix_link_content` 不再往 `link/` 复制副本，并**清理老机器上的残留**。

## 三、被测试抓出来的真实 bug（升级路径）

`ccprivate-upgrade.sh` 的 `fix_link_content` 挂在 `check_link_content` 失败之后才执行。
把检查项从"三个 `.example` 都在"改成"`CLAUDE.md` 在"之后，检查恒过 →
**残留副本永远不会被清理**，且升级报 "结构已是最新"、退出码 0。

修法：`check_link_content` 把"存在已废弃副本"也算作需修状态（返回 1），
使 fix 步骤真正被触发。沙箱 e2e 测试 `T4` 锁死此行为。

## 四、skill-local 移除的连带改动

| 文件 | 改动 |
|---|---|
| `lib/init-skill.sh` | 去掉私有源扫描/覆盖/清理分支；新增"清理老机器上指向 `skill-local` 的遗留死链" |
| `option-skill/init.sh` | 状态统计去掉"私有"档，改「本仓 / 第三方 / 实体」 |
| `lib/ccprivate-upgrade.sh` | `skill-local` 从必备目录列表移除；不再创建 |
| `maintain.sh` | `expected_dirs` 去掉 `skill-local` |

**注意**：`LOCAL_SKILLS_SRC` 变量在 `init-skill.sh` / `option-skill/init.sh` 中**保留**，
用途只剩"识别并清理老机器上的遗留链接"。这是有意的 —— 删掉变量会让那些链接变成
永不被清理的孤儿。

## 五、我**没有**动的东西（避免过度清理）

- `conf/schema/mcp.schema.json`、`conf/feishu.json`、`conf/llm.json` 等：各有真实消费方
- `bin/yaml-edit.sh`、`bin/convert-configs.sh`：运维工具，保留
- `ccprivate/README.md`：重写为当前结构的单一说明源（替代已删的 `CLAUDE.md`）
- `docs/adr/*.md`：历史决策记录，**不回改正文**。skill-local 前提已在本文与
  memory 中标注推翻，ADR 作为当时决策的留档不动。

## 六、验证

- 全量 `tests/*.sh` 通过（含 2 个新测试，共 23 + 14 个断言）
- `lib/secret-patterns.sh` 扫描：公开仓无凭据形状命中
- 沙箱 e2e：假 HOME + 假 ccprivate 跑真实 `setup.sh`（新装 / 二次幂等 / 老机升级）
- 两个新测试已加入 `.github/workflows/check.yml` 的 unit job 显式列表