# lark-cli 速查 + 试错自更新

> **规则**: 任何 lark-cli 命令的 flag 试错成功后，立即将正确用法追加到本文。禁止同一错误犯两次。

## 运行前缀
```bash
export LARKSUITE_CLI_CONFIG_DIR="$HOME/.lark-cli-<account>" && export PATH="$HOME/.local/bin:$PATH"
```

## 命令 → flag 对照

| 命令 | token参数 | 内容参数 | 其他易错 |
|------|----------|---------|---------|
| `docs +update/ +fetch` | `--doc` | v1: `--markdown` v2: `--content` | v2 `--command` 必须配 `--content` |
| `docs +search` | - | `--query` | 无 `--api-version` |
| `wiki +node-get` | `--token` | - | 支持URL |
| `wiki +node-create` | - | `--title` `--obj-type` | 不支持 board 类型 |
| `whiteboard +update` | `--whiteboard-token` | `--source` + `--input_format` | mermaid/plantuml/raw |
| `docs +create` | `--doc-format markdown` | `--content "markdown内容"` | help 显示 `--markdown` 但实际必须用 `--content` |
| `base +*` | `--base-token` | `--json`(单对象) | 不是 `--app-token`/`--fields` |
| `base +record-batch-create` | `--base-token` | `--json '{"fields":[],"rows":[[]]}'` | 数组格式 |
| `sheets +*` | `--spreadsheet-token` | `--values '[[...]]'` | 写数据需 `--range` |
| `drive +create-folder` | `--folder-token` | `--name` | 不是 `--title` |
| `drive +upload` | `--folder-token` | `--file "./rel"` | 必须相对路径，先 cd |

| `base +table-create` | `--base-token` | `--name` `--fields '<json-array>'` | 不是 `--json`，字段用 `--fields` |
| `base +table-update` | `--base-token` | `--name` `--table-id` | 支持按名称匹配，default表叫"数据表" |
| `base +record-get` | `--base-token` `--table-id` `--record-id` | -- | 返回 `data.data` (二维数组) + `data.fields` (字段名), 按 field_id_list 对齐 |
| `base +record-batch-create` | `--base-token` `--table-id` | `--json` | 返回 `data.record_id_list` (不是 `data.records[].record_id`); link 字段 `[{"id":"recXXX"}]`, select `["opt"]` |
| `base +record-update` | **不存在** | - | 用 raw API: `lark-cli api PUT /open-apis/bitable/v1/apps/{app}/tables/{tbl}/records/{id} --data '{"fields":{...}}'` |
| `base +record-search` | `--base-token` `--table-id` | `--keyword` (必填) `--search-field` | `--keyword` 必填, 除非 `--json`; 返回 `record_id_list` (按 search 顺序) |
| `base +field-create` | `--base-token` `--table-id` | `--json '{...}'` | 一次一个字段; 字段名带特殊字符可能需转义 |
| `slides +create` | - | `--title` `--slides '<json-array>'` | JSON 数组每元素是 XML `<slide>` 字符串 |
| `slides 导出` | - | `api POST export_tasks` | `drive +export` 不支持 slides，用 `lark-cli api` 调原始API |
| `drive +export-download` | `--file-token` | `--file-name` | 必须相对路径，先 cd |

## base +field-create 坑点

| 操作 | 错误写法 | 正确写法 |
|------|---------|---------|
| 字段类型 | `"type":3` (数字) | `"type":"select"` (字符串) |
| 选项/链接 | `"property":{"options":[...]}` | `"options":[...]` 在顶层 |
| 关联字段 | `"link_table_id":"tblXXX"` | `"link_table":"tblXXX"` 在顶层 |
| JSON文件路径 | `--json @/tmp/file.json` | `cd /tmp && --json @file.json` (必须相对) |
| 删除确认 | 不加 flag 报错 | `--yes` |
| table-create 加字段带 `formatter` | `--fields '[{...,"formatter":"0%"}]'` | table-create **不支持** formatter, 用 table-create 建空表后逐个 +field-create, formatter 通过 UI 设置 |
| 写 select 字段 | `"v":"NewOption"` | 选项目前必须已存在, 否则 not_found; API 改选项: 用 field-update 或先 field-create 选项 |
| +record-update | `lark-cli base +record-update ...` | **无此命令**, 改用 raw API (见速查表) |
| 拿 record_id | `+record-list` 只返回 fields 数组 | 用 `+record-search` 的 `data.record_id_list` |

### field-create 正确格式示例

```bash
# 单选字段
lark-cli base +field-create --base-token $T --table-id tblXXX \
  --json '{"field_name":"分类","type":"select","options":[{"name":"work","color":0},{"name":"learn","color":1}]}'

# 关联字段（跨表链接）
lark-cli base +field-create --base-token $T --table-id tblXXX \
  --json '{"field_name":"关联O","type":"link","link_table":"tblC4ykRAWqBFGjt"}'
```

## 跨租户访问限制

- **lark-cli 无法读取其他租户分享的文档/Base**，即使有链接和密码
- 表现：`docs +fetch` 报 `10071 unclassified backend reason`；`base +table-list` 报 `800004006 baseToken invalid`
- 不同租户 = 不同域名（`<your-tenant>.feishu.cn` vs `acimdomc.feishu.cn` vs `www.feishu.cn`）
- 解决方案：文档所有者导出文件（docx/csv），本地处理后再上传

## base 命令输出格式差异

| 命令 | 输出格式 | 备注 |
|------|---------|------|
| `base +record-batch-create` | JSON | 可 pipe `python3 -c "json.load()"` |
| `base +record-get` | 文本（key: value） | ❌ 非JSON，不能 pipe json.load |
| `base +record-list` | 默认 markdown 表格，JSON 需 `--format json` | ❌ 默认不能 pipe json.load，必须加 `--format json` |
| `base +table-list` | JSON | |
| `base +base-get` | JSON | 含 `data.base.url` |

## docs +update overwrite 破坏性

- `--command overwrite` 重建全部 block，白板 token 重新生成→图表内容丢失。含嵌入资源文档禁止 overwrite
- colgroup width 属性在 overwrite 后丢失，需逐个 `str_replace` 修复

## docs +fetch 格式差异

| `--detail` | colgroup width | block ID | 用途 |
|------------|---------------|----------|------|
| 默认（simple/clean） | ❌ 不显示 | ❌ 不显示 | 读内容 |
| `with-ids` | ✓ 显示 | ✓ 显示 | 定位 block |
| `full` | ✓ 显示 | ✓ 显示 | 验证宽度/属性 |

## wiki 命令正确 flag

| 命令 | 正确写法 | 错误写法 |
|------|---------|---------|
| `wiki +node-get` | `--token "URL"` 或用 `--node-token` + `--obj-type docx` | `--token "raw_token"` 缺 `--obj-type` |
| `wiki +node-list` | `--parent-node-token X --space-id X` | `--node-token`（不存在） |
| `docs +create --parent-token` | wiki node token（`TWQb...`） | doc token（`DOw...`）— 报 3380002 |

## docs +update 命令选择决策树

```
编辑文档
  ├─ 含白板/嵌入资源？ → block_insert_after / block_delete / str_replace（禁止 overwrite）
  ├─ 全量重写（无嵌入资源） → overwrite
  ├─ 插入到特定 block 后 → block_insert_after --block-id "xxx"
  ├─ 删除特定 block → block_delete --block-id "xxx"
  └─ 替换文本 → str_replace（pattern 需文档内唯一）
```

## 新增踩坑（追加在此）

### colgroup 宽度修复必须用 block_replace
- `str_replace` 不能处理 `<colgroup>` — 报 `Orphan tag was unwrapped`，因为 colgroup 脱离 `<table>` 上下文即孤标签
- ✅ 正确：`block_replace --block-id "<table_id>" --content "$(cat table.xml)"` 替换整个 table
- ✅ colgroup 宽度之和必须 = 822px 才是飞书全宽

<!-- 2026-05-29 | base init | 新建Bitable默认空表"数据表" — 直接rename复用，不新建再删。workflow无delete API。dashboard默认无。→ 结论写入f-logme SKILL.md -->
<!-- 2026-05-29 | base field-create | 7次试错：type数字格式、property嵌套、link_table_id → 全部改用扁平字符串key → 记录到上方速查表 -->
<!-- 2026-05-26 | slides export | drive +export --doc-type slides → 不支持 → lark-cli api POST export_tasks | 用通用API替代 -->

### base +record-list 不返回 record_id
- `+record-list` 只返回 `[fields_array]`，不返回 record_id — 不能直接拿到 id 删/更新
- ✅ 拿 id 用 `+record-search`：返回 `data.record_id_list`（按 search 结果顺序）+ `data.data`（fields 数组）
- ✅ 删：`+record-delete --record-id ID1 --record-id ID2 ... --yes`（高危，必须 `--yes`）
- ✅ 批量大（>50）：分页用 `--offset` + `--limit`

```bash
# 拿 v1 噪音 record_id
lark-cli base +record-search --base-token $T --table-id $TBL \
  --keyword "auto-aggregated" --search-field 说明 --limit 50

# 批量删（高危，必须 --yes）
lark-cli base +record-delete --base-token $T --table-id $TBL \
  --record-id recXXX --record-id recYYY --yes
```

### base +data-query --dsl 不支持 @file
- `lark-cli api POST ...` 支持 `--data @file`，但 `+data-query --dsl` 不接受 `@` 前缀
- 只能 inline JSON 或换 `+record-search` 拿数据

### base 字段 raw API 拿 record_id 失败
- `lark-cli api POST /open-apis/bitable/v1/.../records/search` 需要 scope `base:record:retrieve`
- ailab 账号无此 scope（authorization missing_scope）
- ✅ 用 `+record-search` 走 lark-cli 自己的 search 端点，已包含 record_id_list
