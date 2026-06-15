# lark-cli 速查

> 完整踩坑记录 → `skills/f-doc/references/lark-cli-cheatsheet.md`

## 运行前缀
```bash
export LARKSUITE_CLI_CONFIG_DIR="$HOME/.lark-cli-<account>" && export PATH="$HOME/.local/bin:$PATH"
```

## 命令速查

| 命令 | 关键 flag | 易错 |
|------|----------|------|
| `docs +create` | `--doc-format markdown --content "..."` | help 写 `--markdown`，实际 `--content` |
| `docs +update` | v2: `--command overwrite\|block_insert_after\|str_replace\|block_delete` + `--content` | `--command` 不是 `--mode` |
| `docs +fetch` | v2: `--detail full\|with-ids\|simple` | full 含 colgroup width |
| `whiteboard +update` | `--source @file.mmd --input_format mermaid` | mermaid 不支持 subgraph |
| `whiteboard +query` | `--output_as image\|code\|raw --output ./` | **下划线** `--output_as`；`--output` 必须相对路径 |
| `base +table-create` | `--name --fields '<json-array>'` | 不是 `--json` |
| `base +field-create` | `--json '{"field_name":"X","type":"select","options":[...]}'` | type 是字符串；options 在顶层 |
| `base +record-batch-create` | `--json '{"fields":[],"rows":[[]]}'` | link: `[{"id":"recXXX"}]` |
| `base +record-update` | **不存在** → raw API: `lark-cli api PUT .../records/{id} --data '{"fields":{...}}'` | |
| `base +record-list` | `--base-token X --table-id Y --format json --limit 200` | flag 是 `--base-token` 不是 `--app-token`；默认 table 格式，程序化解析需 `--format json`；limit 最大有效值 200，超 200 条需 `--offset` 分页 |
| `base +record-search` | `--keyword X --search-field Y` | 返回 `record_id_list`；`+record-list` 不返回 record_id |
| `slides +create` | `--title --slides '<json-array>'` | 在线 vs 导入 PPTX API 能力差很多 |
| `slides 导出` | `api POST export_tasks --data '{"type":"slides","token":"X","file_extension":"pptx"}'` | 不是 `drive +export` |
| `drive +upload` | `--folder-token --file "./rel"` | 必须相对路径，先 cd |
| `drive +export-download` | `--file-token --file-name` | 必须相对路径 |
| `wiki +node-get` | `--token "URL"` 或 `--node-token` + `--obj-type` | 支持 URL |

## 关键约束

- **含嵌入资源（白板/图片/电子表格）禁止 overwrite** — 只能用 str_replace / block_insert_after / block_delete
- **@file 路径必须相对当前目录** — `cd /tmp && --json @file` 非 `--json @/tmp/file`；最稳用 heredoc + stdin
- **跨租户无法访问** — 不同域名文档需导出本地处理
- **docs +create 必显式 `--title`** — 否则默认 "Untitled"，事后只能 str_replace 改
- **docx 删除**：`lark-cli api DELETE /open-apis/drive/v1/files/{token} --params '{"type":"docx"}'`
- **colgroup 修复**：用 `block_replace` 替换整个 table（不能用 str_replace 处理 `<colgroup>`）
- **base select 值**：必须用目标字段已有选项，不能想当然传字符串
- **lark-cli stdout**：WSL 会注入 `Shell cwd was reset to <path>` 行 → python json.loads 前过滤

## base +record-list JSON 输出格式

`--format json` 时输出结构：

```json
{
  "ok": true,
  "data": {
    "fields": ["标题", "说明", "日期", ...],
    "field_id_list": [...],
    "data": [
      ["标题值", "说明值", "2026-06-15 00:00:00", ...],
      ...
    ],
    "has_more": true,
    "record_id_list": ["recXXX", ...]
  }
}
```

**关键**：
- 记录在 `data.data`（不是 `data.records`）
- 每条记录是数组，按 `data.fields` 顺序排列，不是 dict
- `has_more: true` 时用 `--offset` 分页（limit 最大有效值 ~200）
- Python 解析：`fields = data['data']['fields']; for rec in data['data']['data']: d = dict(zip(fields, rec))`
